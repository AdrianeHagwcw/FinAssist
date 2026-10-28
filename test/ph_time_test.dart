import 'package:flutter_test/flutter_test.dart';

import 'package:testapp/backend/models/expense_guess.dart';
import 'package:testapp/backend/utils/categories.dart';
import 'package:testapp/backend/utils/ph_time.dart';

void main() {
  group('Philippine time', () {
    test('a phone on GMT still gets the Philippine date', () {
      // 4:58 PM on Oct 27 in London is 12:58 AM on Oct 28 in Manila.
      final ph = philippineTime(DateTime.utc(2026, 10, 27, 16, 58));
      expect([ph.year, ph.month, ph.day, ph.hour, ph.minute], [
        2026,
        10,
        28,
        0,
        58,
      ]);
    });

    test('a Philippine day starts at 4 PM the day before, in GMT', () {
      expect(
        philippineDayStart(DateTime(2026, 10, 28)),
        DateTime.utc(2026, 10, 27, 16),
      );
    });

    test('the month turns over at Philippine midnight', () {
      // 11 PM on Oct 31 in Manila, 3 PM in GMT.
      expect(philippineTime(DateTime.utc(2026, 10, 31, 15)).month, 10);
      // 1 AM on Nov 1 in Manila, still Oct 31 in GMT.
      expect(philippineTime(DateTime.utc(2026, 10, 31, 17)).month, 11);
    });
  });

  test('snacks are Food', () {
    for (final words in [
      'cookies',
      'biscuit',
      'chips',
      'chicharon',
      'candies',
      'ice cream',
      'siomai',
      'milk tea',
    ]) {
      expect(
        suggestCategory(words, from: expenseCategories),
        'Food',
        reason: words,
      );
    }
  });
}
