import 'package:flutter/services.dart';

import '../../backend/utils/text_limits.dart';

/// Groups an amount with commas while it is being typed, so nobody has to
/// count zeroes to tell ₱10,000 from ₱100,000.
///
/// Digits and one decimal point are kept, centavos are capped at two, whole
/// pesos at [maxAmountWholeDigits] (₱999,999,999.99), and everything else is
/// dropped, pasted text included. The caret is moved by counting the characters
/// the user actually typed rather than the characters on screen, so inserting
/// a digit that pushes a new comma in does not leave the caret behind it.
///
/// Every amount is parsed with the commas stripped, so what is stored is
/// unaffected by this.
class ThousandsSeparatorFormatter extends TextInputFormatter {
  const ThousandsSeparatorFormatter();

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final typed = newValue.text;
    final caret = newValue.selection.baseOffset;

    final kept = StringBuffer();
    var keptBeforeCaret = 0;
    var seenPoint = false;
    var decimals = 0;
    var wholeDigits = 0;

    for (var i = 0; i < typed.length; i++) {
      final character = typed[i];
      final code = character.codeUnitAt(0);
      final isDigit = code >= 0x30 && code <= 0x39;

      if (isDigit) {
        // A third centavo is refused rather than silently rounded later.
        if (seenPoint && decimals == 2) continue;
        // So is a tenth whole digit: more than any account holds, and the
        // start of totals that no longer add up exactly.
        if (!seenPoint && wholeDigits == maxAmountWholeDigits) continue;
        if (seenPoint) {
          decimals++;
        } else {
          wholeDigits++;
        }
      } else if (character == '.' && !seenPoint && kept.isNotEmpty) {
        seenPoint = true;
      } else {
        // Commas the user typed, and anything else, are dropped here and
        // put back by the grouping below.
        continue;
      }

      kept.write(character);
      if (i < caret) keptBeforeCaret++;
    }

    final cleaned = kept.toString();
    if (cleaned.isEmpty) {
      return const TextEditingValue(text: '');
    }

    final point = cleaned.indexOf('.');
    final whole = point == -1 ? cleaned : cleaned.substring(0, point);
    final rest = point == -1 ? '' : cleaned.substring(point);
    final grouped = _group(whole) + rest;

    return TextEditingValue(
      text: grouped,
      selection: TextSelection.collapsed(
        offset: _caretAfter(grouped, keptBeforeCaret),
      ),
    );
  }

  /// `1234567` becomes `1,234,567`.
  static String _group(String digits) =>
      digits.replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (match) => ',');

  /// Where the caret belongs once [count] typed characters have been passed,
  /// skipping the commas the grouping added.
  static int _caretAfter(String grouped, int count) {
    var seen = 0;
    for (var i = 0; i < grouped.length; i++) {
      if (grouped[i] != ',') {
        if (seen == count) return i;
        seen++;
      }
    }
    return grouped.length;
  }
}
