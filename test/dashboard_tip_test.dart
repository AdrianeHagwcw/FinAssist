import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:testapp/backend/models/dashboard_tip.dart';
import 'package:testapp/backend/models/safe_to_spend.dart';
import 'package:testapp/frontend/providers/app_settings_provider.dart';
import 'package:testapp/frontend/theme/app_theme.dart';
import 'package:testapp/frontend/widgets/dashboard_tip.dart';

const tip = DashboardTip(title: 'Nothing logged today', message: 'Add it.');

Future<void> pump(WidgetTester tester, Widget card) async {
  await tester.pumpWidget(
    ChangeNotifierProvider(
      create: (_) => AppSettingsProvider(),
      child: MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(body: card),
      ),
    ),
  );
}

void main() {
  testWidgets('the light bulb starts with what is safe to spend today', (
    tester,
  ) async {
    var explained = 0;
    // ₱10,000, less ₱4,000 of bills, over 10 days: ₱615 a day once the
    // ₱150 spent today is counted back in, so ₱465 is left today.
    await pump(
      tester,
      DashboardTipCard(
        tip: tip,
        onOpenHistory: () {},
        safeToSpend: const SafeToSpend(
          walletBalance: 10000,
          billsDue: 4000,
          spentToday: 150,
          daysLeft: 10,
        ),
        onExplain: () => explained++,
      ),
    );

    expect(find.text('Safe to spend today'), findsOneWidget);
    expect(find.text('₱465'), findsOneWidget);
    expect(find.text('₱150 spent of ₱615 for today'), findsOneWidget);
    // The tip is still there, under it.
    expect(find.text('Nothing logged today'), findsOneWidget);

    await tester.tap(find.byKey(const Key('tip-safe-to-spend')));
    expect(explained, 1);
  });

  testWidgets('spending past it shows how far over, in red', (tester) async {
    await pump(
      tester,
      DashboardTipCard(
        tip: tip,
        onOpenHistory: () {},
        safeToSpend: const SafeToSpend(
          walletBalance: 1000,
          billsDue: 0,
          spentToday: 300,
          daysLeft: 13,
        ),
      ),
    );

    // ₱1,300 over 13 days is ₱100 a day; ₱300 spent is ₱200 over.
    expect(find.text('-₱200'), findsOneWidget);
    expect(find.text('Spent ₱300, over the ₱100 for today'), findsOneWidget);
  });

  testWidgets('with nothing in the wallets, only the tip shows', (
    tester,
  ) async {
    await pump(
      tester,
      DashboardTipCard(
        tip: tip,
        onOpenHistory: () {},
        safeToSpend: const SafeToSpend(
          walletBalance: 0,
          billsDue: 0,
          spentToday: 0,
          daysLeft: 10,
        ),
      ),
    );

    expect(find.text('Safe to spend today'), findsNothing);
    expect(find.text('Nothing logged today'), findsOneWidget);
  });
}
