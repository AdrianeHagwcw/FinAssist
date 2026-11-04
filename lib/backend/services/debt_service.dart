import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import '../models/bill.dart';
import '../models/debt.dart';
import 'bill_service.dart';
import 'firestore_write.dart';
import 'wallet_service.dart';

enum FixedInterestChargeResult { recorded, alreadyRecorded, unavailable }

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

  /// Everything the user is paying off in parts: things bought on
  /// installment. Borrowed money has [watchLoans].
  ///
  /// Both kinds share the collection and the [Debt] class; only the screen
  /// they are listed on differs.
  static Stream<List<Debt>> watchInstallments() =>
      watchDebts().map(_owedOnly(loan: false));

  /// Everything the user borrowed and is paying back. Things bought on
  /// installment have [watchInstallments].
  static Stream<List<Debt>> watchLoans() =>
      watchDebts().map(_owedOnly(loan: true));

  /// Keeps the records of one kind that the user owes.
  static List<Debt> Function(List<Debt>) _owedOnly({required bool loan}) =>
      (debts) => [
        for (final debt in debts)
          if (debt.direction == DebtDirection.iOwe &&
              debt.category.isLoan == loan)
            debt,
      ];

  /// Every debt, read once. Returns cached records while offline.
  static Future<List<Debt>> loadDebts() async {
    final snapshot = await _debts.get();
    return [for (final doc in snapshot.docs) Debt.fromMap(doc.id, doc.data())];
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
    String? interestPeriod,
    InterestBasis rateBasis = InterestBasis.wholeAmount,
    double? originalPrincipal,
    int? loanDuration,
    String? loanDurationUnit,
    DateTime? loanStartDate,
    bool balanceBasedSchedule = false,
    double? fixedInterestAmount,
    PaymentFrequency? interestChargedPer,
    double fees = 0,
    String? otherKind,
    String? paidWithWalletId,
    String? paidWithLabel,
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
      paidWithWalletId: _noteOrNull(paidWithWalletId),
      paidWithLabel: _noteOrNull(paidWithLabel),
    );
    final lastDue = terms.lastDueDate!;
    final optionalDetails = <String, dynamic>{};
    if (quotedRate != null) {
      optionalDetails.addAll({
        'quotedRate': quotedRate,
        'quotedRatePer': quotedRatePer.name,
        'rateBasis': rateBasis.name,
      });
      if (interestPeriod != null) {
        optionalDetails['interestPeriod'] = interestPeriod;
      }
    }
    if (originalPrincipal != null) {
      optionalDetails['originalPrincipal'] = originalPrincipal;
    }
    if (loanDuration != null) optionalDetails['loanDuration'] = loanDuration;
    if (loanDurationUnit != null) {
      optionalDetails['loanDurationUnit'] = loanDurationUnit;
    }
    if (loanStartDate != null) {
      optionalDetails['loanStartDate'] = Timestamp.fromDate(loanStartDate);
    }
    if (balanceBasedSchedule) optionalDetails['balanceBasedSchedule'] = true;
    if (fixedInterestAmount != null && interestChargedPer != null) {
      optionalDetails['fixedInterestAmount'] = fixedInterestAmount;
      optionalDetails['interestChargedPer'] = interestChargedPer.name;
    }

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
      ...optionalDetails,
      if (fees > 0) 'fees': fees,
      if (paidWithWalletId != null && paidWithWalletId.trim().isNotEmpty)
        'paidWithWalletId': paidWithWalletId.trim(),
      if (paidWithLabel != null && paidWithLabel.trim().isNotEmpty)
        'paidWithLabel': paidWithLabel.trim(),
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

  /// Records a lender-confirmed fixed interest charge once for the selected
  /// period. This never runs automatically and never changes a wallet or the
  /// payment schedule. The unique period document makes concurrent taps safe.
  static Future<FixedInterestChargeResult> recordFixedInterestCharge({
    required Debt debt,
    required DateTime date,
  }) async {
    final debtReference = _debts.doc(debt.id);
    return _firestore.runTransaction((transaction) async {
      final debtSnapshot = await transaction.get(debtReference);
      if (!debtSnapshot.exists) return FixedInterestChargeResult.unavailable;

      final stored = Debt.fromMap(debtSnapshot.id, debtSnapshot.data());
      final amount = stored.fixedInterestAmount;
      final period = stored.interestChargedPer;
      if (stored.status != DebtStatus.active ||
          stored.direction != DebtDirection.iOwe ||
          amount == null ||
          !amount.isFinite ||
          amount <= 0 ||
          period == null) {
        return FixedInterestChargeResult.unavailable;
      }

      final periodKey = fixedInterestPeriodKey(
        date,
        period,
        anchor: stored.loanStartDate ?? stored.firstDueDate,
      );
      final chargeReference = debtReference
          .collection('interestCharges')
          .doc(periodKey);
      final previousCharge = await transaction.get(chargeReference);
      if (previousCharge.exists) {
        return FixedInterestChargeResult.alreadyRecorded;
      }

      transaction.set(chargeReference, {
        'amount': amount,
        'period': period.name,
        'periodKey': periodKey,
        'chargedAt': Timestamp.fromDate(
          DateTime(date.year, date.month, date.day),
        ),
        'createdAt': FieldValue.serverTimestamp(),
      });
      transaction.update(debtReference, {
        'accruedInterest': stored.accruedInterest + amount,
        'updatedAt': FieldValue.serverTimestamp(),
      });
      return FixedInterestChargeResult.recorded;
    });
  }

  /// Rewrites an installment the user corrected, as one batch: its terms,
  /// its schedule, and every payment the change reaches, so the statement
  /// reads right the moment it is saved. What each payment asks for is
  /// worked out again from the new terms, and a payment the plan no longer
  /// reaches is taken away.
  ///
  /// Returns false, writing nothing, once a payment has been made on it in
  /// any way: from then the plan is a record of what was agreed, and
  /// changing it would rewrite what was paid.
  static Future<bool> updateInstallment({
    required Debt from,
    required String name,
    required DebtCategory category,
    required double principal,
    required double perPayment,
    required int paymentCount,
    double lastPayment = 0,
    String? otherKind,
    String? paidWithWalletId,
    String? paidWithLabel,
  }) async {
    final billId = from.billId;
    if (billId == null) return false;

    // The lock is read from what is stored, not from the copy the screen was
    // opened with: a payment could have been made while the form was being
    // filled in.
    final doc = await _debts.doc(from.id).get();
    if (!doc.exists) return false;
    final stored = Debt.fromMap(doc.id, doc.data());
    if (stored.category.isLoan || stored.paidBefore > 0) return false;
    if (stored.paidOffEarly || stored.status == DebtStatus.settled) {
      return false;
    }
    // The payments are counted by the months they fall in, so only a plan
    // paid monthly is worked out this way. Installments always are.
    if (stored.frequency != PaymentFrequency.monthly) return false;

    final instances = await BillService.loadInstancesForBill(billId);
    for (final instance in instances) {
      if (instance.amountPaid > 0 || instance.paymentIds.isNotEmpty) {
        return false;
      }
      if (instance.status == BillStatus.paid) return false;
    }

    // The dates stay as they were agreed: only what is owed on them, and
    // how many of them there are, can be corrected.
    final firstDueDate = stored.firstDueDate;
    if (firstDueDate == null) return false;

    final terms = Debt(
      id: stored.id,
      direction: stored.direction,
      name: name,
      category: category,
      principal: principal,
      status: stored.status,
      perPayment: perPayment,
      paymentCount: paymentCount,
      lastPayment: lastPayment,
      frequency: stored.frequency,
      firstDueDate: firstDueDate,
      billId: billId,
      paidBefore: stored.paidBefore,
      otherKind: otherKind,
      paidWithWalletId: paidWithWalletId,
      paidWithLabel: paidWithLabel,
    );
    final lastDue = terms.lastDueDate;
    if (lastDue == null) return false;

    final batch = _firestore.batch();

    // Written one field at a time, with the ones that no longer apply set to
    // nothing, so an earlier answer can't be left over on the record.
    batch.set(_debts.doc(stored.id), {
      'name': name.trim(),
      'category': category.name,
      'principal': principal,
      'perPayment': perPayment,
      'paymentCount': paymentCount,
      'lastPayment': terms.hasDifferentLastPayment ? terms.finalPayment : null,
      'otherKind': _noteOrNull(otherKind),
      'paidWithWalletId': _noteOrNull(paidWithWalletId),
      'paidWithLabel': _noteOrNull(paidWithLabel),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    BillService.addInstallmentUpdateToBatch(
      batch,
      billId: billId,
      name: name,
      amount: perPayment,
      firstDueDate: firstDueDate,
      recurrence: stored.frequency.recurrence,
      endDate: lastDue,
      lastAmount: terms.hasDifferentLastPayment ? terms.finalPayment : null,
      interestShare: terms.interestShare,
    );

    for (final edit in recalculateInstallmentPayments(
      terms: terms,
      instances: instances,
    )) {
      final reference = BillService.instanceReference(edit.instance.id);
      if (edit.removes) {
        batch.delete(reference);
        continue;
      }

      // Only what the edit changes, so anything recorded on the payment
      // already is left exactly as it is.
      batch.set(reference, {
        'amount': edit.amount,
        'name': edit.name,
        'interestShare': edit.interestShare,
        // Money a removed payment was carrying is owed again by the
        // payment it came from.
        if (edit.reopenCarry) 'carriedInto': null,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    }

    commitFirestoreWrite(batch.commit(), 'update installment');
    return true;
  }

  /// Gives loans saved before interest was kept apart the same split as new
  /// ones, so every account's Reports show what borrowing cost. Each is done
  /// once; offline, it waits for the next start.
  ///
  /// Installments are left as they are: they no longer carry interest, so
  /// filling theirs now would wipe the interest saved on older ones.
  static Future<void> fillInterestShares() async {
    try {
      final snapshot = await _debts.get();
      for (final doc in snapshot.docs) {
        final debt = Debt.fromMap(doc.id, doc.data());
        final billId = debt.billId;
        if (debt.direction != DebtDirection.iOwe || billId == null) continue;
        if (!debt.category.isLoan) continue;
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

    final reference = _debts.doc(debt.id);
    final charges = await reference.collection('interestCharges').get();
    // Firestore batches are limited to 500 writes. A daily-interest debt can
    // accumulate more charge records than that over its lifetime.
    for (var start = 0; start < charges.docs.length; start += 400) {
      final batch = _firestore.batch();
      for (final charge in charges.docs.skip(start).take(400)) {
        batch.delete(charge.reference);
      }
      await batch.commit();
    }
    final batch = _firestore.batch()..delete(reference);
    commitFirestoreWrite(batch.commit(), 'delete debt');
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

  /// The payment of [debt] still waiting to be paid: the first one neither
  /// settled nor covered by the payments made before it was tracked, with
  /// its occurrence ensured when the Bill Planner has not opened that month
  /// yet. Null when nothing waits.
  static Future<DebtNextPayment?> loadNextUnpaidPayment(Debt debt) async {
    final billId = debt.billId;
    if (billId == null) return null;

    // The early-payoff record is not one of the plan's payments; the
    // statement leaves it out for the same reason.
    final payoffId = BillService.payoffInstanceId(billId);
    final occurrences = [
      for (final instance in await BillService.loadInstancesForBill(billId))
        if (instance.id != payoffId) instance,
    ];

    final waiting = nextUnpaidPayment(debt, occurrences);
    if (waiting == null) return null;

    var instance = waiting.instance;
    if (instance == null) {
      // The month was never opened in the Bill Planner, so no record stands
      // for the payment. The planner makes them the same way when a month
      // is opened: one for this bill, and nothing changes for the others.
      final monthTaken = occurrences.any(
        (occurrence) =>
            occurrence.dueDate.year == waiting.due.year &&
            occurrence.dueDate.month == waiting.due.month,
      );
      if (monthTaken) return null;

      final bill = await BillService.loadBill(billId);
      if (bill == null) return null;
      await BillService.ensureInstances(
        bills: [bill],
        year: waiting.due.year,
        month: waiting.due.month,
      );
      instance = await BillService.loadInstance(
        billInstanceId(billId, waiting.due),
      );
      if (instance == null) return null;
    }

    return DebtNextPayment(
      number: waiting.number,
      due: instance.dueDate,
      scheduledAmount: waiting.scheduledAmount,
      instance: instance,
    );
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
