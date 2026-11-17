import 'package:cloud_firestore/cloud_firestore.dart';

/// A change record written by the account data layer, when audit history is
/// available. Audit records supplement current records; they never replace
/// them.
class AccountAuditLog {
  const AccountAuditLog({
    required this.id,
    required this.action,
    required this.collection,
    required this.documentId,
    required this.occurredAt,
    this.previousAmount,
    this.updatedAmount,
  });

  factory AccountAuditLog.fromMap(String id, Map<String, dynamic>? data) {
    final map = data ?? const <String, dynamic>{};
    return AccountAuditLog(
      id: id,
      action:
          _string(map['action']) ??
          _string(map['operation']) ??
          _string(map['changeType']) ??
          'updated',
      collection:
          _string(map['collection']) ??
          _string(map['collectionName']) ??
          'unknown',
      documentId:
          _string(map['documentId']) ??
          _string(map['recordId']) ??
          _string(map['resourceId']) ??
          '',
      occurredAt:
          _date(map['occurredAt']) ??
          _date(map['timestamp']) ??
          _date(map['createdAt']) ??
          DateTime.fromMillisecondsSinceEpoch(0),
      previousAmount: _amount(
        map['previousAmount'] ??
            map['oldAmount'] ??
            _nestedAmount(map['before']),
      ),
      updatedAmount: _amount(
        map['updatedAmount'] ?? map['newAmount'] ?? _nestedAmount(map['after']),
      ),
    );
  }

  final String id;
  final String action;
  final String collection;
  final String documentId;
  final DateTime occurredAt;
  final double? previousAmount;
  final double? updatedAmount;

  bool get isDeletion =>
      action.toLowerCase() == 'delete' ||
      action.toLowerCase() == 'deleted' ||
      action.toLowerCase() == 'remove' ||
      action.toLowerCase() == 'removed';

  static String? _string(Object? value) =>
      value is String && value.trim().isNotEmpty ? value.trim() : null;

  static DateTime? _date(Object? value) {
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    if (value is String) return DateTime.tryParse(value);
    return null;
  }

  static double? _amount(Object? value) {
    if (value is num && value.isFinite) return value.toDouble().abs();
    return null;
  }

  static Object? _nestedAmount(Object? value) =>
      value is Map ? value['amount'] : null;
}
