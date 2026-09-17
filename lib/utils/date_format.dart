const List<String> _monthNames = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

/// A short readable date, e.g. `Sep 16, 2026`.
String formatShortDate(DateTime date) {
  return '${_monthNames[date.month - 1]} ${date.day}, ${date.year}';
}

/// A month and day without the year, e.g. `Sep 16`.
String formatMonthDay(DateTime date) {
  return '${_monthNames[date.month - 1]} ${date.day}';
}

/// A month's short name, e.g. `Sep`.
String formatMonthName(DateTime date) => _monthNames[date.month - 1];

/// The heading a transaction is grouped under: `Today`, `Yesterday`, or the
/// date itself. [now] is injectable so tests don't depend on the clock.
String transactionDateLabel(DateTime date, {DateTime? now}) {
  final today = _startOfDay(now ?? DateTime.now());
  final day = _startOfDay(date);
  final daysApart = today.difference(day).inDays;

  if (daysApart == 0) return 'Today';
  if (daysApart == 1) return 'Yesterday';
  return formatShortDate(date);
}

DateTime _startOfDay(DateTime date) =>
    DateTime(date.year, date.month, date.day);
