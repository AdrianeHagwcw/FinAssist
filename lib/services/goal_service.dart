import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../models/goal.dart';
import 'firestore_write.dart';

/// Reads and writes goals and the money set aside for them.
class GoalService {
  static FirebaseFirestore get _firestore => FirebaseFirestore.instance;

  static CollectionReference<Map<String, dynamic>> get _goals {
    final user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      throw StateError('No authenticated user.');
    }

    return _firestore.collection('users').doc(user.uid).collection('goals');
  }

  /// Every goal, in priority order, updating live.
  static Stream<List<Goal>> watchGoals() {
    return _goals.snapshots().map(
      (snapshot) => sortGoals(
        snapshot.docs.map((doc) => Goal.fromMap(doc.id, doc.data())),
      ),
    );
  }

  static Stream<Goal?> watchGoal(String goalId) {
    return _goals
        .doc(goalId)
        .snapshots()
        .map((doc) => doc.exists ? Goal.fromMap(doc.id, doc.data()) : null);
  }

  /// A goal's contributions, newest first.
  static Stream<List<GoalContribution>> watchContributions(String goalId) {
    return _goals
        .doc(goalId)
        .collection('contributions')
        .orderBy('date', descending: true)
        .snapshots()
        .map(
          (snapshot) => snapshot.docs
              .map((doc) => GoalContribution.fromMap(doc.id, doc.data()))
              .toList(),
        );
  }

  /// Every contribution to every goal, updating live, in no set order.
  ///
  /// Contributions live under each goal, so this follows the goals and keeps
  /// one feed open per goal. Each call returns its own stream.
  static Stream<List<GoalContribution>> watchAllContributions() {
    late final StreamController<List<GoalContribution>> controller;
    StreamSubscription<List<Goal>>? goalsSubscription;
    final perGoal = <String, StreamSubscription<List<GoalContribution>>>{};
    final byGoal = <String, List<GoalContribution>>{};

    void emit() {
      if (!controller.isClosed) {
        controller.add([for (final list in byGoal.values) ...list]);
      }
    }

    controller = StreamController<List<GoalContribution>>(
      onListen: () {
        goalsSubscription = watchGoals().listen((goals) {
          final ids = {for (final goal in goals) goal.id};

          for (final id in perGoal.keys.toList()) {
            if (ids.contains(id)) continue;
            perGoal.remove(id)?.cancel();
            byGoal.remove(id);
          }

          for (final id in ids) {
            perGoal[id] ??= watchContributions(id).listen((list) {
              byGoal[id] = list;
              emit();
            }, onError: controller.addError);
          }

          // Keeps the total right when goals are removed, or there are none.
          emit();
        }, onError: controller.addError);
      },
      onCancel: () {
        goalsSubscription?.cancel();
        for (final subscription in perGoal.values) {
          subscription.cancel();
        }
        perGoal.clear();
      },
    );

    return controller.stream;
  }

  /// Adds a goal at the end of the priority order.
  ///
  /// [alreadySavedByWallet] is money the user had set aside before using the
  /// app, by the wallet it is in: cash and a bank account together give two
  /// entries. Each is recorded as a first contribution in the same batch as
  /// the goal, so Safe to Spend leaves it alone straight away.
  static void addGoal({
    required String name,
    required double targetAmount,
    DateTime? targetDate,
    required int priority,
    GoalKind kind = GoalKind.regular,
    ContributionFrequency frequency = ContributionFrequency.monthly,
    SavingInterval? customInterval,
    double? planAmount,
    String? walletId,
    GoalFundingSource? fundingSource,
    String? note,
    Map<String, double> alreadySavedByWallet = const {},
  }) {
    final savedByWallet = {
      for (final entry in alreadySavedByWallet.entries)
        if (entry.value > 0) entry.key: entry.value,
    };
    final alreadySaved = savedByWallet.values.fold<double>(
      0,
      (total, amount) => total + amount,
    );
    final batch = _firestore.batch();

    addGoalToBatch(
      batch,
      reference: _goals.doc(),
      name: name,
      targetAmount: targetAmount,
      targetDate: targetDate,
      priority: priority,
      kind: kind,
      frequency: frequency,
      customInterval: customInterval,
      planAmount: planAmount,
      walletId: walletId,
      fundingSource: fundingSource,
      note: note,
      savedAmount: alreadySaved,
      savedByWallet: savedByWallet,
      startingSaved: alreadySaved,
    );

    commitFirestoreWrite(batch.commit(), 'add goal');
  }

  /// Adds an onboarding goal to the caller's batch so all setup data is
  /// committed together.
  static void addGoalToBatch(
    WriteBatch batch, {
    required DocumentReference<Map<String, dynamic>> reference,
    required String name,
    required double targetAmount,
    DateTime? targetDate,
    required int priority,
    GoalKind kind = GoalKind.regular,
    ContributionFrequency frequency = ContributionFrequency.monthly,
    SavingInterval? customInterval,
    double? planAmount,
    String? walletId,
    GoalFundingSource? fundingSource,
    String? note,
    double savedAmount = 0,
    Map<String, double> savedByWallet = const {},
    double startingSaved = 0,
  }) {
    final now = DateTime.now();
    final status = targetAmount > 0 && savedAmount + 0.005 >= targetAmount
        ? GoalStatus.completed
        : GoalStatus.active;
    batch.set(reference, {
      'name': name.trim(),
      'targetAmount': targetAmount,
      // Money already set aside for this goal when it was created. It is a
      // claim on the wallet balance, not a transfer, so no balance moves.
      'savedAmount': savedAmount,
      if (savedByWallet.isNotEmpty) 'savedByWallet': savedByWallet,
      'targetDate': targetDate == null ? null : Timestamp.fromDate(targetDate),
      'priority': priority,
      'status': status.name,
      if (status == GoalStatus.completed)
        'completedAt': FieldValue.serverTimestamp(),
      ..._planFields(
        kind: kind,
        frequency: frequency,
        customInterval: customInterval,
        planAmount: planAmount,
        walletId: walletId,
        note: note,
      ),
      if (fundingSource != null) 'fundingSource': fundingSource.name,
      'startingSaved': startingSaved,
      // Kept on the device's clock: a server timestamp is empty until it
      // syncs, and the plan needs a start date straight away.
      'planStartedAt': Timestamp.fromDate(now),
      'createdAt': FieldValue.serverTimestamp(),
    });
    for (final entry in savedByWallet.entries) {
      if (entry.value <= 0) continue;
      batch.set(reference.collection('contributions').doc(), {
        'amount': entry.value,
        'walletId': entry.key,
        'date': Timestamp.fromDate(now),
        'createdAt': FieldValue.serverTimestamp(),
      });
    }
  }

  static Map<String, dynamic> _planFields({
    required GoalKind kind,
    required ContributionFrequency frequency,
    required SavingInterval? customInterval,
    required double? planAmount,
    required String? walletId,
    required String? note,
  }) {
    final trimmed = note?.trim();
    // Kept only with Custom, so a preset never carries an old custom rhythm.
    final custom = frequency == ContributionFrequency.custom
        ? customInterval
        : null;

    return {
      'kind': kind.name,
      'frequency': frequency.name,
      'frequencyEvery': custom?.count,
      'frequencyUnit': custom?.unit.name,
      'planAmount': planAmount != null && planAmount > 0 ? planAmount : null,
      'walletId': walletId,
      'note': trimmed == null || trimmed.isEmpty ? null : trimmed,
    };
  }

  /// Changes a goal's details. Raising the target of a finished goal puts it
  /// back to active, since it is no longer reached.
  static void updateGoal(
    Goal goal, {
    required String name,
    required double targetAmount,
    DateTime? targetDate,
    GoalKind? kind,
    ContributionFrequency? frequency,
    SavingInterval? customInterval,
    double? planAmount,
    String? walletId,
    String? note,
  }) {
    final newFrequency = frequency ?? goal.frequency;
    final newInterval = newFrequency == ContributionFrequency.custom
        ? customInterval ?? goal.customInterval
        : null;
    final reached = targetAmount > 0 && goal.shownSaved + 0.005 >= targetAmount;
    final status = goal.status == GoalStatus.used
        ? GoalStatus.used
        : reached
        ? GoalStatus.completed
        : GoalStatus.active;

    // Changing the plan restarts its clock, so the user isn't shown as behind
    // for months that were under the old plan.
    final planChanged =
        planAmount != goal.planAmount ||
        newFrequency != goal.frequency ||
        (newFrequency == ContributionFrequency.custom &&
            newInterval != goal.customInterval);

    commitFirestoreWrite(
      _goals.doc(goal.id).set({
        'name': name.trim(),
        'targetAmount': targetAmount,
        'targetDate': targetDate == null
            ? null
            : Timestamp.fromDate(targetDate),
        'status': status.name,
        ..._planFields(
          kind: kind ?? goal.kind,
          frequency: newFrequency,
          customInterval: newInterval,
          planAmount: planAmount,
          walletId: walletId ?? goal.walletId,
          note: note,
        ),
        'savedByWallet': goal.savedByWallet.isNotEmpty
            ? goal.savedByWallet
            : goal.shownSaved > 0
            ? {goal.walletId ?? '': goal.shownSaved}
            : const <String, double>{},
        if (planChanged) ...{
          'planStartedAt': Timestamp.fromDate(DateTime.now()),
          'startingSaved': goal.shownSaved,
        },
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true)),
      'update goal',
    );
  }

  /// Deletes a goal and its history. Whatever was set aside for it becomes
  /// spendable again; no wallet balance changes, because the money never
  /// left the wallet.
  static Future<void> deleteGoal(Goal goal) async {
    final contributions = await _goals
        .doc(goal.id)
        .collection('contributions')
        .get();

    final batch = _firestore.batch();
    for (final doc in contributions.docs) {
      batch.delete(doc.reference);
    }
    batch.delete(_goals.doc(goal.id));

    commitFirestoreWrite(batch.commit(), 'delete goal');
  }

  /// Saves a new priority order: first in the list gets money first.
  static void reorder(List<Goal> goals) {
    final batch = _firestore.batch();

    for (var i = 0; i < goals.length; i++) {
      if (goals[i].priority == i) continue;
      batch.set(_goals.doc(goals[i].id), {
        'priority': i,
      }, SetOptions(merge: true));
    }

    commitFirestoreWrite(batch.commit(), 'reorder goals');
  }

  /// Sets money aside for a goal, or takes it back out when [amount] is
  /// negative.
  static void contribute(
    Goal goal, {
    required double amount,
    required String walletId,
    DateTime? date,
  }) {
    final batch = _firestore.batch();
    addContributionToBatch(
      batch,
      goal: goal,
      amount: amount,
      walletId: walletId,
      date: date,
    );
    commitFirestoreWrite(batch.commit(), 'contribute to goal');
  }

  /// Sets money aside for a goal from several wallets at once, one
  /// contribution each, in one write. Each is worked out from the goal as the
  /// one before left it, so their per-wallet amounts never overwrite each
  /// other.
  static void contributeFromWallets(
    Goal goal,
    Map<String, double> amounts, {
    DateTime? date,
  }) {
    final batch = _firestore.batch();
    var running = goal;
    for (final entry in amounts.entries) {
      if (entry.value <= 0) continue;
      addContributionToBatch(
        batch,
        goal: running,
        amount: entry.value,
        walletId: entry.key,
        date: date,
      );
      running = running.withContribution(entry.key, entry.value);
    }
    commitFirestoreWrite(batch.commit(), 'contribute to goal');
  }

  /// The batch counterpart of [contribute], for the income waterfall.
  ///
  /// The goal's status follows its new total: reaching the target completes
  /// it, and taking money back out of a completed goal reopens it.
  static void addContributionToBatch(
    WriteBatch batch, {
    required Goal goal,
    required double amount,
    required String walletId,
    DateTime? date,
    String? cycleId,
  }) {
    if (!amount.isFinite || amount == 0) {
      throw ArgumentError.value(amount, 'amount', 'Must not be zero.');
    }

    final reference = _goals.doc(goal.id);
    final newTotal = goal.shownSaved + amount;
    final reached =
        goal.targetAmount > 0 && newTotal + 0.005 >= goal.targetAmount;
    final savedByWallet = goal.savedByWallet.isNotEmpty
        ? Map<String, double>.from(goal.savedByWallet)
        : <String, double>{
            if (goal.shownSaved > 0)
              (goal.walletId ?? walletId): goal.shownSaved,
          };
    final walletAmount = (savedByWallet[walletId] ?? 0) + amount;
    if (amount < 0 && walletAmount < -0.005) {
      throw ArgumentError('This wallet does not hold that much for the goal.');
    }
    if (walletAmount.abs() < 0.005) {
      savedByWallet.remove(walletId);
    } else {
      savedByWallet[walletId] = walletAmount;
    }

    batch.set(reference.collection('contributions').doc(), {
      'amount': amount,
      'walletId': walletId,
      'date': Timestamp.fromDate(date ?? DateTime.now()),
      'cycleId': cycleId,
      'createdAt': FieldValue.serverTimestamp(),
    });

    batch.set(reference, {
      'savedAmount': FieldValue.increment(amount),
      'savedByWallet': savedByWallet,
      if (goal.status != GoalStatus.used)
        'status': (reached ? GoalStatus.completed : GoalStatus.active).name,
      if (reached && goal.status == GoalStatus.active)
        'completedAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  /// Marks a reached goal's money as spent on what it was for. It stops being
  /// set aside, and the goal stays as a record.
  /// Moves [amount] of [goal]'s money from wallet [from] to [to] in
  /// [batch], as when a time deposit matures and is taken out: the goal
  /// keeps its money, now in the wallet it really went to, so it stays set
  /// aside there rather than being counted as free to spend.
  static void moveMoneyInBatch(
    WriteBatch batch,
    Goal goal, {
    required String from,
    required String to,
    required double amount,
  }) {
    if (amount <= 0 || from == to) return;
    final Map<String, Object> moved;
    if (goal.savedByWallet.isNotEmpty) {
      moved = {
        from: FieldValue.increment(-amount),
        to: FieldValue.increment(amount),
      };
    } else {
      // Saved before the per-wallet amounts: all of it was in [from].
      final left = ((goal.shownSaved - amount) * 100).round() / 100;
      moved = {if (left > 0.005) from: left, to: amount};
    }
    batch.set(_goals.doc(goal.id), {
      'savedByWallet': moved,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  static void markUsed(Goal goal) {
    commitFirestoreWrite(
      _goals.doc(goal.id).set({
        'status': GoalStatus.used.name,
        'usedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true)),
      'mark goal used',
    );
  }
}
