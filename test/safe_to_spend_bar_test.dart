import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:testapp/backend/models/safe_to_spend.dart';
import 'package:testapp/frontend/providers/app_settings_provider.dart';
import 'package:testapp/frontend/theme/app_theme.dart';
import 'package:testapp/frontend/widgets/safe_to_spend_bar.dart';
import 'package:testapp/frontend/widgets/safe_to_spend_card.dart';

Future<void> pump(WidgetTester tester, Widget child) async {
  await tester.pumpWidget(
    ChangeNotifierProvider(
      create: (_) => AppSettingsProvider(),
      child: MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          backgroundColor: Colors.blue,
          body: Padding(padding: const EdgeInsets.all(16), child: child),
        ),
      ),
    ),
  );
}

/// ₱10,000, less ₱4,000 of bills, over 10 days: ₱615 a day once the ₱150
/// spent today is counted back in, so ₱465 is left today.
const today = SafeToSpend(
  walletBalance: 10000,
  billsDue: 4000,
  spentToday: 150,
  daysLeft: 10,
);

void main() {
  testWidgets('the bar shows what is spent of today\'s safe amount', (
    tester,
  ) async {
    var tapped = 0;
    await pump(
      tester,
      SafeToSpendBar(safeToSpend: today, onTap: () => tapped++),
    );

    expect(find.text('Safe to spend today'), findsOneWidget);
    expect(find.text('₱150 / ₱615'), findsOneWidget);
    final bar = tester.widget<LinearProgressIndicator>(
      find.byType(LinearProgressIndicator),
    );
    expect(bar.value, closeTo(150 / 615, 0.0001));

    await tester.tap(find.byKey(const Key('safe-to-spend-bar')));
    expect(tapped, 1);
  });

  testWidgets('spending past it says so', (tester) async {
    // ₱1,300 over 13 days is ₱100 a day; ₱300 is spent.
    await pump(
      tester,
      const SafeToSpendBar(
        safeToSpend: SafeToSpend(
          walletBalance: 1000,
          billsDue: 0,
          spentToday: 300,
          daysLeft: 13,
        ),
      ),
    );

    expect(find.text("Over today's safe amount"), findsOneWidget);
    expect(find.text('₱300 / ₱100'), findsOneWidget);
  });

  testWidgets('the working ends on what is left today', (tester) async {
    await pump(tester, const SafeToSpendWorking(today));

    expect(find.text('Money in your wallets'), findsOneWidget);
    expect(find.text('Bills still to pay'), findsOneWidget);
    expect(
      find.text(
        "That is ₱615 a day for the 10 days left this month. You've spent "
        '₱150 today, so ₱465 is left.',
      ),
      findsOneWidget,
    );
  });
}
