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

  /// Adds a goal at the end of the priority order.
  static void addGoal({
    required String name,
    required double targetAmount,
    DateTime? targetDate,
    required int priority,
  }) {
    commitFirestoreWrite(
      _goals.doc().set({
        'name': name.trim(),
        'targetAmount': targetAmount,
        'savedAmount': 0,
        'targetDate': targetDate == null
            ? null
            : Timestamp.fromDate(targetDate),
        'priority': priority,
        'status': GoalStatus.active.name,
        'createdAt': FieldValue.serverTimestamp(),
      }),
      'add goal',
    );
  }

  /// Changes a goal's details. Raising the target of a finished goal puts it
  /// back to active, since it is no longer reached.
  static void updateGoal(
    Goal goal, {
    required String name,
    required double targetAmount,
    DateTime? targetDate,
  }) {
    final reached = targetAmount > 0 && goal.shownSaved + 0.005 >= targetAmount;
    final status = goal.status == GoalStatus.used
        ? GoalStatus.used
        : reached
        ? GoalStatus.completed
        : GoalStatus.active;

    commitFirestoreWrite(
      _goals.doc(goal.id).set({
        'name': name.trim(),
        'targetAmount': targetAmount,
        'targetDate': targetDate == null
            ? null
            : Timestamp.fromDate(targetDate),
        'status': status.name,
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
