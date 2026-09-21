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

/// [day]'s date carrying [existing]'s time of day.
///
/// A date picker only asks for a day and hands back midnight. Putting the
/// two together keeps the time an entry already had, so choosing a date —
/// even today's, just to check it — never silently drops it.
DateTime keepTimeOfDay(DateTime day, DateTime existing) =>
    DateTime(day.year, day.month, day.day, existing.hour, existing.minute);

/// A transaction's time of day, e.g. `7:42 PM`, or null when the record
/// carries no time to show.
///
/// An entry made on the spot keeps the moment it was made. One back-dated
/// with the calendar picker lands on midnight instead, because the picker
/// asks for a day and nothing more — so midnight is read as "no time was
/// given" and nothing is shown, rather than claiming it happened at
/// 12:00 AM.
String? formatTransactionTime(DateTime date) {
  if (date.hour == 0 && date.minute == 0) return null;

  final hour = date.hour % 12 == 0 ? 12 : date.hour % 12;
  final minute = date.minute.toString().padLeft(2, '0');
  return '$hour:$minute ${date.hour < 12 ? 'AM' : 'PM'}';
}

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
