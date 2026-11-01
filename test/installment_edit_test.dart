import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:testapp/backend/models/bill.dart';
import 'package:testapp/backend/models/debt.dart';
import 'package:testapp/frontend/providers/app_settings_provider.dart';
import 'package:testapp/frontend/screens/debt_detail_screen.dart';
import 'package:testapp/frontend/theme/app_theme.dart';
import 'package:testapp/frontend/widgets/installment_form_sheet.dart';

/// A phone bought on installment: ₱48,000 in 12 payments of ₱4,000, first
/// due on 10 June 2026.
Debt installment({
  String name = 'iPhone 15',
  double perPayment = 4000,
  int paymentCount = 12,
  String? paidWithWalletId,
  DateTime? firstDueDate,
  double lastPayment = 0,
}) => Debt(
  id: 'phone',
  direction: DebtDirection.iOwe,
  name: name,
  category: DebtCategory.gadget,
  principal: perPayment * paymentCount,
  perPayment: perPayment,
  paymentCount: paymentCount,
  lastPayment: lastPayment,
  firstDueDate: firstDueDate ?? DateTime(2026, 6, 10),
  billId: 'bill',
  paidWithWalletId: paidWithWalletId,
  paidWithLabel: paidWithWalletId == null ? null : 'Cash',
  status: DebtStatus.active,
);

/// The worked-out payment for month [month] of 2026, of [amount].
BillInstance payment({
  required int month,
  required double amount,
  String id = '',
  double amountPaid = 0,
  BillStatus status = BillStatus.unpaid,
  double carriedOver = 0,
  String? carriedInto,
}) => BillInstance(
  id: id.isEmpty ? 'bill-2026-$month-10' : id,
  billId: 'bill',
  name: 'iPhone 15',
  amount: amount,
  category: 'Bills',
  dueDate: DateTime(2026, month, 10),
  status: status,
  amountPaid: amountPaid,
  carriedOver: carriedOver,
  carriedInto: carriedInto,
);

Future<void> pumpForm(
  WidgetTester tester,
  InstallmentFormSheet sheet,
) async {
  tester.view.physicalSize = const Size(800, 3200);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    ChangeNotifierProvider(
      create: (_) => AppSettingsProvider(),
      child: MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(body: sheet),
      ),
    ),
  );
  await tester.pump();
}

/// What is typed in a field of the form, found by the key it carries: on the
/// field itself, or on a wrapper such as AmountField that holds one.
String textOf(WidgetTester tester, Key key) {
  final finder = find.byKey(key);
  final carried = finder.evaluate().firstOrNull?.widget;
  if (carried is TextField) return carried.controller?.text ?? '';

  return tester
      .widget<TextField>(
        find.descendant(of: finder, matching: find.byType(TextField)),
      )
      .controller
      ?.text ??
      '';
}

void main() {
  group('the notice on the installment form', () {
    testWidgets('says a plan can be fixed until a payment is made', (
      tester,
    ) async {
      await pumpForm(tester, const InstallmentFormSheet());

      // Said up front, before anything is typed.
      expect(find.byKey(const Key('installment-edit-note')), findsOneWidget);
      expect(
        find.text(
          'You can fix this plan any time before a payment is made on it — '
          'its payments are worked out from what you enter. Once a payment '
          'has been made on it, it can no longer be edited.',
        ),
        findsOneWidget,
      );
      expect(find.text('Add Installment'), findsOneWidget);
    });

    testWidgets('is there when the plan is opened to be corrected', (
      tester,
    ) async {
      await pumpForm(
        tester,
        InstallmentFormSheet(existing: installment(paidWithWalletId: 'cash')),
      );

      expect(find.byKey(const Key('installment-edit-note')), findsOneWidget);
      expect(
        find.text(
          'You can fix this plan any time before a payment is made on it — '
          'every payment is worked out again from what you change. Once a '
          'payment has been made on it, it can no longer be edited.',
        ),
        findsOneWidget,
      );
      expect(find.text('Edit Installment'), findsOneWidget);
      expect(find.text('Add Installment'), findsNothing);
      // The plan's own date is kept, so the payments already laid out stay
      // on the days they were agreed.
      expect(find.text('Save Changes'), findsOneWidget);
    });
  });

  group('correcting a plan', () {
    testWidgets('starts filled in as it was saved', (tester) async {
      InstallmentDraft? saved;
      await pumpForm(
        tester,
        InstallmentFormSheet(
          existing: installment(
            name: 'Aircon',
            perPayment: 2500,
            paymentCount: 10,
            firstDueDate: DateTime(2026, 3, 5),
            paidWithWalletId: 'cash',
          ),
          onSave: (draft) => saved = draft,
        ),
      );

      expect(textOf(tester, const Key('installment-description')), 'Aircon');
      // The cash price is the whole left to pay, so it comes back as it was
      // saved rather than being guessed at again.
      expect(textOf(tester, const Key('installment-price')), '25000');
      expect(textOf(tester, const Key('installment-months')), '10');

      await tester.ensureVisible(find.text('Save Changes'));
      await tester.tap(find.text('Save Changes'));
      await tester.pump();

      // Nothing was mistyped, so nothing is changed: the same plan comes
      // back, on the same first date.
      expect(saved, isNotNull);
      expect(saved!.name, 'Aircon');
      expect(saved!.perPayment, 2500);
      expect(saved!.paymentCount, 10);
      expect(saved!.firstDueDate, DateTime(2026, 3, 5));
      // The wallet it was charged to stays, even though this form was given
      // no wallets to offer.
      expect(saved!.paidWithWalletId, 'cash');
      expect(saved!.paidWithLabel, 'Cash');
    });

    testWidgets('sends what was changed back to be worked out again', (
      tester,
    ) async {
      InstallmentDraft? saved;
      await pumpForm(
        tester,
        InstallmentFormSheet(
          existing: installment(
            name: 'Aircon',
            perPayment: 2500,
            paymentCount: 10,
            firstDueDate: DateTime(2026, 3, 5),
            paidWithWalletId: 'cash',
          ),
          onSave: (draft) => saved = draft,
        ),
      );

      // The months were wrong: it is 12, not 10.
      await tester.enterText(find.byKey(const Key('installment-months')), '12');
      await tester.pump();

      await tester.ensureVisible(find.text('Save Changes'));
      await tester.tap(find.text('Save Changes'));
      await tester.pump();

      // ₱25,000 over 12 months, and still starting on the day it was agreed.
      expect(saved!.perPayment, closeTo(2083.33, 0.01));
      expect(saved!.paymentCount, 12);
      expect(saved!.firstDueDate, DateTime(2026, 3, 5));
      expect(saved!.paidWithWalletId, 'cash');
      expect(saved!.paidWithLabel, 'Cash');
    });
  });

  group('the Edit entry on a plan', () {
    Future<void> openOptions(WidgetTester tester, Widget screen) async {
      tester.view.physicalSize = const Size(800, 3200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        ChangeNotifierProvider(
          create: (_) => AppSettingsProvider(),
          child: MaterialApp(theme: AppTheme.light, home: screen),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Options'));
      await tester.pumpAndSettle();
    }

    Widget detail(Debt debt, List<BillInstance> payments) =>
        InstallmentDetailScreen(
          debt: debt,
          liveDebt: Stream.value(debt),
          payments: Stream.value(payments),
          wallets: Stream.value(const []),
        );

    testWidgets('is there while nothing has been paid', (tester) async {
      await openOptions(tester, detail(installment(), const []));

      expect(find.text('Edit'), findsOneWidget);
      expect(find.text('Delete'), findsOneWidget);
    });

    testWidgets('is still there with payments waiting, none paid', (
      tester,
    ) async {
      await openOptions(
        tester,
        detail(
          installment(),
          [
            payment(month: 6, amount: 4000),
            payment(month: 7, amount: 4000),
          ],
        ),
      );

      expect(find.text('Edit'), findsOneWidget);
    });

    testWidgets('is gone once a payment has been made', (tester) async {
      await openOptions(
        tester,
        detail(
          installment(),
          [
            payment(month: 6, amount: 4000, amountPaid: 4000, status: BillStatus.paid),
            payment(month: 7, amount: 4000),
          ],
        ),
      );

      // From the first payment the plan is the record of what was agreed.
      expect(find.text('Edit'), findsNothing);
      expect(find.text('Delete'), findsOneWidget);
    });

    testWidgets('is never on borrowed money', (tester) async {
      final loan = Debt(
        id: 'juan',
        direction: DebtDirection.iOwe,
        name: 'Personal loan',
        category: DebtCategory.personalLoan,
        principal: 24000,
        perPayment: 2000,
        paymentCount: 12,
        firstDueDate: DateTime(2026, 6, 5),
        billId: 'bill',
        status: DebtStatus.active,
      );

      await openOptions(tester, detail(loan, const []));

      expect(find.text('Edit'), findsNothing);
      expect(find.text('Delete'), findsOneWidget);
    });
  });

  group('working the payments out again', () {
    Debt terms({
      required double perPayment,
      required int paymentCount,
      String name = 'iPhone 15',
      double lastPayment = 0,
    }) => installment(
      name: name,
      perPayment: perPayment,
      paymentCount: paymentCount,
      lastPayment: lastPayment,
    );

    List<InstallmentPaymentEdit> recalc(
      Debt plan,
      List<BillInstance> instances,
    ) => recalculateInstallmentPayments(terms: plan, instances: instances);

    test('a price that was too high brings every payment down', () {
      // Was ₱4,000 a month; the receipt said ₱3,500.
      final edits = recalc(
        terms(perPayment: 3500, paymentCount: 12),
        [for (var month = 6; month <= 17; month++) payment(month: month, amount: 4000)],
      );

      expect(edits, hasLength(12));
      for (final edit in edits) {
        expect(edit.removes, isFalse);
        expect(edit.amount, 3500);
      }
    });

    test('a plan cut short takes the payments it no longer reaches', () {
      // 12 months down to 8: June through January stay, February to March
      // are gone.
      final edits = recalc(
        terms(perPayment: 4000, paymentCount: 8),
        [for (var month = 6; month <= 17; month++) payment(month: month, amount: 4000)],
      );

      final removed = edits.where((edit) => edit.removes).toList();
      expect(removed, hasLength(4));
      expect(
        removed.map((edit) => edit.instance.dueDate),
        [
          DateTime(2027, 2, 10),
          DateTime(2027, 3, 10),
          DateTime(2027, 4, 10),
          DateTime(2027, 5, 10),
        ],
      );
      // What stays is untouched: the plan still asks for ₱4,000 on each.
      expect(edits.where((edit) => !edit.removes), isEmpty);
    });

    test('a payment already part-paid keeps what was paid on it', () {
      final edits = recalc(
        terms(perPayment: 3500, paymentCount: 12),
        [payment(month: 6, amount: 4000, amountPaid: 500)],
      );

      expect(edits.single.amount, 3500);
      // The ₱500 already paid is not touched by the rewrite.
      expect(edits.single.instance.amountPaid, 500);
    });

    test('a last payment that differs is worked out again', () {
      // 10 months of ₱2,500 with ₱2,000 left over, corrected to ₱2,600 with
      // ₱1,600 at the end.
      final edits = recalc(
        terms(perPayment: 2600, paymentCount: 10, lastPayment: 1600),
        [
          for (var month = 6; month <= 15; month++)
            payment(month: month, amount: month == 15 ? 2000 : 2500),
        ],
      );

      expect(edits, hasLength(10));
      expect(edits.first.amount, 2600);
      expect(edits.last.amount, 1600);
    });

    test('a renamed plan renames the payments with it', () {
      final edits = recalc(
        terms(perPayment: 4000, paymentCount: 12, name: 'Aircon'),
        [payment(month: 6, amount: 4000)],
      );

      expect(edits.single.name, 'Aircon');
      expect(edits.single.amount, 4000);
    });

    test('money a removed payment was carrying goes back to where it came '
        'from', () {
      // August carried ₱500 forward into September, which the shortened
      // plan no longer reaches: August owes that ₱500 again.
      final edits = recalc(
        terms(perPayment: 4000, paymentCount: 2),
        [
          payment(month: 6, amount: 4000),
          payment(
            month: 7,
            amount: 4000,
            carriedInto: 'bill-2026-8-10',
          ),
          payment(month: 8, amount: 4500, carriedOver: 500),
        ],
      );

      final removed = edits.where((edit) => edit.removes).toList();
      expect(removed.single.instance.dueDate, DateTime(2026, 8, 10));

      final reopened = edits.singleWhere((edit) => !edit.removes);
      expect(reopened.instance.dueDate, DateTime(2026, 7, 10));
      expect(reopened.reopenCarry, isTrue);
      expect(reopened.amount, 4000);
    });

    test('a plan left exactly as it is changes nothing', () {
      final edits = recalc(
        terms(perPayment: 4000, paymentCount: 12),
        [for (var month = 6; month <= 17; month++) payment(month: month, amount: 4000)],
      );

      expect(edits, isEmpty);
    });

    test('payments from before the plan are left alone', () {
      // Dated before the plan's own first payment: not one of its dates, so
      // it stands as it is rather than being taken away.
      final edits = recalc(
        terms(perPayment: 3500, paymentCount: 12),
        [
          BillInstance(
            id: 'old',
            billId: 'bill',
            name: 'iPhone 15',
            amount: 4000,
            category: 'Bills',
            dueDate: DateTime(2026, 5, 10),
            status: BillStatus.unpaid,
          ),
        ],
      );

      expect(edits, isEmpty);
    });
  });
}
