import 'package:flutter_test/flutter_test.dart';

import 'package:testapp/backend/models/app_transaction.dart';
import 'package:testapp/backend/models/wallet.dart';

void main() {
  test('20% of interest earned is withheld, and the parts add back up', () {
    expect(interestTax(300), 60);
    expect(afterTax(300), 240);
    // ₱351.78 is ₱70.36 of tax and ₱281.42 that reaches the account.
    expect(interestTax(351.775), 70.36);
    expect(afterTax(351.775), 281.42);
    expect(interestTax(351.775) + afterTax(351.775), closeTo(351.78, 0.001));
  });

  test('the tax is worked back from what came in when that is all known', () {
    expect(taxWithheldOn(80), 20);
    expect(taxWithheldOn(240), 60);
  });

  test('interest income keeps the tax it had withheld', () {
    final saved = AppTransaction.fromMap('i', {
      'type': 'income',
      'amount': 80,
      'label': 'Interest',
      'taxWithheld': 20,
      'date': DateTime(2026, 11, 1),
    });
    expect(saved.taxWithheld, 20);
    // Recorded before the tax was counted: nothing is made up.
    expect(
      AppTransaction.fromMap('o', {
        'type': 'income',
        'amount': 100,
        'label': 'Interest',
      }).taxWithheld,
      0,
    );
  });
}
