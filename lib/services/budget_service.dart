import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../models/allocation.dart';
import 'firestore_write.dart';

/// The daily limit, the savings set aside, and the leftover decisions that
/// feed the Safe-to-Spend card.
///
/// These live on the profile rather than per wallet: a daily limit and money
/// set aside are about the user's spending as a whole, not one wallet.
class BudgetService {
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

  /// Saves a daily limit the user typed. Null goes back to the recommended
  /// figure, which is worked out fresh each day instead of being stored.
  static void setDailyLimit(double? customLimit) {
    commitFirestoreWrite(
      _profile.set({
        'dailyLimitMode': customLimit == null ? 'recommended' : 'custom',
        'dailyBudget': customLimit ?? FieldValue.delete(),
        'budget': customLimit ?? FieldValue.delete(),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true)),
      'set daily limit',
    );
  }

  /// Replaces how much is set aside as savings, for when the user has spent
  /// some of it or wants to set more aside by hand.
  static void setSavingsReserve(double amount) {
    commitFirestoreWrite(
      _profile.set({
        'savingsReserve': amount < 0 ? 0 : amount,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true)),
      'set savings reserve',
    );
  }

  /// Records what the user decided about a cycle's leftover.
  ///
  /// Whatever is saved is added to the savings set aside in the same batch,
  /// so the Safe-to-Spend figure stops counting it as spendable at the same
  /// moment the cycle is marked saved.
  static void resolveLeftover({
    required AllocationCycle cycle,
    required LeftoverDecision decision,
    double saved = 0,
    double spent = 0,
  }) {
    final batch = FirebaseFirestore.instance.batch();

    batch.set(_profile.collection('allocationCycles').doc(cycle.id), {
      'leftoverDecision': decision.name,
      'leftoverSaved': saved,
      'leftoverSpent': spent,
      'leftoverDecidedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    if (saved > 0) {
      batch.set(_profile, {
        'savingsReserve': FieldValue.increment(saved),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    }

    commitFirestoreWrite(batch.commit(), 'resolve leftover');
  }
}

/// The daily limit a profile has chosen, or null to use the recommendation.
///
/// Profiles made before the recommendation existed have a `dailyBudget` and
/// no mode. Their limit was typed by hand, so it is honoured as a custom one.
double? customDailyLimitFrom(Map<String, dynamic>? profile) {
  final mode = profile?['dailyLimitMode'];
  final stored = profile?['dailyBudget'] ?? profile?['budget'];
  final amount = stored is num ? stored.toDouble() : null;

  if (mode == 'recommended') return null;
  if (amount == null || amount <= 0) return null;
  return amount;
}

double savingsReserveFrom(Map<String, dynamic>? profile) {
  final value = profile?['savingsReserve'];
  return value is num && value > 0 ? value.toDouble() : 0;
}
