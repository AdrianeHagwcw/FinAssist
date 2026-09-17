import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../models/app_transaction.dart';
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

  static Stream<Debt?> watchDebt(String id) {
    return _debts
        .doc(id)
        .snapshots()
        .map((doc) => doc.exists ? Debt.fromMap(doc.id, doc.data()) : null);
  }

  /// Saves an installment or loan the user is paying back.
  ///
  /// The terms, the payment schedule in the Bill Planner, and (when
  /// [receivedIntoWalletId] is given) the borrowed money arriving in a wallet
  /// all go in one batch. The schedule ends on the last payment's date, so it
  /// never asks for a thirteenth payment on a twelve-month plan.
  static String addInstallment({
    required String name,
    required DebtCategory category,
    required double principal,
    required double perPayment,
    required int paymentCount,
    required PaymentFrequency frequency,
    required DateTime firstDueDate,
    String? payFromWalletId,
    String? receivedIntoWalletId,
    String? note,
  }) {
    final batch = _firestore.batch();
    final debt = _debts.doc();
    final bill = BillService.newBillReference();

    final lastDue = Debt(
      id: debt.id,
      direction: DebtDirection.iOwe,
      name: name,
      category: category,
      principal: principal,
      perPayment: perPayment,
      paymentCount: paymentCount,
      frequency: frequency,
      firstDueDate: firstDueDate,
      status: DebtStatus.active,
    ).lastDueDate!;

    batch.set(debt, {
      'direction': DebtDirection.iOwe.name,
      'name': name.trim(),
      'category': category.name,
      'principal': principal,
      'perPayment': perPayment,
      'paymentCount': paymentCount,
      'frequency': frequency.name,
      'firstDueDate': Timestamp.fromDate(firstDueDate),
      'billId': bill.id,
      'note': _noteOrNull(note),
      'status': DebtStatus.active.name,
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
      walletId: payFromWalletId,
      endDate: lastDue,
      debtId: debt.id,
    );

    if (receivedIntoWalletId != null && principal > 0) {
      WalletService.addTransactionToBatch(
        batch,
        type: TransactionType.income,
        amount: principal,
        label: 'Borrowed',
        walletId: receivedIntoWalletId,
        note: name,
        debtId: debt.id,
      );
    }

    commitFirestoreWrite(batch.commit(), 'add installment');
    return debt.id;
  }

  /// Saves money someone owes the user. When [lentFromWalletId] is given, the
  /// money leaving that wallet is recorded in the same batch.
  static String addLent({
    required String name,
    required double amount,
    DateTime? dueDate,
    String? lentFromWalletId,
    String? note,
  }) {
    final batch = _firestore.batch();
    final debt = _debts.doc();

    batch.set(debt, {
      'direction': DebtDirection.owedToMe.name,
      'name': name.trim(),
      'category': DebtCategory.familyFriend.name,
      'principal': amount,
      'received': 0,
      'dueDate': dueDate == null ? null : Timestamp.fromDate(dueDate),
      'note': _noteOrNull(note),
      'status': DebtStatus.active.name,
      'createdAt': FieldValue.serverTimestamp(),
    });

    if (lentFromWalletId != null) {
      WalletService.addTransactionToBatch(
        batch,
        type: TransactionType.expense,
        amount: amount,
        label: 'Lent',
        walletId: lentFromWalletId,
        note: name,
        debtId: debt.id,
      );
    }

    commitFirestoreWrite(batch.commit(), 'add money owed to me');
    return debt.id;
  }

  /// Records money paid back to the user into a wallet. Paying back the full
  /// amount settles it.
  static void recordRepayment(
    Debt debt, {
    required double amount,
    required String walletId,
  }) {
    if (!amount.isFinite || amount <= 0) {
      throw ArgumentError.value(amount, 'amount', 'Must be greater than zero.');
    }

    final batch = _firestore.batch();

    WalletService.addTransactionToBatch(
      batch,
      type: TransactionType.income,
      amount: amount,
      label: 'Repayment',
      walletId: walletId,
      note: debt.name,
      debtId: debt.id,
    );

    final settled = debt.received + amount + 0.005 >= debt.principal;
    batch.set(_debts.doc(debt.id), {
      'received': FieldValue.increment(amount),
      'status': (settled ? DebtStatus.settled : DebtStatus.active).name,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    commitFirestoreWrite(batch.commit(), 'record repayment');
  }

  /// Undoes one repayment: the money leaves the wallet again and is owed
  /// again.
  static void undoRepayment(Debt debt, AppTransaction repayment) {
    final batch = _firestore.batch();
    WalletService.removeTransactionFromBatch(batch, repayment);

    batch.set(_debts.doc(debt.id), {
      'received': FieldValue.increment(-repayment.amount),
      'status': DebtStatus.active.name,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    commitFirestoreWrite(batch.commit(), 'undo repayment');
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

  /// Marks money owed to the user as no longer expected back. Nothing moves
  /// between wallets.
  static void forgive(Debt debt) {
    commitFirestoreWrite(
      _debts.doc(debt.id).set({
        'status': DebtStatus.settled.name,
        'forgiven': true,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true)),
      'forgive debt',
    );
  }

  static String? _noteOrNull(String? note) {
    final trimmed = note?.trim();
    return trimmed == null || trimmed.isEmpty ? null : trimmed;
  }
}
