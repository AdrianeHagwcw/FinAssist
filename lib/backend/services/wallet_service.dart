import 'dart:async';
import 'dart:convert';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/app_transaction.dart';
import '../models/goal.dart';
import '../models/transfer_direction.dart';
import '../models/wallet.dart';
import '../utils/unique_name.dart';
import '../utils/text_limits.dart';
import '../utils/ph_time.dart';
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

/// One time deposit whose maturity interest is still to be written as income.
///
/// The [entryId] is fixed per deposit, so planning again or retrying after an
/// offline load writes the same entry rather than a second one.
class TimeDepositInterest {
  const TimeDepositInterest({
    required this.wallet,
    required this.interest,
    required this.date,
  });

  final Wallet wallet;
  final double interest;

  /// The maturity date, which is the day the interest was earned.
  final DateTime date;

  String get entryId => 'td-interest-${wallet.id}';
}

enum TimeDepositSettlementStatus { completed, queued, alreadyHandled }

class TimeDepositSettlementResult {
  const TimeDepositSettlementResult(this.status, {this.renewedWalletId});

  final TimeDepositSettlementStatus status;
  final String? renewedWalletId;

  bool get accepted => status != TimeDepositSettlementStatus.alreadyHandled;
}

class TimeDepositSettlementUpdate {
  const TimeDepositSettlementUpdate({
    required this.walletId,
    required this.status,
  });

  final String walletId;
  final TimeDepositSettlementStatus status;
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
  static const _pendingTimeDepositPrefix = 'finassist:td-settlement:';
  static final StreamController<TimeDepositSettlementUpdate>
  _timeDepositSettlementUpdates =
      StreamController<TimeDepositSettlementUpdate>.broadcast();

  static Stream<TimeDepositSettlementUpdate> get timeDepositSettlementUpdates =>
      _timeDepositSettlementUpdates.stream;

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
    final isTimeDeposit =
        purpose == WalletPurpose.savings &&
        savingsKind == SavingsKind.timeDeposit.name;
    final fundingSources = isTimeDeposit
        ? _roundedAmounts(fundedFrom)
        : fundedFrom;
    if (isTimeDeposit &&
        fundedFrom.values.any((amount) => !amount.isFinite || amount < 0)) {
      throw ArgumentError('Funding amounts must be nonnegative.');
    }
    final rawPlaced = fundingSources.isEmpty
        ? startingBalance
        : fundingSources.values
              .where((amount) => amount.isFinite && amount > 0)
              .fold<double>(0, (total, amount) => total + amount);
    final placed = isTimeDeposit ? (rawPlaced * 100).round() / 100 : rawPlaced;
    if (isTimeDeposit && (!placed.isFinite || placed <= 0)) {
      throw ArgumentError('A time deposit needs an opening amount.');
    }
    if (fundingSources.isNotEmpty) {
      final newWallet = Wallet(
        id: reference.id,
        name: trimmedName,
        type: type,
        balance: 0,
        startingBalance: 0,
        receivesIncome: false,
        archived: false,
        sortOrder: 0,
        purpose: purpose,
        savingsKind: savingsKind,
        depositStartDate: depositStartDate,
        maturityDate: maturityDate,
        principal: isTimeDeposit ? placed : null,
      );
      for (final entry in fundingSources.entries) {
        if (!entry.value.isFinite || entry.value <= 0) continue;
        final source = wallets
            .where((wallet) => wallet.id == entry.key)
            .firstOrNull;
        if (source == null) {
          throw ArgumentError('Choose an existing wallet to fund the deposit.');
        }
        if (!source.hasRecordedBalance) {
          throw ArgumentError('Choose a wallet with a recorded balance.');
        }
        if (entry.value > source.balance + 0.005) {
          throw ArgumentError(
            'A funding amount is more than its wallet holds.',
          );
        }
        final rule = transferRuleBetween(
          from: source,
          to: newWallet,
          openingDeposit: isTimeDeposit,
        );
        if (!rule.allowed) throw ArgumentError(rule.reason);
      }
    }

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
        'balance': fundingSources.isEmpty ? placed : 0,
        'balanceRecorded': balanceRecorded,
        'startingBalance': fundingSources.isEmpty ? placed : 0,
        'annualInterestRatePercent': ?annualInterestRatePercent,
        'receivesIncome': receivesIncome,
        'archived': false,
        'sortOrder': nextWalletSortOrder(wallets),
        'purpose': purpose.name,
        'savingsKind': ?savingsKind,
        if (depositStartDate != null)
          'depositStartDate': Timestamp.fromDate(
            isTimeDeposit
                ? philippineDayStart(depositStartDate)
                : depositStartDate,
          ),
        if (maturityDate != null)
          'maturityDate': Timestamp.fromDate(
            isTimeDeposit ? philippineDayStart(maturityDate) : maturityDate,
          ),
        if (isTimeDeposit) 'principal': placed,
        if (isTimeDeposit) 'maturityInterestRecorded': false,
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
    if (fundingSources.isNotEmpty) {
      final deltas = <String, double>{};
      fundingSources.forEach((walletId, amount) {
        if (!amount.isFinite || amount <= 0) return;
        final source = wallets
            .where((wallet) => wallet.id == walletId)
            .firstOrNull;
        // Opening a time deposit is the one moment money may enter it. Cash
        // and e-wallets read as a deposit; a bank or another savings record
        // reads as a transfer.
        final label = isTimeDeposit && source != null
            ? TransferDirection.betweenWallets(
                from: source,
                to: Wallet(
                  id: reference.id,
                  name: trimmedName,
                  type: type,
                  balance: 0,
                  startingBalance: 0,
                  receivesIncome: false,
                  archived: false,
                  sortOrder: 0,
                  purpose: purpose,
                  savingsKind: savingsKind,
                ),
                openingDeposit: true,
              ).label
            : TransactionType.transfer.label;
        addTransactionToBatch(
          batch,
          type: TransactionType.transfer,
          amount: amount,
          label: label,
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
    Wallet? currentWallet,
  }) {
    if (updateSavingsMetadata) {
      if (currentWallet == null) {
        throw ArgumentError('Include the wallet being updated.');
      }
      if (savingsKind == SavingsKind.timeDeposit.name &&
          !currentWallet.isTimeDeposit) {
        throw ArgumentError(
          'Open a new time deposit instead of converting one.',
        );
      }
      if (currentWallet.isTimeDeposit &&
          (savingsKind != currentWallet.savingsKind ||
              (currentWallet.annualInterestRatePercent != null &&
                  annualInterestRatePercent !=
                      currentWallet.annualInterestRatePercent) ||
              (currentWallet.depositStartDate != null &&
                  !_sameCalendarDate(
                    depositStartDate,
                    currentWallet.depositStartDate,
                  )) ||
              (currentWallet.maturityDate != null &&
                  !_sameCalendarDate(
                    maturityDate,
                    currentWallet.maturityDate,
                  )))) {
        throw ArgumentError(
          'A time deposit’s terms are fixed after it is opened.',
        );
      }
      _validateSavingsDetails(
        purpose: WalletPurpose.savings,
        savingsKind: savingsKind,
        annualInterestRatePercent: annualInterestRatePercent,
        depositStartDate: depositStartDate,
        maturityDate: maturityDate,
      );
    }
    if (currentWallet?.isTimeDeposit == true &&
        type != null &&
        type != currentWallet!.type) {
      throw ArgumentError('A time deposit type cannot be changed.');
    }
    if (currentWallet?.isTimeDeposit == true &&
        updateAnnualInterestRate &&
        annualInterestRatePercent != currentWallet!.annualInterestRatePercent) {
      throw ArgumentError('A time deposit rate is fixed when it is opened.');
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
          : Timestamp.fromDate(
              savingsKind == SavingsKind.timeDeposit.name
                  ? philippineDayStart(depositStartDate)
                  : depositStartDate,
            );
      fields['maturityDate'] = maturityDate == null
          ? FieldValue.delete()
          : Timestamp.fromDate(
              savingsKind == SavingsKind.timeDeposit.name
                  ? philippineDayStart(maturityDate)
                  : maturityDate,
            );
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

  static bool _sameCalendarDate(DateTime? left, DateTime? right) => left == null
      ? right == null
      : right != null &&
            left.year == right.year &&
            left.month == right.month &&
            left.day == right.day;

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
    List<Wallet> wallets = const [],
  }) {
    if (type == TransactionType.transfer) {
      throw ArgumentError('Use recordTransfer for transfers.');
    }
    if (walletId != null) {
      _checkOrdinaryTransactionWallets(walletIds: [walletId], wallets: wallets);
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
    List<Wallet> wallets = const [],
  }) {
    if (type == TransactionType.transfer) {
      throw ArgumentError('Use recordTransfers for transfers.');
    }
    _checkOrdinaryTransactionWallets(walletIds: amounts.keys, wallets: wallets);
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
    List<Wallet> wallets = const [],
  }) {
    if (expenses.isEmpty) {
      throw ArgumentError('An expense batch cannot be empty.');
    }
    _checkOrdinaryTransactionWallets(
      walletIds: [
        for (final expense in expenses) expense.walletId ?? walletId,
      ].whereType<String>(),
      wallets: wallets,
    );

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

  /// Rejects a move the central matrix does not allow, when the caller gave
  /// the wallet list it is working from. Screens pass it; older call sites
  /// keep working without it.
  static void _checkTransferRules({
    required String fromWalletId,
    required Iterable<String> toWalletIds,
    required List<Wallet> wallets,
  }) {
    if (wallets.isEmpty) return;
    final byId = {for (final wallet in wallets) wallet.id: wallet};
    final from = byId[fromWalletId];
    if (from == null) return;
    for (final toId in toWalletIds) {
      final to = byId[toId];
      if (to == null) continue;
      final rule = transferRuleBetween(from: from, to: to);
      if (!rule.allowed) throw ArgumentError(rule.reason);
    }
  }

  static void _checkOrdinaryTransactionWallets({
    required Iterable<String> walletIds,
    required List<Wallet> wallets,
  }) {
    if (wallets.isEmpty) return;
    final byId = {for (final wallet in wallets) wallet.id: wallet};
    for (final walletId in walletIds) {
      if (byId[walletId]?.isTimeDeposit ?? false) {
        throw ArgumentError(
          'A time deposit only moves through its maturity claim or renewal.',
        );
      }
    }
  }

  static String _transferLabelForIds({
    required String fromWalletId,
    required String toWalletId,
    required List<Wallet> wallets,
  }) {
    final from = wallets
        .where((wallet) => wallet.id == fromWalletId)
        .firstOrNull;
    final to = wallets.where((wallet) => wallet.id == toWalletId).firstOrNull;
    if (from == null || to == null) return TransactionType.transfer.label;
    return transferRuleBetween(from: from, to: to).label;
  }

  static void _checkMaturedTimeDepositDestinations({
    required Wallet timeDeposit,
    required Map<String, double> amounts,
    required List<Wallet> wallets,
    required DateTime now,
  }) {
    final byId = {for (final wallet in wallets) wallet.id: wallet};
    for (final entry in amounts.entries) {
      if (entry.value <= 0) continue;
      final destination = byId[entry.key];
      if (destination == null) {
        throw ArgumentError('Choose an existing wallet for the money.');
      }
      final rule = transferRuleBetween(
        from: timeDeposit,
        to: destination,
        now: now,
      );
      if (!rule.allowed) throw ArgumentError(rule.reason);
    }
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
    List<Wallet> wallets = const [],
  }) {
    if (to.containsKey(fromWalletId)) {
      throw ArgumentError('A transfer needs two different wallets.');
    }
    _checkTransferRules(
      fromWalletId: fromWalletId,
      toWalletIds: to.keys,
      wallets: wallets,
    );

    final batch = _firestore.batch();
    final deltas = <String, double>{};
    for (final entry in to.entries) {
      if (entry.value <= 0) continue;
      addTransactionToBatch(
        batch,
        type: TransactionType.transfer,
        amount: entry.value,
        label: _transferLabelForIds(
          fromWalletId: fromWalletId,
          toWalletId: entry.key,
          wallets: wallets,
        ),
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

  /// Transfers money from an interest-bearing savings deposit, writing down
  /// the unrecorded simple interest as income first.
  ///
  /// The transfer itself stays a transfer; the interest is separate income.
  static void recordSavingsDepositTransfer({
    required Wallet wallet,
    required Map<String, double> to,
    double serviceCharge = 0,
    DateTime? date,
    required Iterable<AppTransaction> transactions,
  }) {
    if (wallet.purpose != WalletPurpose.savings ||
        wallet.savingsType != SavingsKind.savingsDeposit) {
      throw ArgumentError.value(
        wallet.id,
        'wallet',
        'Must be a savings deposit.',
      );
    }
    if (!serviceCharge.isFinite || serviceCharge < 0) {
      throw ArgumentError.value(
        serviceCharge,
        'serviceCharge',
        'Must be a nonnegative amount.',
      );
    }
    if (to.containsKey(wallet.id)) {
      throw ArgumentError('A transfer needs two different wallets.');
    }
    if (to.values.any((amount) => !amount.isFinite || amount < 0)) {
      throw ArgumentError('Transfer amounts must be finite and nonnegative.');
    }
    final transfers = {
      for (final entry in to.entries)
        if (entry.value > 0) entry.key: (entry.value * 100).round() / 100,
    };
    if (transfers.values.fold<double>(0, (total, amount) => total + amount) <=
        0) {
      throw ArgumentError('Enter an amount to transfer.');
    }

    final when = date ?? DateTime.now();
    final amount = transfers.values.fold<double>(
      0,
      (total, transfer) => total + transfer,
    );
    final taken = ((amount + serviceCharge) * 100).round() / 100;
    final recordedBalance = (wallet.balance * 100).round() / 100;

    // The simple-interest estimate is the amount recorded. Do not apply a
    // separate tax adjustment to it here.
    final accrued = wallet.estimatedUnrecordedSavingsDepositInterest(
      transactions: transactions,
      asOf: when,
    );
    final interest = accrued == null ? 0.0 : (accrued * 100).round() / 100;

    if (taken > recordedBalance + interest + 0.005) {
      throw ArgumentError.value(
        taken,
        'to',
        'More than the balance and interest in the savings deposit.',
      );
    }

    final batch = _firestore.batch();
    final deltas = <String, double>{};

    if (interest > 0.005) {
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
    for (final entry in transfers.entries) {
      addTransactionToBatch(
        batch,
        type: TransactionType.transfer,
        amount: entry.value,
        label: TransactionType.transfer.label,
        walletId: wallet.id,
        toWalletId: entry.key,
        date: when,
        collectDeltasInto: deltas,
      );
    }
    addServiceChargeToBatch(
      batch,
      walletId: wallet.id,
      amount: serviceCharge,
      note: 'For a transfer',
      date: when,
      collectDeltasInto: deltas,
    );
    _applyDeltas(batch, deltas);
    commitFirestoreWrite(batch.commit(), 'transfer from savings deposit');
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
    List<Wallet> wallets = const [],
  }) {
    if (fromWalletId == toWalletId) {
      throw ArgumentError('A transfer needs two different wallets.');
    }
    _checkTransferRules(
      fromWalletId: fromWalletId,
      toWalletIds: [toWalletId],
      wallets: wallets,
    );

    // With a service charge, the transfer and the charge go in one batch:
    // both or neither, and one balance change per wallet.
    if (serviceCharge > 0) {
      final batch = _firestore.batch();
      final deltas = <String, double>{};
      final id = addTransactionToBatch(
        batch,
        type: TransactionType.transfer,
        amount: amount,
        label: _transferLabelForIds(
          fromWalletId: fromWalletId,
          toWalletId: toWalletId,
          wallets: wallets,
        ),
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
      label: _transferLabelForIds(
        fromWalletId: fromWalletId,
        toWalletId: toWalletId,
        wallets: wallets,
      ),
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
    if (wallet.isTimeDeposit &&
        ((recorded - wallet.balance) * 100).round() != 0) {
      throw ArgumentError('A time deposit balance is locked after opening.');
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
    if (wallet.isTimeDeposit) {
      throw ArgumentError(
        'Use the full claim or renewal flow for a time deposit.',
      );
    }
    _settleSavings(
      wallet: wallet,
      received: received,
      to: to,
      date: date,
      goals: goals,
      transferNote: '${wallet.name} matured',
      clearMaturityWhenEmpty: true,
      action: 'settle matured savings',
    );
  }

  /// Claims already being written in this session, so a double tap cannot
  /// write the same capital and interest twice.
  static final Set<String> _claimsInFlight = <String>{};
  static final Set<String> _maturityInterestInFlight = <String>{};

  /// The matured time deposits whose interest has not been written down yet.
  ///
  /// Kept pure so the once-only rule can be checked without a database: a
  /// record with [Wallet.maturityInterestRecorded] set is left out, and the
  /// fixed [TimeDepositInterest.entryId] makes a second write the same entry.
  static List<TimeDepositInterest> pendingTimeDepositInterest(
    List<Wallet> wallets, {
    DateTime? now,
  }) {
    final when = now ?? DateTime.now();
    return [
      for (final wallet in wallets)
        if (wallet.timeDepositStatusAt(when) == TimeDepositStatus.matured &&
            !wallet.maturityInterestRecorded)
          TimeDepositInterest(
            wallet: wallet,
            interest: _timeDepositInterestOf(wallet) > 0
                ? _timeDepositInterestOf(wallet)
                : (wallet.timeDepositMaturityInterest * 100).round() / 100,
            date: wallet.maturityDate == null
                ? when
                : philippineDayStart(wallet.maturityDate!),
          ),
    ];
  }

  /// Writes down the interest a time deposit earned at maturity, once.
  ///
  /// Call on every app load. The stored [Wallet.maturityInterestRecorded]
  /// flag and a fixed transaction id make a second run a no-op, even when
  /// the phone was offline on the maturity day. Interest is dated the
  /// maturity date, not the day it was written, and is income; the original
  /// money is never income.
  static void syncTimeDepositMaturities({
    required List<Wallet> wallets,
    DateTime? now,
  }) {
    final when = now ?? DateTime.now();
    for (final pending in pendingTimeDepositInterest(wallets, now: when)) {
      final wallet = pending.wallet;
      final interest = pending.interest;
      if (!_maturityInterestInFlight.add(wallet.id)) continue;
      final write = _syncMaturityInterest(
        wallet,
        interest,
        now: when,
      ).whenComplete(() => _maturityInterestInFlight.remove(wallet.id));
      commitFirestoreWrite(write, 'record time deposit interest');
    }
  }

  /// Records one deposit's maturity income inside a server transaction. A
  /// batch is atomic but can still be queued twice by two offline devices;
  /// checking the stored flag in a transaction prevents both queued syncs from
  /// incrementing the balance after they reconnect.
  static Future<void> _syncMaturityInterest(
    Wallet candidate,
    double fallbackInterest, {
    required DateTime now,
  }) async {
    final walletReference = _walletsCollection.doc(candidate.id);
    await _firestore.runTransaction<void>((transaction) async {
      final snapshot = await transaction.get(walletReference);
      if (!snapshot.exists) return;
      final wallet = Wallet.fromMap(snapshot.id, snapshot.data());
      if (wallet.timeDepositStatusAt(now) != TimeDepositStatus.matured ||
          wallet.maturityInterestRecorded) {
        return;
      }

      final interestReference = _transactionsCollection.doc(
        'td-interest-${wallet.id}',
      );
      final previousIncome = await transaction.get(interestReference);
      if (previousIncome.exists) {
        transaction.set(walletReference, {
          'principal': wallet.timeDepositPrincipal,
          'maturityInterestRecorded': true,
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
        return;
      }

      final recorded = _timeDepositInterestOf(wallet);
      final interest = recorded > 0 ? recorded : fallbackInterest;
      final deltas = <String, double>{};
      _recordMaturityInterestInTransaction(
        transaction,
        deltas,
        wallet: wallet,
        interest: interest,
      );
      transaction.set(walletReference, {
        'principal': wallet.timeDepositPrincipal,
        'maturityInterestRecorded': true,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      _applyDeltasToTransaction(transaction, deltas);
    });
  }

  /// Runs [syncTimeDepositMaturities] against the signed-in user's wallets.
  /// Never throws: it is a background tidy-up, not a blocking load.
  static Future<void> syncLoadedTimeDeposits() async {
    try {
      final wallets = await loadWallets();
      syncTimeDepositMaturities(wallets: wallets);
    } catch (_) {
      // Offline with nothing cached: the next load tries again.
    }
  }

  /// Replays locally saved maturity actions after connectivity returns.
  /// Each action carries a stable id; a transaction that committed just before
  /// a lost connection is recognized as the same action and is not repeated.
  static Future<void> syncPendingTimeDepositSettlements() async {
    if (_pendingSettlementSyncInFlight || !await _deviceHasConnection()) return;
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    _pendingSettlementSyncInFlight = true;
    try {
      final preferences = await SharedPreferences.getInstance();
      final prefix = '$_pendingTimeDepositPrefix${user.uid}:';
      final keys = preferences
          .getKeys()
          .where((key) => key.startsWith(prefix))
          .toList();
      if (keys.isEmpty) return;

      for (final key in keys) {
        final saved = preferences.getString(key);
        if (saved == null) continue;
        final action = Map<String, dynamic>.from(jsonDecode(saved) as Map);
        final walletId = action['walletId'] as String?;
        final wallets = await loadWallets();
        final wallet = wallets.where((item) => item.id == walletId).firstOrNull;
        if (wallet == null || walletId == null) continue;
        final goals = await GoalService.loadGoals();

        final actionId = action['actionId'] as String;
        final date = DateTime.parse(action['when'] as String);
        TimeDepositSettlementResult result;
        if (action['type'] == 'claim') {
          result = await claimTimeDeposit(
            wallet: wallet,
            capitalTo: _mapAmounts(action['capitalTo']),
            interestTo: _mapAmounts(action['interestTo']),
            capitalAmount: (action['principal'] as num).toDouble(),
            interestAmount: (action['interest'] as num).toDouble(),
            date: date,
            goals: goals,
            wallets: wallets,
            requestId: actionId,
            queueIfOffline: false,
          );
        } else {
          result = await renewTimeDeposit(
            wallet: wallet,
            maturityDate: DateTime.parse(action['maturityDate'] as String),
            annualInterestRatePercent: (action['rate'] as num).toDouble(),
            interestAmount: (action['interest'] as num).toDouble(),
            includeInterest: action['includeInterest'] == true,
            interestTo: _mapAmounts(action['interestTo']),
            date: date,
            goals: goals,
            currentWallets: wallets,
            requestId: actionId,
            queueIfOffline: false,
          );
        }

        if (result.status == TimeDepositSettlementStatus.queued) continue;
        await preferences.remove(key);
        _timeDepositSettlementUpdates.add(
          TimeDepositSettlementUpdate(
            walletId: wallet.id,
            status: result.status,
          ),
        );
      }
    } catch (_) {
      // Keep the saved intent and retry the next time the app is resumed.
    } finally {
      _pendingSettlementSyncInFlight = false;
    }
  }

  static bool _pendingSettlementSyncInFlight = false;

  static String _pendingSettlementKey(String uid, String walletId) =>
      '$_pendingTimeDepositPrefix$uid:$walletId';

  static String _newTimeDepositActionId(String walletId) =>
      'td-action-$walletId-${DateTime.now().microsecondsSinceEpoch}';

  static Future<bool> _deviceHasConnection() async {
    try {
      return (await Connectivity().checkConnectivity()).any(
        (result) => result != ConnectivityResult.none,
      );
    } catch (_) {
      // The Firestore request below will identify a true network failure.
      return true;
    }
  }

  static bool _isOfflineFirestoreError(FirebaseException error) => const {
    'unavailable',
    'deadline-exceeded',
    'network-request-failed',
  }.contains(error.code);

  static Future<bool> _hasPendingTimeDepositAction(String walletId) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return false;
    final preferences = await SharedPreferences.getInstance();
    return preferences.containsKey(_pendingSettlementKey(user.uid, walletId));
  }

  static Future<TimeDepositSettlementResult> _queueTimeDepositAction(
    String walletId,
    Map<String, Object?> action,
  ) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) throw StateError('No authenticated user.');
    final preferences = await SharedPreferences.getInstance();
    final key = _pendingSettlementKey(user.uid, walletId);
    if (!preferences.containsKey(key)) {
      await preferences.setString(key, jsonEncode(action));
    }
    return const TimeDepositSettlementResult(
      TimeDepositSettlementStatus.queued,
    );
  }

  static Map<String, double> _mapAmounts(Object? raw) {
    if (raw is! Map) return const {};
    return {
      for (final entry in raw.entries)
        if (entry.key is String && entry.value is num)
          entry.key as String: (entry.value as num).toDouble(),
    };
  }

  /// Takes a matured time deposit out: its original money and its interest
  /// go to the chosen wallets.
  ///
  /// The interest was already written as income when the deposit matured, so
  /// this only moves money; it never counts the same interest twice.
  /// Returns [TimeDepositSettlementStatus.queued] when the device is offline;
  /// the action is saved locally and replayed once connectivity returns.
  static Future<TimeDepositSettlementResult> claimTimeDeposit({
    required Wallet wallet,
    required Map<String, double> capitalTo,
    Map<String, double> interestTo = const {},
    double? capitalAmount,
    double? interestAmount,
    DateTime? date,
    List<Goal> goals = const [],
    List<Wallet> wallets = const [],
    String? requestId,
    bool queueIfOffline = true,
  }) async {
    final when = date ?? DateTime.now();
    if (!wallet.isTimeDeposit) {
      throw ArgumentError.value(wallet.id, 'wallet', 'Not a time deposit.');
    }
    if (queueIfOffline &&
        (wallet.timeDepositStatusAt(when) != TimeDepositStatus.matured ||
            wallet.isClosedTimeDeposit ||
            _claimsInFlight.contains(wallet.id))) {
      return const TimeDepositSettlementResult(
        TimeDepositSettlementStatus.alreadyHandled,
      );
    }
    final actionId = requestId ?? _newTimeDepositActionId(wallet.id);
    final requestedPrincipal = _cents(
      capitalAmount ?? wallet.timeDepositPrincipal,
    );
    if (requestedPrincipal != _cents(wallet.timeDepositPrincipal)) {
      throw ArgumentError('A time deposit claim must include all its capital.');
    }
    final capitalDestinations = _roundedAmounts(capitalTo);
    final interestDestinations = interestTo.isEmpty
        ? const <String, double>{}
        : _roundedAmounts(interestTo);
    final recordedInterest = _timeDepositInterestOf(wallet);
    final requestedInterest =
        _cents(
          interestAmount ??
              (recordedInterest > 0
                  ? recordedInterest
                  : wallet.timeDepositMaturityInterest),
        ) /
        100;
    final totalCents =
        _cents(wallet.timeDepositPrincipal) + _cents(requestedInterest);
    final combined = <String, double>{};
    capitalDestinations.forEach((id, amount) {
      combined[id] = (combined[id] ?? 0) + amount;
    });
    interestDestinations.forEach((id, amount) {
      combined[id] = (combined[id] ?? 0) + amount;
    });
    if (requestedInterest < 0 ||
        totalCents <= 0 ||
        totalCents > 99999999900 ||
        _cents(_sum(combined)) != totalCents) {
      throw ArgumentError('Where it went must add up to what came out.');
    }

    if (queueIfOffline && await _hasPendingTimeDepositAction(wallet.id)) {
      return const TimeDepositSettlementResult(
        TimeDepositSettlementStatus.queued,
      );
    }
    if (queueIfOffline && !await _deviceHasConnection()) {
      if (wallets.isEmpty) {
        throw ArgumentError(
          'Load the available wallets before queuing a claim.',
        );
      }
      _checkMaturedTimeDepositDestinations(
        timeDeposit: wallet,
        amounts: combined,
        wallets: wallets,
        now: when,
      );
      return _queueTimeDepositAction(wallet.id, {
        'actionId': actionId,
        'type': 'claim',
        'walletId': wallet.id,
        'when': when.toIso8601String(),
        'principal': wallet.timeDepositPrincipal,
        'interest': requestedInterest,
        'capitalTo': capitalDestinations,
        'interestTo': interestDestinations,
      });
    }
    if (!_claimsInFlight.add(wallet.id)) {
      return const TimeDepositSettlementResult(
        TimeDepositSettlementStatus.alreadyHandled,
      );
    }
    try {
      final walletReference = _walletsCollection.doc(wallet.id);
      final claimed = await _firestore.runTransaction<bool>((
        transaction,
      ) async {
        final storedSnapshot = await transaction.get(walletReference);
        if (!storedSnapshot.exists) return false;
        final stored = Wallet.fromMap(storedSnapshot.id, storedSnapshot.data());
        if (stored.timeDepositStatusAt(when) != TimeDepositStatus.matured ||
            stored.isClosedTimeDeposit) {
          return storedSnapshot.data()?['settlementId'] == actionId;
        }

        final principal =
            (_cents(capitalAmount ?? stored.timeDepositPrincipal)) / 100;
        if (_cents(principal) != _cents(stored.timeDepositPrincipal)) {
          throw ArgumentError(
            'A time deposit claim must include all its capital.',
          );
        }
        final interest = requestedInterest;
        final totalCents = _cents(principal) + _cents(interest);
        final total = totalCents / 100;
        if (principal <= 0 ||
            interest < 0 ||
            totalCents <= 0 ||
            totalCents > 99999999900) {
          throw ArgumentError('Nothing to claim.');
        }

        final declaredCents = _cents(_sum(combined));
        if (declaredCents != totalCents) {
          throw ArgumentError('Where it went must add up to what came out.');
        }

        final destinations = <Wallet>[];
        for (final id in combined.keys) {
          final snapshot = await transaction.get(_walletsCollection.doc(id));
          if (snapshot.exists) {
            destinations.add(Wallet.fromMap(snapshot.id, snapshot.data()));
          }
        }
        _checkMaturedTimeDepositDestinations(
          timeDeposit: stored,
          amounts: combined,
          wallets: destinations,
          now: when,
        );

        final deltas = <String, double>{};
        _recordMaturityInterestInTransaction(
          transaction,
          deltas,
          wallet: stored,
          interest: interest,
        );
        combined.forEach((destinationId, amount) {
          if (amount <= 0) return;
          _addTransactionToTransaction(
            transaction,
            type: TransactionType.transfer,
            amount: amount,
            label: _transferLabel(stored, destinationId, wallets: destinations),
            walletId: stored.id,
            toWalletId: destinationId,
            note: 'Claimed from ${stored.name}',
            date: when,
            deltas: deltas,
          );
        });
        _moveGoalMoneyInTransaction(
          transaction,
          goals,
          from: stored.id,
          moved: total,
          into: combined,
        );
        _applyDeltasToTransaction(transaction, deltas);
        transaction.set(walletReference, {
          'principal': stored.timeDepositPrincipal,
          'maturityInterestRecorded': true,
          'settlementId': actionId,
          'closedAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
        return true;
      });
      return TimeDepositSettlementResult(
        claimed
            ? TimeDepositSettlementStatus.completed
            : TimeDepositSettlementStatus.alreadyHandled,
      );
    } on FirebaseException catch (error) {
      if (!queueIfOffline || !_isOfflineFirestoreError(error)) rethrow;
      return _queueTimeDepositAction(wallet.id, {
        'actionId': actionId,
        'type': 'claim',
        'walletId': wallet.id,
        'when': when.toIso8601String(),
        'principal': wallet.timeDepositPrincipal,
        'interest': requestedInterest,
        'capitalTo': capitalDestinations,
        'interestTo': interestDestinations,
      });
    } finally {
      _claimsInFlight.remove(wallet.id);
    }
  }

  /// Renews a matured time deposit into a new record.
  ///
  /// [includeInterest] keeps the interest in the new deposit; otherwise it is
  /// paid out to [interestTo]. The old record is kept, closed and linked, so
  /// its principal, interest and dates stay in history. Returns the new
  /// deposit's id. Offline actions are stored locally and replayed later.
  static Future<TimeDepositSettlementResult> renewTimeDeposit({
    required Wallet wallet,
    required DateTime maturityDate,
    required double annualInterestRatePercent,
    double? interestAmount,
    bool includeInterest = true,
    Map<String, double> interestTo = const {},
    DateTime? date,
    List<Goal> goals = const [],
    List<Wallet> currentWallets = const [],
    String? requestId,
    bool queueIfOffline = true,
  }) async {
    final when = date ?? DateTime.now();
    if (!wallet.isTimeDeposit) {
      throw ArgumentError.value(wallet.id, 'wallet', 'Not a time deposit.');
    }
    if (queueIfOffline &&
        (wallet.timeDepositStatusAt(when) != TimeDepositStatus.matured ||
            wallet.isClosedTimeDeposit ||
            _claimsInFlight.contains(wallet.id))) {
      return const TimeDepositSettlementResult(
        TimeDepositSettlementStatus.alreadyHandled,
      );
    }
    final actionId = requestId ?? _newTimeDepositActionId(wallet.id);
    if (!isValidAnnualInterestRatePercent(annualInterestRatePercent)) {
      throw ArgumentError('Enter a valid interest rate.');
    }
    final roundedMaturity = philippineDayStart(maturityDate);
    final interestDestinations = _roundedAmounts(interestTo);
    final recordedInterest = _timeDepositInterestOf(wallet);
    final requestedInterest =
        _cents(
          interestAmount ??
              (recordedInterest > 0
                  ? recordedInterest
                  : wallet.timeDepositMaturityInterest),
        ) /
        100;
    final interestCents = _cents(requestedInterest);
    final principalCents = _cents(wallet.timeDepositPrincipal);
    if (principalCents <= 0 || interestCents < 0) {
      throw ArgumentError('Enter a valid amount to renew.');
    }
    final newPrincipalCents =
        principalCents + (includeInterest ? interestCents : 0);
    if (newPrincipalCents > 99999999900) {
      throw ArgumentError('Enter a valid amount to renew.');
    }
    if (wallet.maturityDate == null ||
        !roundedMaturity.isAfter(philippineDayStart(wallet.maturityDate!))) {
      throw ArgumentError('The new end date must be after the old one.');
    }
    if (!includeInterest &&
        interestCents > 0 &&
        _cents(_sum(interestDestinations)) != interestCents) {
      throw ArgumentError('Choose where the interest went.');
    }
    if (queueIfOffline && await _hasPendingTimeDepositAction(wallet.id)) {
      return const TimeDepositSettlementResult(
        TimeDepositSettlementStatus.queued,
      );
    }
    if (queueIfOffline && !await _deviceHasConnection()) {
      if (!includeInterest && interestCents > 0) {
        _checkMaturedTimeDepositDestinations(
          timeDeposit: wallet,
          amounts: interestDestinations,
          wallets: currentWallets,
          now: when,
        );
      }
      return _queueTimeDepositAction(wallet.id, {
        'actionId': actionId,
        'type': 'renew',
        'walletId': wallet.id,
        'when': when.toIso8601String(),
        'maturityDate': roundedMaturity.toIso8601String(),
        'rate': annualInterestRatePercent,
        'interest': requestedInterest,
        'includeInterest': includeInterest,
        'interestTo': interestDestinations,
      });
    }
    if (!_claimsInFlight.add(wallet.id)) {
      return const TimeDepositSettlementResult(
        TimeDepositSettlementStatus.alreadyHandled,
      );
    }
    try {
      final reference = _walletsCollection.doc();
      final renewedWalletId = await _firestore.runTransaction<String?>((
        transaction,
      ) async {
        final walletReference = _walletsCollection.doc(wallet.id);
        final storedSnapshot = await transaction.get(walletReference);
        if (!storedSnapshot.exists) return null;
        final stored = Wallet.fromMap(storedSnapshot.id, storedSnapshot.data());
        if (stored.timeDepositStatusAt(when) != TimeDepositStatus.matured ||
            stored.isClosedTimeDeposit) {
          final storedData = storedSnapshot.data();
          return storedData?['settlementId'] == actionId
              ? stored.renewedIntoId
              : null;
        }
        final oldMaturity = stored.maturityDate;
        if (oldMaturity == null ||
            !roundedMaturity.isAfter(philippineDayStart(oldMaturity))) {
          throw ArgumentError('The new end date must be after the old one.');
        }

        final principal = _cents(stored.timeDepositPrincipal) / 100;
        final interest = requestedInterest;
        final interestCents = _cents(interest);
        final principalCents = _cents(principal);
        if (principalCents <= 0 || interestCents < 0) {
          throw ArgumentError('Enter a valid amount to renew.');
        }
        final newPrincipalCents =
            principalCents + (includeInterest ? interestCents : 0);
        final newPrincipal = newPrincipalCents / 100;
        if (newPrincipalCents > 99999999900) {
          throw ArgumentError('Enter a valid amount to renew.');
        }

        final destinations = <Wallet>[];
        if (!includeInterest && interestCents > 0) {
          if (_cents(_sum(interestDestinations)) != interestCents) {
            throw ArgumentError('Choose where the interest went.');
          }
          for (final id in interestDestinations.keys) {
            final snapshot = await transaction.get(_walletsCollection.doc(id));
            if (snapshot.exists) {
              destinations.add(Wallet.fromMap(snapshot.id, snapshot.data()));
            }
          }
          _checkMaturedTimeDepositDestinations(
            timeDeposit: stored,
            amounts: interestDestinations,
            wallets: destinations,
            now: when,
          );
        }

        final deltas = <String, double>{};
        _recordMaturityInterestInTransaction(
          transaction,
          deltas,
          wallet: stored,
          interest: interest,
        );
        _addTransactionToTransaction(
          transaction,
          type: TransactionType.transfer,
          amount: newPrincipal,
          label: TransactionType.transfer.label,
          walletId: stored.id,
          toWalletId: reference.id,
          note: 'Renewed ${stored.name}',
          date: when,
          deltas: deltas,
        );
        if (!includeInterest) {
          interestDestinations.forEach((destinationId, amount) {
            if (amount <= 0) return;
            _addTransactionToTransaction(
              transaction,
              type: TransactionType.transfer,
              amount: amount,
              label: _transferLabel(
                stored,
                destinationId,
                wallets: destinations,
              ),
              walletId: stored.id,
              toWalletId: destinationId,
              note: 'Interest from ${stored.name}',
              date: when,
              deltas: deltas,
            );
          });
        }

        final combined = <String, double>{reference.id: newPrincipal};
        if (!includeInterest) {
          interestDestinations.forEach((id, amount) {
            combined[id] = (combined[id] ?? 0) + amount;
          });
        }
        _moveGoalMoneyInTransaction(
          transaction,
          goals,
          from: stored.id,
          moved: principal + interest,
          into: combined,
        );
        transaction.set(reference, {
          'name': uniqueName('${stored.name} Renewal', [
            for (final other in currentWallets)
              if (!other.archived) other.name,
          ], maxLength: maxItemNameLength),
          'type': stored.type.name,
          // The transfer in this same transaction fills the new record.
          'balance': 0,
          'balanceRecorded': true,
          'startingBalance': 0,
          'principal': newPrincipal,
          'annualInterestRatePercent': annualInterestRatePercent,
          'receivesIncome': false,
          'archived': false,
          'sortOrder': stored.sortOrder + 1,
          'purpose': WalletPurpose.savings.name,
          'savingsKind': SavingsKind.timeDeposit.name,
          'depositStartDate': Timestamp.fromDate(
            philippineDayStart(oldMaturity),
          ),
          'maturityDate': Timestamp.fromDate(roundedMaturity),
          'maturityInterestRecorded': false,
          'createdAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        });
        _applyDeltasToTransaction(transaction, deltas);
        transaction.set(walletReference, {
          'principal': principal,
          'maturityInterestRecorded': true,
          'settlementId': actionId,
          'closedAt': FieldValue.serverTimestamp(),
          'renewedIntoId': reference.id,
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
        return reference.id;
      });
      return TimeDepositSettlementResult(
        renewedWalletId == null
            ? TimeDepositSettlementStatus.alreadyHandled
            : TimeDepositSettlementStatus.completed,
        renewedWalletId: renewedWalletId,
      );
    } on FirebaseException catch (error) {
      if (!queueIfOffline || !_isOfflineFirestoreError(error)) rethrow;
      return _queueTimeDepositAction(wallet.id, {
        'actionId': actionId,
        'type': 'renew',
        'walletId': wallet.id,
        'when': when.toIso8601String(),
        'maturityDate': roundedMaturity.toIso8601String(),
        'rate': annualInterestRatePercent,
        'interest': requestedInterest,
        'includeInterest': includeInterest,
        'interestTo': interestDestinations,
      });
    } finally {
      _claimsInFlight.remove(wallet.id);
    }
  }

  /// The interest a matured deposit carries above its original money, rounded
  /// to centavos.
  static double _timeDepositInterestOf(Wallet wallet) {
    final interest = wallet.balance - wallet.timeDepositPrincipal;
    return interest > 0 ? (interest * 100).round() / 100 : 0;
  }

  static void _recordMaturityInterestInTransaction(
    Transaction transaction,
    Map<String, double> deltas, {
    required Wallet wallet,
    required double interest,
  }) {
    final amount = (interest * 100).round() / 100;
    final recorded = _timeDepositInterestOf(wallet);
    final maturity = wallet.maturityDate;
    final date = maturity == null
        ? DateTime.now()
        : philippineDayStart(maturity);
    if (!wallet.maturityInterestRecorded && recorded <= 0.005) {
      if (amount > 0) {
        _addTransactionToTransaction(
          transaction,
          type: TransactionType.income,
          amount: amount,
          label: interestIncomeLabel,
          id: 'td-interest-${wallet.id}',
          walletId: wallet.id,
          note: 'Interest on ${wallet.name}',
          date: date,
          deltas: deltas,
        );
      }
      return;
    }

    if (!wallet.maturityInterestRecorded && recorded > 0.005) {
      _addTransactionToTransaction(
        transaction,
        type: TransactionType.income,
        amount: recorded,
        label: interestIncomeLabel,
        id: 'td-interest-${wallet.id}',
        walletId: wallet.id,
        note: 'Interest on ${wallet.name}',
        date: date,
        deltas: <String, double>{},
      );
    }

    final correction = ((amount - recorded) * 100).round() / 100;
    if (correction.abs() <= 0.005) return;
    _addTransactionToTransaction(
      transaction,
      type: correction > 0 ? TransactionType.income : TransactionType.expense,
      amount: correction.abs(),
      label: correction > 0 ? interestIncomeLabel : 'Interest correction',
      id: 'td-interest-correction-${wallet.id}',
      walletId: wallet.id,
      note: 'Correction for interest on ${wallet.name}',
      date: date,
      deltas: deltas,
    );
  }

  static String _addTransactionToTransaction(
    Transaction transaction, {
    required TransactionType type,
    required double amount,
    required String label,
    required Map<String, double> deltas,
    String? id,
    String? walletId,
    String? toWalletId,
    String? note,
    DateTime? date,
  }) {
    if (!amount.isFinite || amount <= 0) {
      throw ArgumentError.value(amount, 'amount', 'Must be greater than zero.');
    }
    final reference = id == null
        ? _transactionsCollection.doc()
        : _transactionsCollection.doc(id);
    final trimmedNote = note?.trim();
    final entry = AppTransaction(
      id: reference.id,
      type: type,
      amount: amount,
      label: label,
      date: date ?? DateTime.now(),
      walletId: walletId,
      toWalletId: toWalletId,
      note: trimmedNote,
    );
    transaction.set(reference, {
      'type': entry.type.name,
      'amount': entry.amount,
      'label': entry.label,
      'walletId': entry.walletId,
      'toWalletId': entry.toWalletId,
      'note': trimmedNote == null || trimmedNote.isEmpty ? null : trimmedNote,
      'date': Timestamp.fromDate(entry.date),
      'legacy': false,
      'isInternalTransfer': type == TransactionType.transfer,
      'createdAt': FieldValue.serverTimestamp(),
    });
    _collectDeltas(deltas, entry, reverse: false);
    return reference.id;
  }

  static void _applyDeltasToTransaction(
    Transaction transaction,
    Map<String, double> deltas,
  ) {
    deltas.forEach((walletId, delta) {
      if (delta == 0) return;
      transaction.set(_walletsCollection.doc(walletId), {
        'balance': FieldValue.increment(delta),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    });
  }

  static Map<String, double> _roundedAmounts(Map<String, double> amounts) => {
    for (final entry in amounts.entries)
      if (entry.value.isFinite && entry.value > 0)
        entry.key: (entry.value * 100).round() / 100,
  };

  static int _cents(double amount) {
    if (!amount.isFinite) {
      throw ArgumentError.value(amount, 'amount', 'Must be a finite amount.');
    }
    return (amount * 100).round();
  }

  static double _sum(Map<String, double> amounts) =>
      _cents(
        amounts.values.fold<double>(0, (total, amount) => total + amount),
      ) /
      100;

  static String _transferLabel(
    Wallet from,
    String toId, {
    required List<Wallet> wallets,
  }) {
    final to = wallets.where((wallet) => wallet.id == toId).firstOrNull;
    return to == null
        ? TransferDirection.transfer.label
        : TransferDirection.betweenWallets(from: from, to: to).label;
  }

  static void _moveGoalMoneyInTransaction(
    Transaction transaction,
    List<Goal> goals, {
    required String from,
    required double moved,
    required Map<String, double> into,
  }) {
    final room = {
      for (final entry in into.entries) entry.key: (entry.value * 100).round(),
    };
    goalMoneyMoving(goals, from: from, moved: moved).forEach((goal, amount) {
      var left = (amount * 100).round();
      var running = goal;
      for (final destination in room.keys.toList()) {
        if (left <= 0) break;
        final space = room[destination]!;
        if (space <= 0) continue;
        final part = left < space ? left : space;
        GoalService.moveMoneyInTransaction(
          transaction,
          running,
          from: from,
          to: destination,
          amount: part / 100,
        );
        running = running
            .withContribution(from, -part / 100)
            .withContribution(destination, part / 100);
        room[destination] = space - part;
        left -= part;
      }
    });
  }

  /// Records a user-reported withdrawal from an interest-bearing savings
  /// deposit, including any interest received and where the money went.
  static void settleSavingsWithdrawal({
    required Wallet wallet,
    required double received,
    required Map<String, double> to,
    DateTime? date,
    List<Goal> goals = const [],
  }) {
    if (wallet.purpose != WalletPurpose.savings ||
        wallet.savingsType != SavingsKind.savingsDeposit) {
      throw ArgumentError.value(
        wallet.id,
        'wallet',
        'Must be a savings deposit.',
      );
    }
    _settleSavings(
      wallet: wallet,
      received: received,
      to: to,
      date: date,
      goals: goals,
      transferNote: 'Withdrawn from ${wallet.name}',
      clearMaturityWhenEmpty: false,
      action: 'settle savings withdrawal',
    );
  }

  static void _settleSavings({
    required Wallet wallet,
    required double received,
    required Map<String, double> to,
    required String transferNote,
    required bool clearMaturityWhenEmpty,
    required String action,
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
        note: transferNote,
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
    if (clearMaturityWhenEmpty && taken >= balance) {
      batch.set(_walletsCollection.doc(wallet.id), {
        'maturityDate': FieldValue.delete(),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    }

    commitFirestoreWrite(batch.commit(), action);
  }

  /// Records interest the user says [wallet] was paid, as income into that
  /// account. FinAssist cannot see a real account, so this is only ever
  /// what the user enters, never an estimate added by itself.
  static void recordInterest({
    required Wallet wallet,
    required double amount,
    DateTime? date,
  }) {
    if (wallet.isTimeDeposit) {
      throw ArgumentError(
        'Time deposit interest is recorded at maturity, not as regular income.',
      );
    }
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
    if (wallet.isTimeDeposit) {
      throw ArgumentError(
        'Use renewTimeDeposit to keep the old record and link its renewal.',
      );
    }
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
    Map<String, double>? collectDeltasInto,
    String? billInstanceId,
    String? debtId,
    double interest = 0,
    bool installmentPayment = false,
    bool? internalTransfer,
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
      if (installmentPayment) 'installmentPayment': true,
      'isInternalTransfer':
          internalTransfer ?? type == TransactionType.transfer,
      'createdAt': FieldValue.serverTimestamp(),
    });

    final deltas = collectDeltasInto ?? <String, double>{};
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
