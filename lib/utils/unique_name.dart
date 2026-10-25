/// [name] made different from every name in [taken], so two items never read
/// the same. A name not used yet stays as it is. A repeat gets the next number
/// after the highest one used: "Petty Cash", then "Petty Cash 2", then
/// "Petty Cash 3". Numbers only go up, so a deleted "Petty Cash 2" is not
/// reused. Names are compared ignoring case and outer spaces, and a repeat
/// follows the spelling already there. With [maxLength], the name is cut
/// short before its number, so "Petty Cash 2" still fits the limit.
String uniqueName(String name, Iterable<String> taken, {int? maxLength}) {
  final names = [for (final other in taken) other.trim()];
  var base = name.trim();

  // "Cash 2" typed when it is already taken counts on from "Cash".
  final stem = RegExp(r'^(.*\S) \d+$').firstMatch(base);
  if (stem != null &&
      names.any((other) => other.toLowerCase() == base.toLowerCase())) {
    base = stem.group(1)!;
  }

  final numbered = RegExp('^${RegExp.escape(base.toLowerCase())} (\\d+)\$');
  String? spelling;
  var highest = 1;
  for (final other in names) {
    final lower = other.toLowerCase();
    if (lower == base.toLowerCase()) {
      spelling = other;
      continue;
    }
    final match = numbered.firstMatch(lower);
    final number = int.tryParse(match?.group(1) ?? '');
    if (number == null) continue;
    spelling ??= other.substring(0, other.length - match!.group(1)!.length - 1);
    if (number > highest) highest = number;
  }
  if (spelling == null) return base;
  final number = ' ${highest + 1}';
  final room = maxLength == null ? spelling.length : maxLength - number.length;
  final kept = spelling.length > room
      ? spelling.substring(0, room < 0 ? 0 : room).trimRight()
      : spelling;
  return '$kept$number';
}
