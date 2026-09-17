import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart' show IconData, Icons;

/// What a goal is for. Only a label and an icon; the saving works the same.
enum GoalKind {
  regular('Regular goal', Icons.flag_outlined),
  emergencyFund('Emergency fund', Icons.health_and_safety_outlined),
  savingsAccount('Savings account', Icons.account_balance_outlined),
  timeDeposit('Time deposit', Icons.lock_clock_outlined);

  const GoalKind(this.label, this.icon);

  final String label;
  final IconData icon;

  static GoalKind fromName(String? name) => GoalKind.values.firstWhere(
    (kind) => kind.name == name,
    orElse: () => GoalKind.regular,
  );
}

/// How often the user means to put money toward a goal. Kept to the rhythms
/// a student's money actually arrives in.
enum ContributionFrequency {
  weekly('Weekly', 'a week', 52 / 12),
  twiceMonthly('Twice a month', 'twice a month', 2),
  monthly('Monthly', 'a month', 1);

  const ContributionFrequency(this.label, this.per, this.perMonth);

  final String label;

  /// Reads after an amount: "₱500 a week".
  final String per;

  /// How many contributions fall in a month.
  final double perMonth;

  /// Average days between contributions.
  double get days => 365.25 / 12 / perMonth;

  static ContributionFrequency fromName(String? name) =>
      ContributionFrequency.values.firstWhere(
        (frequency) => frequency.name == name,
        orElse: () => ContributionFrequency.monthly,
      );
}

/// Where a goal stands.
enum GoalStatus {
  /// Still being saved toward.
  active,

  /// Reached its target. The money is still set aside.
  completed,

  /// The user spent the money on what it was for, so it is no longer set
  /// aside. Kept as a record of what was achieved.
  used;

  static GoalStatus fromName(String? name) {
    return GoalStatus.values.firstWhere(
      (status) => status.name == name,
      orElse: () => GoalStatus.active,
    );
  }
}

/// Something the user is saving toward.
///
/// Money put toward a goal stays in the wallet it came from and is marked as
/// set aside, the way a student keeps laptop money in the same GCash as
/// everything else. The wallet's balance keeps matching what the real wallet
/// holds, and Safe to Spend stops counting that money as spendable.
class Goal {
  const Goal({
    required this.id,
    required this.name,
    required this.targetAmount,
    required this.savedAmount,
    required this.priority,
    required this.status,
    this.targetDate,
    this.kind = GoalKind.regular,
    this.frequency = ContributionFrequency.monthly,
    this.planAmount,
    this.walletId,
    this.note,
    this.planStartedAt,
    this.startingSaved = 0,
  });

  factory Goal.fromMap(String id, Map<String, dynamic>? data) {
    final map = data ?? const <String, dynamic>{};
    final name = map['name'] is String ? (map['name'] as String).trim() : '';
    final date = map['targetDate'];

    return Goal(
      id: id,
      name: name.isEmpty ? 'Goal' : name,
      targetAmount: _asDouble(map['targetAmount']).abs(),
      savedAmount: _asDouble(map['savedAmount']),
      priority: _asDouble(map['priority']).toInt(),
      status: GoalStatus.fromName(
        map['status'] is String ? map['status'] as String : null,
      ),
      targetDate: date is Timestamp ? date.toDate() : null,
      kind: GoalKind.fromName(
        map['kind'] is String ? map['kind'] as String : null,
      ),
      frequency: ContributionFrequency.fromName(
        map['frequency'] is String ? map['frequency'] as String : null,
      ),
      planAmount: map['planAmount'] is num && (map['planAmount'] as num) > 0
          ? (map['planAmount'] as num).toDouble()
          : null,
      walletId: map['walletId'] is String ? map['walletId'] as String : null,
      note: map['note'] is String && (map['note'] as String).isNotEmpty
          ? map['note'] as String
          : null,
      planStartedAt: map['planStartedAt'] is Timestamp
          ? (map['planStartedAt'] as Timestamp).toDate()
          : null,
      startingSaved: _asDouble(map['startingSaved']),
    );
  }

  final String id;
  final String name;
  final double targetAmount;

  /// Set aside so far. Never shown below zero.
  final double savedAmount;

  /// Lower comes first, and gets money first when income is allocated.
  final int priority;
  final GoalStatus status;
  final DateTime? targetDate;
  final GoalKind kind;

  /// How often the user plans to contribute.
  final ContributionFrequency frequency;

  /// How much each contribution is meant to be. Null when there's no plan.
  final double? planAmount;

  /// The wallet contributions usually go into.
  final String? walletId;
  final String? note;

  /// When the plan began, for telling whether the user is keeping up.
  final DateTime? planStartedAt;

  /// Already saved before the goal was added to the app.
  final double startingSaved;

  double get shownSaved => savedAmount > 0 ? savedAmount : 0;

  double get remaining {
    final left = targetAmount - shownSaved;
    return left > 0 ? left : 0;
  }

  /// 0 to 1.
  double get progress {
    if (targetAmount <= 0) return 0;
    return (shownSaved / targetAmount).clamp(0.0, 1.0).toDouble();
  }

  bool get isReached => targetAmount > 0 && shownSaved + 0.005 >= targetAmount;

  /// Money still set aside for this goal, which Safe to Spend leaves alone.
  double get setAside => status == GoalStatus.used ? 0 : shownSaved;

  static double _asDouble(Object? value) => value is num ? value.toDouble() : 0;
}

/// One amount put into, or taken back out of, a goal.
class GoalContribution {
  const GoalContribution({
    required this.id,
    required this.amount,
    required this.date,
    this.walletId,
  });

  factory GoalContribution.fromMap(String id, Map<String, dynamic>? data) {
    final map = data ?? const <String, dynamic>{};
    final date = map['date'];

    return GoalContribution(
      id: id,
      amount: map['amount'] is num ? (map['amount'] as num).toDouble() : 0,
      date: date is Timestamp ? date.toDate() : DateTime.now(),
      walletId: map['walletId'] is String ? map['walletId'] as String : null,
    );
  }

  final String id;

  /// Positive when money was set aside, negative when taken back out.
  final double amount;
  final DateTime date;

  /// The wallet the money was set aside in.
  final String? walletId;

  bool get isWithdrawal => amount < 0;
}

/// Goals in the order money should reach them.
List<Goal> sortGoals(Iterable<Goal> goals) {
  return goals.toList()..sort((a, b) {
    final byPriority = a.priority.compareTo(b.priority);
    return byPriority != 0 ? byPriority : a.name.compareTo(b.name);
  });
}

/// Money set aside across every goal that hasn't been used yet.
double totalSetAside(Iterable<Goal> goals) =>
    goals.fold<double>(0, (total, goal) => total + goal.setAside);

/// When the goal will be reached at the pace the user has been saving, or
/// null when there isn't enough history to say.
///
/// The pace is everything set aside so far divided by the days since the first
/// contribution. One contribution, or a pace of nothing, gives no projection
/// rather than a made-up date.
DateTime? projectedCompletion(
  Goal goal,
  Iterable<GoalContribution> contributions, {
  required DateTime now,
}) {
  if (goal.isReached) return null;

  final history = contributions.toList()
    ..sort((a, b) => a.date.compareTo(b.date));
  if (history.length < 2) return null;

  final saved = history.fold<double>(0, (total, c) => total + c.amount);
  final days = now.difference(history.first.date).inDays;
  if (saved <= 0 || days < 1) return null;

  final perDay = saved / days;
  final daysToGo = (goal.remaining / perDay).ceil();
  return DateTime(now.year, now.month, now.day + daysToGo);
}

/// How much to put in each time to reach [remaining] by [targetDate], or null
/// without a date. A date already here or past means all of it now.
double? neededPerContribution({
  required double remaining,
  required DateTime? targetDate,
  required ContributionFrequency frequency,
  required DateTime now,
}) {
  if (targetDate == null) return null;
  if (remaining <= 0) return 0;

  final today = DateTime(now.year, now.month, now.day);
  final days = targetDate.difference(today).inDays;
  if (days <= 0) return remaining;

  // Rounded rather than floored: a year away is 11.99 average months, and
  // that is twelve monthly contributions, not eleven. At least one, even when
  // the date is days away.
  final contributions = (days / frequency.days).round();
  return remaining / (contributions < 1 ? 1 : contributions);
}

/// When a plan of [amount] each [frequency] reaches [remaining], or null
/// without a plan.
DateTime? reachedByPlan({
  required double remaining,
  required double? amount,
  required ContributionFrequency frequency,
  required DateTime now,
}) {
  if (amount == null || amount <= 0) return null;

  final today = DateTime(now.year, now.month, now.day);
  if (remaining <= 0) return today;

  final contributions = (remaining / amount - 1e-9).ceil();
  final days = (contributions * frequency.days).round();
  return today.add(Duration(days: days));
}

/// How far behind a goal's plan the saving is. Zero or less means on track.
///
/// The plan expects what was already saved at the start, plus one planned
/// amount for every full period since. A period not yet finished isn't
/// counted, so nobody is "behind" the day after starting.
double? behindPlan(Goal goal, {required DateTime now}) {
  final amount = goal.planAmount;
  final start = goal.planStartedAt;
  if (amount == null || start == null) return null;

  final days = now.difference(start).inDays;
  final periods = days < 0 ? 0 : (days / goal.frequency.days).floor();
  final expected = goal.startingSaved + amount * periods;
  final target = goal.targetAmount;

  // Never expect more than the goal itself.
  final capped = target > 0 && expected > target ? target : expected;
  return capped - goal.shownSaved;
}
