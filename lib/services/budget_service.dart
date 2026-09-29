import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../models/allocation.dart';
import '../models/app_transaction.dart';
import '../models/wallet.dart';
import 'firestore_write.dart';
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
  /// Whatever is saved is moved into the savings wallet in the same batch, so
  /// it leaves the spending balance at the very moment the cycle is marked
  /// saved. [wallets] is the current list, used to find that wallet or create
  /// it; without a wallet to take the money from, the amount is only recorded
  /// against the cycle.
  static void resolveLeftover({
    required AllocationCycle cycle,
    required LeftoverDecision decision,
    double saved = 0,
    double spent = 0,
    List<Wallet> wallets = const [],
  }) {
    if (cycle.isResolved) {
      throw StateError('This cycle has already been reviewed.');
    }
    if (!saved.isFinite || !spent.isFinite || saved < 0 || spent < 0) {
      throw ArgumentError('Enter valid leftover amounts.');
    }
    final batch = FirebaseFirestore.instance.batch();

    batch.set(
      _profile.collection('allocationCycles').doc(cycle.id),
      {
        'leftoverDecision': decision.name,
        'leftoverSaved': saved,
        'leftoverSpent': spent,
        'leftoverDecidedAt': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );

    final from = cycle.walletId ?? _spendingWalletId(wallets);

    if (saved > 0 && from != null) {
      final savingsWalletId = WalletService.addPurposeWalletToBatch(
        batch,
        purpose: WalletPurpose.savings,
        wallets: wallets,
      );

      WalletService.addTransactionToBatch(
        batch,
        type: TransactionType.transfer,
        amount: saved,
        label: TransactionType.transfer.label,
        walletId: from,
        toWalletId: savingsWalletId,
        note: 'Saved from leftover',
        date: DateTime.now(),
      );
    }

    commitFirestoreWrite(batch.commit(), 'resolve leftover');
  }
}

/// The wallet a leftover is saved out of when the cycle no longer names one:
/// the wallet income is paid into, else the first wallet the user can spend
/// from. Never the bills or savings wallet, which hold committed money.
String? _spendingWalletId(List<Wallet> wallets) {
  for (final wallet in wallets) {
    if (!wallet.archived && !wallet.isSetAside && wallet.receivesIncome) {
      return wallet.id;
    }
  }
  for (final wallet in wallets) {
    if (!wallet.archived && !wallet.isSetAside) return wallet.id;
  }
  return null;
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

/// The day the current pay period starts.
///
/// The payday the user entered during setup or in Financial preferences.
/// Recording income changes the available balance, but does not restart the
/// countdown; pay periods roll forward on the saved schedule.
DateTime? periodAnchor(
  Iterable<AllocationCycle> cycles,
  Map<String, dynamic>? profile,
) {
  return setupPaydayFrom(profile);
}

/// The payday the user gave during setup, before any income is recorded.
///
/// Without it a fresh account has nothing to count a pay period from, and
/// Home would fall back to the calendar instead of the user's own payday.
DateTime? setupPaydayFrom(Map<String, dynamic>? profile) {
  final value = profile?['lastPaydayAt'];
  if (value is Timestamp) return value.toDate();
  if (value is DateTime) return value;
  return null;
}

double savingsReserveFrom(Map<String, dynamic>? profile) {
  final value = profile?['savingsReserve'];
  return value is num && value > 0 ? value.toDouble() : 0;
}

double? plannedAllocationFrom(Map<String, dynamic>? profile, String key) {
  final allocations = profile?['plannedAllocations'];
  if (allocations is! Map) return null;
  final amount = allocations[key];
  return amount is num && amount.isFinite && amount >= 0
      ? amount.toDouble()
      : null;
}
