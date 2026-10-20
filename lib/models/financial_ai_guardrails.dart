/// Generated prose supplements the app's calculations; it never supplies them.
/// This rejects common unsupported numeric/guarantee claims, not every possible
/// factual error. Real-model evaluation is still necessary.
bool isUsableFinancialExplanation(String text) {
  final value = text.trim();
  if (value.isEmpty || value.length > 5000) return false;
  if (RegExp(r'[\d₱$€£%]').hasMatch(value)) return false;
  if (RegExp(
    r'\b(?:zero|one|two|three|four|five|six|seven|eight|nine|ten|'
    r'eleven|twelve|twenty|thirty|fifty|hundred|thousand|million|billion|'
    r'percent|percentage|pesos?|dollars?|doble|triple|porsiyento|'
    r'isa|dalawa|tatlo|apat|lima|anim|pito|walo|siyam|sampu|daan|libo|milyon)\b',
    caseSensitive: false,
  ).hasMatch(value)) {
    return false;
  }
  if (RegExp(
    r'\b(?:guaranteed|risk.free|certainly afford|definitely afford|'
    r'you can afford|you can safely|kayang.kaya|siguradong|tiyak na)\b',
    caseSensitive: false,
  ).hasMatch(value)) {
    return false;
  }
  return true;
}

bool isUncertainFinancialExplanation(String text) => RegExp(
  r'\b(?:i\s+(?:do not|dont|can not|cant|cannot)\s+know|'
  r'not\s+sure|unclear|need\s+more\s+(?:information|details)|'
  r'could\s+not\s+determine|i\s+cannot\s+answer)\b',
  caseSensitive: false,
).hasMatch(text);
