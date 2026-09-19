import 'package:cloud_firestore/cloud_firestore.dart';

/// How often a bill comes back.
enum BillRecurrence {
  once('One time', 'Happens once, on the due date.'),
  weekly('Every week', 'Falls due on the same weekday each week.'),
  monthly('Every month', 'Falls due on the same date each month.'),
  quarterly('Every 3 months', 'Falls due every third month.'),
  yearly('Every year', 'Falls due once a year, on the same date.');

  const BillRecurrence(this.label, this.explanation);

  final String label;
  final String explanation;

  static BillRecurrence fromName(String? name) {
    return BillRecurrence.values.firstWhere(
      (recurrence) => recurrence.name == name,
      orElse: () => BillRecurrence.monthly,
    );
  }
}

/// What the user has decided about one due bill.
///
/// "Overdue" is deliberately not here: it is not a decision, it is just what
/// [unpaid] looks like once the date has passed. See [BillUrgency].
enum BillStatus {
  unpaid('Unpaid'),
  partial('Partly paid'),
  paid('Paid'),
  skipped('Skipped');

  const BillStatus(this.label);

  final String label;

  static BillStatus fromName(String? name) {
    return BillStatus.values.firstWhere(
      (status) => status.name == name,
      orElse: () => BillStatus.unpaid,
    );
  }
}

/// How a bill should read on the calendar, which is status plus how close the
/// due date is. [moved] is a bill whose unpaid part was carried into its next
/// occurrence, where it is paid instead.
enum BillUrgency { paid, skipped, moved, overdue, dueSoon, upcoming }

/// A bill the user owes, and the schedule it repeats on. One of these is the
/// template; each time it falls due produces a [BillInstance].
class Bill {
  const Bill({
    required this.id,
    required this.name,
    required this.amount,
    required this.category,
    required this.firstDueDate,
    required this.recurrence,
    this.walletId,
    this.archived = false,
    this.endDate,
    this.debtId,
    this.lastAmount,
  });

  factory Bill.fromMap(String id, Map<String, dynamic>? data) {
    final map = data ?? const <String, dynamic>{};
    final name = _asString(map['name'])?.trim();

    return Bill(
      id: id,
      name: name == null || name.isEmpty ? 'Bill' : name,
      amount: _asDouble(map['amount']).abs(),
      category: _asString(map['category']) ?? 'Bills',
      firstDueDate: _asDate(map['firstDueDate']) ?? DateTime.now(),
      recurrence: BillRecurrence.fromName(_asString(map['recurrence'])),
      walletId: _asString(map['walletId']),
      archived: map['archived'] == true,
      endDate: _asDate(map['endDate']),
      debtId: _asString(map['debtId']),
      lastAmount: map['lastAmount'] is num && (map['lastAmount'] as num) > 0
          ? (map['lastAmount'] as num).toDouble()
          : null,
    );
  }

  final String id;
  final String name;
  final double amount;
  final String category;

  /// The first time this bill falls due. Later due dates are worked out from
  /// here rather than stored, so changing the schedule fixes every future
  /// occurrence at once.
  final DateTime firstDueDate;
  final BillRecurrence recurrence;

  /// The wallet the user usually pays this from. Only a suggestion; the
  /// wallet is confirmed at payment time.
  final String? walletId;
  final bool archived;

  /// The last day this bill can fall due. Null means it repeats with no end;
  /// an installment has one, so its twelfth payment is its last.
  final DateTime? endDate;

  /// Set when this schedule is the payments of an installment or loan.
  final String? debtId;

  /// What the occurrence on [endDate] asks for when the contract's last
  /// payment differs from the others.
  final double? lastAmount;

  /// What the occurrence due on [dueDate] asks for.
  double amountOn(DateTime dueDate) {
    final last = lastAmount;
    final end = endDate;
    if (last == null || end == null) return amount;
    return _dateOnly(dueDate) == _dateOnly(end) ? last : amount;
  }

  /// Every date this bill falls due inside the given month.
  ///
  /// Nothing is stored until the user opens that month, so a bill set up
  /// years ago doesn't fill the database with rows nobody has looked at.
  List<DateTime> occurrencesIn(int year, int month) {
    final end = endDate == null ? null : _dateOnly(endDate!);
    return _occurrencesIn(
      year,
      month,
    ).where((date) => end == null || !date.isAfter(end)).toList();
  }

  List<DateTime> _occurrencesIn(int year, int month) {
    final first = _dateOnly(firstDueDate);
    final monthStart = DateTime(year, month);
    final monthEnd = DateTime(year, month + 1);

    switch (recurrence) {
      case BillRecurrence.once:
        return first.year == year && first.month == month ? [first] : const [];

      case BillRecurrence.weekly:
        return _weeklyOccurrences(first, monthStart, monthEnd);

      case BillRecurrence.monthly:
        return _repeatEveryMonths(first, year, month, 1);

      case BillRecurrence.quarterly:
        return _repeatEveryMonths(first, year, month, 3);

      case BillRecurrence.yearly:
        return _repeatEveryMonths(first, year, month, 12);
    }
  }

  static List<DateTime> _weeklyOccurrences(
    DateTime first,
    DateTime monthStart,
    DateTime monthEnd,
  ) {
    if (!first.isBefore(monthEnd)) return const [];

    // Jumps straight to the first occurrence in the month instead of stepping
    // week by week from a start date that may be years back.
    final daysUntilMonth = monthStart.difference(first).inDays;
    final weeksToSkip = daysUntilMonth <= 0 ? 0 : (daysUntilMonth + 6) ~/ 7;

    final dates = <DateTime>[];
    var date = first.add(Duration(days: 7 * weeksToSkip));

    while (date.isBefore(monthEnd)) {
      dates.add(date);
      date = date.add(const Duration(days: 7));
    }

    return dates;
  }

  static List<DateTime> _repeatEveryMonths(
    DateTime first,
    int year,
    int month,
    int step,
  ) {
    final monthsApart = (year - first.year) * 12 + (month - first.month);

    if (monthsApart < 0 || monthsApart % step != 0) return const [];

    return [_clampDay(year, month, first.day)];
  }

  /// A bill due on the 31st still falls due in February, on the 28th or 29th.
  static DateTime _clampDay(int year, int month, int day) {
    final lastDayOfMonth = DateTime(year, month + 1, 0).day;
    return DateTime(year, month, day < lastDayOfMonth ? day : lastDayOfMonth);
  }

  static String? _asString(Object? value) => value is String ? value : null;

  static double _asDouble(Object? value) => value is num ? value.toDouble() : 0;

  static DateTime? _asDate(Object? value) {
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    return null;
  }
}

/// One occurrence of a bill: this month's rent, this week's load.
///
/// Each occurrence is its own record so the user can change just one of them
/// — a higher electricity bill this month — without touching the schedule.
class BillInstance {
  const BillInstance({
    required this.id,
    required this.billId,
    required this.name,
    required this.amount,
    required this.category,
    required this.dueDate,
    required this.status,
    this.amountPaid = 0,
    this.carriedOver = 0,
    this.paymentIds = const [],
    this.walletId,
    this.carriedInto,
  });

  factory BillInstance.fromMap(String id, Map<String, dynamic>? data) {
    final map = data ?? const <String, dynamic>{};
    final name = _asString(map['name'])?.trim();

    return BillInstance(
      id: id,
      billId: _asString(map['billId']) ?? '',
      name: name == null || name.isEmpty ? 'Bill' : name,
      amount: _asDouble(map['amount']).abs(),
      category: _asString(map['category']) ?? 'Bills',
      dueDate: _asDate(map['dueDate']) ?? DateTime.now(),
      status: BillStatus.fromName(_asString(map['status'])),
      amountPaid: _asDouble(map['amountPaid']).abs(),
      carriedOver: _asDouble(map['carriedOver']).abs(),
      paymentIds: _asStringList(map['paymentIds']),
      walletId: _asString(map['walletId']),
      carriedInto: _asString(map['carriedInto']),
    );
  }

  final String id;
  final String billId;
  final String name;

  /// What is owed this cycle, including anything [carriedOver].
  final double amount;
  final String category;
  final DateTime dueDate;
  final BillStatus status;
  final double amountPaid;

  /// Left unpaid from the previous cycle and rolled into this one.
  final double carriedOver;

  /// Ids of the transactions that paid this, so a payment can be undone and
  /// the wallet put back.
  final List<String> paymentIds;

  /// The wallet the payment came from, once paid.
  final String? walletId;

  /// The occurrence this one's unpaid part was carried into. The money is
  /// then owed there, not here, so it is never counted twice.
  final String? carriedInto;

  /// Whether the unpaid part moved to the next occurrence.
  bool get isCarriedForward =>
      carriedInto != null &&
      (status == BillStatus.unpaid || status == BillStatus.partial);

  /// What moved to the next occurrence.
  double get movedAmount {
    if (!isCarriedForward) return 0;
    final left = amount - amountPaid;
    return left > 0 ? left : 0;
  }

  /// Still owed this cycle. Never negative, even if the user overpaid, and
  /// nothing once the rest was carried forward.
  double get remaining {
    if (isCarriedForward) return 0;
    final left = amount - amountPaid;
    return left > 0 ? left : 0;
  }

  bool get isSettled =>
      status == BillStatus.paid ||
      status == BillStatus.skipped ||
      isCarriedForward;

  /// How this should read on the calendar. [dueSoonDays] is how many days
  /// ahead still counts as "due soon".
  BillUrgency urgency({DateTime? now, int dueSoonDays = 3}) {
    if (status == BillStatus.paid) return BillUrgency.paid;
    if (status == BillStatus.skipped) return BillUrgency.skipped;
    if (isCarriedForward) return BillUrgency.moved;

    final today = _dateOnly(now ?? DateTime.now());
    final due = _dateOnly(dueDate);

    if (due.isBefore(today)) return BillUrgency.overdue;

    return due.difference(today).inDays <= dueSoonDays
        ? BillUrgency.dueSoon
        : BillUrgency.upcoming;
  }

  /// The status implied by paying [paid] of [amount].
  static BillStatus statusForPayment(double paid, double amount) {
    if (paid <= 0) return BillStatus.unpaid;
    return paid + 0.005 >= amount ? BillStatus.paid : BillStatus.partial;
  }

  static String? _asString(Object? value) => value is String ? value : null;

  static double _asDouble(Object? value) => value is num ? value.toDouble() : 0;

  static DateTime? _asDate(Object? value) {
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    return null;
  }

  static List<String> _asStringList(Object? value) {
    if (value is! List) return const [];
    return value.whereType<String>().toList(growable: false);
  }
}

/// The due date of payment number [count] for a schedule starting on
/// [firstDueDate]: the last payment of an installment. Monthly dates keep the
/// original day where the month allows, so the 31st lands on the 28th in
/// February without every later payment moving earlier too.
DateTime lastDueDateFor(
  DateTime firstDueDate,
  BillRecurrence recurrence,
  int count,
) {
  final first = _dateOnly(firstDueDate);
  final steps = count < 1 ? 0 : count - 1;

  switch (recurrence) {
    case BillRecurrence.once:
      return first;
    case BillRecurrence.weekly:
      return DateTime(first.year, first.month, first.day + 7 * steps);
    case BillRecurrence.monthly:
      return _addMonths(first, steps);
    case BillRecurrence.quarterly:
      return _addMonths(first, 3 * steps);
    case BillRecurrence.yearly:
      return _addMonths(first, 12 * steps);
  }
}

DateTime _addMonths(DateTime date, int months) {
  final lastDay = DateTime(date.year, date.month + months + 1, 0).day;
  return DateTime(
    date.year,
    date.month + months,
    date.day < lastDay ? date.day : lastDay,
  );
}

/// The id an occurrence is stored under.
///
/// Built from the bill and the date rather than generated, so opening the
/// same month twice can never produce two copies of the same bill.
String billInstanceId(String billId, DateTime dueDate) {
  final date = _dateOnly(dueDate);
  final month = date.month.toString().padLeft(2, '0');
  final day = date.day.toString().padLeft(2, '0');

  return '${billId}_${date.year}$month$day';
}

/// What an unpaid occurrence should roll into the next cycle.
///
/// Only bills whose date has passed carry over; a bill due later this month
/// is not late yet. Skipped bills carry nothing, because skipping is the user
/// deciding not to pay it at all.
double carryOverFrom(BillInstance? previous, {DateTime? now}) {
  if (previous == null) return 0;
  if (previous.status == BillStatus.skipped) return 0;
  // Already moved once; it is owed in the occurrence it moved to.
  if (previous.carriedInto != null) return 0;
  if (!_dateOnly(previous.dueDate).isBefore(_dateOnly(now ?? DateTime.now()))) {
    return 0;
  }

  return previous.remaining;
}

/// The latest occurrence of [billId] among [instances].
BillInstance? latestOccurrence(
  Iterable<BillInstance> instances,
  String billId,
) {
  BillInstance? latest;
  for (final instance in instances) {
    if (instance.billId != billId) continue;
    if (latest == null || instance.dueDate.isAfter(latest.dueDate)) {
      latest = instance;
    }
  }
  return latest;
}

/// An occurrence a month is missing, and what it carries over from the
/// month before.
class NewOccurrence {
  const NewOccurrence({
    required this.bill,
    required this.dueDate,
    this.carried = 0,
    this.from,
  });

  final Bill bill;
  final DateTime dueDate;

  /// Left unpaid last time, added to this occurrence's amount.
  final double carried;

  /// The occurrence it was carried from, which is then closed.
  final BillInstance? from;

  /// What it asks for: its own amount, plus anything carried over.
  double get amount => bill.amountOn(dueDate) + carried;

  String get id => billInstanceId(bill.id, dueDate);
}

/// The occurrences of [bills] that [year]/[month] is missing.
///
/// What an overdue bill left unpaid moves once, into that bill's first new
/// occurrence, and the old one is closed. Every later occurrence in the month,
/// such as the other weeks of a weekly bill, starts from its own amount.
List<NewOccurrence> newOccurrences({
  required Iterable<Bill> bills,
  required int year,
  required int month,
  required Set<String> existingIds,
  required Iterable<BillInstance> previousMonth,
  DateTime? now,
}) {
  final result = <NewOccurrence>[];
  for (final bill in bills) {
    final last = latestOccurrence(previousMonth, bill.id);
    var carried = carryOverFrom(last, now: now);

    for (final dueDate in bill.occurrencesIn(year, month)) {
      if (existingIds.contains(billInstanceId(bill.id, dueDate))) continue;
      result.add(
        NewOccurrence(
          bill: bill,
          dueDate: dueDate,
          carried: carried,
          from: carried > 0 ? last : null,
        ),
      );
      carried = 0;
    }
  }
  return result;
}

/// Occurrences whose unpaid part was carried into [monthInstances] but that
/// were never closed, as (from, into) ids.
///
/// Carrying over used to leave the earlier occurrence open as well, so the
/// same money was owed twice. Only the first carried occurrence of a bill in
/// the month counts as where it went.
List<({String from, String into})> unclosedCarries(
  Iterable<BillInstance> monthInstances,
  Iterable<BillInstance> previousMonth,
) {
  final carriedIn = monthInstances.where((i) => i.carriedOver > 0).toList()
    ..sort((a, b) => a.dueDate.compareTo(b.dueDate));
  final seen = <String>{};
  final pairs = <({String from, String into})>[];

  for (final instance in carriedIn) {
    if (!seen.add(instance.billId)) continue;
    final from = latestOccurrence(previousMonth, instance.billId);
    if (from == null || from.carriedInto != null) continue;
    if (from.status == BillStatus.paid || from.status == BillStatus.skipped) {
      continue;
    }
    pairs.add((from: from.id, into: instance.id));
  }
  return pairs;
}

DateTime _dateOnly(DateTime date) => DateTime(date.year, date.month, date.day);
