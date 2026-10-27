import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../models/app_transaction.dart';

/// Brings records written before wallets existed into the one ledger.
///
/// Nothing is deleted or edited: each old record is *copied* into
/// `transactions` and the original is left exactly where it is, so the older
/// screens keep working and a mistake here costs nothing.
///
/// Copies are marked `legacy: true` and carry no wallet, so they show up in
/// history but never move a balance. Without that, importing an expense the
/// user had already paid for out of a wallet whose starting balance they
/// entered by hand would subtract the same money twice.
///
/// Each copy reuses its source document's id, which makes the whole import
/// repeatable: running it again overwrites the same documents instead of
/// creating a second set.
class LegacyMigration {
  /// Firestore allows 500 writes per batch; this leaves room to spare.
  static const int _batchLimit = 400;

  static FirebaseFirestore get _firestore => FirebaseFirestore.instance;

  static DocumentReference<Map<String, dynamic>> get _profile {
    final user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      throw StateError('No authenticated user.');
    }

    return _firestore.collection('users').doc(user.uid);
  }

  /// Turns an old `expenses` document into a ledger entry.
  static Map<String, dynamic> expenseToTransaction(Map<String, dynamic> data) {
    final description = _text(data['description']);
    final notes = _text(data['notes']);

    return _entry(
      type: TransactionType.expense,
      amount: _amount(data['amount']),
      label: _text(data['category']) ?? 'Others',
      note: description ?? notes,
      date: _date(data['date']) ?? _date(data['createdAt']),
    );
  }

  /// Turns an old `dailyIncomeTransactions` document into a ledger entry.
  static Map<String, dynamic> incomeToTransaction(Map<String, dynamic> data) {
    return _entry(
      type: TransactionType.income,
      amount: _amount(data['amount']),
      label: _text(data['source']) ?? 'Income',
      note: _text(data['notes']),
      date: _date(data['date']) ?? _date(data['createdAt']),
    );
  }

  static Map<String, dynamic> _entry({
    required TransactionType type,
    required double amount,
    required String label,
    required String? note,
    required DateTime? date,
  }) {
    return {
      'type': type.name,
      'amount': amount,
      'label': label,
      // No wallet: these predate wallets, so they must not move a balance.
      'walletId': null,
      'toWalletId': null,
      'note': note,
      'date': Timestamp.fromDate(date ?? DateTime.now()),
      'legacy': true,
      'createdAt': FieldValue.serverTimestamp(),
    };
  }

  /// How many old records have not been copied across yet.
  static Future<int> countPending() async {
    final pending = await _pending();
    return pending.length;
  }

  /// Copies the outstanding records and returns how many were copied.
  static Future<int> run() async {
    final pending = await _pending();

    if (pending.isEmpty) return 0;

    final transactions = _profile.collection('transactions');

    for (var start = 0; start < pending.length; start += _batchLimit) {
      final end = (start + _batchLimit).clamp(0, pending.length);
      final batch = _firestore.batch();

      for (final record in pending.sublist(start, end)) {
        batch.set(transactions.doc(record.id), record.data);
      }

      await batch.commit();
    }

    await _profile.set({
      'legacyImportedAt': FieldValue.serverTimestamp(),
      'legacyImportedCount': pending.length,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    return pending.length;
  }

  /// Old records with no ledger entry yet. Anything already in `transactions`
  /// under the same id is skipped, which is what keeps repeat runs safe and
  /// leaves entries written by the app itself untouched.
  static Future<List<_PendingRecord>> _pending() async {
    final existingIds = (await _profile.collection('transactions').get()).docs
        .map((doc) => doc.id)
        .toSet();

    final expenses = await _profile.collection('expenses').get();
    final income = await _profile.collection('dailyIncomeTransactions').get();

    return [
      for (final doc in expenses.docs)
        if (!existingIds.contains(doc.id))
          _PendingRecord(doc.id, expenseToTransaction(doc.data())),
      for (final doc in income.docs)
        if (!existingIds.contains(doc.id))
          _PendingRecord(doc.id, incomeToTransaction(doc.data())),
    ];
  }

  static double _amount(Object? value) =>
      value is num ? value.toDouble().abs() : 0;

  static String? _text(Object? value) {
    if (value is! String) return null;
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  static DateTime? _date(Object? value) {
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    return null;
  }
}

class _PendingRecord {
  const _PendingRecord(this.id, this.data);

  final String id;
  final Map<String, dynamic> data;
}
