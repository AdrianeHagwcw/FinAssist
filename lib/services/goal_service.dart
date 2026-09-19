import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../models/goal.dart';
import 'firestore_write.dart';

/// Reads and writes savings goals and the money set aside for them.
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
  /// [alreadySaved] is money the user had put aside before using the app. It
  /// is recorded as a first contribution kept in [walletId], in the same
  /// batch as the goal, so Safe to Spend sets it aside straight away.
  static void addGoal({
    required String name,
    required double targetAmount,
    DateTime? targetDate,
    required int priority,
    GoalKind kind = GoalKind.regular,
    ContributionFrequency frequency = ContributionFrequency.monthly,
    double? planAmount,
    String? walletId,
    String? note,
    double alreadySaved = 0,
  }) {
    final batch = _firestore.batch();
    final reference = _goals.doc();
    final now = DateTime.now();

    batch.set(reference, {
      'name': name.trim(),
      'targetAmount': targetAmount,
      'savedAmount': 0,
      'targetDate': targetDate == null ? null : Timestamp.fromDate(targetDate),
      'priority': priority,
      'status': GoalStatus.active.name,
      ..._planFields(
        kind: kind,
        frequency: frequency,
        planAmount: planAmount,
        walletId: walletId,
        note: note,
      ),
      'startingSaved': alreadySaved > 0 ? alreadySaved : 0,
      // Kept on the device's clock: a server timestamp is empty until it
      // syncs, and the plan needs a start date straight away.
      'planStartedAt': Timestamp.fromDate(now),
      'createdAt': FieldValue.serverTimestamp(),
    });

    if (alreadySaved > 0 && walletId != null) {
      addContributionToBatch(
        batch,
        goal: Goal(
          id: reference.id,
          name: name,
          targetAmount: targetAmount,
          savedAmount: 0,
          priority: priority,
          status: GoalStatus.active,
        ),
        amount: alreadySaved,
        walletId: walletId,
        date: now,
      );
    }

    commitFirestoreWrite(batch.commit(), 'add goal');
  }

  static Map<String, dynamic> _planFields({
    required GoalKind kind,
    required ContributionFrequency frequency,
    required double? planAmount,
    required String? walletId,
    required String? note,
  }) {
    final trimmed = note?.trim();

    return {
      'kind': kind.name,
      'frequency': frequency.name,
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
    double? planAmount,
    String? walletId,
    String? note,
  }) {
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
        (frequency != null && frequency != goal.frequency);

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
          frequency: frequency ?? goal.frequency,
          planAmount: planAmount,
          walletId: walletId ?? goal.walletId,
          note: note,
        ),
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

    batch.set(reference.collection('contributions').doc(), {
      'amount': amount,
      'walletId': walletId,
      'date': Timestamp.fromDate(date ?? DateTime.now()),
      'cycleId': cycleId,
      'createdAt': FieldValue.serverTimestamp(),
    });

    batch.set(reference, {
      'savedAmount': FieldValue.increment(amount),
      if (goal.status != GoalStatus.used)
        'status': (reached ? GoalStatus.completed : GoalStatus.active).name,
      if (reached && goal.status == GoalStatus.active)
        'completedAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  /// Marks a reached goal's money as spent on what it was for. It stops being
  /// set aside, and the goal stays as a record.
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
