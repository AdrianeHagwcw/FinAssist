import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart' show IconData, Icons;

import '../utils/date_format.dart';
import '../utils/money_format.dart';
import 'wallet.dart';

/// What a goal is for. Only a label and an icon; the saving works the same.
enum GoalKind {
  regular('Regular goal', Icons.flag_outlined),
  emergencyFund('Emergency fund', Icons.health_and_safety_outlined),
  savingsAccount('Savings account', Icons.account_balance_outlined),
  timeDeposit('Time deposit', Icons.lock_clock_outlined);

  const GoalKind(this.label, this.icon);

  final String label;
  final IconData icon;

  /// The kinds a goal can be set to now. Savings account and time deposit
  /// describe where money is kept, so they belong to savings records; goals
  /// saved under them before stay readable and keep their label.
  static const choosable = [GoalKind.regular, GoalKind.emergencyFund];

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
  monthly('Monthly', 'a month', 1),

  /// Every so many days, weeks or months, as the user sets it in a
  /// [SavingInterval]. Without one it falls back to monthly.
  custom('Custom', 'a month', 1);

  const ContributionFrequency(this.label, this.per, this.perMonth);

  final String label;

  /// Reads after an amount: "₱500 a week".
  final String per;

  /// How many contributions fall in a month.
  final double perMonth;

  /// Average days between contributions.
  double get days => 365.25 / 12 / perMonth;

  /// The steps the saving calendar takes: [custom] for Custom, and the same
  /// steps as always for the others.
  SavingInterval intervalWith(SavingInterval? custom) => switch (this) {
    ContributionFrequency.weekly => const SavingInterval(1, SavingUnit.weeks),
    ContributionFrequency.twiceMonthly => const SavingInterval(
      15,
      SavingUnit.days,
    ),
    ContributionFrequency.monthly => const SavingInterval(1, SavingUnit.months),
    ContributionFrequency.custom =>
      custom ?? const SavingInterval(1, SavingUnit.months),
  };

  /// Reads after an amount, with [custom] for Custom: "₱500 every 10 days".
  String perWith(SavingInterval? custom) =>
      this == ContributionFrequency.custom && custom != null ? custom.per : per;

  /// Average days between contributions, with [custom] for Custom.
  double daysWith(SavingInterval? custom) =>
      this == ContributionFrequency.custom && custom != null
      ? custom.days
      : days;

  static ContributionFrequency fromName(String? name) =>
      ContributionFrequency.values.firstWhere(
        (frequency) => frequency.name == name,
        orElse: () => ContributionFrequency.monthly,
      );

  /// The rhythm that matches how often the user is paid, as stored in the
  /// profile's `incomeFrequency`: money is easiest to put aside the day it
  /// arrives. Irregular or unknown pay starts on monthly.
  static ContributionFrequency forPay(String? incomeFrequency) =>
      switch (incomeFrequency) {
        'Weekly' => ContributionFrequency.weekly,
        'Semi-monthly' || 'Bi-weekly' => ContributionFrequency.twiceMonthly,
        _ => ContributionFrequency.monthly,
      };
}

/// What a custom saving rhythm counts in.
enum SavingUnit {
  days('day', 'days', 365),
  weeks('week', 'weeks', 52),
  months('month', 'months', 12);

  const SavingUnit(this.one, this.many, this.most);

  final String one;
  final String many;

  /// The most of this unit a rhythm can be: one year's worth.
  final int most;

  static SavingUnit fromName(String? name) => SavingUnit.values.firstWhere(
    (unit) => unit.name == name,
    orElse: () => SavingUnit.weeks,
  );
}

/// Every [count] [unit]s: how often the user saves when no preset fits, such
/// as every 2 weeks for pay that comes every other Friday.
class SavingInterval {
  const SavingInterval(this.count, this.unit);

  final int count;
  final SavingUnit unit;

  /// At least once a year and at most once a day.
  bool get isValid => count >= 1 && count <= unit.most;

  /// Reads after an amount: "a week", "every 10 days".
  String get per => count == 1 ? 'a ${unit.one}' : 'every $count ${unit.many}';

  /// "Every week", "Every 10 days".
  String get label =>
      count == 1 ? 'Every ${unit.one}' : 'Every $count ${unit.many}';

  /// Average days between contributions.
  double get days => switch (unit) {
    SavingUnit.days => count.toDouble(),
    SavingUnit.weeks => count * 7.0,
    SavingUnit.months => count * 365.25 / 12,
  };

  /// Read from a goal's saved fields; null when they are missing or broken.
  static SavingInterval? fromFields(Object? count, Object? unit) {
    if (count is! num || unit is! String) return null;
    final interval = SavingInterval(count.toInt(), SavingUnit.fromName(unit));
    return interval.isValid ? interval : null;
  }

  @override
  bool operator ==(Object other) =>
      other is SavingInterval && other.count == count && other.unit == unit;

  @override
  int get hashCode => Object.hash(count, unit);
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

/// The kind of account from which a goal's initial money was set aside.
enum GoalFundingSource {
  cash,
  bank,
  ewallet,
  savings,

  /// Cash on hand together with money in one or more accounts.
  both;

  static GoalFundingSource? fromName(String? name) {
    for (final source in GoalFundingSource.values) {
      if (source.name == name) return source;
    }
    return null;
  }

  static GoalFundingSource fromType(WalletType type) {
    if (type == WalletType.cash) return GoalFundingSource.cash;
    if (isEWalletType(type)) return GoalFundingSource.ewallet;
    if (type == WalletType.bank) return GoalFundingSource.bank;
    return GoalFundingSource.savings;
  }

  static GoalFundingSource fromWallet(Wallet wallet) => fromType(wallet.type);

  /// The source for money drawn from wallets of [types]: cash with any
  /// account is [both], otherwise the first wallet's kind. Null for none.
  static GoalFundingSource? fromTypes(Iterable<WalletType> types) {
    if (types.isEmpty) return null;
    final hasCash = types.any((type) => type == WalletType.cash);
    final hasAccount = types.any((type) => type != WalletType.cash);
    if (hasCash && hasAccount) return GoalFundingSource.both;
    return fromType(types.first);
  }
}

/// The wallet holding most of a goal's money, which later contributions
/// start on. The first one wins a tie; null when nothing is set aside.
String? mainFundingWallet(Map<String, double> amounts) {
  String? main;
  var largest = 0.0;
  for (final entry in amounts.entries) {
    if (entry.value > largest) {
      main = entry.key;
      largest = entry.value;
    }
  }
  return main;
}

/// About what [amount] kept in [wallet] may earn in a year at the recorded
/// rate, after the tax banks keep: zero where the money earns nothing, null
/// when no rate is recorded.
///
/// It is a share of what the account already earns, so it is never added to
/// the account's own estimate, and it is never counted as money saved: it is
/// added as income when the bank pays it.
double? yearlyInterestOnGoalMoney(Wallet wallet, double amount) {
  if (wallet.earnsNoInterest) return 0;
  final gross = calculateAnnualInterestEstimate(
    balance: amount,
    annualInterestRatePercent: wallet.annualInterestRatePercent,
  );
  return gross == null ? null : afterTax(gross);
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
    this.customInterval,
    this.planAmount,
    this.walletId,
    this.fundingSource,
    this.note,
    this.planStartedAt,
    this.startingSaved = 0,
    this.savedByWallet = const {},
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
      customInterval: SavingInterval.fromFields(
        map['frequencyEvery'],
        map['frequencyUnit'],
      ),
      planAmount: map['planAmount'] is num && (map['planAmount'] as num) > 0
          ? (map['planAmount'] as num).toDouble()
          : null,
      walletId: map['walletId'] is String ? map['walletId'] as String : null,
      fundingSource: GoalFundingSource.fromName(
        map['fundingSource'] is String ? map['fundingSource'] as String : null,
      ),
      note: map['note'] is String && (map['note'] as String).isNotEmpty
          ? map['note'] as String
          : null,
      planStartedAt: map['planStartedAt'] is Timestamp
          ? (map['planStartedAt'] as Timestamp).toDate()
          : null,
      startingSaved: _asDouble(map['startingSaved']),
      savedByWallet: _walletAmounts(map['savedByWallet']),
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

  /// The rhythm the user set when [frequency] is Custom.
  final SavingInterval? customInterval;

  /// Reads after an amount: "₱500 a month", "₱500 every 2 weeks".
  String get savingPer => frequency.perWith(customInterval);

  /// How much each contribution is meant to be. Null when there's no plan.
  final double? planAmount;

  /// The wallet contributions usually go into.
  final String? walletId;
  final GoalFundingSource? fundingSource;
  final String? note;

  /// When the plan began, for telling whether the user is keeping up.
  final DateTime? planStartedAt;

  /// Already saved before the goal was added to the app.
  final double startingSaved;

  /// Net amount assigned to this goal from each wallet.
  final Map<String, double> savedByWallet;

  double get shownSaved => savedAmount > 0 ? savedAmount : 0;

  /// This goal after [amount] more is set aside in [walletId], for writing
  /// several contributions in one go. A goal saved before the per-wallet
  /// amounts existed starts from its one wallet, as a contribution does.
  Goal withContribution(String walletId, double amount) {
    final byWallet = savedByWallet.isNotEmpty
        ? Map<String, double>.from(savedByWallet)
        : <String, double>{
            if (shownSaved > 0) (this.walletId ?? walletId): shownSaved,
          };
    byWallet[walletId] = (byWallet[walletId] ?? 0) + amount;
    return Goal(
      id: id,
      name: name,
      targetAmount: targetAmount,
      savedAmount: savedAmount + amount,
      priority: priority,
      status: status,
      targetDate: targetDate,
      kind: kind,
      frequency: frequency,
      customInterval: customInterval,
      planAmount: planAmount,
      walletId: this.walletId,
      fundingSource: fundingSource,
      note: note,
      planStartedAt: planStartedAt,
      startingSaved: startingSaved,
      savedByWallet: byWallet,
    );
  }

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

  static Map<String, double> _walletAmounts(Object? value) {
    if (value is! Map) return const {};
    return {
      for (final entry in value.entries)
        if (entry.key is String && entry.value is num)
          entry.key as String: (entry.value as num).toDouble(),
    };
  }
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

/// Goal money in spending wallets still needs to be removed from Safe to
/// Spend. Money already in the Savings wallet is excluded from spending by
/// the wallet balance itself, so counting it again would subtract it twice.
double totalSetAsideInSpendingWallets(
  Iterable<Goal> goals,
  Iterable<Wallet> wallets,
) {
  final byId = {for (final wallet in wallets) wallet.id: wallet};
  return goals.fold<double>(0, (total, goal) {
    if (goal.status == GoalStatus.used) return total;
    if (goal.savedByWallet.isNotEmpty) {
      return total +
          goal.savedByWallet.entries.fold<double>(
            0,
            (subtotal, entry) =>
                byId[entry.key]?.purpose == WalletPurpose.savings
                ? subtotal
                : subtotal + entry.value,
          );
    }
    final wallet = byId[goal.walletId];
    return wallet?.purpose == WalletPurpose.savings
        ? total
        : total + goal.shownSaved;
  });
}

double totalSetAsideInPurposeWallets(
  Iterable<Goal> goals,
  Iterable<Wallet> wallets,
  WalletPurpose purpose,
) {
  final byId = {for (final wallet in wallets) wallet.id: wallet};
  return goals.fold<double>(0, (total, goal) {
    if (goal.status == GoalStatus.used) return total;
    if (goal.savedByWallet.isNotEmpty) {
      return total +
          goal.savedByWallet.entries.fold<double>(
            0,
            (subtotal, entry) => byId[entry.key]?.purpose == purpose
                ? subtotal + entry.value
                : subtotal,
          );
    }
    return byId[goal.walletId]?.purpose == purpose
        ? total + goal.shownSaved
        : total;
  });
}

/// What the goals already hold inside one wallet.
///
/// Goal money is tracked per wallet, so asking per wallet is the only way to
/// know how much of one savings record is still free to promise. A goal
/// saved before the per-wallet map existed counts against the single wallet
/// it was recorded under.
double goalMoneyInWallet(Iterable<Goal> goals, String walletId) {
  return goals.fold<double>(0, (total, goal) {
    if (goal.status == GoalStatus.used) return total;
    if (goal.savedByWallet.isNotEmpty) {
      return total + (goal.savedByWallet[walletId] ?? 0);
    }
    return goal.walletId == walletId ? total + goal.shownSaved : total;
  });
}

/// The savings records a goal can be funded from: money the user can
/// actually draw on today. A time deposit or government savings is left out,
/// because promising money that cannot be touched would be a promise the
/// user cannot keep.
List<Wallet> promisableSavingsRecords(Iterable<Wallet> wallets) => [
  for (final wallet in wallets)
    if (!wallet.archived &&
        wallet.purpose == WalletPurpose.savings &&
        !wallet.isLockedSavings)
      wallet,
];

/// Accounts whose recorded money can be set aside for a goal: cash, banks,
/// e-wallets, and savings records.
///
/// A time deposit counts too. Money placed for a set time is a common way to
/// save for something with a date, such as next year's tuition; it counts
/// toward the goal at once and is shown as ready on its end date, since it
/// cannot be taken out before then.
List<Wallet> goalFundingWallets(Iterable<Wallet> wallets) => [
  for (final wallet in wallets)
    if (!wallet.archived &&
        ((!wallet.isSetAside &&
                (wallet.type == WalletType.cash || wallet.isBankOrEWallet)) ||
            wallet.purpose == WalletPurpose.savings))
      wallet,
];

/// Where each goal's money in [from] goes when that money moves to [to], as
/// when a time deposit matures and is taken out: up to [moved] in all, the
/// highest-priority goal first. What a goal held in [from] beyond that stays
/// there. Goals with nothing in [from] are left out.
Map<Goal, double> goalMoneyMoving(
  Iterable<Goal> goals, {
  required String from,
  required double moved,
}) {
  final holding =
      goals
          .where(
            (goal) =>
                goal.status != GoalStatus.used &&
                goalMoneyInWallet([goal], from) > 0.005,
          )
          .toList()
        ..sort((a, b) => a.priority.compareTo(b.priority));
  var left = moved;
  final moving = <Goal, double>{};
  for (final goal in holding) {
    if (left <= 0.005) break;
    final held = goalMoneyInWallet([goal], from);
    final amount = held < left ? held : left;
    moving[goal] = (amount * 100).round() / 100;
    left -= amount;
  }
  return moving;
}

/// What is left in [wallet] once the goals' claims on it are taken off.
double freeInWallet(Wallet wallet, Iterable<Goal> goals) =>
    (wallet.balance - goalMoneyInWallet(goals, wallet.id))
        .clamp(0.0, double.infinity)
        .toDouble();

/// The Available Balance: what every spending wallet has free, after the
/// money goals hold in it. Savings are not counted. The same figure Home
/// shows.
double availableBalance(Iterable<Wallet> wallets, Iterable<Goal> goals) =>
    wallets
        .where((wallet) => !wallet.archived && !wallet.isSetAside)
        .fold<double>(
          0,
          (total, wallet) => total + freeInWallet(wallet, goals),
        );

/// What each wallet has free to spend, by id, for a wallet picker: its
/// balance less what goals hold in it.
Map<String, double> freeByWallet(
  Iterable<Wallet> wallets,
  Iterable<Goal> goals,
) => {for (final wallet in wallets) wallet.id: freeInWallet(wallet, goals)};

/// Under a wallet picker whose amounts leave goal money out, so a smaller
/// figure than the bank shows is never a surprise. Null when no goal holds
/// money in [wallets].
String? goalMoneyNote(Iterable<Wallet> wallets, Iterable<Goal> goals) =>
    wallets.any((wallet) => goalMoneyInWallet(goals, wallet.id) > 0.005)
    ? 'Amounts are what is free to spend, after money set aside for goals.'
    : null;

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
///
/// Counts the real saving days left before the date, on the plan's own
/// calendar from [planStartedAt] (or from today for a new goal): the same
/// days the reminders ask on. Averages would say 350 days holds twelve
/// monthly contributions when only eleven saving days fit.
double? neededPerContribution({
  required double remaining,
  required DateTime? targetDate,
  required ContributionFrequency frequency,
  required DateTime now,
  DateTime? planStartedAt,
  SavingInterval? custom,
}) {
  if (targetDate == null) return null;
  if (remaining <= 0) return 0;

  final contributions = savingDaysLeft(
    targetDate: targetDate,
    frequency: frequency,
    now: now,
    planStartedAt: planStartedAt,
    custom: custom,
  );
  // No saving day fits before the date: all of it by then.
  return remaining / (contributions < 1 ? 1 : contributions);
}

/// How many saving days are left after today, up to and including
/// [targetDate], on the plan's own calendar. Zero when the date is today or
/// past, or comes before the next saving day: then it is all at once.
int savingDaysLeft({
  required DateTime targetDate,
  required ContributionFrequency frequency,
  required DateTime now,
  DateTime? planStartedAt,
  SavingInterval? custom,
}) {
  final today = DateTime(now.year, now.month, now.day);
  final target = DateTime(targetDate.year, targetDate.month, targetDate.day);
  if (!target.isAfter(today)) return 0;

  return planDates(
    planStartedAt ?? today,
    frequency,
    from: DateTime(today.year, today.month, today.day + 1),
    until: target,
    custom: custom,
  ).length;
}

/// The one line that says what reaching [targetDate] takes: an amount each
/// time while there are several saving days left, or the whole amount by the
/// date when there is only one, so a goal due in six days never reads
/// "₱6,500 a month".
String neededText({
  required double needed,
  required DateTime targetDate,
  required int savingDays,
  required String per,
  String finish = 'reach it',
}) {
  final date = formatShortDate(targetDate);
  return savingDays > 1
      ? 'Save ${formatPeso(needed)} $per to $finish by $date.'
      : 'Save ${formatPeso(needed)} by $date to $finish.';
}

/// How a goal's plan line reads: a plan to follow, keeping up or falling
/// behind an amount the user set, or something to fix first.
enum GoalPlanTone { plan, onTrack, behind, needsDate, datePassed }

/// The line on a goal's card about its plan, the same in setup, on Goals and
/// on the goal itself. A goal is planned by the calendar: what is still to
/// save, spread over the months left to its finish date. Null once nothing
/// is left to save, since the progress bar says so.
///
/// A goal saved before with its own amount each time ([planAmount]) keeps
/// it, with how far [behind] it is.
({String text, GoalPlanTone tone})? goalPlanLine({
  required double remaining,
  required DateTime? targetDate,
  required DateTime now,
  ContributionFrequency frequency = ContributionFrequency.monthly,
  SavingInterval? custom,
  DateTime? planStartedAt,
  double? planAmount,
  double? behind,
}) {
  if (remaining <= 0.005) return null;
  final per = frequency.perWith(custom);

  if (planAmount != null) {
    final short = behind ?? 0;
    return short > 0.005
        ? (
            text:
                'Plan: ${formatPeso(planAmount)} $per · behind by '
                '${formatPeso(short)}',
            tone: GoalPlanTone.behind,
          )
        : (
            text: 'Plan: ${formatPeso(planAmount)} $per · on track',
            tone: GoalPlanTone.onTrack,
          );
  }

  if (targetDate == null) {
    return (
      text: 'Add a finish date to see how much to save each month.',
      tone: GoalPlanTone.needsDate,
    );
  }

  final today = DateTime(now.year, now.month, now.day);
  final finish = DateTime(targetDate.year, targetDate.month, targetDate.day);
  if (finish.isBefore(today)) {
    return (
      text: 'The finish date has passed. Pick a new one.',
      tone: GoalPlanTone.datePassed,
    );
  }

  final savingDays = savingDaysLeft(
    targetDate: finish,
    frequency: frequency,
    now: now,
    planStartedAt: planStartedAt,
    custom: custom,
  );
  return (
    text: neededText(
      needed: remaining / (savingDays < 1 ? 1 : savingDays),
      targetDate: finish,
      savingDays: savingDays,
      per: per,
    ),
    tone: GoalPlanTone.plan,
  );
}

/// When a plan of [amount] each [frequency] reaches [remaining], or null
/// without a plan: the saving day, on the plan's own calendar, on which the
/// last amount needed goes in.
DateTime? reachedByPlan({
  required double remaining,
  required double? amount,
  required ContributionFrequency frequency,
  required DateTime now,
  DateTime? planStartedAt,
  SavingInterval? custom,
}) {
  if (amount == null || amount <= 0) return null;

  final today = DateTime(now.year, now.month, now.day);
  if (remaining <= 0) return today;

  final contributions = (remaining / amount - 1e-9).ceil();
  final interval = frequency.intervalWith(custom);
  // The longest gap between saving days: a year for a yearly rhythm.
  final gap = interval.unit == SavingUnit.months
      ? 31 * interval.count
      : interval.days.ceil();
  final dates = planDates(
    planStartedAt ?? today,
    frequency,
    from: DateTime(today.year, today.month, today.day + 1),
    until: DateTime(today.year, today.month, today.day + gap * contributions),
    custom: custom,
  );
  if (dates.length >= contributions) return dates[contributions - 1];

  // Further out than the calendar is worked through: the average is close.
  final days = (contributions * frequency.daysWith(custom)).round();
  return today.add(Duration(days: days));
}

/// The days a saving plan asks for money, from [from] up to [until].
///
/// Monthly plans land on the day of the month the plan started, moved to the
/// month's last day when it is shorter. Weekly plans keep the weekday, and
/// twice-a-month plans fall every 15 days. A custom plan ([custom]) steps the
/// same way: every so many months on that day of the month, or every so many
/// days or weeks.
List<DateTime> planDates(
  DateTime started,
  ContributionFrequency frequency, {
  required DateTime from,
  required DateTime until,
  SavingInterval? custom,
}) {
  final start = DateTime(started.year, started.month, started.day);
  final interval = frequency.intervalWith(custom);
  final dates = <DateTime>[];

  // The plan's own start day is when money was first set aside, so reminders
  // begin with the next one. Enough steps for a daily plan over decades.
  for (var step = 1; step < 40000; step++) {
    final DateTime day;
    if (interval.unit == SavingUnit.months) {
      final months = interval.count * step;
      final lastDay = DateTime(start.year, start.month + months + 1, 0).day;
      day = DateTime(
        start.year,
        start.month + months,
        start.day < lastDay ? start.day : lastDay,
      );
    } else {
      final days = interval.unit == SavingUnit.weeks
          ? 7 * interval.count
          : interval.count;
      day = DateTime(start.year, start.month, start.day + days * step);
    }

    if (day.isAfter(until)) break;
    if (!day.isBefore(from)) dates.add(day);
  }

  return dates;
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
  final periods = days < 0
      ? 0
      : (days / goal.frequency.daysWith(goal.customInterval)).floor();
  final expected = goal.startingSaved + amount * periods;
  final target = goal.targetAmount;

  // Never expect more than the goal itself.
  final capped = target > 0 && expected > target ? target : expected;
  return capped - goal.shownSaved;
}
