import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:testapp/utils/text_limits.dart';
import 'package:testapp/utils/unique_name.dart';

void main() {
  TextEditingValue run(TextInputFormatter formatter, String text) =>
      formatter.formatEditUpdate(
        TextEditingValue.empty,
        TextEditingValue(
          text: text,
          selection: TextSelection.collapsed(offset: text.length),
        ),
      );

  group('names', () {
    test('hidden characters never get in, typed or pasted', () {
      const formatter = SafeTextFormatter();
      // A zero-width space, a right-to-left override and a control character
      // are all invisible, and the override can make text read backwards.
      final hidden =
          'Rent${String.fromCharCode(0x200B)}'
          '${String.fromCharCode(0x202E)}al${String.fromCharCode(0x07)}';
      expect(run(formatter, hidden).text, 'Rental');
      // A second space in a row, and spaces at the start, are dropped.
      expect(run(formatter, '  Petty   Cash').text, 'Petty Cash');
      // Emoji are fine in a goal or bill name.
      expect(run(formatter, 'Trip ✈️').text, 'Trip ✈️');
    });

    test('a saved name is clean', () {
      final pasted = ' Petty\tCash${String.fromCharCode(0xFEFF)}\n ';
      expect(cleanText(pasted), 'Petty Cash');
    });

    test('a name needs something readable, within its limit', () {
      expect(
        itemNameProblem('', maxLength: maxItemNameLength),
        'Give it a name.',
      );
      // Spaces and invisible characters alone count as empty.
      expect(
        itemNameProblem(
          '   ${String.fromCharCode(0x200B)}',
          maxLength: maxItemNameLength,
        ),
        'Give it a name.',
      );
      const noWord =
          "Add a word, not just numbers, so it isn't read as an amount.";
      expect(itemNameProblem('...---', maxLength: maxItemNameLength), noWord);
      expect(
        itemNameProblem('a' * 41, maxLength: maxItemNameLength),
        'Keep it to 40 characters.',
      );
      expect(itemNameProblem('Tuition 2026', maxLength: 40), isNull);
      expect(itemNameProblem('Bahay 🏠', maxLength: 40), isNull);
    });

    test('a name needs a word, and never holds an account number', () {
      const noWord =
          "Add a word, not just numbers, so it isn't read as an amount.";
      // Only digits would read as an amount beside the balance.
      expect(
        itemNameProblem('545636456456464', maxLength: maxWalletNameLength),
        noWord,
      );
      expect(itemNameProblem('2026', maxLength: maxItemNameLength), noWord);
      // Numbers as part of a name are fine: a repeat, a year, last 4 digits.
      for (final name in [
        'BPI 2',
        'Cash 2026',
        'GCash 0917',
        'BDO ending 1234',
        '2026 Trip',
      ]) {
        expect(
          itemNameProblem(name, maxLength: maxWalletNameLength),
          isNull,
          reason: name,
        );
      }
      // A whole card, account or phone number is refused, written any way.
      for (final name in [
        'Card 4111111111111111',
        'BDO 1234 5678 9012',
        'GCash 0917-123-4567',
        'Savings 1234567',
      ]) {
        expect(
          itemNameProblem(name, maxLength: maxSavedWalletNameLength),
          accountNumberProblem,
          reason: name,
        );
      }
      // Six in a row is still a name; seven is a number.
      expect(hasAccountNumber('Fund 202612'), isFalse);
      expect(hasAccountNumber('Fund 2026123'), isTrue);
      // A person's name is held to the same.
      expect(
        personNameProblem('Dave 09171234567'),
        'Leave out phone or account numbers. Your name is enough.',
      );
    });

    test('a person name allows every way Filipino names are spelled', () {
      expect(personNameProblem('Dave'), isNull);
      expect(personNameProblem("Ma. Niño O'Neil-Peña"), isNull);
      expect(personNameProblem(''), 'Please enter your name.');
      expect(personNameProblem('123'), 'Your name needs at least one letter.');
      expect(
        personNameProblem('Dave<script>'),
        "Use letters, numbers, spaces, and . ' - only.",
      );
      expect(personNameProblem('a' * 41), 'Keep it to 40 characters.');
    });

    test('a numbered repeat still fits the name limit', () {
      final long = 'a' * 30;
      final numbered = uniqueName(long, [long], maxLength: 30);
      expect(numbered.length, 30);
      expect(numbered, endsWith(' 2'));
      // A listed bank name keeps its whole name within the saved limit.
      const rcbc = 'Rizal Commercial Banking Corporation (RCBC)';
      expect(
        uniqueName(rcbc, [rcbc], maxLength: maxSavedWalletNameLength),
        '$rcbc 2',
      );
    });
  });

  group('interest rates', () {
    test('only a plain number fits, up to 100 and four decimals', () {
      const formatter = RateInputFormatter();
      expect(run(formatter, '6.25').text, '6.25');
      expect(run(formatter, '0.0625').text, '0.0625');
      // Extra decimals, a fourth whole digit, signs and letters are dropped.
      expect(run(formatter, '0.06251').text, '0.0625');
      expect(run(formatter, '1000').text, '100');
      expect(run(formatter, '-3').text, '3');
      expect(run(formatter, '1e5').text, '15');
      expect(run(formatter, '3.5.1').text, '3.51');
    });
  });
}
