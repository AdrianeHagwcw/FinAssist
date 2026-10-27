import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:testapp/backend/models/wallet.dart';
import 'package:testapp/frontend/theme/app_theme.dart';
import 'package:testapp/frontend/widgets/wallets_added_sheet.dart';

Wallet wallet(String id, String name, WalletType type, double balance) =>
    Wallet(
      id: id,
      name: name,
      type: type,
      balance: balance,
      startingBalance: balance,
      receivesIncome: false,
      archived: false,
      sortOrder: 0,
    );

/// ₱5,000 cash already there; ₱1,000 more cash and ₱10,000 in BPI just
/// added.
final wallets = [
  wallet('cash', 'Cash', WalletType.cash, 5000),
  wallet('cash2', 'Cash 2', WalletType.cash, 1000),
  wallet('bpi', 'BPI', WalletType.bank, 10000),
];

void main() {
  Future<bool?> open(WidgetTester tester) async {
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    bool? answer;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async => answer = await showWalletsAddedSheet(
                context,
                addedIds: {'cash2', 'bpi'},
                goals: const [],
                wallets: Stream.value(wallets),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    return answer;
  }

  testWidgets('shows what was added and the Cash Summary', (tester) async {
    await open(tester);

    expect(find.text('2 wallets added'), findsOneWidget);
    // Only the wallets just added are listed, each with its balance.
    expect(find.byKey(const Key('added-cash2')), findsOneWidget);
    expect(find.byKey(const Key('added-bpi')), findsOneWidget);
    expect(find.byKey(const Key('added-cash')), findsNothing);

    // Every wallet counts in the summary: ₱6,000 cash, ₱10,000 in the bank.
    expect(find.text('Cash on Hand'), findsOneWidget);
    expect(find.text('₱6,000'), findsOneWidget);
    expect(find.text('Cash in Bank'), findsOneWidget);
    expect(find.text('₱10,000'), findsNWidgets(2), reason: 'BPI and the bank');
    expect(
      find.descendant(
        of: find.byKey(const Key('added-total')),
        matching: find.text('₱16,000'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('Add Another keeps going; Done stops', (tester) async {
    bool? answer;
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async => answer = await showWalletsAddedSheet(
                context,
                addedIds: {'cash2'},
                goals: const [],
                wallets: Stream.value(wallets),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('Wallet added'), findsOneWidget);
    await tester.tap(find.text('Add Another'));
    await tester.pumpAndSettle();
    expect(answer, isTrue);

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    expect(answer, isFalse);
  });
}
