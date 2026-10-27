import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import '../models/debt.dart';
import 'bill_service.dart';
import 'firestore_write.dart';
import 'wallet_service.dart';

/// Reads and writes installments, loans, and money owed to the user.
class DebtService {
  static FirebaseFirestore get _firestore => FirebaseFirestore.instance;

  static CollectionReference<Map<String, dynamic>> get _debts {
    final user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      throw StateError('No authenticated user.');
    }

    return _firestore.collection('users').doc(user.uid).collection('debts');
  }

  /// Every debt, updating live: still-open ones first, then by name.
  ///
  /// Sorted here rather than with `orderBy('createdAt')`, because a debt
  /// saved offline has no server timestamp yet and would drop out of an
  /// ordered query until it synced.
  static Stream<List<Debt>> watchDebts() {
    return _debts.snapshots().map((snapshot) {
      final debts = snapshot.docs
          .map((doc) => Debt.fromMap(doc.id, doc.data()))
          .toList();
      debts.sort((a, b) {
        final byStatus = a.status.index.compareTo(b.status.index);
        return byStatus != 0
            ? byStatus
            : a.name.toLowerCase().compareTo(b.name.toLowerCase());
      });
      return debts;
    });
  }

  /// Every debt, read once. Returns cached records while offline.
  static Future<List<Debt>> loadDebts() async {
    final snapshot = await _debts.get();
    return [
      for (final doc in snapshot.docs) Debt.fromMap(doc.id, doc.data()),
    ];
  }

  static Stream<Debt?> watchDebt(String id) {
    return _debts
        .doc(id)
        .snapshots()
        .map((doc) => doc.exists ? Debt.fromMap(doc.id, doc.data()) : null);
  }

  /// Saves an installment or loan the user is paying back.
  ///
  /// The terms and the payment schedule in the Bill Planner go in one batch,
  /// and nothing else: a plan is not a payment, so no wallet moves until a
  /// payment is actually recorded. The schedule ends on the last payment's
  /// date, so it never asks for a thirteenth payment on a twelve-month plan,
  /// and starts after the [paidBefore] payments made before it was tracked,
  /// so those are never asked for again.
  static String addInstallment({
    required String name,
    required DebtCategory category,
    required double principal,
    required double perPayment,
    required int paymentCount,
    required PaymentFrequency frequency,
    required DateTime firstDueDate,
    double lastPayment = 0,
    String? note,
    int paidBefore = 0,
    double? quotedRate,
    RatePeriod quotedRatePer = RatePeriod.year,
    InterestBasis rateBasis = InterestBasis.wholeAmount,
    double fees = 0,
    String? otherKind,
  }) {
    final batch = _firestore.batch();
    final debt = _debts.doc();
    final bill = BillService.newBillReference();

    final terms = Debt(
      id: debt.id,
      direction: DebtDirection.iOwe,
      name: name,
      category: category,
      principal: principal,
      perPayment: perPayment,
      paymentCount: paymentCount,
      lastPayment: lastPayment,
      frequency: frequency,
      firstDueDate: firstDueDate,
      status: DebtStatus.active,
      paidBefore: paidBefore,
      // Fees count toward what borrowing costs, so toward the interest
      // recorded in each payment.
      fees: fees,
    );
    final lastDue = terms.lastDueDate!;

    batch.set(debt, {
      'direction': DebtDirection.iOwe.name,
      'name': name.trim(),
      'category': category.name,
      'principal': principal,
      'perPayment': perPayment,
      'paymentCount': paymentCount,
      if (terms.hasDifferentLastPayment) 'lastPayment': terms.finalPayment,
      'frequency': frequency.name,
      'firstDueDate': Timestamp.fromDate(firstDueDate),
      'billId': bill.id,
      'note': _noteOrNull(note),
      'status': DebtStatus.active.name,
      if (paidBefore > 0) 'paidBefore': paidBefore,
      if ((category == DebtCategory.other ||
              category == DebtCategory.otherLoan) &&
          (otherKind ?? '').trim().isNotEmpty)
        'otherKind': otherKind!.trim(),
      if (quotedRate != null) ...{
        'quotedRate': quotedRate,
        'quotedRatePer': quotedRatePer.name,
        'rateBasis': rateBasis.name,
      },
      if (fees > 0) 'fees': fees,
      'createdAt': FieldValue.serverTimestamp(),
    });

    BillService.addBillToBatch(
      batch,
      reference: bill,
      name: name,
      amount: perPayment,
      category: 'Bills',
      firstDueDate: firstDueDate,
      recurrence: frequency.recurrence,
      endDate: lastDue,
      debtId: debt.id,
      lastAmount: terms.hasDifferentLastPayment ? terms.finalPayment : null,
      startDate: paidBefore > 0 ? terms.dueDateOf(paidBefore + 1) : null,
      // Each payment then records the interest inside it.
      interestShare: terms.interestShare,
    );

    commitFirestoreWrite(batch.commit(), 'add installment');
    return debt.id;
  }

  /// Gives installments saved before interest was kept apart the same split
  /// as new ones, so every account's Reports show what borrowing cost. Each
  /// is done once; offline, it waits for the next start.
  static Future<void> fillInterestShares() async {
    try {
      final snapshot = await _debts.get();
      for (final doc in snapshot.docs) {
        final debt = Debt.fromMap(doc.id, doc.data());
        final billId = debt.billId;
        if (debt.direction != DebtDirection.iOwe || billId == null) continue;
        await BillService.fillInterestShare(billId, debt.interestShare);
      }
    } on FirebaseException catch (error) {
      debugPrint('Installment interest: $error');
    }
  }

  /// Deletes a debt. For an installment, its unpaid payments leave the Bill
  /// Planner too; payments already made stay, because that money really left
  /// a wallet. Money that moved when the debt was made stays recorded for the
  /// same reason.
  static Future<void> deleteDebt(Debt debt) async {
    final billId = debt.billId;
    if (billId != null) await BillService.deleteBill(billId);

    commitFirestoreWrite(_debts.doc(debt.id).delete(), 'delete debt');
  }

  /// Closes an installment or debt paid off before its schedule ended. The
  /// amount the lender or store asked for comes out of the wallets in
  /// [parts], split into what was still owed of the money borrowed and
  /// interest, and the payments still to come leave the Bill Planner. It
  /// stays listed, paid off early, and [undoPayOff] puts it back.
  static Future<void> payOffEarly({
    required Debt debt,
    required List<BillPaymentPart> parts,
    required DateTime date,
  }) async {
    final billId = debt.billId;
    if (billId == null) return;
    final instances = await BillService.loadInstancesForBill(billId);
    final progress = DebtProgress.of(debt, instances);
    final amount = parts.fold<double>(0, (total, part) => total + part.amount);
    final split = debt.payoffSplit(amount, progress.paid);

    final batch = _firestore.batch();
    final deltas = <String, double>{};
    BillService.addPayoffToBatch(
      batch,
      billId: billId,
      name: debt.name,
      parts: parts,
      interest: split.interest,
      date: date,
      instances: instances,
      collectDeltasInto: deltas,
    );
    WalletService.applyDeltasToBatch(batch, deltas);
    batch.set(_debts.doc(debt.id), {
      'status': DebtStatus.settled.name,
      'paidOffAt': Timestamp.fromDate(date),
      'paidOffAmount': amount,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    commitFirestoreWrite(batch.commit(), 'pay off early');
  }

  /// Takes back a payoff made by mistake: the money returns to its wallets
  /// and the payments left are owed again.
  static Future<void> undoPayOff(Debt debt) async {
    final billId = debt.billId;
    if (billId == null) return;
    final batch = _firestore.batch();
    await BillService.addUndoPayoffToBatch(batch, billId);
    batch.set(_debts.doc(debt.id), {
      'status': DebtStatus.active.name,
      'paidOffAt': FieldValue.delete(),
      'paidOffAmount': FieldValue.delete(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    commitFirestoreWrite(batch.commit(), 'undo pay off');
  }

  static String? _noteOrNull(String? note) {
    final trimmed = note?.trim();
    return trimmed == null || trimmed.isEmpty ? null : trimmed;
  }
}
