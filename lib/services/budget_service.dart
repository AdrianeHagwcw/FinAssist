import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../models/allocation.dart';
import '../models/app_transaction.dart';
import '../models/goal.dart';
import 'firestore_write.dart';
import 'goal_service.dart';
import 'wallet_service.dart';

/// The daily limit, the savings set aside, and the leftover decisions that
/// feed the Safe-to-Spend card.
///
/// These live on the profile rather than per wallet: a daily limit and money
/// set aside are about the user's spending as a whole, not one wallet.
class BudgetService {
  /// Complete history; the dashboard's small window must not hide old pending cycles.
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

  /// Records what the user decided about a cycle's leftover.
  ///
  /// What is saved goes where the user chose, in the same batch, so it stops
  /// counting as spending money the moment the cycle is marked saved: to a
  /// goal, whose money stays in the wallets it is in, or into a savings
  /// account, moved out of those wallets.
  static void resolveLeftover({
    required AllocationCycle cycle,
    required LeftoverDecision decision,
    double saved = 0,
    double spent = 0,
    LeftoverSaving? saving,
  }) {
    if (cycle.isResolved) {
      throw StateError('This cycle has already been reviewed.');
    }
    if (!saved.isFinite || !spent.isFinite || saved < 0 || spent < 0) {
      throw ArgumentError('Enter valid leftover amounts.');
    }
    if (saved > 0 && saving == null) {
      throw ArgumentError('Choose where to save it.');
    }
    final batch = FirebaseFirestore.instance.batch();

    batch.set(_profile.collection('allocationCycles').doc(cycle.id), {
      'leftoverDecision': decision.name,
      'leftoverSaved': saved,
      'leftoverSpent': spent,
      'leftoverDecidedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    if (saved > 0 && saving != null) {
      final now = DateTime.now();
      final goal = saving.goal;
      final savingsId = saving.savingsWalletId;
      if (goal != null) {
        GoalService.addContributionsToBatch(
          batch,
          goal: goal,
          amounts: saving.from,
          date: now,
          cycleId: cycle.id,
        );
      } else if (savingsId != null) {
        final deltas = <String, double>{};
        for (final entry in saving.from.entries) {
          if (entry.value <= 0) continue;
          WalletService.addTransactionToBatch(
            batch,
            type: TransactionType.transfer,
            amount: entry.value,
            label: TransactionType.transfer.label,
            walletId: entry.key,
            toWalletId: savingsId,
            note: 'Saved from leftover',
            date: now,
            collectDeltasInto: deltas,
          );
        }
        WalletService.applyDeltasToBatch(batch, deltas);
      }
    }

    commitFirestoreWrite(batch.commit(), 'resolve leftover');
  }
}

/// Where a saved leftover goes: a [goal], whose money stays in the wallets
/// it is in, or the savings account [savingsWalletId], which it moves into.
/// [from] is how much of it is in each wallet.
class LeftoverSaving {
  const LeftoverSaving({this.goal, this.savingsWalletId, required this.from});

  final Goal? goal;
  final String? savingsWalletId;
  final Map<String, double> from;
}

double? plannedAllocationFrom(Map<String, dynamic>? profile, String key) {
  final allocations = profile?['plannedAllocations'];
  if (allocations is! Map) return null;
  final amount = allocations[key];
  return amount is num && amount.isFinite && amount >= 0
      ? amount.toDouble()
      : null;
}
