import 'allocation.dart';
import 'app_transaction.dart';
import 'bill.dart';
import 'goal.dart';
import 'wallet.dart';
import 'onboarding_data.dart';
import 'safe_to_spend.dart';
import '../utils/date_format.dart';
import '../utils/money_format.dart';

/// The kinds of reminder FinAssist can send.
enum ReminderKind {
  bills,
  payday,
  goals,
  leftover,
  dailyLog,

  /// Interest a bank or e-wallet may have paid, to check and add.
  interest;

  static ReminderKind? fromName(String? name) {
    for (final kind in ReminderKind.values) {
      if (kind.name == name) return kind;
    }
    return null;
  }
}

/// How many reminders each rank gets: #1 four, #2 three, #3 two, #4 one.
/// Whatever the user puts in a place gets that many, so every rank matters.
const List<int> remindersByRank = [4, 3, 2, 1];

/// "4 reminders" for #1, down to "1 reminder" for #4.
String reminderCountText(int rank) {
  final times = rank >= 1 && rank <= remindersByRank.length
      ? remindersByRank[rank - 1]
      : 1;
  return '$times reminder${times == 1 ? '' : 's'}';
}

/// Which reminders are on, and how many each gets from the user's ranking.
///
/// Every reminder starts on; the ranking decides how many come. Only the
/// ones the user switched by hand are stored, so re-ranking changes the
/// counts and leaves those choices alone.
class ReminderSettings {
  const ReminderSettings({
    required this.enabled,
    required this.priorities,
    this.overrides = const {},
  });

  /// Reads the profile: the onboarding "Allow reminders" answer, the ranked
  /// priorities, and any reminder switched on or off by hand.
  factory ReminderSettings.fromProfile(Map<String, dynamic>? profile) {
    final reminders = profile?['reminders'];
    final map = reminders is Map ? reminders : const {};

    final overrides = <ReminderKind, bool>{};
    for (final kind in ReminderKind.values) {
      final value = map[kind.name];
      if (value is bool) overrides[kind] = value;
    }

    final enabled = map['enabled'];

    return ReminderSettings(
      enabled: enabled is bool
          ? enabled
          : profile?['notificationsEnabled'] == true,
      priorities: prioritiesFrom(profile),
      overrides: overrides,
    );
  }

  /// Every reminder at once. Off means no phone notifications at all.
  final bool enabled;

  /// Most important first.
  final List<FinancialPriority> priorities;

  /// Reminders the user switched on or off by hand.
  final Map<ReminderKind, bool> overrides;

  /// Where a priority sits in the user's ranking, 0 being the top.
  int rankOf(FinancialPriority priority) {
    final index = priorities.indexOf(priority);
    return index < 0 ? priorities.length : index;
  }

  /// Whether a reminder is on. Each starts on, since even #4 gets one; the
  /// user can still switch any of them off.
  bool isOn(ReminderKind kind) => overrides[kind] ?? true;

  /// How many reminders [kind] gets from its place in the ranking. Payday is
  /// not ranked: it keeps its own pattern.
  int timesFor(ReminderKind kind) {
    final priority = priorityFor(kind);
    if (priority == null) return 0;
    final rank = rankOf(priority);
    return rank < remindersByRank.length ? remindersByRank[rank] : 1;
  }

  /// The priority a reminder follows, or null for payday, which is always
  /// the same.
  static FinancialPriority? priorityFor(ReminderKind kind) {
    return switch (kind) {
      ReminderKind.payday || ReminderKind.interest => null,
      ReminderKind.bills => FinancialPriority.payBills,
      ReminderKind.goals => FinancialPriority.saveForGoal,
      ReminderKind.leftover => FinancialPriority.generalSavings,
      ReminderKind.dailyLog => FinancialPriority.trackSpending,
    };
  }
}

/// Days before a bill's due date its reminders come, by how many it gets.
const Map<int, List<int>> billReminderDays = {
  4: [7, 3, 1, 0],
  3: [3, 1, 0],
  2: [1, 0],
  1: [0],
};

/// Weekdays the logging reminder comes, by how many a week it gets.
const Map<int, List<int>> logReminderWeekdays = {
  4: [DateTime.monday, DateTime.wednesday, DateTime.friday, DateTime.sunday],
  3: [DateTime.tuesday, DateTime.thursday, DateTime.sunday],
  2: [DateTime.wednesday, DateTime.sunday],
  1: [DateTime.sunday],
};

/// When a reminder comes, in plain words, for [times] reminders.
String reminderTimingText(ReminderKind kind, int times) {
  return switch (kind) {
    ReminderKind.payday => 'This reminder is no longer available.',
    ReminderKind.bills => switch (times) {
      4 => '7 days, 3 days and 1 day before, and on the due day, at 9 AM.',
      3 => '3 days and 1 day before, and on the due day, at 9 AM.',
      2 => '1 day before and on the due day, at 9 AM.',
      _ => 'On the due day, at 9 AM.',
    },
    ReminderKind.goals => switch (times) {
      4 =>
        'The day before each saving day, on it, then 1 and 3 days after '
            "if you haven't saved.",
      3 => "On each saving day, then 1 and 3 days after if you haven't saved.",
      2 => "On each saving day, then 3 days after if you haven't saved.",
      _ => 'On each saving day, at 9 AM.',
    },
    ReminderKind.leftover => switch (times) {
      4 =>
        '3 days and 1 day before the end of the month, then on it and 2 days '
            "after if you haven't decided.",
      3 =>
        'The night before the month ends, then on it and 2 days after '
            "if you haven't decided.",
      2 =>
        "The night before the month ends, then on it if you haven't "
            'decided.',
      _ => 'The night before the month ends.',
    },
    ReminderKind.dailyLog => switch (times) {
      4 => 'Monday, Wednesday, Friday and Sunday at 8 PM.',
      3 => 'Tuesday, Thursday and Sunday at 8 PM.',
      2 => 'Wednesday and Sunday at 8 PM.',
      _ => 'Sundays at 8 PM.',
    },
    ReminderKind.interest =>
      'On the 1st after each account pays interest, at 9 AM. Skipped if you '
          'already added it. Each January 1, the interest your installments '
          'cost the year before.',
  };
}

/// The ranked priorities saved at onboarding, in the default order when
/// there are none. A priority missing from an older profile goes last.
List<FinancialPriority> prioritiesFrom(Map<String, dynamic>? profile) {
  final saved = profile?['priorities'];
  final ordered = <FinancialPriority>[];

  if (saved is List) {
    for (final name in saved) {
      for (final priority in FinancialPriority.values) {
        if (priority.name == name && !ordered.contains(priority)) {
          ordered.add(priority);
        }
      }
    }
  }

  for (final priority in FinancialPriority.values) {
    if (!ordered.contains(priority)) ordered.add(priority);
  }
  return ordered;
}

/// One notification to schedule.
class PlannedReminder {
  const PlannedReminder({
    required this.kind,
    required this.key,
    required this.at,
    required this.title,
    required this.body,
    required this.payload,
  });

  final ReminderKind kind;

  /// Stable across plans, so the same reminder keeps the same id.
  final String key;
  final DateTime at;
  final String title;
  final String body;

  /// What tapping it opens: `bill:<id>`, `goal:<id>`, `income`, `leftover`
  /// or `log`.
  final String payload;

  /// A notification id that stays the same for the same reminder.
  int get id {
    // FNV-1a, kept within a positive 31-bit int as Android requires.
    var hash = 0x811c9dc5;
    for (final unit in key.codeUnits) {
      hash ^= unit;
      hash = (hash * 0x01000193) & 0x7fffffff;
    }
    // 0 and 1 are kept for the app's own notifications, like the test one.
    return hash < 2 ? hash + 2 : hash;
  }
}

/// Hours reminders go out at: bills and goals in the morning, payday at noon
/// when pay has usually come in, the leftover question before dinner, and the
/// logging nudge once the day is mostly done.
const int morningHour = 9;
const int paydayHour = 12;
const int leftoverHour = 19;
const int eveningHour = 20;

/// Days after a payday to ask again while no pay is logged, since pay can
/// come late.
const int latePayDays = 3;

/// Android keeps a limited number of scheduled alarms per app. Well under it,
/// and more than enough between app opens.
const int maxPlannedReminders = 60;

/// Every reminder due from [now] on, soonest first.
///
/// Planned again whenever the data changes, so paying a bill or reaching a
/// goal simply leaves its reminders out of the next plan.
List<PlannedReminder> planReminders({
  required ReminderSettings settings,
  required List<BillInstance> bills,
  required List<Goal> goals,
  required List<AllocationCycle> cycles,
  List<Wallet> wallets = const [],
  required String? incomeFrequency,
  required List<AppTransaction> transactions,
  required DateTime now,
  String? incomeSource,
  DateTime? setupLastPayday,
}) {
  if (!settings.enabled) return const [];

  final planned = <PlannedReminder>[];
  final today = DateTime(now.year, now.month, now.day);

  void add(PlannedReminder reminder) {
    if (reminder.at.isAfter(now)) planned.add(reminder);
  }

  DateTime at(DateTime day, int hour) =>
      DateTime(day.year, day.month, day.day, hour);

  // Bills: as many reminders as the ranking gives, the last on the due day.
  // Every bill reminded on the same morning shares one notification, however
  // many there are, so the phone never buzzes once per bill.
  if (settings.isOn(ReminderKind.bills)) {
    final daysBefore = billReminderDays[settings.timesFor(ReminderKind.bills)]!;
    final byDay = <DateTime, List<(BillInstance, int)>>{};

    for (final bill in bills) {
      if (bill.isSettled || bill.remaining <= 0) continue;
      final due = DateTime(
        bill.dueDate.year,
        bill.dueDate.month,
        bill.dueDate.day,
      );
      for (final before in daysBefore) {
        final day = due.subtract(Duration(days: before));
        if (!at(day, morningHour).isAfter(now)) continue;
        (byDay[day] ??= []).add((bill, before));
      }
    }

    for (final entry in byDay.entries) {
      final day = entry.key;
      final due = entry.value
        ..sort((a, b) {
          final byWhen = a.$2.compareTo(b.$2);
          return byWhen != 0 ? byWhen : a.$1.name.compareTo(b.$1.name);
        });

      if (due.length == 1) {
        final (bill, before) = due.single;
        add(
          PlannedReminder(
            kind: ReminderKind.bills,
            key: 'bill:${bill.id}:$before',
            at: at(day, morningHour),
            title: '${bill.name} is due ${_whenDue(before)}',
            body: '${formatPeso(bill.remaining)} to pay. Tap to pay it now.',
            payload: 'bill:${bill.id}',
          ),
        );
        continue;
      }

      final sameDay = due.every((item) => item.$2 == due.first.$2);
      final names = [
        for (final (bill, before) in due)
          sameDay
              ? '${bill.name} ${formatPeso(bill.remaining)}'
              : '${bill.name} ${formatPeso(bill.remaining)} '
                    '(${_whenDue(before)})',
      ];
      add(
        PlannedReminder(
          kind: ReminderKind.bills,
          key: 'bills:${day.year}-${day.month}-${day.day}',
          at: at(day, morningHour),
          title: sameDay
              ? '${due.length} bills due ${_whenDue(due.first.$2)}'
              : '${due.length} bills to pay soon',
          body: '${_listNames(names)}. Tap to see them.',
          payload: 'bills',
        ),
      );
    }
  }

  // Goals: on each day of the goal's saving rhythm, for the next six weeks.
  // With a plan amount the reminder repeats it; with only a target date it
  // says what is needed each time to get there. The ranking adds, in order:
  // the saving day, 3 days after, 1 day after, and the day before. The ones
  // after only come while the cycle's amount is still missing; saving
  // silences the rest.
  if (settings.isOn(ReminderKind.goals)) {
    final until = today.add(const Duration(days: 42));
    final times = settings.timesFor(ReminderKind.goals);

    for (final goal in goals) {
      final start = goal.planStartedAt;
      if (goal.status != GoalStatus.active || goal.isReached) continue;
      if (start == null) continue;

      final perCycle =
          goal.planAmount ??
          neededPerContribution(
            remaining: goal.remaining,
            targetDate: goal.targetDate,
            frequency: goal.frequency,
            now: now,
            planStartedAt: start,
            custom: goal.customInterval,
          );
      // No amount and no date: nothing honest to remind about.
      if (perCycle == null || perCycle <= 0) continue;

      // Planned by its finish date: once that date has passed there is no
      // plan to keep, only a new date to pick, and no saving day after it
      // is asked for.
      final finish = goal.planAmount == null ? goal.targetDate : null;
      final lastDay = finish == null
          ? null
          : DateTime(finish.year, finish.month, finish.day);
      if (lastDay != null && lastDay.isBefore(today)) continue;

      // What the plan has asked for since it started, against what went in.
      // Money saved before the goal existed is not part of the plan.
      final asked = planDates(
        start,
        goal.frequency,
        from: start,
        until: today,
        custom: goal.customInterval,
      ).length;
      final saved = goal.savedAmount - goal.startingSaved;
      final behind = perCycle * asked - (saved < 0 ? 0 : saved);
      final owing = behind <= 0 ? 0.0 : (behind > perCycle ? perCycle : behind);

      // Saving days that have just passed stay in range, so one that was
      // missed can still be chased today.
      final days = [
        for (final day in planDates(
          start,
          goal.frequency,
          from: today.subtract(const Duration(days: 3)),
          until: until,
          custom: goal.customInterval,
        ))
          if (lastDay == null || !day.isAfter(lastDay)) day,
      ];
      // Due before its next saving day, so all of it by the date: that day
      // is the one to be reminded of.
      if (days.isEmpty &&
          lastDay != null &&
          !lastDay.isBefore(today) &&
          !lastDay.isAfter(until)) {
        days.add(lastDay);
      }

      for (final day in days) {
        final isCurrent = !day.isAfter(today);
        // This cycle's amount is already set aside, so say nothing.
        if (isCurrent && owing <= 0) continue;

        final due = isCurrent ? owing : perCycle;
        final key = 'goal:${goal.id}:${day.year}-${day.month}-${day.day}';

        if (times >= 4) {
          add(
            PlannedReminder(
              kind: ReminderKind.goals,
              key: '$key:before',
              at: at(day.subtract(const Duration(days: 1)), morningHour),
              title: 'Saving day tomorrow: ${goal.name}',
              body: 'Get ${formatPeso(due)} ready to set aside.',
              payload: 'goal:${goal.id}',
            ),
          );
        }

        add(
          PlannedReminder(
            kind: ReminderKind.goals,
            key: key,
            at: at(day, morningHour),
            title: 'Time to save for ${goal.name}',
            // With a plan the figure is the user's own; with only a target
            // date it is what that date asks for, so the date is named.
            body: goal.planAmount != null || goal.targetDate == null
                ? '${formatPeso(due)} ${goal.savingPer}. '
                      '${formatPeso(goal.remaining)} to go.'
                : neededText(
                    needed: due,
                    targetDate: goal.targetDate!,
                    savingDays: savingDaysLeft(
                      targetDate: goal.targetDate!,
                      frequency: goal.frequency,
                      now: now,
                      planStartedAt: start,
                      custom: goal.customInterval,
                    ),
                    per: goal.savingPer,
                  ),
            payload: 'goal:${goal.id}',
          ),
        );

        if (times >= 3) {
          add(
            PlannedReminder(
              kind: ReminderKind.goals,
              key: '$key:late',
              at: at(day.add(const Duration(days: 1)), morningHour),
              title: 'Missed: ${goal.name}',
              body: '${formatPeso(due)} is still to be set aside.',
              payload: 'goal:${goal.id}',
            ),
          );
        }
        if (times < 2) continue;

        // The last one names the date this pace now reaches, so the warning
        // is a fact rather than a scare.
        final slipsTo = reachedByPlan(
          remaining: goal.remaining,
          amount: perCycle,
          frequency: goal.frequency,
          now: day.add(const Duration(days: 3)),
          planStartedAt: start,
          custom: goal.customInterval,
        );

        add(
          PlannedReminder(
            kind: ReminderKind.goals,
            key: '$key:last',
            at: at(day.add(const Duration(days: 3)), morningHour),
            title: 'Last reminder for ${goal.name}',
            body: slipsTo == null
                ? 'Still ${formatPeso(due)} short this time.'
                : 'Still ${formatPeso(due)} short. At this pace you reach it '
                      'around ${formatShortDate(slipsTo)}.',
            payload: 'goal:${goal.id}',
          ),
        );
      }
    }
  }

  // Savings that have come due. FinAssist cannot see a real account, so it
  // asks once on the day and once a week later, then leaves the card on Home
  // to do the rest. Settling the record clears its date, which cancels both.
  if (settings.isOn(ReminderKind.goals)) {
    for (final wallet in wallets) {
      final due = wallet.maturityDate;
      if (due == null) continue;
      if (wallet.purpose != WalletPurpose.savings) continue;
      if (wallet.archived || wallet.balance <= 0) continue;

      final day = DateTime(due.year, due.month, due.day);
      // Older than a fortnight is the card's job now, not a notification's.
      if (day.isBefore(today.subtract(const Duration(days: 14)))) continue;
      // What it should have earned, after tax, so the user knows what to
      // look for.
      final gross = wallet.estimatedTimeDepositInterest();
      final interest = gross == null || gross <= 0 ? null : afterTax(gross);

      add(
        PlannedReminder(
          kind: ReminderKind.goals,
          key: 'savings:${wallet.id}:matured',
          at: at(day, morningHour),
          title: '${wallet.name} matures today',
          body: interest == null
              ? '${formatPeso(wallet.balance)} is recorded. Open FinAssist to '
                    'say what you did with it.'
              : '${formatPeso(wallet.balance)} is recorded, plus about '
                    '${formatPeso(interest)} interest after tax. Open '
                    'FinAssist to say what you got back.',
          payload: 'savings:${wallet.id}',
        ),
      );

      add(
        PlannedReminder(
          kind: ReminderKind.goals,
          key: 'savings:${wallet.id}:matured:late',
          at: at(day.add(const Duration(days: 7)), morningHour),
          title: '${wallet.name} matured a week ago',
          body: 'Still waiting on you to say where the money went.',
          payload: 'savings:${wallet.id}',
        ),
      );
    }
  }

  // Interest: on the 1st after each time an account pays it, a nudge to
  // check the account and add what came in. FinAssist cannot see the bank,
  // so it never adds interest by itself, and an amount already added in the
  // week before means there is nothing to ask.
  if (settings.isOn(ReminderKind.interest)) {
    for (final wallet in wallets) {
      final expected = wallet.interestPerPayoutAfterTax;
      if (expected == null || !isRecordableAmount(expected)) continue;

      final payout = wallet.interestPayout;
      // The next two months' reminders, or for a longer schedule at least
      // the next one, up to a year away.
      var planned = 0;
      for (var ahead = 0; ahead <= 12; ahead++) {
        final day = DateTime(today.year, today.month + ahead, 1);
        if (!payout.remindsOn(day) || !at(day, morningHour).isAfter(now)) {
          continue;
        }
        if (ahead > 2 && planned > 0) break;
        planned++;
        final weekBefore = day.subtract(const Duration(days: 7));
        final added = transactions.any(
          (t) =>
              t.type == TransactionType.income &&
              t.walletId == wallet.id &&
              t.label == interestIncomeLabel &&
              !t.date.isBefore(weekBefore),
        );
        if (added) continue;

        add(
          PlannedReminder(
            kind: ReminderKind.interest,
            key: 'interest:${wallet.id}:${day.year}-${day.month}',
            at: at(day, morningHour),
            title: 'Interest from ${wallet.name} may be in',
            // Paid daily, it is the month's total that is added.
            body: payout.isDaily
                ? 'About ${formatPeso(expected)} this month after tax. Check '
                      "your app and add the month's total."
                : 'About ${formatPeso(expected)} after tax. Check your app '
                      'and add what it paid.',
            payload: 'interest:${wallet.id}',
          ),
        );
      }
    }
  }

  // Installments: on January 1, what the year's payments cost in interest,
  // the yearly figure an accountant would give. Only payments really
  // recorded count, and recording one plans this again, so the figure is
  // the year's own by the time it comes.
  if (settings.isOn(ReminderKind.interest)) {
    final year = today.year;
    final byInstallment = <String, double>{};
    for (final t in transactions) {
      if (t.type != TransactionType.expense || t.interest <= 0) continue;
      if (t.date.year != year) continue;
      final name = t.note ?? 'Installment';
      byInstallment[name] = (byInstallment[name] ?? 0) + t.interest;
    }
    final total = byInstallment.values.fold<double>(0, (sum, v) => sum + v);

    if (isRecordableAmount(total)) {
      final largest = byInstallment.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));
      add(
        PlannedReminder(
          kind: ReminderKind.interest,
          key: 'installment-interest:$year',
          at: at(DateTime(year + 1, 1, 1), morningHour),
          title: 'Interest you paid in $year',
          body: largest.length == 1
              ? '${formatPeso(total)} of your ${largest.first.key} payments '
                    'was interest. Tap to see what it has cost.'
              : '${formatPeso(total)} of your installment payments was '
                    'interest: ${[for (final e in largest.take(3)) '${e.key} ${formatPeso(e.value)}'].join(', ')}.',
          payload: 'installments',
        ),
      );
    }
  }

  // Leftover: around the end of each pay period still undecided. The night
  // before the next pay always; the ranking adds payday morning, 2 days
  // after, then a heads-up 3 days before. Deciding silences the rest.
  if (settings.isOn(ReminderKind.leftover) && cycles.isNotEmpty) {
    final times = settings.timesFor(ReminderKind.leftover);
    final newest = cycles.reduce(
      (a, b) => a.receivedAt.isAfter(b.receivedAt) ? a : b,
    );
    final waiting = cycleAwaitingReview(cycles, null, now: now);
    final undecided = {?waiting, if (!newest.isResolved) newest};

    for (final cycle in undecided) {
      final end = periodOf(cycle, null).end;
      final nextPay = DateTime(end.year, end.month, end.day);
      final source = cycle.source.toLowerCase();

      if (times >= 4) {
        add(
          PlannedReminder(
            kind: ReminderKind.leftover,
            key: 'leftover:${cycle.id}:3-before',
            at: at(nextPay.subtract(const Duration(days: 3)), leftoverHour),
            title: '3 days until month end',
            body:
                'See what is left of your $source and plan to save it or '
                'spend it.',
            payload: 'leftover',
          ),
        );
      }
      add(
        PlannedReminder(
          kind: ReminderKind.leftover,
          key: 'leftover:${cycle.id}',
          at: at(nextPay.subtract(const Duration(days: 1)), leftoverHour),
          title: 'This month ends tomorrow',
          body:
              'See what is left of your $source and choose to save it or '
              'spend it.',
          payload: 'leftover',
        ),
      );
      if (times >= 2) {
        add(
          PlannedReminder(
            kind: ReminderKind.leftover,
            key: 'leftover-pending:${cycle.id}',
            at: at(nextPay, morningHour),
            title: 'Your leftover is still waiting',
            body:
                'Decide whether to save or spend what was left of your '
                '$source.',
            payload: 'leftover',
          ),
        );
      }
      if (times >= 3) {
        add(
          PlannedReminder(
            kind: ReminderKind.leftover,
            key: 'leftover-pending:${cycle.id}:last',
            at: at(nextPay.add(const Duration(days: 2)), morningHour),
            title: 'Last reminder: your leftover',
            body:
                'What was left of your $source is still undecided. Save it '
                'or spend it.',
            payload: 'leftover',
          ),
        );
      }
    }
  }

  // Logging: on the ranking's weekdays this week, skipping today once
  // something is in.
  if (settings.isOn(ReminderKind.dailyLog)) {
    final weekdays =
        logReminderWeekdays[settings.timesFor(ReminderKind.dailyLog)]!;
    final loggedToday = transactions.any(
      (t) =>
          !t.isLegacy &&
          t.date.year == today.year &&
          t.date.month == today.month &&
          t.date.day == today.day,
    );

    for (var offset = loggedToday ? 1 : 0; offset < 7; offset++) {
      final day = today.add(Duration(days: offset));
      if (!weekdays.contains(day.weekday)) continue;
      add(
        PlannedReminder(
          kind: ReminderKind.dailyLog,
          key: 'log:${day.year}-${day.month}-${day.day}',
          at: at(day, eveningHour),
          title: 'Time to log your spending',
          body:
              "Add anything you've spent since you last logged, so Safe to "
              'Spend stays right.',
          payload: 'log',
        ),
      );
    }
  }

  planned.sort((a, b) => a.at.compareTo(b.at));
  return planned.take(maxPlannedReminders).toList();
}

/// "today", "tomorrow" or "in 3 days", for a bill due [before] days on.
String _whenDue(int before) => switch (before) {
  0 => 'today',
  1 => 'tomorrow',
  _ => 'in $before days',
};

/// "A", "A and B", "A, B and C", or the first three "and 2 more", so a
/// notification naming many bills still fits on the screen.
String _listNames(List<String> names) {
  if (names.length > 3) {
    return '${names.take(3).join(', ')} and ${names.length - 3} more';
  }
  if (names.length < 2) return names.join();
  return '${names.sublist(0, names.length - 1).join(', ')} and '
      '${names.last}';
}

/// The days pay is expected from [from] up to [until], leaving out any
/// already paid.
///
/// Twice a month is the 15th and the 30th (the last day in February), as
/// onboarding describes it; pay logged up to three days early counts for
/// that payday. Monthly, weekly and every-two-weeks pay follow the pay
/// periods Safe to Spend uses, counted from [lastPay], so they need pay
/// logged once to know the day. Irregular income has no payday.
List<DateTime> expectedPaydays(
  String? frequency, {
  required DateTime? lastPay,
  required DateTime from,
  required DateTime until,
}) {
  final start = DateTime(from.year, from.month, from.day);
  final paid = lastPay == null
      ? null
      : DateTime(lastPay.year, lastPay.month, lastPay.day);
  final days = <DateTime>[];

  switch (frequency) {
    case 'Semi-monthly':
      for (var month = 0; month < 1200; month++) {
        final lastDay = DateTime(start.year, start.month + month + 1, 0).day;
        for (final date in [15, 30 < lastDay ? 30 : lastDay]) {
          final day = DateTime(start.year, start.month + month, date);
          if (day.isAfter(until)) return days;
          if (day.isBefore(start)) continue;
          if (paid != null &&
              !paid.isBefore(DateTime(day.year, day.month, day.day - 3))) {
            continue;
          }
          days.add(day);
        }
      }
      return days;

    case 'Monthly' || 'Weekly' || 'Bi-weekly':
      if (paid == null) return days;
      // Each pay period ends on the next payday.
      DateTime next(DateTime day) =>
          payPeriodFor(frequency, lastIncomeAt: paid, now: day).end;

      var day = start.isAfter(paid)
          ? payPeriodFor(frequency, lastIncomeAt: paid, now: start).start
          : paid;
      for (var i = 0; i < 2000 && !day.isAfter(until); i++) {
        if (day.isAfter(paid) && !day.isBefore(start)) days.add(day);
        day = next(day);
      }
      return days;

    default:
      return days;
  }
}

/// What the user calls their pay, from their usual income source.
String _payWord(String? source) {
  final name = source?.toLowerCase() ?? '';
  if (name.contains('salary') || name.contains('sahod')) return 'salary';
  if (name.contains('allowance') || name.contains('baon')) return 'allowance';
  return 'pay';
}

/// Bills worth a notice on Home: unpaid, and overdue or due within [days].
List<BillInstance> billsDueSoon(
  Iterable<BillInstance> bills, {
  required DateTime now,
  int days = 3,
}) {
  final today = DateTime(now.year, now.month, now.day);
  final horizon = today.add(Duration(days: days));

  return bills
      .where(
        (bill) =>
            !bill.isSettled &&
            bill.remaining > 0 &&
            !DateTime(
              bill.dueDate.year,
              bill.dueDate.month,
              bill.dueDate.day,
            ).isAfter(horizon),
      )
      .toList()
    ..sort((a, b) => a.dueDate.compareTo(b.dueDate));
}
