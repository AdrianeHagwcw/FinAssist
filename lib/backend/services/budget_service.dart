import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../models/allocation.dart';

/// The incomes logged with a plan, which feed the Safe-to-Spend card and
/// Cash Inflows.
///
/// These live on the profile rather than per wallet: they are about the
/// user's money as a whole, not one wallet.
class BudgetService {
  /// Complete history; the dashboard's small window must not hide old months.
  static Stream<List<AllocationCycle>> watchHistory() => _profile
      .collection('allocationCycles')
      .orderBy('receivedAt', descending: true)
      .snapshots()
      .map(
        (snapshot) => snapshot.docs
            .map((doc) => AllocationCycle.fromMap(doc.id, doc.data()))
            .toList(),
      );

  static DocumentReference<Map<String, dynamic>> get _profile {
    final user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      throw StateError('No authenticated user.');
    }

    return FirebaseFirestore.instance.collection('users').doc(user.uid);
  }

  /// The most recent allocation cycles, newest first, updating live.
  static Stream<List<AllocationCycle>> watchRecentCycles({int limit = 6}) {
    return _profile
        .collection('allocationCycles')
        .orderBy('receivedAt', descending: true)
        .limit(limit)
        .snapshots()
        .map(
          (snapshot) => snapshot.docs
              .map((doc) => AllocationCycle.fromMap(doc.id, doc.data()))
              .toList(),
        );
  }
}

double? plannedAllocationFrom(Map<String, dynamic>? profile, String key) {
  final allocations = profile?['plannedAllocations'];
  if (allocations is! Map) return null;
  final amount = allocations[key];
  return amount is num && amount.isFinite && amount >= 0
      ? amount.toDouble()
      : null;
}
