import 'allocation.dart';
import 'app_transaction.dart';
import 'bill.dart';
import 'goal.dart';
import 'onboarding_data.dart';
import '../utils/date_format.dart';
import '../utils/money_format.dart';

/// The kinds of reminder FinAssist can send.
enum ReminderKind {
  bills,
  goals,
  leftover,
  dailyLog;

  static ReminderKind? fromName(String? name) {
    for (final kind in ReminderKind.values) {
      if (kind.name == name) return kind;
    }
    return null;
  }
}

/// How early a bill reminder comes, in days before the due date.
const List<int> billLeadDayChoices = [0, 1, 3, 7];

/// Which reminders are on, worked out from the user's priorities unless the
/// user has switched one by hand.
///
/// Only the hand-made choices are stored. Everything else follows the
/// priority ranking, so re-ranking priorities changes the reminders that the
/// user never touched, and leaves alone the ones they did.
class ReminderSettings {
  const ReminderSettings({
    required this.enabled,
    required this.priorities,
    this.overrides = const {},
    this.billLeadDaysOverride,
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

    final lead = map['billLeadDays'];
    final enabled = map['enabled'];

    return ReminderSettings(
      enabled: enabled is bool
          ? enabled
          : profile?['notificationsEnabled'] == true,
      priorities: prioritiesFrom(profile),
      overrides: overrides,
      billLeadDaysOverride: lead is int && billLeadDayChoices.contains(lead)
          ? lead
          : null,
    );
  }

  /// Every reminder at once. Off means no phone notifications at all.
  final bool enabled;

  /// Most important first.
  final List<FinancialPriority> priorities;

  /// Reminders the user switched on or off by hand.
  final Map<ReminderKind, bool> overrides;
  final int? billLeadDaysOverride;

  /// Where a priority sits in the user's ranking, 0 being the top.
  int rankOf(FinancialPriority priority) {
    final index = priorities.indexOf(priority);
    return index < 0 ? priorities.length : index;
  }

  /// Whether a reminder is on by default for this ranking.
  ///
  /// Bills are always on: a missed bill costs money whatever else matters
  /// most. Each other reminder belongs to one priority and is on when that
  /// priority is in the user's top two.
  bool suggested(ReminderKind kind) {
    return switch (kind) {
      ReminderKind.bills => true,
      ReminderKind.goals => rankOf(FinancialPriority.saveForGoal) <= 1,
      ReminderKind.leftover => rankOf(FinancialPriority.generalSavings) <= 1,
      ReminderKind.dailyLog => rankOf(FinancialPriority.trackSpending) <= 1,
    };
  }

  /// Whether a reminder is on: the user's own choice, or the suggestion.
  bool isOn(ReminderKind kind) => overrides[kind] ?? suggested(kind);

  /// Paying bills on time as the top priority means an earlier heads-up.
  int get suggestedBillLeadDays =>
      rankOf(FinancialPriority.payBills) == 0 ? 3 : 1;

  int get billLeadDays => billLeadDaysOverride ?? suggestedBillLeadDays;

  /// The priority a reminder follows, or null for bills, which are always on.
  static FinancialPriority? priorityFor(ReminderKind kind) {
    return switch (kind) {
      ReminderKind.bills => null,
      ReminderKind.goals => FinancialPriority.saveForGoal,
      ReminderKind.leftover => FinancialPriority.generalSavings,
      ReminderKind.dailyLog => FinancialPriority.trackSpending,
    };
  }
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

  /// What tapping it opens: `bill:<id>`, `goal:<id>`, `leftover` or `log`.
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

/// Hours reminders go out at: bills and goals in the morning, the leftover
/// question before dinner, and the logging nudge once the day is mostly done.
const int morningHour = 9;
const int leftoverHour = 19;
const int eveningHour = 20;

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
  required String? incomeFrequency,
  required List<AppTransaction> transactions,
  required DateTime now,
}) {
  if (!settings.enabled) return const [];

  final planned = <PlannedReminder>[];
  final today = DateTime(now.year, now.month, now.day);

  void add(PlannedReminder reminder) {
    if (reminder.at.isAfter(now)) planned.add(reminder);
  }

  DateTime at(DateTime day, int hour) =>
      DateTime(day.year, day.month, day.day, hour);

  // Bills: a heads-up, then the day itself.
  if (settings.isOn(ReminderKind.bills)) {
    final lead = settings.billLeadDays;

    for (final bill in bills) {
      if (bill.isSettled || bill.remaining <= 0) continue;
      final due = DateTime(
        bill.dueDate.year,
        bill.dueDate.month,
        bill.dueDate.day,
      );
      final amount = formatPeso(bill.remaining);

      if (lead > 0) {
        add(
          PlannedReminder(
            kind: ReminderKind.bills,
            key: 'bill-early:${bill.id}',
            at: at(due.subtract(Duration(days: lead)), morningHour),
            title: lead == 1
                ? '${bill.name} is due tomorrow'
                : '${bill.name} is due in $lead days',
            body: '$amount to pay. Tap to pay it now.',
            payload: 'bill:${bill.id}',
          ),
        );
      }
      add(
        PlannedReminder(
          kind: ReminderKind.bills,
          key: 'bill-due:${bill.id}',
          at: at(due, morningHour),
          title: '${bill.name} is due today',
          body: '$amount to pay. Tap to pay it now.',
          payload: 'bill:${bill.id}',
        ),
      );
    }
  }

  // Goals: on each day of the goal's saving rhythm, for the next six weeks.
  // With a plan amount the reminder repeats it; with only a target date it
  // says what is needed each time to get there.
  if (settings.isOn(ReminderKind.goals)) {
    final until = today.add(const Duration(days: 42));

    for (final goal in goals) {
      final start = goal.planStartedAt;
      if (goal.status != GoalStatus.active || goal.isReached) continue;
      if (start == null) continue;

      final plan = goal.planAmount;
      final needed = neededPerContribution(
        remaining: goal.remaining,
        targetDate: goal.targetDate,
        frequency: goal.frequency,
        now: now,
      );
      final String body;
      if (plan != null) {
        body =
            'Your plan is ${formatPeso(plan)} ${goal.frequency.per}. '
            '${formatPeso(goal.remaining)} to go.';
      } else if (needed != null && goal.targetDate != null) {
        body =
            'Save ${formatPeso(needed)} ${goal.frequency.per} to reach it by '
            '${formatShortDate(goal.targetDate!)}.';
      } else {
        // No amount and no date: nothing honest to remind about.
        continue;
      }

      for (final day in planDates(
        start,
        goal.frequency,
        from: today,
        until: until,
      )) {
        add(
          PlannedReminder(
            kind: ReminderKind.goals,
            key: 'goal:${goal.id}:${day.year}-${day.month}-${day.day}',
            at: at(day, morningHour),
            title: 'Time to save for ${goal.name}',
            body: body,
            payload: 'goal:${goal.id}',
          ),
        );
      }
    }
  }

  // Leftover: the evening before the pay period ends, and the next morning
  // while a past period is still undecided.
  if (settings.isOn(ReminderKind.leftover) && cycles.isNotEmpty) {
    final newest = cycles.reduce(
      (a, b) => a.receivedAt.isAfter(b.receivedAt) ? a : b,
    );
    final waiting = cycleAwaitingReview(cycles, incomeFrequency, now: now);

    // A period that is already over, not one on its last day: days left is
    // never counted below one, so the last-day test can't tell them apart.
    if (waiting != null &&
        !now.isBefore(periodOf(waiting, incomeFrequency).end)) {
      add(
        PlannedReminder(
          kind: ReminderKind.leftover,
          key: 'leftover-pending:${waiting.id}',
          at: at(today.add(const Duration(days: 1)), morningHour),
          title: 'Your leftover is still waiting',
          body:
              'Decide whether to save or spend what was left of your '
              '${waiting.source.toLowerCase()}.',
          payload: 'leftover',
        ),
      );
    } else if (!newest.isResolved) {
      final lastDay = periodOf(
        newest,
        incomeFrequency,
      ).end.subtract(const Duration(days: 1));
      add(
        PlannedReminder(
          kind: ReminderKind.leftover,
          key: 'leftover:${newest.id}',
          at: at(lastDay, leftoverHour),
          title: 'Your pay period ends today',
          body:
              'See what is left of your ${newest.source.toLowerCase()} and '
              'choose to save it or spend it.',
          payload: 'leftover',
        ),
      );
    }
  }

  // Logging: each evening this week, skipping today once something is in.
  if (settings.isOn(ReminderKind.dailyLog)) {
    final loggedToday = transactions.any(
      (t) =>
          !t.isLegacy &&
          t.date.year == today.year &&
          t.date.month == today.month &&
          t.date.day == today.day,
    );

    for (var offset = loggedToday ? 1 : 0; offset < 7; offset++) {
      final day = today.add(Duration(days: offset));
      add(
        PlannedReminder(
          kind: ReminderKind.dailyLog,
          key: 'log:${day.year}-${day.month}-${day.day}',
          at: at(day, eveningHour),
          title: 'Anything spent today?',
          body:
              'Take a moment to log today\'s expenses so your Safe to '
              'Spend stays right.',
          payload: 'log',
        ),
      );
    }
  }

  planned.sort((a, b) => a.at.compareTo(b.at));
  return planned.take(maxPlannedReminders).toList();
}

/// The days a saving plan asks for money, from [from] up to [until].
///
/// Monthly plans land on the day of the month the plan started, moved to the
/// month's last day when it is shorter. Weekly plans keep the weekday, and
/// twice-a-month plans fall every 15 days.
List<DateTime> planDates(
  DateTime started,
  ContributionFrequency frequency, {
  required DateTime from,
  required DateTime until,
}) {
  final start = DateTime(started.year, started.month, started.day);
  final dates = <DateTime>[];

  // The plan's own start day is when money was first set aside, so reminders
  // begin with the next one.
  for (var step = 1; step < 400; step++) {
    final DateTime day;
    if (frequency == ContributionFrequency.monthly) {
      final lastDay = DateTime(start.year, start.month + step + 1, 0).day;
      day = DateTime(
        start.year,
        start.month + step,
        start.day < lastDay ? start.day : lastDay,
      );
    } else {
      final days = frequency == ContributionFrequency.weekly ? 7 : 15;
      day = DateTime(start.year, start.month, start.day + days * step);
    }

    if (day.isAfter(until)) break;
    if (!day.isBefore(from)) dates.add(day);
  }

  return dates;
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
