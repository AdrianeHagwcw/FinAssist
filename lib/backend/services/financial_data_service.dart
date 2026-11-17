import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../models/account_audit_log.dart';

/// Reads optional audit history for the authenticated account.
///
/// The existing domain services remain the source of truth for current
/// wallets, transactions, goals, debts and bills. This service only reads
/// change history and never accepts a user id from callers or chat text.
class FinancialDataService {
  static FirebaseFirestore get _firestore => FirebaseFirestore.instance;

  static CollectionReference<Map<String, dynamic>> get _auditLogs {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) throw StateError('No authenticated user.');
    return _firestore.collection('users').doc(user.uid).collection('auditLogs');
  }

  static Stream<List<AccountAuditLog>> watchAuditLogs() {
    return _auditLogs.snapshots().map(_parse);
  }

  static Future<List<AccountAuditLog>> loadAuditLogs() async =>
      _parse(await _auditLogs.get());

  static void recordInBatch(
    WriteBatch batch, {
    required String action,
    required String collection,
    required String documentId,
    double? previousAmount,
    double? updatedAmount,
  }) {
    final audit = _auditLogs.doc();
    batch.set(audit, {
      'action': action,
      'collection': collection,
      'documentId': documentId,
      'occurredAt': FieldValue.serverTimestamp(),
      'previousAmount': ?previousAmount,
      'updatedAmount': ?updatedAmount,
    });
  }

  static List<AccountAuditLog> _parse(
    QuerySnapshot<Map<String, dynamic>> snapshot,
  ) {
    final logs = [
      for (final doc in snapshot.docs)
        AccountAuditLog.fromMap(doc.id, doc.data()),
    ]..sort((a, b) => b.occurredAt.compareTo(a.occurredAt));
    return logs;
  }
}
