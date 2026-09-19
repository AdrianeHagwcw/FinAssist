import 'package:flutter_test/flutter_test.dart';

import 'package:testapp/models/expense_guess.dart';
import 'package:testapp/utils/categories.dart';

void main() {
  const all = expenseCategories;

  group('what was said', () {
    ExpenseGuess say(String words, {List<String> categories = all}) =>
        guessFromSpeech(words, categories: categories);

    test('takes out the amount and keeps the rest as the description', () {
      final guess = say('lunch at jollibee 150 pesos');
      expect(guess.amount, 150);
      expect(guess.category, 'Food');
      expect(guess.description, 'Lunch at jollibee');
    });

    test('drops "I spent" and dangling words', () {
      final guess = say('I spent 150 on lunch');
      expect(guess.amount, 150);
      expect(guess.description, 'Lunch');
      expect(guess.category, 'Food');
    });

    test('reads the ways people say an amount', () {
      expect(say('P85 7 eleven').amount, 85);
      expect(say('php150 kape').amount, 150);
      expect(say('₱ 1,250.50 groceries').amount, 1250.5);
      expect(say('meralco 2,350.75').amount, 2350.75);
      expect(say('rent 3.5k').amount, 3500);
      expect(say('kape 60 piso').amount, 60);
      expect(say('netflix 549').amount, 549);
    });

    test('numbers that are part of a name or a unit are not amounts', () {
      expect(say('PS5 controller 3500').amount, 3500);
      expect(say('Biogesic 500mg 45 pesos').amount, 45);
      expect(say('flash drive 16GB').amount, isNull);
      expect(say('2 burgers 150 pesos').category, 'Food', reason: 'plural');
    });

    test('money words beat other numbers, and times are not amounts', () {
      expect(say('2 burgers 150 pesos').amount, 150);
      expect(say('coffee at 3:30 120').amount, 120);
      expect(say('7 eleven 85').amount, 85);
    });

    test('only an amount leaves the description to the user', () {
      final guess = say('150 pesos');
      expect(guess.amount, 150);
      expect(guess.description, isNull);
      expect(guess.category, isNull);
    });

    test('nothing to go on means nothing guessed', () {
      final guess = say('something something');
      expect(guess.amount, isNull);
      expect(guess.category, isNull);
      expect(guess.foundSomething, isFalse);
    });
  });

  group('category suggestion', () {
    String? suggest(String text, {List<String> from = all}) =>
        suggestCategory(text, from: from);

    test('knows local stores and Taglish', () {
      expect(suggest('Mang Inasal'), 'Food');
      expect(suggest('pamasahe jeep'), 'Transportation');
      expect(suggest('bayad sa Meralco'), 'Bills');
      expect(suggest('gamot sa Mercury Drug'), 'Healthcare');
      expect(suggest('pagkain ng pusa'), 'Pets');
      expect(suggest('Shopee order'), 'Shopping');
      expect(suggest('ML diamonds'), 'Entertainment');
      expect(suggest('tuition fee'), 'Education');
    });

    test('a longer phrase wins over a shorter one inside it', () {
      expect(suggest('grab food'), 'Food');
      expect(suggest('grab'), 'Transportation');
      expect(suggest('dog food'), 'Pets');
    });

    test('with a ride, the place gone to does not count', () {
      expect(suggest('Grab papunta sa school'), 'Transportation');
      expect(suggest('taxi to the mall'), 'Transportation');
      // Without a ride, the place is where the money went.
      expect(suggest('went to Jollibee'), 'Food');
    });

    test('a date is going out, unless what was paid for is named', () {
      expect(suggest('date with my girlfriend'), 'Entertainment');
      expect(suggest('nag-date kami'), 'Entertainment');
      expect(suggest('date night'), 'Entertainment');
      expect(suggest('dinner date with my girlfriend'), 'Food');
      expect(suggest('coffee date'), 'Food');
      expect(suggest('date with my girlfriend sa Jollibee'), 'Food');
      expect(suggest('movie date'), 'Entertainment');
      expect(suggest('Grab papunta sa date namin'), 'Transportation');
      // A calendar date isn't an occasion.
      expect(suggest('due date'), isNull);
      expect(suggest('girlfriend'), isNull);
    });

    test('a tie suggests nothing rather than guessing', () {
      expect(suggest('load and kape'), isNull);
    });

    test('never suggests a hidden category', () {
      final visible = all.where((c) => c != 'Pets').toList();
      expect(suggest('dog food', from: visible), 'Food');
      expect(suggest('vet', from: visible), isNull);
    });

    test('matches whole words only', () {
      expect(suggest('supermarket'), isNull, reason: 'not "market"');
      expect(suggest('smart watch'), isNull, reason: 'not the telco');
    });
  });

  group('receipt', () {
    final now = DateTime(2026, 9, 19, 10);
    ExpenseGuess read(String text, {List<String> categories = all}) =>
        guessFromReceipt(text, categories: categories, now: now);

    test('a fast-food receipt: total, store, category and date', () {
      final guess = read('''
JOLLIBEE
SM City Manila Branch
Official Receipt
09/18/2026 12:41 PM
1 Chickenjoy w/ Rice  99.00
1 Jolly Spaghetti  60.00
1 Coke Float  45.00
TOTAL  204.00
CASH  500.00
CHANGE  296.00
Thank you!''');
      expect(guess.amount, 204);
      expect(guess.description, 'Jollibee');
      expect(guess.category, 'Food');
      expect(guess.date, DateTime(2026, 9, 18));
    });

    test('skips headings and tax lines to find the store', () {
      final guess = read('''
OFFICIAL RECEIPT
SM SUPERMARKET
TIN 000-123-456-000
SUBTOTAL 1,250.00
TOTAL 1,250.00''');
      expect(guess.description, 'SM Supermarket');
      expect(guess.category, 'Food');
      expect(guess.amount, 1250);
    });

    test('an amount on the line after TOTAL DUE', () {
      final guess = read('''
MERCURY DRUG
Biogesic 500mg
SUBTOTAL 350.00
TOTAL DUE
P350.00
CASH 400.00''');
      expect(guess.amount, 350);
      expect(guess.description, 'Mercury Drug');
      expect(guess.category, 'Healthcare');
    });

    test('the date printed on a receipt is not an outing', () {
      final guess = read('''
ABC TRADING
Date: 09/18/2026
TOTAL 99.00''');
      expect(guess.category, isNull);
      expect(guess.date, DateTime(2026, 9, 18));
    });

    test('greetings are neither the store nor a clue to the category', () {
      final guess = read('''
THANK YOU FOR SHOPPING
ABC TRADING
TOTAL 99.00
Thank you for shopping!''');
      expect(guess.description, 'ABC Trading');
      expect(guess.category, isNull, reason: 'not Shopping from the footer');
      expect(read('Thank you for shopping').description, isNull);
    });

    test('label lines are never the store', () {
      expect(read('Cashier: Maria\nTOTAL 99.00').description, isNull);
      expect(read('Time 6:15 PM\nTOTAL 99.00').description, isNull);
    });

    test('an item with its price is never the store', () {
      final guess = read('''
Instant Noodles x10  95.00
Canned Tuna x5  175.00
TOTAL  270.00''');
      expect(guess.description, isNull);
      expect(guess.amount, 270);
    });

    test('the amount due beats a plain total before a discount', () {
      final guess = read('''
STORE
TOTAL 500.00
DISCOUNT 50.00
AMOUNT DUE 450.00''');
      expect(guess.amount, 450);
    });

    test('never takes the cash or change, and no total means no amount', () {
      final guess = read('''
STORE
CASH 1,000.00
CHANGE 796.00''');
      expect(guess.amount, isNull);
    });

    test('reads dates, and ignores future or very old ones', () {
      expect(read('Sep 18, 2026').date, DateTime(2026, 9, 18));
      expect(read('18 Sep 2026').date, DateTime(2026, 9, 18));
      expect(read('2026-09-01').date, DateTime(2026, 9, 1));
      expect(
        read('09/18/ 2026 6:15 PM').date,
        DateTime(2026, 9, 18),
        reason: 'the reader sometimes sees a space after a slash',
      );
      expect(read('valid until 09/18/2031').date, isNull);
      expect(read('issued 01/05/2020').date, isNull);
      // Month first, unless that is impossible.
      expect(read('25/08/2026').date, DateTime(2026, 8, 25));
    });
  });
}
