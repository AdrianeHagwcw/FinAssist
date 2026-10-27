import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:testapp/frontend/utils/amount_input_formatter.dart';
import 'package:testapp/backend/utils/money_format.dart';

void main() {
  const formatter = ThousandsSeparatorFormatter();

  /// Types [text] from empty, with the caret at its end.
  TextEditingValue type(String text, {int? caret}) {
    return formatter.formatEditUpdate(
      const TextEditingValue(),
      TextEditingValue(
        text: text,
        selection: TextSelection.collapsed(offset: caret ?? text.length),
      ),
    );
  }

  group('typing an amount', () {
    test('commas appear once the thousands do', () {
      expect(type('999').text, '999');
      expect(type('1000').text, '1,000');
      expect(type('10000').text, '10,000');
      expect(type('100000').text, '100,000');
      expect(type('1234567').text, '1,234,567');
    });

    test('it keeps grouping up to the largest amount, ₱999,999,999.99', () {
      expect(type('12345').text, '12,345');
      expect(type('123456').text, '123,456');
      expect(type('12345678').text, '12,345,678');
      expect(type('123456789').text, '123,456,789');
      // A tenth whole digit is refused, typed or pasted.
      expect(type('1234567890').text, '123,456,789');
      expect(type('123456789012').text, '123,456,789');
      // Centavos still fit on the end of the largest one.
      expect(type('9876543210.25').text, '987,654,321.25');
      expect(type('999999999.99').text, '999,999,999.99');
    });

    test('centavos are kept, and capped at two', () {
      expect(type('1500.5').text, '1,500.5');
      expect(type('1500.50').text, '1,500.50');
      // A third centavo is refused rather than rounded away later.
      expect(type('1500.509').text, '1,500.50');
    });

    test('only one decimal point survives', () {
      expect(type('12.34.56').text, '12.34');
    });

    test('a stray point before any digit is ignored', () {
      expect(type('.').text, '');
      expect(type('.5').text, '5');
    });

    test('letters and symbols are dropped', () {
      expect(type('1a2b3').text, '123');
      expect(type('₱2,500').text, '2,500');
    });

    test('an emptied field stays empty', () {
      expect(type('').text, '');
      expect(type('abc').text, '');
    });

    test('the caret follows the digit just typed, not the new comma', () {
      // "100" with a 0 added at the end becomes "1,000": four digits typed,
      // so the caret sits after the last of them.
      final value = type('1000');
      expect(value.text, '1,000');
      expect(value.selection.baseOffset, 5);

      // Typing in the middle: caret after three typed characters of "12345"
      // lands after the "3" in "12,345".
      final middle = type('12345', caret: 3);
      expect(middle.text, '12,345');
      expect(middle.text[middle.selection.baseOffset - 1], '3');
    });

    test('what is typed still parses to the same amount', () {
      final shown = type('1234567.89').text;
      expect(shown, '1,234,567.89');
      expect(double.parse(shown.replaceAll(',', '')), 1234567.89);
    });
  });

  group('the smallest amount worth recording', () {
    test('nothing, zero and negatives are refused', () {
      expect(isRecordableAmount(null), isFalse);
      expect(isRecordableAmount(0), isFalse);
      expect(isRecordableAmount(-5), isFalse);
      expect(isRecordableAmount(double.nan), isFalse);
      expect(isRecordableAmount(double.infinity), isFalse);
    });

    test('anything that would show as ₱0 is refused', () {
      // These round to nothing on screen, so storing them would hide money
      // the user could never see or correct.
      expect(isRecordableAmount(0.004), isFalse);
      expect(formatPeso(0.004), '₱0');

      expect(isRecordableAmount(0.005), isFalse);
      expect(isRecordableAmount(0.009), isFalse);
      expect(formatPeso(0.005), '₱0.01');
      expect(isRecordableAmount(minimumAmount), isTrue);
    });
  });
}
