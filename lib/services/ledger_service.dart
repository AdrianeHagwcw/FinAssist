import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../models/app_transaction.dart';
import 'bill_service.dart';
import 'firestore_write.dart';
import 'wallet_service.dart';

/// Edits and deletes made from the Transactions screen.
///
/// A transaction can have copies elsewhere that must stay in step with it:
/// an expense made from Add Expense also lives in the older `expenses`
/// collection that Home's spending summary still reads, and a bill payment is
/// counted on the bill it paid. This keeps those in line instead of leaving
/// each screen to remember.
class LedgerService {
  static DocumentReference<Map<String, dynamic>> get _profile {
    final user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      throw StateError('No authenticated user.');
    }

    return FirebaseFirestore.instance.collection('users').doc(user.uid);
  }

  /// Why a transaction can't be edited here, or null when it can.
  static String? whyNotEditable(AppTransaction transaction) {
    if (transaction.isLegacy) {
      return 'This record is from before you had wallets, so it has no wallet '
          'to change. You can still delete it.';
    }

    if (transaction.isDebtMovement) {
      return 'This came from a loan or money lent. Manage it from Debts, so '
          'what is owed stays right.';
    }

    if (transaction.isBillPayment) {
      return 'This is a bill payment. Change it from the bill, so the bill '
          'stays in step. You can still delete it here.';
    }

    return null;
  }

  /// Loan movements are undone from Debts, where the amount owed is kept in
  /// step. Everything else can be deleted here.
  static bool canDeleteHere(AppTransaction transaction) =>
      !transaction.isDebtMovement;

  static Future<void> update(
    AppTransaction original, {
    required double amount,
    required String label,
    required String? walletId,
    String? toWalletId,
    String? note,
    required DateTime date,
  }) async {
    final reason = whyNotEditable(original);
    if (reason != null) throw StateError(reason);

    await WalletService.replaceTransaction(
      id: original.id,
      type: original.type,
      amount: amount,
      label: label,
      walletId: walletId,
      toWalletId: toWalletId,
      note: note,
      date: date,
    );

    if (original.type == TransactionType.expense) {
      await _mirrorExpense(
        original.id,
        amount: amount,
        category: label,
        note: note,
        date: date,
        walletId: walletId,
      );
    }
  }

  /// Deletes a transaction and puts back whatever it changed.
  ///
  /// A bill payment is undone through the bill, so the bill shows that much
  /// owing again as well as the money returning to the wallet.
  static Future<void> delete(AppTransaction transaction) async {
    final instanceId = transaction.billInstanceId;

    if (instanceId != null) {
      final instance = await BillService.loadInstance(instanceId);

      if (instance != null) {
        BillService.undoPayment(instance, transaction);
        return;
      }
    }

    WalletService.deleteTransaction(transaction);

    // Copies written by the older screens share the transaction's id.
    // Deleting a document that isn't there does nothing, so no read is needed.
    commitFirestoreWrite(
      _profile.collection('expenses').doc(transaction.id).delete(),
      'delete expense copy',
    );
    commitFirestoreWrite(
      _profile
          .collection('dailyIncomeTransactions')
          .doc(transaction.id)
          .delete(),
      'delete income copy',
    );
  }

  /// Updates the older `expenses` copy of an expense, if it has one. It is
  /// never created here: an expense recorded somewhere else, like a bill
  /// payment, was never in that collection.
  static Future<void> _mirrorExpense(
    String id, {
    required double amount,
    required String category,
    required String? note,
    required DateTime date,
    required String? walletId,
  }) async {
    final reference = _profile.collection('expenses').doc(id);

    try {
      final snapshot = await reference.get();
      if (!snapshot.exists) return;
    } on FirebaseException {
      return;
    }

    commitFirestoreWrite(
      reference.set({
        'amount': amount,
        'category': category,
        'description': note ?? '',
        'date': Timestamp.fromDate(date),
        'walletId': walletId,
      }, SetOptions(merge: true)),
      'update expense copy',
    );
  }
}
