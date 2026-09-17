import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../models/app_transaction.dart';
import '../models/wallet.dart';
import 'firestore_write.dart';

/// Reads and writes the user's wallets and transactions.
///
/// Anything that changes a balance is written as a single [WriteBatch] holding
/// both the transaction and the matching balance change, so a balance can
/// never drift away from the history that explains it. Firestore applies a
/// batch to its local cache straight away, so the app stays correct offline
/// and syncs the same batch once there is a connection.
///
/// Balances are moved with [FieldValue.increment] rather than by writing a new
/// total. The server applies the change to whatever the balance is at the
/// time, so two devices adding expenses at once can't overwrite each other.
class WalletService {
  static FirebaseFirestore get _firestore => FirebaseFirestore.instance;

  static String get _uid {
    final user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      throw StateError('No authenticated user.');
    }

    return user.uid;
  }

  static CollectionReference<Map<String, dynamic>> get _walletsCollection =>
      _firestore.collection('users').doc(_uid).collection('wallets');

  static CollectionReference<Map<String, dynamic>>
  get _transactionsCollection =>
      _firestore.collection('users').doc(_uid).collection('transactions');

  // ---------------------------------------------------------------- reading

  /// The user's wallets, updating live. Ordering happens here instead of with
  /// `orderBy` so wallets saved without a `sortOrder` are still included.
  static Stream<List<Wallet>> watchWallets({bool includeArchived = false}) {
    return _walletsCollection.snapshots().map((snapshot) {
      final wallets = snapshot.docs
          .map((doc) => Wallet.fromMap(doc.id, doc.data()))
          .where((wallet) => includeArchived || !wallet.archived)
          .toList();
      sortWallets(wallets);
      return wallets;
    });
  }

  /// Combined balance of every active wallet, updating live.
  static Stream<double> watchTotalBalance() {
    return watchWallets().map(totalWalletBalance);
  }

  /// Every transaction, newest first, updating live.
  ///
  /// The whole collection is streamed and filtered in the app rather than
  /// queried per wallet, because a transfer belongs to two wallets at once and
  /// a two-field query would need a composite index to be set up by hand.
  static Stream<List<AppTransaction>> watchTransactions({int? limit}) {
    Query<Map<String, dynamic>> query = _transactionsCollection.orderBy(
      'date',
      descending: true,
    );

    if (limit != null) query = query.limit(limit);

    return query.snapshots().map(
      (snapshot) => snapshot.docs
          .map((doc) => AppTransaction.fromMap(doc.id, doc.data()))
          .toList(),
    );
  }

  /// One wallet's transactions, newest first. Includes transfers in and out.
  static Stream<List<AppTransaction>> watchWalletTransactions(String walletId) {
    return watchTransactions().map(
      (transactions) => transactionsForWallet(transactions, walletId),
    );
  }

  /// Reads the wallets once. Returns cached wallets while offline.
  static Future<List<Wallet>> loadWallets() async {
    final snapshot = await _walletsCollection.get();
    final wallets = snapshot.docs
        .map((doc) => Wallet.fromMap(doc.id, doc.data()))
        .toList();
    sortWallets(wallets);
    return wallets;
  }

  // ---------------------------------------------------------------- wallets

  /// Adds a wallet and returns its id, which is available immediately even
  /// while offline. Pass [currentWallets] when the caller already has the live
  /// list, to place the new wallet at the end without another read.
  static Future<String> addWallet({
    required WalletType type,
    required String name,
    double startingBalance = 0,
    bool receivesIncome = false,
    List<Wallet>? currentWallets,
  }) async {
    final wallets = currentWallets ?? await loadWallets();
    final trimmedName = name.trim();
    final reference = _walletsCollection.doc();

    final batch = _firestore.batch()
      ..set(reference, {
        'name': trimmedName.isEmpty ? type.label : trimmedName,
        'type': type.name,
        'balance': startingBalance,
        'startingBalance': startingBalance,
        'receivesIncome': receivesIncome,
        'archived': false,
        'sortOrder': nextWalletSortOrder(wallets),
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });

    // A second wallet can't quietly take over as the income wallet.
    if (receivesIncome) {
      _addIncomeWalletUpdates(batch, wallets, reference.id);
    }

    commitFirestoreWrite(batch.commit(), 'add wallet');
    return reference.id;
  }

  /// Renames a wallet or changes its type. The balance is never touched here;
  /// only a transaction may move money.
  static void updateWallet({
    required String walletId,
    String? name,
    WalletType? type,
  }) {
    final fields = <String, dynamic>{'updatedAt': FieldValue.serverTimestamp()};
    final trimmedName = name?.trim();

    if (trimmedName != null && trimmedName.isNotEmpty) {
      fields['name'] = trimmedName;
    }

    if (type != null) fields['type'] = type.name;

    commitFirestoreWrite(
      _walletsCollection.doc(walletId).set(fields, SetOptions(merge: true)),
      'update wallet',
    );
  }

  /// Hides a wallet without deleting it, so its past transactions keep the
  /// name they were recorded under. Also drops the income flag, which would
  /// otherwise point at a wallet the user can no longer see.
  static void archiveWallet(String walletId) {
    commitFirestoreWrite(
      _walletsCollection.doc(walletId).set({
        'archived': true,
        'receivesIncome': false,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true)),
      'archive wallet',
    );
  }

  /// Brings an archived wallet back into the list.
  static void restoreWallet(String walletId) {
    commitFirestoreWrite(
      _walletsCollection.doc(walletId).set({
        'archived': false,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true)),
      'restore wallet',
    );
  }

  /// Marks [walletId] as the wallet the user's income is paid into, clearing
  /// the flag everywhere else in the same batch so exactly one wallet holds
  /// it.
  static Future<void> setIncomeWallet(
    String walletId, {
    List<Wallet>? currentWallets,
  }) async {
    final wallets = currentWallets ?? await loadWallets();
    final batch = _firestore.batch();

    if (!_addIncomeWalletUpdates(batch, wallets, walletId)) return;

    commitFirestoreWrite(batch.commit(), 'set income wallet');
  }

  /// Adds the flag changes to [batch]. Returns whether anything changed.
  static bool _addIncomeWalletUpdates(
    WriteBatch batch,
    Iterable<Wallet> wallets,
    String selectedId,
  ) {
    final updates = incomeWalletUpdates(wallets, selectedId);

    updates.forEach((id, receivesIncome) {
      batch.set(_walletsCollection.doc(id), {
        'receivesIncome': receivesIncome,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    });

    return updates.isNotEmpty;
  }

  // ----------------------------------------------------------- transactions

  /// Records an expense or an income against one wallet, moving that wallet's
  /// balance in the same batch. Returns the new transaction's id.
  ///
  /// [walletId] may be null while the user has no wallets yet; the entry is
  /// then kept as history only and no balance moves.
  static String recordTransaction({
    required TransactionType type,
    required double amount,
    required String label,
    String? id,
    String? walletId,
    String? note,
    DateTime? date,
  }) {
    if (type == TransactionType.transfer) {
      throw ArgumentError('Use recordTransfer for transfers.');
    }

    return _writeTransaction(
      id: id,
      type: type,
      amount: amount,
      label: label,
      walletId: walletId,
      note: note,
      date: date,
    );
  }

  /// Rewrites an existing transaction: takes back what the old version did to
  /// the balances and applies the new one, in the same batch.
  ///
  /// Used when an entry is edited. If there is no transaction with [id] yet,
  /// this simply records a new one under that id, which is what happens the
  /// first time an older expense is edited.
  static Future<void> replaceTransaction({
    required String id,
    required TransactionType type,
    required double amount,
    required String label,
    String? walletId,
    String? toWalletId,
    String? note,
    DateTime? date,
  }) async {
    if (type == TransactionType.transfer &&
        (walletId == null || walletId == toWalletId)) {
      throw ArgumentError('A transfer needs two different wallets.');
    }

    _writeTransaction(
      id: id,
      type: type,
      amount: amount,
      label: label,
      walletId: walletId,
      toWalletId: type == TransactionType.transfer ? toWalletId : null,
      note: note,
      date: date,
      previous: await loadTransaction(id),
    );
  }

  /// Reads one transaction, or null when it isn't there or can't be reached.
  static Future<AppTransaction?> loadTransaction(String id) async {
    try {
      final snapshot = await _transactionsCollection.doc(id).get();

      if (!snapshot.exists) return null;

      return AppTransaction.fromMap(snapshot.id, snapshot.data());
    } on FirebaseException {
      return null;
    }
  }

  /// Moves money between two wallets: one transaction, two balance changes,
  /// one batch. Returns the new transaction's id.
  static String recordTransfer({
    required String fromWalletId,
    required String toWalletId,
    required double amount,
    String? note,
    DateTime? date,
  }) {
    if (fromWalletId == toWalletId) {
      throw ArgumentError('A transfer needs two different wallets.');
    }

    return _writeTransaction(
      type: TransactionType.transfer,
      amount: amount,
      label: TransactionType.transfer.label,
      walletId: fromWalletId,
      toWalletId: toWalletId,
      note: note,
      date: date,
    );
  }

  static String _writeTransaction({
    required TransactionType type,
    required double amount,
    required String label,
    String? id,
    String? walletId,
    String? toWalletId,
    String? note,
    DateTime? date,
    AppTransaction? previous,
  }) {
    final batch = _firestore.batch();
    final transactionId = addTransactionToBatch(
      batch,
      type: type,
      amount: amount,
      label: label,
      id: id,
      walletId: walletId,
      toWalletId: toWalletId,
      note: note,
      date: date,
      previous: previous,
    );

    commitFirestoreWrite(batch.commit(), 'record ${type.name}');
    return transactionId;
  }

  /// Adds a transaction, and the balance changes it causes, to [batch].
  ///
  /// This exists so a caller that must save something else in the very same
  /// write — marking a bill paid, say — can do it atomically instead of
  /// hoping two separate writes both land. Returns the transaction's id.
  ///
  /// Pass [collectDeltasInto] when the batch will hold several transactions
  /// touching the same wallet. The balance changes are then added to that map
  /// instead of written, and the caller writes the totals once with
  /// [applyDeltasToBatch].
  static String addTransactionToBatch(
    WriteBatch batch, {
    required TransactionType type,
    required double amount,
    required String label,
    String? id,
    String? walletId,
    String? toWalletId,
    String? note,
    DateTime? date,
    AppTransaction? previous,
    Map<String, double>? collectDeltasInto,
    String? billInstanceId,
  }) {
    if (!amount.isFinite || amount <= 0) {
      throw ArgumentError.value(amount, 'amount', 'Must be greater than zero.');
    }

    final reference = id == null
        ? _transactionsCollection.doc()
        : _transactionsCollection.doc(id);
    final trimmedNote = note?.trim();
    final transaction = AppTransaction(
      id: reference.id,
      type: type,
      amount: amount,
      label: label,
      date: date ?? DateTime.now(),
      walletId: walletId,
      toWalletId: toWalletId,
      note: trimmedNote,
    );

    batch.set(reference, {
      'type': transaction.type.name,
      'amount': transaction.amount,
      'label': transaction.label,
      'walletId': transaction.walletId,
      'toWalletId': transaction.toWalletId,
      'note': trimmedNote == null || trimmedNote.isEmpty ? null : trimmedNote,
      'date': Timestamp.fromDate(transaction.date),
      'legacy': false,
      'billInstanceId': billInstanceId,
      'createdAt': FieldValue.serverTimestamp(),
    });

    final deltas = collectDeltasInto ?? <String, double>{};
    if (previous != null) _collectDeltas(deltas, previous, reverse: true);
    _collectDeltas(deltas, transaction, reverse: false);

    // A caller gathering several transactions applies the total itself.
    if (collectDeltasInto == null) _applyDeltas(batch, deltas);

    return reference.id;
  }

  /// Writes balance changes gathered with `collectDeltasInto`, one write per
  /// wallet.
  static void applyDeltasToBatch(WriteBatch batch, Map<String, double> deltas) {
    _applyDeltas(batch, deltas);
  }

  /// Removes a transaction and puts the money it moved back, in one batch.
  static void deleteTransaction(AppTransaction transaction) {
    final batch = _firestore.batch();
    removeTransactionFromBatch(batch, transaction);

    commitFirestoreWrite(batch.commit(), 'delete transaction');
  }

  /// Adds the removal of [transaction], and the balance it gives back, to
  /// [batch]. The batch counterpart of [deleteTransaction].
  static void removeTransactionFromBatch(
    WriteBatch batch,
    AppTransaction transaction,
  ) {
    batch.delete(_transactionsCollection.doc(transaction.id));

    final deltas = <String, double>{};
    _collectDeltas(deltas, transaction, reverse: true);
    _applyDeltas(batch, deltas);
  }

  /// Adds a transaction's effect on the wallets it touches into [into], or
  /// subtracts it when [reverse] is true. Legacy records carry no wallet, so
  /// they add nothing here.
  ///
  /// Effects are gathered per wallet before being written, so editing an
  /// entry results in one balance change per wallet rather than two.
  static void _collectDeltas(
    Map<String, double> into,
    AppTransaction transaction, {
    required bool reverse,
  }) {
    final direction = reverse ? -1 : 1;

    final source = transaction.walletId;
    if (source != null) {
      into[source] = (into[source] ?? 0) + transaction.sourceDelta * direction;
    }

    final destination = transaction.toWalletId;
    if (destination != null) {
      into[destination] =
          (into[destination] ?? 0) + transaction.destinationDelta * direction;
    }
  }

  /// Writes the gathered balance changes, skipping wallets that net to zero.
  static void _applyDeltas(WriteBatch batch, Map<String, double> deltas) {
    deltas.forEach((walletId, delta) {
      if (delta == 0) return;

      batch.set(_walletsCollection.doc(walletId), {
        'balance': FieldValue.increment(delta),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    });
  }
}
