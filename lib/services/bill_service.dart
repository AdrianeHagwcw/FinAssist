import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../models/app_transaction.dart';
import '../models/bill.dart';
import 'firestore_write.dart';
import 'wallet_service.dart';

/// Reads and writes the user's bills.
///
/// Bills are stored twice over, on purpose:
///
/// * `bills` holds the schedule — "Rent, ₱3,000, the 5th of every month".
/// * `billInstances` holds one record per time it actually falls due.
///
/// The plan asks that each occurrence be editable on its own (a bigger
/// electricity bill this month shouldn't rewrite the schedule), and one
/// recurring record can't do that. Occurrences are created only when the user
/// opens the month they fall in, and their ids are built from the bill and
/// the date, so opening a month twice can't produce duplicates.
class BillService {
  static FirebaseFirestore get _firestore => FirebaseFirestore.instance;

  static DocumentReference<Map<String, dynamic>> get _profile {
    final user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      throw StateError('No authenticated user.');
    }

    return _firestore.collection('users').doc(user.uid);
  }

  static CollectionReference<Map<String, dynamic>> get _bills =>
      _profile.collection('bills');

  static CollectionReference<Map<String, dynamic>> get _instances =>
      _profile.collection('billInstances');

  // ---------------------------------------------------------------- reading

  /// The user's bill schedules, updating live.
  static Stream<List<Bill>> watchBills({bool includeArchived = false}) {
    return _bills.snapshots().map((snapshot) {
      final bills = snapshot.docs
          .map((doc) => Bill.fromMap(doc.id, doc.data()))
          .where((bill) => includeArchived || !bill.archived)
          .toList();
      bills.sort((a, b) => a.firstDueDate.day.compareTo(b.firstDueDate.day));
      return bills;
    });
  }

  /// Reads the bill schedules once. Returns cached data while offline.
  static Future<List<Bill>> loadBills() async {
    final snapshot = await _bills.get();

    return snapshot.docs
        .map((doc) => Bill.fromMap(doc.id, doc.data()))
        .where((bill) => !bill.archived)
        .toList();
  }

  /// Every occurrence falling due in the given month, updating live.
  static Stream<List<BillInstance>> watchInstances(int year, int month) {
    return _instances
        .where(
          'dueDate',
          isGreaterThanOrEqualTo: Timestamp.fromDate(DateTime(year, month)),
          isLessThan: Timestamp.fromDate(DateTime(year, month + 1)),
        )
        .snapshots()
        .map((snapshot) {
          final instances = snapshot.docs
              .map((doc) => BillInstance.fromMap(doc.id, doc.data()))
              .toList();
          instances.sort((a, b) => a.dueDate.compareTo(b.dueDate));
          return instances;
        });
  }

  /// One occurrence, updating live. Null once it has been deleted.
  static Stream<BillInstance?> watchInstance(String instanceId) {
    return _instances
        .doc(instanceId)
        .snapshots()
        .map(
          (doc) => doc.exists ? BillInstance.fromMap(doc.id, doc.data()) : null,
        );
  }

  /// Reads one occurrence once, or null when it no longer exists.
  static Future<BillInstance?> loadInstance(String instanceId) async {
    final doc = await _instances.doc(instanceId).get();
    return doc.exists ? BillInstance.fromMap(doc.id, doc.data()) : null;
  }

  /// Every cycle of one bill, newest first, so the user can see what they
  /// paid last month and the month before.
  static Stream<List<BillInstance>> watchInstancesForBill(String billId) {
    return _instances.where('billId', isEqualTo: billId).snapshots().map((
      snapshot,
    ) {
      final instances = snapshot.docs
          .map((doc) => BillInstance.fromMap(doc.id, doc.data()))
          .toList();
      instances.sort((a, b) => b.dueDate.compareTo(a.dueDate));
      return instances;
    });
  }

  /// Reads one month's occurrences once. Returns cached data while offline.
  static Future<List<BillInstance>> loadInstances(int year, int month) async {
    final snapshot = await _instances
        .where(
          'dueDate',
          isGreaterThanOrEqualTo: Timestamp.fromDate(DateTime(year, month)),
          isLessThan: Timestamp.fromDate(DateTime(year, month + 1)),
        )
        .get();

    return snapshot.docs
        .map((doc) => BillInstance.fromMap(doc.id, doc.data()))
        .toList();
  }

  // ------------------------------------------------------------- schedules

  /// Adds a bill schedule and returns its id.
  static String addBill({
    required String name,
    required double amount,
    required String category,
    required DateTime firstDueDate,
    required BillRecurrence recurrence,
    String? walletId,
  }) {
    final reference = _bills.doc();

    commitFirestoreWrite(
      reference.set(
        _billData(
          name: name,
          amount: amount,
          category: category,
          firstDueDate: firstDueDate,
          recurrence: recurrence,
          walletId: walletId,
        )..['createdAt'] = FieldValue.serverTimestamp(),
      ),
      'add bill',
    );

    return reference.id;
  }

  /// Changes a bill's schedule. Occurrences already created keep the amount
  /// and date they were given; the new schedule applies to months the user
  /// has not opened yet.
  static void updateBill({
    required String billId,
    required String name,
    required double amount,
    required String category,
    required DateTime firstDueDate,
    required BillRecurrence recurrence,
    String? walletId,
  }) {
    commitFirestoreWrite(
      _bills
          .doc(billId)
          .set(
            _billData(
              name: name,
              amount: amount,
              category: category,
              firstDueDate: firstDueDate,
              recurrence: recurrence,
              walletId: walletId,
            ),
            SetOptions(merge: true),
          ),
      'update bill',
    );
  }

  static Map<String, dynamic> _billData({
    required String name,
    required double amount,
    required String category,
    required DateTime firstDueDate,
    required BillRecurrence recurrence,
    String? walletId,
  }) {
    final trimmedName = name.trim();

    return <String, dynamic>{
      'name': trimmedName.isEmpty ? 'Bill' : trimmedName,
      'amount': amount.abs(),
      'category': category,
      'firstDueDate': Timestamp.fromDate(
        DateTime(firstDueDate.year, firstDueDate.month, firstDueDate.day),
      ),
      'recurrence': recurrence.name,
      'walletId': walletId,
      'archived': false,
      'updatedAt': FieldValue.serverTimestamp(),
    };
  }

  /// Stops a bill from producing any more occurrences, and clears the ones
  /// still outstanding.
  ///
  /// Occurrences already paid stay put, because they explain an expense that
  /// really came out of a wallet. Deleting them would leave that money
  /// unaccounted for.
  static Future<void> deleteBill(String billId) async {
    final outstanding = await _instances
        .where('billId', isEqualTo: billId)
        .get();

    final batch = _firestore.batch()..delete(_bills.doc(billId));

    for (final doc in outstanding.docs) {
      final instance = BillInstance.fromMap(doc.id, doc.data());
      if (instance.amountPaid > 0) continue;

      batch.delete(doc.reference);
    }

    commitFirestoreWrite(batch.commit(), 'delete bill');
  }

  // ------------------------------------------------------------ occurrences

  /// Creates whatever occurrences the given month is missing.
  ///
  /// Safe to call every time the month is opened: ids come from the bill and
  /// the due date, and anything already there is left exactly as it is, so a
  /// payment can never be overwritten by a later visit.
  static Future<int> ensureInstances({
    required List<Bill> bills,
    required int year,
    required int month,
    DateTime? now,
  }) async {
    if (bills.isEmpty) return 0;

    final existing = (await loadInstances(
      year,
      month,
    )).map((instance) => instance.id).toSet();

    // The previous month decides what is rolled into this one.
    final previousMonth = DateTime(year, month - 1);
    final previous = await loadInstances(
      previousMonth.year,
      previousMonth.month,
    );

    final batch = _firestore.batch();
    var created = 0;

    for (final bill in bills) {
      for (final dueDate in bill.occurrencesIn(year, month)) {
        final id = billInstanceId(bill.id, dueDate);

        if (existing.contains(id)) continue;

        final carried = carryOverFrom(_lastFor(previous, bill.id), now: now);

        batch.set(_instances.doc(id), {
          'billId': bill.id,
          'name': bill.name,
          'amount': bill.amount + carried,
          'category': bill.category,
          'dueDate': Timestamp.fromDate(dueDate),
          'status': BillStatus.unpaid.name,
          'amountPaid': 0,
          'carriedOver': carried,
          'paymentIds': <String>[],
          'walletId': bill.walletId,
          'createdAt': FieldValue.serverTimestamp(),
        });
        created++;
      }
    }

    if (created > 0) commitFirestoreWrite(batch.commit(), 'add bill dates');

    return created;
  }

  static BillInstance? _lastFor(List<BillInstance> instances, String billId) {
    BillInstance? latest;

    for (final instance in instances) {
      if (instance.billId != billId) continue;
      if (latest == null || instance.dueDate.isAfter(latest.dueDate)) {
        latest = instance;
      }
    }

    return latest;
  }

  /// Changes one occurrence without touching the schedule it came from.
  static void updateInstance({
    required String instanceId,
    String? name,
    double? amount,
    DateTime? dueDate,
  }) {
    final fields = <String, dynamic>{'updatedAt': FieldValue.serverTimestamp()};
    final trimmedName = name?.trim();

    if (trimmedName != null && trimmedName.isNotEmpty) {
      fields['name'] = trimmedName;
    }

    if (amount != null) fields['amount'] = amount.abs();

    if (dueDate != null) {
      fields['dueDate'] = Timestamp.fromDate(
        DateTime(dueDate.year, dueDate.month, dueDate.day),
      );
    }

    commitFirestoreWrite(
      _instances.doc(instanceId).set(fields, SetOptions(merge: true)),
      'update bill date',
    );
  }

  // --------------------------------------------------------------- payments

  /// Records a payment against a bill.
  ///
  /// The bill's status, the expense, and the wallet's balance all go in one
  /// batch, so a paid bill always has the spending to show for it. Pass
  /// [amount] to pay only part of what is owed.
  static void payInstance({
    required BillInstance instance,
    required String walletId,
    double? amount,
  }) {
    final batch = _firestore.batch();
    addPaymentToBatch(
      batch,
      instance: instance,
      walletId: walletId,
      amount: amount ?? instance.remaining,
    );

    commitFirestoreWrite(batch.commit(), 'pay bill');
  }

  /// Adds a payment against [instance] to [batch]: the expense, the wallet's
  /// balance change, and the bill's new status. Returns the expense's id.
  ///
  /// Pass [collectDeltasInto] when the same batch moves that wallet more than
  /// once; see [WalletService.addTransactionToBatch].
  static String addPaymentToBatch(
    WriteBatch batch, {
    required BillInstance instance,
    required String walletId,
    required double amount,
    DateTime? date,
    Map<String, double>? collectDeltasInto,
  }) {
    if (!amount.isFinite || amount <= 0) {
      throw ArgumentError.value(amount, 'amount', 'Must be greater than zero.');
    }

    final transactionId = WalletService.addTransactionToBatch(
      batch,
      type: TransactionType.expense,
      amount: amount,
      label: instance.category,
      walletId: walletId,
      note: instance.name,
      date: date,
      collectDeltasInto: collectDeltasInto,
      billInstanceId: instance.id,
    );

    final paid = instance.amountPaid + amount;

    batch.set(_instances.doc(instance.id), {
      'status': BillInstance.statusForPayment(paid, instance.amount).name,
      'amountPaid': paid,
      'walletId': walletId,
      'paidAt': FieldValue.serverTimestamp(),
      'paymentIds': FieldValue.arrayUnion([transactionId]),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    return transactionId;
  }

  /// The payments made against a bill, oldest first.
  ///
  /// Each payment is its own transaction against its own wallet, so a bill
  /// part-paid in cash today and by GCash tomorrow reads exactly that way.
  static Future<List<AppTransaction>> loadPayments(
    BillInstance instance,
  ) async {
    final payments = <AppTransaction>[];

    for (final paymentId in instance.paymentIds) {
      final transaction = await WalletService.loadTransaction(paymentId);

      if (transaction != null) payments.add(transaction);
    }

    payments.sort((a, b) => a.date.compareTo(b.date));
    return payments;
  }

  /// Undoes a single payment, leaving the others alone. The money goes back
  /// to the wallet that particular payment came out of.
  static void undoPayment(BillInstance instance, AppTransaction payment) {
    final batch = _firestore.batch();
    WalletService.removeTransactionFromBatch(batch, payment);

    final paid = instance.amountPaid - payment.amount;
    final remainingPaid = paid > 0 ? paid : 0.0;

    batch.set(_instances.doc(instance.id), {
      'status': BillInstance.statusForPayment(
        remainingPaid,
        instance.amount,
      ).name,
      'amountPaid': remainingPaid,
      'paymentIds': FieldValue.arrayRemove([payment.id]),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    commitFirestoreWrite(batch.commit(), 'undo one bill payment');
  }

  /// Undoes every payment on a bill and puts the money back in the wallets it
  /// came from, in one batch.
  static Future<void> undoPayments(BillInstance instance) async {
    final batch = _firestore.batch();

    for (final paymentId in instance.paymentIds) {
      final transaction = await WalletService.loadTransaction(paymentId);

      if (transaction == null) continue;

      WalletService.removeTransactionFromBatch(batch, transaction);
    }

    batch.set(_instances.doc(instance.id), {
      'status': BillStatus.unpaid.name,
      'amountPaid': 0,
      'paidAt': null,
      'paymentIds': <String>[],
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    commitFirestoreWrite(batch.commit(), 'undo bill payment');
  }

  /// Marks a bill as deliberately not paid. It stays on the calendar, and
  /// unlike an unpaid bill it rolls nothing into the next cycle.
  static void skipInstance(String instanceId) {
    final batch = _firestore.batch();
    addSkipToBatch(batch, instanceId);
    commitFirestoreWrite(batch.commit(), 'skip bill');
  }

  /// The batch counterpart of [skipInstance].
  static void addSkipToBatch(WriteBatch batch, String instanceId) {
    batch.set(_instances.doc(instanceId), {
      'status': BillStatus.skipped.name,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  /// Puts a skipped bill back to unpaid.
  static void unskipInstance(String instanceId) {
    commitFirestoreWrite(
      _instances.doc(instanceId).set({
        'status': BillStatus.unpaid.name,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true)),
      'unskip bill',
    );
  }
}
