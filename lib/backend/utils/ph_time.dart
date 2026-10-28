/// FinAssist's days follow Philippine time (UTC+8, with no daylight saving),
/// whatever time zone the phone is set to: today starts at midnight in the
/// Philippines, and so does the month.
const philippineOffset = Duration(hours: 8);

/// [instant] as a clock in the Philippines reads it. For the date, the day
/// of the month and the days left; compare recorded times with
/// [philippineDayStart] instead, which is a real moment.
DateTime philippineTime(DateTime instant) {
  final ph = instant.toUtc().add(philippineOffset);
  return DateTime(
    ph.year,
    ph.month,
    ph.day,
    ph.hour,
    ph.minute,
    ph.second,
    ph.millisecond,
  );
}

/// The time now, as a clock in the Philippines reads it.
DateTime philippineNow() => philippineTime(DateTime.now());

/// The moment [day], a date on the Philippine calendar, began.
DateTime philippineDayStart(DateTime day) =>
    DateTime.utc(day.year, day.month, day.day).subtract(philippineOffset);
