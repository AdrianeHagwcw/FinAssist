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

    // Available Balance is shown before today's spending, then today's spend
    // and Bills are taken off to reach what remains in the wallets.
    expect(
      find.text('Available Balance before today\'s spending'),
      findsOneWidget,
    );
    expect(find.text('₱10,150'), findsOneWidget);
    expect(find.text('Spent today'), findsOneWidget);
    expect(find.text('− ₱150'), findsOneWidget);
    expect(find.text('Bills due this month'), findsOneWidget);
    expect(find.text('− ₱4,000'), findsOneWidget);
    // Left is the money actually still there: ₱10,000 less the bills, with
    // the ₱150 spent today counted only once.
    expect(find.text('Left through the end of this month'), findsOneWidget);
    expect(find.text('₱6,000'), findsOneWidget);
    expect(
      find.text(
        'Before today\'s spending, your Available Balance after this month\'s '
        'Bills was ₱6,150. That is ₱615 a day for the 10 days left this month. '
        'You\'ve spent ₱150 today, so ₱465 is left.',
      ),
      findsOneWidget,
    );
    // The figure is for this month; next month is not counted yet.
    expect(
      find.textContaining('Only bills due this month are counted'),
      findsOneWidget,
    );
  });

  testWidgets('the working starts from Available Balance, after Goals', (
    tester,
  ) async {
    await pump(
      tester,
      const SafeToSpendWorking(
        SafeToSpend(
          walletBalance: 32845,
          billsDue: 2500,
          goalSavings: 2665,
          spentToday: 0,
          daysLeft: 26,
        ),
      ),
    );

    expect(find.text('Available Balance'), findsOneWidget);
    expect(find.text('₱30,180'), findsOneWidget);
    expect(find.text('Bills due this month'), findsOneWidget);
    expect(find.text('− ₱2,500'), findsOneWidget);
    expect(find.text('Saved for your goals'), findsNothing);
    expect(find.text('₱27,680'), findsOneWidget);
    expect(
      find.text(
        'After this month\'s Bills, ₱27,680 is left for the 26 days left this '
        'month: ₱1,064.62 a day.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('the working names bills, installments and debts apart', (
    tester,
  ) async {
    await pump(
      tester,
      const SafeToSpendWorking(
        SafeToSpend(
          walletBalance: 10000,
          billsDue: 6000,
          installmentsDue: 2000,
          debtsDue: 1000,
          spentToday: 0,
          daysLeft: 10,
        ),
      ),
    );

    expect(find.text('Bills due this month'), findsOneWidget);
    expect(find.text('− ₱3,000'), findsOneWidget);
    expect(find.text('Installments due this month'), findsOneWidget);
    expect(find.text('− ₱2,000'), findsOneWidget);
    expect(find.text('Debts due this month'), findsOneWidget);
    expect(find.text('− ₱1,000'), findsOneWidget);
    // One total would repeat the three lines above it.
    expect(find.text('Bills still to pay'), findsNothing);
  });

  testWidgets('a kind with nothing due has no row', (tester) async {
    await pump(
      tester,
      const SafeToSpendWorking(
        SafeToSpend(
          walletBalance: 10000,
          billsDue: 3000,
          installmentsDue: 0,
          debtsDue: 0,
          spentToday: 0,
          daysLeft: 10,
        ),
      ),
    );

    expect(find.text('Bills due this month'), findsOneWidget);
    expect(find.text('− ₱3,000'), findsOneWidget);
    expect(find.text('Installments due this month'), findsNothing);
    expect(find.text('Debts due this month'), findsNothing);
  });

  testWidgets('says when bills are not in the figure yet', (tester) async {
    await pump(
      tester,
      const SafeToSpendBar(
        safeToSpend: SafeToSpend(
          walletBalance: 1000,
          billsDue: 0,
          spentToday: 0,
          daysLeft: 10,
          billsUnknown: true,
        ),
      ),
    );

    expect(find.text("Bills aren't counted yet."), findsOneWidget);
  });

  testWidgets('says when the bills may be out of date', (tester) async {
    await pump(
      tester,
      const SafeToSpendBar(
        safeToSpend: SafeToSpend(
          walletBalance: 1000,
          billsDue: 500,
          spentToday: 0,
          daysLeft: 10,
          billsOutOfDate: true,
        ),
      ),
    );

    expect(find.text('Bills may be out of date.'), findsOneWidget);
    expect(find.text("Bills aren't counted yet."), findsNothing);
  });
}
