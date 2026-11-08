import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:testapp/backend/models/app_transaction.dart';
import 'package:testapp/backend/models/bill.dart';
import 'package:testapp/backend/models/dashboard_tip.dart';
import 'package:testapp/backend/models/onboarding_data.dart';
import 'package:testapp/backend/models/reminder.dart';
import 'package:testapp/backend/models/wallet.dart';
import 'package:testapp/frontend/providers/app_settings_provider.dart';
import 'package:testapp/frontend/theme/app_theme.dart';
import 'package:testapp/frontend/widgets/due_soon_notice.dart';

const cash = Wallet(
  id: 'cash',
  name: 'Cash',
  type: WalletType.cash,
  balance: 20000,
  startingBalance: 20000,
  receivesIncome: false,
  archived: false,
  sortOrder: 0,
);

/// A profile with "Pay bills on time" in [place], counting from one.
Map<String, dynamic> profileAt(
  int place, {
  bool enabled = true,
  bool billsOn = true,
}) {
  final order = [FinancialPriority.saveForGoal, FinancialPriority.trackSpending]
    ..insert(place - 1, FinancialPriority.payBills);
  return {
    'notificationsEnabled': enabled,
    'reminders': {'enabled': enabled, if (!billsOn) 'bills': false},
    'priorities': [for (final priority in order) priority.name],
  };
}

BillInstance bill(String name, DateTime due) => BillInstance(
  id: 'i-$name',
  billId: 'b-$name',
  name: name,
  amount: 1000,
  category: 'Bills',
  dueDate: due,
  status: BillStatus.unpaid,
);

Future<void> pumpNotice(
  WidgetTester tester, {
  required List<BillInstance> bills,
  required int days,
}) async {
  tester.view.physicalSize = const Size(800, 1600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    ChangeNotifierProvider(
      create: (_) => AppSettingsProvider(),
      child: MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: DueSoonNotice(
            bills: bills,
            now: DateTime(2026, 9, 18, 10),
            days: days,
            onOpen: (_) {},
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  group('billDueSoonDays', () {
    test('looks as far ahead as the furthest bill reminder', () {
      expect(billDueSoonDays(ReminderSettings.fromProfile(profileAt(1))), 7);
      expect(billDueSoonDays(ReminderSettings.fromProfile(profileAt(2))), 3);
      expect(billDueSoonDays(ReminderSettings.fromProfile(profileAt(3))), 1);
    });

    test('keeps the safety net when reminders are off', () {
      expect(
        billDueSoonDays(
          ReminderSettings.fromProfile(profileAt(3, enabled: false)),
        ),
        3,
      );
      expect(
        billDueSoonDays(
          ReminderSettings.fromProfile(profileAt(3, billsOn: false)),
        ),
        3,
      );
      expect(billDueSoonDays(ReminderSettings.fromProfile(null)), 3);
    });
  });

  group('the due-soon card', () {
    testWidgets('with two reminders, shows only today, tomorrow and overdue', (
      tester,
    ) async {
      await pumpNotice(
        tester,
        days: 1,
        bills: [
          bill('Overdue', DateTime(2026, 9, 16)),
          bill('Today', DateTime(2026, 9, 18)),
          bill('Tomorrow', DateTime(2026, 9, 19)),
          bill('In two days', DateTime(2026, 9, 20)),
          bill('In three days', DateTime(2026, 9, 21)),
        ],
      );

      expect(find.text('Overdue'), findsOneWidget);
      expect(find.text('Today'), findsOneWidget);
      expect(find.text('Tomorrow'), findsOneWidget);
      expect(find.text('In two days'), findsNothing);
      expect(find.text('In three days'), findsNothing);
      expect(find.text('2 days overdue'), findsOneWidget);
      expect(find.text('due today'), findsOneWidget);
      expect(find.text('due tomorrow'), findsOneWidget);
    });

    testWidgets('with three reminders, reaches three days', (tester) async {
      await pumpNotice(
        tester,
        days: 3,
        bills: [
          bill('In two days', DateTime(2026, 9, 20)),
          bill('In three days', DateTime(2026, 9, 21)),
          bill('In four days', DateTime(2026, 9, 22)),
        ],
      );

      expect(find.text('In two days'), findsOneWidget);
      expect(find.text('In three days'), findsOneWidget);
      expect(find.text('In four days'), findsNothing);
    });

    testWidgets('with four reminders, reaches a week', (tester) async {
      await pumpNotice(
        tester,
        days: 7,
        bills: [
          bill('In seven days', DateTime(2026, 9, 25)),
          bill('In eight days', DateTime(2026, 9, 26)),
        ],
      );

      expect(find.text('In seven days'), findsOneWidget);
      expect(find.text('In eight days'), findsNothing);
    });

    testWidgets('still shows an overdue bill with no reminders ahead', (
      tester,
    ) async {
      await pumpNotice(
        tester,
        days: 0,
        bills: [
          bill('Overdue', DateTime(2026, 9, 17)),
          bill('Today', DateTime(2026, 9, 18)),
          bill('Tomorrow', DateTime(2026, 9, 19)),
        ],
      );

      expect(find.text('Overdue'), findsOneWidget);
      expect(find.text('Today'), findsOneWidget);
      expect(find.text('Tomorrow'), findsNothing);
    });
  });

  group('the tip above spending', () {
    final now = DateTime(2026, 9, 18, 10);
    final record = AppTransaction(
      id: 't1',
      type: TransactionType.expense,
      amount: 100,
      label: 'Food',
      date: now,
    );
    final soon = [bill('In two days', DateTime(2026, 9, 20))];

    test('looks no further ahead than the card', () {
      final short = dashboardTipFor(
        wallets: const [cash],
        transactions: [record],
        bills: soon,
        now: now,
        days: 1,
      );
      expect(short.title, isNot('A bill needs you soon'));

      final longer = dashboardTipFor(
        wallets: const [cash],
        transactions: [record],
        bills: soon,
        now: now,
        days: 3,
      );
      expect(longer.title, 'A bill needs you soon');
    });
  });
}
