import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../models/app_transaction.dart';
import '../models/goal.dart';
import '../models/wallet.dart';
import '../utils/unique_name.dart';
import '../utils/text_limits.dart';
import 'firestore_write.dart';
import 'goal_service.dart';
import '../utils/categories.dart';

class ExpenseBatchEntry {
  const ExpenseBatchEntry({
    required this.amount,
    required this.label,
    required this.note,
    this.walletId,
  });

  final double amount;
  final String label;
  final String note;

  /// The wallet this one was paid from, when the batch is split across
  /// several; otherwise the batch's own.
  final String? walletId;
}

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

  /// Reads every transaction once, newest first, the same order as
  /// [watchTransactions]. Returns cached records while offline.
  static Future<List<AppTransaction>> loadTransactions() async {
    final snapshot = await _transactionsCollection
        .orderBy('date', descending: true)
        .get();
    return snapshot.docs
        .map((doc) => AppTransaction.fromMap(doc.id, doc.data()))
        .toList();
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
    bool balanceRecorded = true,
    double? annualInterestRatePercent,
    List<Wallet>? currentWallets,
    WalletPurpose purpose = WalletPurpose.spending,
    String? savingsKind,
    DateTime? maturityDate,
    DateTime? depositStartDate,
    InterestPayout? interestPayout,
    Map<String, double> fundedFrom = const {},
  }) async {
    if (annualInterestRatePercent != null &&
        !isValidAnnualInterestRatePercent(annualInterestRatePercent)) {
      throw ArgumentError.value(
        annualInterestRatePercent,
        'annualInterestRatePercent',
        'Must be between 0 and '
            '${maximumAnnualInterestRatePercent.toInt()}%.',
      );
    }
    _validateSavingsDetails(
      purpose: purpose,
      savingsKind: savingsKind,
      annualInterestRatePercent: annualInterestRatePercent,
      depositStartDate: depositStartDate,
      maturityDate: maturityDate,
    );
    final wallets = currentWallets ?? await loadWallets();
    final trimmedName = cleanText(name);
    final reference = _walletsCollection.doc();

    final batch = _firestore.batch()
      ..set(reference, {
        // A repeated name gets the next number: "Cash", then "Cash 2".
        'name': uniqueName(
          trimmedName.isEmpty ? type.label : trimmedName,
          [
            for (final wallet in wallets)
              if (!wallet.archived) wallet.name,
          ],
          maxLength: purpose == WalletPurpose.spending
              ? maxSavedWalletNameLength
              : maxItemNameLength,
        ),
        'type': type.name,
        // Money moved in from other wallets arrives by the transfers below,
        // so the record starts empty and they fill it.
        'balance': fundedFrom.isEmpty ? startingBalance : 0,
        'balanceRecorded': balanceRecorded,
        'startingBalance': fundedFrom.isEmpty ? startingBalance : 0,
        'annualInterestRatePercent': ?annualInterestRatePercent,
        'receivesIncome': receivesIncome,
        'archived': false,
        'sortOrder': nextWalletSortOrder(wallets),
        'purpose': purpose.name,
        'savingsKind': ?savingsKind,
        if (depositStartDate != null)
          'depositStartDate': Timestamp.fromDate(depositStartDate),
        if (maturityDate != null)
          'maturityDate': Timestamp.fromDate(maturityDate),
        'interestPayoutMonths': ?interestPayout?.months,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });

    // A second wallet can't quietly take over as the income wallet.
    if (receivesIncome) {
      _addIncomeWalletUpdates(batch, wallets, reference.id);
    }

    // Money moved in from the user's wallets, as when savings are opened
    // with cash or bank money: transfers in the same batch, so it leaves
    // them as it arrives here, all or nothing, and the total stays the same.
    if (fundedFrom.isNotEmpty) {
      final deltas = <String, double>{};
      fundedFrom.forEach((walletId, amount) {
        if (!amount.isFinite || amount <= 0) return;
        addTransactionToBatch(
          batch,
          type: TransactionType.transfer,
          amount: amount,
          label: TransactionType.transfer.label,
          walletId: walletId,
          toWalletId: reference.id,
          note: 'Moved into ${trimmedName.isEmpty ? type.label : trimmedName}',
          collectDeltasInto: deltas,
        );
      });
      _applyDeltas(batch, deltas);
    }

    commitFirestoreWrite(batch.commit(), 'add wallet');
    return reference.id;
  }

  /// The wallet kept for [purpose], or null when there is none yet.
  static Wallet? walletFor(List<Wallet> wallets, WalletPurpose purpose) {
    for (final wallet in wallets) {
      if (!wallet.archived && wallet.purpose == purpose) return wallet;
    }
    return null;
  }

  /// Renames a wallet or changes its type. The balance is never touched here;
  /// only a transaction may move money.
  static void updateWallet({
    required String walletId,
    String? name,
    WalletType? type,
    bool updateAnnualInterestRate = false,
    double? annualInterestRatePercent,
    bool updateSavingsMetadata = false,
    String? savingsKind,
    DateTime? depositStartDate,
    DateTime? maturityDate,
  }) {
    if (updateSavingsMetadata) {
      _validateSavingsDetails(
        purpose: WalletPurpose.savings,
        savingsKind: savingsKind,
        annualInterestRatePercent: annualInterestRatePercent,
        depositStartDate: depositStartDate,
        maturityDate: maturityDate,
      );
    }
    if (updateAnnualInterestRate &&
        annualInterestRatePercent != null &&
        !isValidAnnualInterestRatePercent(annualInterestRatePercent)) {
      throw ArgumentError.value(
        annualInterestRatePercent,
        'annualInterestRatePercent',
        'Must be between 0 and '
            '${maximumAnnualInterestRatePercent.toInt()}%.',
      );
    }

    final fields = <String, dynamic>{'updatedAt': FieldValue.serverTimestamp()};
    final trimmedName = name?.trim();

    if (trimmedName != null && trimmedName.isNotEmpty) {
      fields['name'] = trimmedName;
    }

    if (type != null) fields['type'] = type.name;
    if (updateAnnualInterestRate) {
      fields['annualInterestRatePercent'] =
          annualInterestRatePercent ?? FieldValue.delete();
    }
    if (updateSavingsMetadata) {
      fields['savingsKind'] = savingsKind ?? FieldValue.delete();
      fields['depositStartDate'] = depositStartDate == null
          ? FieldValue.delete()
          : Timestamp.fromDate(depositStartDate);
      fields['maturityDate'] = maturityDate == null
          ? FieldValue.delete()
          : Timestamp.fromDate(maturityDate);
      if (annualInterestRatePercent == null) {
        fields['annualInterestRatePercent'] = FieldValue.delete();
      } else {
        fields['annualInterestRatePercent'] = annualInterestRatePercent;
      }
    }

    commitFirestoreWrite(
      _walletsCollection.doc(walletId).set(fields, SetOptions(merge: true)),
      'update wallet',
    );
  }

  static void _validateSavingsDetails({
    required WalletPurpose purpose,
    required String? savingsKind,
    required double? annualInterestRatePercent,
    required DateTime? depositStartDate,
    required DateTime? maturityDate,
  }) {
    if (purpose != WalletPurpose.savings || savingsKind == null) return;
    final kind = SavingsKind.fromName(savingsKind);
    if (kind.isInterestBearing) {
      if (!isValidAnnualInterestRatePercent(annualInterestRatePercent)) {
        throw ArgumentError('Interest-bearing savings require a valid rate.');
      }
      if (depositStartDate == null) {
        throw ArgumentError('Interest-bearing savings require a start date.');
      }
    }
    if (kind == SavingsKind.timeDeposit &&
        (depositStartDate == null ||
            maturityDate == null ||
            !maturityDate.isAfter(depositStartDate))) {
      throw ArgumentError(
        'A time deposit maturity date must be after its start date.',
      );
    }
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

  /// Records one expense or income split across wallets: a transaction in
  /// each, with the same category, note and date, in one batch, so it is
  /// never half recorded.
  static void recordSplit({
    required TransactionType type,
    required Map<String, double> amounts,
    required String label,
    String? note,
    DateTime? date,
  }) {
    if (type == TransactionType.transfer) {
      throw ArgumentError('Use recordTransfers for transfers.');
    }
    final batch = _firestore.batch();
    final deltas = <String, double>{};
    for (final entry in amounts.entries) {
      if (entry.value <= 0) continue;
      addTransactionToBatch(
        batch,
        type: type,
        amount: entry.value,
        label: label,
        walletId: entry.key,
        note: note,
        date: date,
        collectDeltasInto: deltas,
      );
    }
    _applyDeltas(batch, deltas);
    commitFirestoreWrite(batch.commit(), 'record ${type.name}');
  }

  /// Records multiple expenses in one Firestore batch. Each entry keeps its
  /// own category and description while sharing the selected wallet.
  static void recordExpenseBatch({
    required List<ExpenseBatchEntry> expenses,
    String? walletId,
    DateTime? date,
  }) {
    if (expenses.isEmpty) {
      throw ArgumentError('An expense batch cannot be empty.');
    }

    final batch = _firestore.batch();
    final deltas = <String, double>{};
    for (final expense in expenses) {
      addTransactionToBatch(
        batch,
        type: TransactionType.expense,
        amount: expense.amount,
        label: expense.label,
        walletId: expense.walletId ?? walletId,
        note: expense.note,
        date: date,
        collectDeltasInto: deltas,
      );
    }
    _applyDeltas(batch, deltas);
    commitFirestoreWrite(batch.commit(), 'record expense batch');
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

    final snapshot = await _transactionsCollection.doc(id).get();
    final previous = snapshot.exists
        ? AppTransaction.fromMap(snapshot.id, snapshot.data())
        : null;
    if (previous?.type == TransactionType.expense) {
      throw StateError('Recorded expenses cannot be edited.');
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
      previous: previous,
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

  /// Adds what a bank or e-wallet charged, as a Service Charge expense from
  /// [walletId], to [batch]. Nothing when [amount] is zero: a charge is only
  /// recorded when the user says there was one.
  ///
  /// It is an expense of its own, apart from the money moved or the bill
  /// paid, so it is counted with the rest of the spending.
  static void addServiceChargeToBatch(
    WriteBatch batch, {
    required String walletId,
    required double amount,
    required String note,
    DateTime? date,
    Map<String, double>? collectDeltasInto,
  }) {
    if (!amount.isFinite || amount <= 0) return;
    addTransactionToBatch(
      batch,
      type: TransactionType.expense,
      amount: amount,
      label: serviceChargeCategory,
      walletId: walletId,
      note: note,
      date: date,
      collectDeltasInto: collectDeltasInto,
    );
  }

  /// [rememberServiceCharge], in a batch being written anyway.
  static void rememberServiceChargeInBatch(
    WriteBatch batch,
    String walletId,
    double amount,
  ) {
    if (!amount.isFinite || amount <= 0) return;
    batch.set(_walletsCollection.doc(walletId), {
      'serviceCharge': amount,
    }, SetOptions(merge: true));
  }

  /// Keeps [amount] as [walletId]'s service charge, to fill in next time.
  static void rememberServiceCharge(String walletId, double amount) {
    if (!amount.isFinite || amount <= 0) return;
    commitFirestoreWrite(
      _walletsCollection.doc(walletId).set({
        'serviceCharge': amount,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true)),
      'remember service charge',
    );
  }

  /// Moves money from one wallet into one or more others: a transfer for
  /// each, and the [serviceCharge] once, all in one batch so the money is
  /// never half moved. Each wallet's balance changes once.
  static void recordTransfers({
    required String fromWalletId,
    required Map<String, double> to,
    String? note,
    DateTime? date,
    double serviceCharge = 0,
  }) {
    if (to.containsKey(fromWalletId)) {
      throw ArgumentError('A transfer needs two different wallets.');
    }

    final batch = _firestore.batch();
    final deltas = <String, double>{};
    for (final entry in to.entries) {
      if (entry.value <= 0) continue;
      addTransactionToBatch(
        batch,
        type: TransactionType.transfer,
        amount: entry.value,
        label: TransactionType.transfer.label,
        walletId: fromWalletId,
        toWalletId: entry.key,
        note: note,
        date: date,
        collectDeltasInto: deltas,
      );
    }
    addServiceChargeToBatch(
      batch,
      walletId: fromWalletId,
      amount: serviceCharge,
      note: 'For a transfer',
      date: date,
      collectDeltasInto: deltas,
    );
    _applyDeltas(batch, deltas);
    commitFirestoreWrite(batch.commit(), 'record transfer');
  }

  /// Moves money between two wallets: one transaction, two balance changes,
  /// one batch. Returns the new transaction's id.
  static String recordTransfer({
    required String fromWalletId,
    required String toWalletId,
    required double amount,
    String? note,
    DateTime? date,
    double serviceCharge = 0,
  }) {
    if (fromWalletId == toWalletId) {
      throw ArgumentError('A transfer needs two different wallets.');
    }

    // With a service charge, the transfer and the charge go in one batch:
    // both or neither, and one balance change per wallet.
    if (serviceCharge > 0) {
      final batch = _firestore.batch();
      final deltas = <String, double>{};
      final id = addTransactionToBatch(
        batch,
        type: TransactionType.transfer,
        amount: amount,
        label: TransactionType.transfer.label,
        walletId: fromWalletId,
        toWalletId: toWalletId,
        note: note,
        date: date,
        collectDeltasInto: deltas,
      );
      addServiceChargeToBatch(
        batch,
        walletId: fromWalletId,
        amount: serviceCharge,
        note: 'For a transfer',
        date: date,
        collectDeltasInto: deltas,
      );
      _applyDeltas(batch, deltas);
      commitFirestoreWrite(batch.commit(), 'record transfer');
      return id;
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

  /// Fixes a balance the user declared wrongly, such as a typo at sign up.
  ///
  /// The money never existed, so this is neither income nor spending. The
  /// starting figure and the balance both move by the difference, which
  /// leaves reports untouched.
  static void correctDeclaredBalance({
    required Wallet wallet,
    required double recorded,
  }) {
    if (!recorded.isFinite || recorded < 0) {
      throw ArgumentError.value(recorded, 'recorded', 'Cannot be negative.');
    }
    // Rounded to centavos, so a long decimal cannot leave a stray fraction.
    final delta = ((recorded - wallet.balance) * 100).round() / 100;
    final fields = <String, dynamic>{
      'balanceRecorded': true,
      'updatedAt': FieldValue.serverTimestamp(),
    };
    if (delta != 0) {
      fields['balance'] = FieldValue.increment(delta);
      fields['startingBalance'] = FieldValue.increment(delta);
    }
    commitFirestoreWrite(
      _walletsCollection.doc(wallet.id).set(fields, SetOptions(merge: true)),
      'correct declared balance',
    );
  }

  /// Records what the user did with a matured time deposit or government
  /// savings.
  ///
  /// [received] is what they say came back, which is often more than the
  /// recorded balance because of interest or dividends. The difference is
  /// written as income so reports stay honest, then the whole amount moves to
  /// [toWalletId]. Taking only part of it leaves the rest where it is.
  ///
  /// Nothing happens to a real account; this only records what the user says
  /// already happened.
  ///
  /// Goal money in [wallet] goes with it to [toWalletId], up to what was
  /// taken out, so a goal saved in a time deposit stays set aside once the
  /// deposit is paid out.
  static void settleMatured({
    required Wallet wallet,
    required double received,
    required Map<String, double> to,
    DateTime? date,
    List<Goal> goals = const [],
  }) {
    if (!received.isFinite || received <= 0) {
      throw ArgumentError.value(
        received,
        'received',
        'Must be more than zero.',
      );
    }
    if (to.containsKey(wallet.id)) {
      throw ArgumentError('Choose a different wallet to move it into.');
    }
    final into = {
      for (final entry in to.entries)
        if (entry.value > 0) entry.key: (entry.value * 100).round(),
    };
    if (into.values.fold<int>(0, (total, cents) => total + cents) !=
        (received * 100).round()) {
      throw ArgumentError('Where it went must add up to what came back.');
    }

    final when = date ?? DateTime.now();
    final batch = FirebaseFirestore.instance.batch();
    final deltas = <String, double>{};
    // Rounded to centavos, so a long decimal cannot leave a few stray
    // thousandths behind in the record.
    final taken = (received * 100).round() / 100;
    final balance = (wallet.balance * 100).round() / 100;
    final interest = taken > balance ? taken - balance : 0.0;

    if (interest > 0) {
      // Interest is new money, so it is income, not a transfer.
      addTransactionToBatch(
        batch,
        type: TransactionType.income,
        amount: interest,
        label: interestIncomeLabel,
        walletId: wallet.id,
        note: 'Interest on ${wallet.name}',
        date: when,
        collectDeltasInto: deltas,
      );
    }

    for (final entry in into.entries) {
      addTransactionToBatch(
        batch,
        type: TransactionType.transfer,
        amount: entry.value / 100,
        label: TransactionType.transfer.label,
        walletId: wallet.id,
        toWalletId: entry.key,
        note: '${wallet.name} matured',
        date: when,
        collectDeltasInto: deltas,
      );
    }

    applyDeltasToBatch(batch, deltas);

    // Goal money goes with it, still set aside: into the wallets it went
    // to, in turn, never more than went into each.
    final room = {...into};
    goalMoneyMoving(goals, from: wallet.id, moved: taken).forEach((
      goal,
      amount,
    ) {
      var left = (amount * 100).round();
      var running = goal;
      for (final destination in room.keys.toList()) {
        if (left <= 0) break;
        final space = room[destination]!;
        if (space <= 0) continue;
        final part = left < space ? left : space;
        GoalService.moveMoneyInBatch(
          batch,
          running,
          from: wallet.id,
          to: destination,
          amount: part / 100,
        );
        // The next move counts from where this one leaves the goal.
        running = running
            .withContribution(wallet.id, -part / 100)
            .withContribution(destination, part / 100);
        room[destination] = space - part;
        left -= part;
      }
    });

    // Whatever is left keeps its own maturity until the user says otherwise;
    // an emptied record has nothing left to come due.
    if (taken >= balance) {
      batch.set(_walletsCollection.doc(wallet.id), {
        'maturityDate': FieldValue.delete(),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    }

    commitFirestoreWrite(batch.commit(), 'settle matured savings');
  }

  /// Records interest the user says [wallet] was paid, as income into that
  /// account. FinAssist cannot see a real account, so this is only ever
  /// what the user enters, never an estimate added by itself.
  static void recordInterest({
    required Wallet wallet,
    required double amount,
    DateTime? date,
  }) {
    final batch = FirebaseFirestore.instance.batch();
    final deltas = <String, double>{};
    addTransactionToBatch(
      batch,
      type: TransactionType.income,
      amount: amount,
      label: interestIncomeLabel,
      walletId: wallet.id,
      note: 'Interest from ${wallet.name}',
      date: date ?? DateTime.now(),
      collectDeltasInto: deltas,
    );
    applyDeltasToBatch(batch, deltas);
    commitFirestoreWrite(batch.commit(), 'record interest');
  }

  /// Saves how often [wallet] pays its interest, for its reminders.
  static void setInterestPayout(Wallet wallet, InterestPayout payout) {
    commitFirestoreWrite(
      _walletsCollection.doc(wallet.id).set({
        // Months between payments, 0 for every day. Any older named one is
        // still read, but this number wins.
        'interestPayoutMonths': payout.months,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true)),
      'set interest payout',
    );
  }

  /// Pushes a matured record's date forward, for a deposit that rolled over.
  ///
  /// [interest] the bank added on renewal is income, kept in the same deposit.
  /// The new term starts where the old one ended, so its interest is counted
  /// from there and not twice.
  static void rollOverMaturity(
    Wallet wallet,
    DateTime nextDate, {
    double interest = 0,
  }) {
    final batch = FirebaseFirestore.instance.batch();
    if (interest > 0) {
      final deltas = <String, double>{};
      addTransactionToBatch(
        batch,
        type: TransactionType.income,
        amount: interest,
        label: interestIncomeLabel,
        walletId: wallet.id,
        note: 'Interest on ${wallet.name}',
        date: DateTime.now(),
        collectDeltasInto: deltas,
      );
      applyDeltasToBatch(batch, deltas);
    }
    batch.set(_walletsCollection.doc(wallet.id), {
      'maturityDate': Timestamp.fromDate(nextDate),
      if (wallet.maturityDate != null)
        'depositStartDate': Timestamp.fromDate(wallet.maturityDate!),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    commitFirestoreWrite(batch.commit(), 'roll over maturity');
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
    String? debtId,
    double interest = 0,
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
      'debtId': debtId,
      if (interest > 0) 'interest': interest,
      'createdAt': FieldValue.serverTimestamp(),
    });

    final deltas = collectDeltasInto ?? <String, double>{};
    if (previous != null) _collectDeltas(deltas, previous, reverse: true);
    _collectDeltas(deltas, transaction, reverse: false);

    // A caller gathering several transactions applies the total itself.
    if (collectDeltasInto == null) _applyDeltas(batch, deltas);

    return reference.id;
  }

  /// Marks how much of a payment already made was interest. Only that one
  /// field changes; the amount and the balance stay as they were.
  static void setInterestInBatch(
    WriteBatch batch,
    String transactionId,
    double interest,
  ) {
    batch.set(_transactionsCollection.doc(transactionId), {
      'interest': interest,
    }, SetOptions(merge: true));
  }

  /// Writes balance changes gathered with `collectDeltasInto`, one write per
  /// wallet.
  static void applyDeltasToBatch(WriteBatch batch, Map<String, double> deltas) {
    _applyDeltas(batch, deltas);
  }

  /// Adds the removal of [transaction], and the balance it gives back, to
  /// [batch]. Used by bill and debt workflows that must update related records
  /// together with their transaction.
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
