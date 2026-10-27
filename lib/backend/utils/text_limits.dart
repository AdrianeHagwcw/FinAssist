import 'package:flutter/services.dart';

// How long each kind of text can be, in one place so sign-up, setup, the
// forms setup shares with the rest of the app, and Profile all agree. A
// field that is shorter somewhere can be gone around from somewhere else.

/// A person's name: room for "Maria Clara Dela Cruz-Santos", short enough to
/// greet someone with.
const int maxPersonNameLength = 40;

/// A wallet or account name typed by the user, shown in pickers beside its
/// balance.
const int maxWalletNameLength = 30;

/// A wallet name as saved. Bank names from the list run to 43 characters
/// ("Rizal Commercial Banking Corporation (RCBC)"), and a repeat adds its
/// number, so a saved name has more room than a typed one.
const int maxSavedWalletNameLength = 50;

/// A goal, bill or savings record name.
const int maxItemNameLength = 40;

/// An email address: longer than nearly any real one, school ones included.
const int maxEmailLength = 100;

/// A password: room for one made by a password manager, which can be 64
/// characters or more. Capped so a pasted page cannot be sent to sign in.
const int maxPasswordLength = 128;

/// Whole pesos in an amount: up to ₱999,999,999.99. More than any personal
/// account holds, and far below where totals stop adding up exactly.
const int maxAmountWholeDigits = 9;
const double maximumAmount = 999999999.99;

/// An interest rate: up to 100%, to four decimals, since savings rates such
/// as 0.0625% are common.
const int maxRateWholeDigits = 3;
const int maxRateDecimals = 4;

/// Characters nobody can see, that can hide text or flip its direction:
/// control characters, zero-width spaces, soft hyphens, and the marks that
/// make text read right to left. Emoji joiners are kept, so emoji still work.
final RegExp _hidden = RegExp(
  '[\u0000-\u001F\u007F-\u009F\u00AD\u200B\u200C\u200E\u200F'
  '\u202A-\u202E\u2060-\u2064\u2066-\u2069\uFEFF]',
);

/// Tabs and line breaks, which read as a space between words rather than
/// nothing.
final RegExp _breaks = RegExp(r'[\t\n\r\v\f]');

/// [text] as it should be saved: hidden characters gone, any run of spaces
/// made one, and none at either end.
String cleanText(String text) => text
    .replaceAll(_breaks, ' ')
    .replaceAll(_hidden, '')
    .replaceAll(RegExp(r'\s+'), ' ')
    .trim();

/// Keeps hidden characters out of a name as it is typed or pasted, and a
/// second space in a row from going in. Works with any language and emoji.
class SafeTextFormatter extends TextInputFormatter {
  const SafeTextFormatter();

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final typed = newValue.text;
    final cleaned = typed
        .replaceAll(_breaks, ' ')
        .replaceAll(_hidden, '')
        .replaceAll(RegExp(r'\s{2,}'), ' ')
        .replaceFirst(RegExp(r'^\s+'), '');
    if (cleaned == typed) return newValue;

    // What was taken out was at or before the caret, so it moves back by
    // as much, and never past either end.
    final caret =
        newValue.selection.baseOffset - (typed.length - cleaned.length);
    return TextEditingValue(
      text: cleaned,
      selection: TextSelection.collapsed(
        offset: caret.clamp(0, cleaned.length),
      ),
    );
  }
}

/// A person's name may use letters from any language (Niño, Peña), marks,
/// numbers, spaces, and the . ' - of "Ma. Clara", "O'Neil" and "Mary-Ann".
final TextInputFormatter personNameFormatter =
    FilteringTextInputFormatter.allow(
      RegExp(r"[\p{L}\p{M}0-9 .'’\-]", unicode: true),
    );

/// Why [name] cannot be a person's name, or null when it can.
String? personNameProblem(
  String name, {
  String empty = 'Please enter your name.',
}) {
  final cleaned = cleanText(name);
  if (cleaned.isEmpty) return empty;
  if (cleaned.length > maxPersonNameLength) {
    return 'Keep it to $maxPersonNameLength characters.';
  }
  if (!RegExp(r'\p{L}', unicode: true).hasMatch(cleaned)) {
    return 'Your name needs at least one letter.';
  }
  if (!RegExp(r"^[\p{L}\p{M}0-9 .'’\-]+$", unicode: true).hasMatch(cleaned)) {
    return 'Use letters, numbers, spaces, and . \' - only.';
  }
  // A phone number has no place in a name that is shown and exported.
  if (hasAccountNumber(cleaned)) {
    return "Leave out phone or account numbers. Your name is enough.";
  }
  return null;
}

/// Why [name] cannot name a wallet, goal, bill or savings record, or null
/// when it can.
///
/// Numbers may be part of a name ("BPI 2", "Cash 2026", "GCash 0917"), but
/// a name needs a word, so it is never read as an amount beside the balance
/// it sits next to. And a long run of digits is refused: a name is stored
/// as it is, shown on screen and exported, so it must never hold a full
/// account, card or phone number.
String? itemNameProblem(
  String name, {
  required int maxLength,
  String empty = 'Give it a name.',
}) {
  final cleaned = cleanText(name);
  if (cleaned.isEmpty) return empty;
  if (cleaned.length > maxLength) return 'Keep it to $maxLength characters.';
  if (!RegExp(r'\p{L}', unicode: true).hasMatch(cleaned)) {
    return "Add a word, not just numbers, so it isn't read as an amount.";
  }
  if (hasAccountNumber(cleaned)) return accountNumberProblem;
  return null;
}

/// The most digits a name can hold in a row: enough for a year or the last
/// 4 digits of an account, too few for a whole account, card or phone
/// number.
const int maxDigitsInARow = 6;

const String accountNumberProblem =
    'Use a nickname, not an account or card number. The last 4 digits are '
    'enough.';

/// Whether [text] has more than [maxDigitsInARow] digits together, counting
/// digits split only by single spaces or dashes, as "1234 5678 9012" or
/// "0917-123-4567" are written.
bool hasAccountNumber(String text) =>
    RegExp('\\d(?:[\\s-]?\\d){$maxDigitsInARow,}').hasMatch(text);

/// Lets an interest rate be typed as digits and one decimal point, up to
/// [maxRateWholeDigits] whole digits and [maxRateDecimals] decimals, so
/// "1e5", "-3" or a pasted paragraph never reach the field.
class RateInputFormatter extends TextInputFormatter {
  const RateInputFormatter();

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final kept = StringBuffer();
    var seenPoint = false;
    var whole = 0;
    var decimals = 0;
    for (final character in newValue.text.split('')) {
      final isDigit = RegExp(r'[0-9]').hasMatch(character);
      if (isDigit) {
        if (seenPoint) {
          if (decimals == maxRateDecimals) continue;
          decimals++;
        } else {
          if (whole == maxRateWholeDigits) continue;
          whole++;
        }
      } else if (character == '.' && !seenPoint) {
        seenPoint = true;
      } else {
        continue;
      }
      kept.write(character);
    }
    final text = kept.toString();
    if (text == newValue.text) return newValue;
    return TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }
}
