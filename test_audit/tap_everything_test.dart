// QA audit: opens every screen with made-up records and taps every control
// on it, one at a time, on a small phone in light and dark mode, then at a
// large text size. Anything that throws, overflows or asserts is collected
// and printed. Run with:
//   flutter test test_audit
// Kept out of test/: buttons that reach Firebase (Pay, upcoming months)
// cannot run here, and are listed, not failed.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:testapp/backend/models/allocation.dart';
import 'package:testapp/backend/models/app_transaction.dart';
import 'package:testapp/backend/models/bill.dart';
import 'package:testapp/backend/models/debt.dart';
import 'package:testapp/backend/models/finance_snapshot.dart';
import 'package:testapp/backend/models/goal.dart';
import 'package:testapp/backend/models/wallet.dart';
import 'package:testapp/frontend/providers/app_settings_provider.dart';
import 'package:testapp/frontend/screens/add_expense_screen.dart';
import 'package:testapp/frontend/screens/bill_calendar_screen.dart';
import 'package:testapp/frontend/screens/bill_detail_screen.dart';
import 'package:testapp/frontend/screens/categories_screen.dart';
import 'package:testapp/frontend/screens/debt_detail_screen.dart';
import 'package:testapp/frontend/screens/debts_screen.dart';
import 'package:testapp/frontend/screens/goal_detail_screen.dart';
import 'package:testapp/frontend/screens/goals_screen.dart';
import 'package:testapp/frontend/screens/help_screen.dart';
import 'package:testapp/frontend/screens/history_screen.dart';
import 'package:testapp/frontend/screens/home_screen.dart';
import 'package:testapp/frontend/screens/income_waterfall_screen.dart';
import 'package:testapp/frontend/screens/reminders_screen.dart';
import 'package:testapp/frontend/screens/reports_screen.dart';
import 'package:testapp/frontend/screens/set_aside_screen.dart';
import 'package:testapp/frontend/screens/transactions_screen.dart';
import 'package:testapp/frontend/screens/wallet_detail_screen.dart';
import 'package:testapp/frontend/screens/wallets_screen.dart';
import 'package:testapp/frontend/theme/app_theme.dart';
import 'package:testapp/frontend/widgets/safe_to_spend_card.dart';

final today = DateTime(2026, 11, 22, 10);

Wallet wallet(
  String id,
  String name,
  WalletType type,
  double balance, {
  WalletPurpose purpose = WalletPurpose.spending,
  String? savingsKind,
  DateTime? maturityDate,
  double? rate,
}) => Wallet(
  id: id,
  name: name,
  type: type,
  balance: balance,
  startingBalance: balance,
  receivesIncome: id == 'cash',
  archived: false,
  sortOrder: 0,
  purpose: purpose,
  savingsKind: savingsKind,
  maturityDate: maturityDate,
  annualInterestRatePercent: rate,
);

/// True for a brand-new user: no records at all.
var empty = false;

List<Wallet> get wallets => empty ? const [] : _wallets;
final _wallets = [
  wallet('cash', 'Cash', WalletType.cash, 20665),
  wallet('cash2', 'Cash 2', WalletType.cash, 5000),
  wallet('maya', 'Maya', WalletType.maya, 10000, rate: 3),
  wallet('gotyme', 'GoTyme Bank', WalletType.bank, 3000, rate: 4),
  wallet(
    'sd',
    'Savings Deposit',
    WalletType.other,
    15000,
    purpose: WalletPurpose.savings,
    savingsKind: SavingsKind.savingsDeposit.name,
    rate: 2,
  ),
  wallet(
    'td',
    'Time Deposit',
    WalletType.other,
    10000,
    purpose: WalletPurpose.savings,
    savingsKind: SavingsKind.timeDeposit.name,
    maturityDate: DateTime(2027, 4, 25),
    rate: 5,
  ),
];

List<Goal> get goals => empty ? const [] : _goals;
final _goals = [
  Goal(
    id: 'laptop',
    name: 'Laptop',
    targetAmount: 25000,
    savedAmount: 3000,
    priority: 0,
    status: GoalStatus.active,
    savedByWallet: const {'cash': 2500, 'gotyme': 500},
    targetDate: DateTime(2027, 6, 1),
    planStartedAt: DateTime(2026, 10, 1),
  ),
  const Goal(
    id: 'phone',
    name: 'Phone',
    targetAmount: 5000,
    savedAmount: 5000,
    priority: 1,
    status: GoalStatus.completed,
    savedByWallet: {'maya': 5000},
  ),
];

AppTransaction tx(
  String id,
  TransactionType type,
  double amount,
  String label, {
  String? walletId = 'cash',
  String? toWalletId,
  String? note,
  String? bill,
  String? goalId,
  int daysAgo = 0,
}) => AppTransaction(
  id: id,
  type: type,
  amount: amount,
  label: label,
  date: today.subtract(Duration(days: daysAgo, hours: 1)),
  walletId: walletId,
  toWalletId: toWalletId,
  note: note,
  billInstanceId: bill,
  goalId: goalId,
);

List<AppTransaction> get transactions => empty ? const [] : _transactions;
final _transactions = [
  tx('e1', TransactionType.expense, 450, 'Food', note: 'Lunch'),
  tx('e2', TransactionType.expense, 1200, 'Groceries', daysAgo: 2),
  tx('i1', TransactionType.income, 15000, 'Salary', daysAgo: 5),
  tx('t1', TransactionType.transfer, 500, 'Transfer', toWalletId: 'maya'),
  tx(
    'g1',
    TransactionType.goal,
    500,
    goalDepositLabel,
    note: 'Laptop',
    goalId: 'laptop',
  ),
  tx(
    'g2',
    TransactionType.goal,
    200,
    goalWithdrawalLabel,
    walletId: 'gotyme',
    note: 'Laptop',
    goalId: 'laptop',
  ),
  tx('b1', TransactionType.expense, 1500, 'Utilities', bill: 'rent_2026-11'),
];

BillInstance instance(
  String id,
  String name,
  double amount,
  DateTime due, {
  BillStatus status = BillStatus.unpaid,
  double paid = 0,
  String? debtId,
}) => BillInstance(
  id: id,
  billId: id.split('_').first,
  name: name,
  amount: amount,
  category: 'Utilities',
  dueDate: due,
  status: status,
  amountPaid: paid,
  debtId: debtId,
);

List<BillInstance> get instances => empty ? const [] : _instances;
final _instances = [
  instance('rent_2026-11', 'Rent', 8000, DateTime(2026, 11, 25)),
  instance('net_2026-11', 'Internet', 1599, DateTime(2026, 11, 18)),
  instance(
    'water_2026-11',
    'Water',
    600,
    DateTime(2026, 11, 22),
    status: BillStatus.partial,
    paid: 200,
  ),
  instance(
    'phone_2026-11',
    'Phone installment',
    2400,
    DateTime(2026, 11, 30),
    debtId: 'phone',
  ),
];

List<Bill> get bills => empty ? const [] : _bills;
final _bills = [
  Bill(
    id: 'rent',
    name: 'Rent',
    amount: 8000,
    category: 'Utilities',
    firstDueDate: DateTime(2026, 1, 25),
    recurrence: BillRecurrence.monthly,
  ),
  Bill(
    id: 'net',
    name: 'Internet',
    amount: 1599,
    category: 'Utilities',
    firstDueDate: DateTime(2026, 1, 18),
    recurrence: BillRecurrence.monthly,
  ),
];

final installment = Debt(
  id: 'phone',
  direction: DebtDirection.iOwe,
  name: 'Phone',
  category: DebtCategory.gadget,
  principal: 24000,
  perPayment: 2400,
  paymentCount: 10,
  firstDueDate: DateTime(2026, 6, 30),
  billId: 'phone',
  status: DebtStatus.active,
);

final loan = Debt(
  id: 'loan',
  direction: DebtDirection.iOwe,
  name: 'Cash2Go',
  category: DebtCategory.personalLoan,
  principal: 5000,
  perPayment: 1716.67,
  paymentCount: 3,
  firstDueDate: DateTime(2026, 11, 30),
  billId: 'loan',
  status: DebtStatus.active,
  quotedRate: 1,
);

List<AllocationCycle> get cycles => empty ? const [] : _cycles;
final _cycles = [
  AllocationCycle(
    id: 'c1',
    income: 15000,
    remaining: 6000,
    receivedAt: today.subtract(const Duration(days: 5)),
    source: 'Salary',
    walletId: 'cash',
    toBills: 9000,
  ),
];

final profile = <String, dynamic>{
  'fullName': 'Test User',
  'priorities': ['payBills', 'saveForGoal', 'trackSpending'],
  'reminders': {'enabled': true},
};

FinanceSnapshot get snapshot => FinanceSnapshot(
  now: today,
  wallets: wallets,
  transactions: transactions,
  bills: instances,
  goals: goals,
  debts: [installment, loan],
);

Stream<T> live<T>(T value) => Stream<T>.value(value).asBroadcastStream();

/// Every screen, built fresh each time with the made-up records.
final screens = <String, Widget Function()>{
  'Home': () => HomeScreen(
    userName: 'Dave',
    wallets: live(wallets),
    goals: live(goals),
    transactions: live(transactions),
    profile: live(profile),
    today: today,
    onOpenTransactions: () {},
    onOpenWallets: () {},
    onOpenBills: () {},
    onOpenSavings: () {},
    onOpenGoals: () {},
    onOpenDebts: () {},
    onOpenReports: () {},
    safeToSpend: SafeToSpendCard(
      wallets: live(wallets),
      transactions: live(transactions),
      goals: live(goals),
      billSchedules: live(bills),
      loadBills: () async => instances,
      loadDebts: () async => [installment, loan],
      today: today,
    ),
  ),
  'Wallets': () => WalletsScreen(wallets: live(wallets), goals: live(goals)),
  'Wallet detail': () => WalletDetailScreen(
    wallet: _wallets.first,
    wallets: live(wallets),
    transactions: live(transactions),
    goals: live(goals),
  ),
  'Transactions': () => TransactionsScreen(
    transactions: live(transactions),
    wallets: live(wallets),
    showLegacyImport: false,
  ),
  'Add Expense': () => AddExpenseScreen(
    wallets: live(wallets),
    goals: live(goals),
    transactions: live(transactions),
    loadBills: () async => instances,
  ),
  'Add Income': () => IncomeWaterfallScreen(
    wallets: live(wallets),
    goals: live(goals),
    loadBills: () async => instances,
    cycles: live(cycles),
    today: today,
  ),
  'Goals': () => GoalsScreen(
    goals: live(goals),
    wallets: live(wallets),
    onReorder: (_) {},
    onOpen: (_) {},
  ),
  'Goal detail': () => GoalDetailScreen(
    goal: _goals.first,
    liveGoal: live<Goal?>(_goals.first),
    contributions: live([
      GoalContribution(id: 'c1', amount: 2500, date: today, walletId: 'cash'),
    ]),
    wallets: live(wallets),
    today: today,
  ),
  'Bill Planner': () => BillCalendarScreen(
    bills: live(bills),
    instancesFor: (_, _) => live(instances),
    today: today,
    wallets: live(wallets),
    goals: live(goals),
  ),
  'Bill detail': () => BillDetailScreen(
    instance: _instances.first,
    liveInstance: live<BillInstance?>(_instances.first),
    history: live(instances.take(1).toList()),
    bills: live(bills),
    wallets: live(wallets),
    loadPayments: (_) async => const [],
    today: today,
  ),
  'Installments': () => Scaffold(
    body: InstallmentsView(
      debts: live([installment]),
      paymentsFor: (_) => live([_instances.last]),
      onOpen: (_) {},
    ),
  ),
  'Debts': () => Scaffold(
    body: DebtsView(
      debts: live([loan]),
      paymentsFor: (_) => live(const <BillInstance>[]),
      onOpen: (_) {},
    ),
  ),
  'Installment detail': () => InstallmentDetailScreen(
    debt: installment,
    liveDebt: live<Debt?>(installment),
    payments: live([_instances.last]),
    wallets: live(wallets),
    interestCharges: live(const []),
    today: today,
  ),
  'Debt detail': () => LoanDetailScreen(
    debt: loan,
    liveDebt: live<Debt?>(loan),
    payments: live(const <BillInstance>[]),
    wallets: live(wallets),
    interestCharges: live(const []),
    today: today,
  ),
  'Savings': () => SetAsideScreen(
    wallets: live(wallets),
    transactions: live(transactions),
    goals: live(goals),
    today: today,
  ),
  'Reports': () => ReportsScreen(
    transactions: live(transactions),
    contributions: live(const []),
    records: live(snapshot),
    today: today,
    onOpenCategory: (_) {},
  ),
  'Cash Inflows': () => HistoryScreen(
    cycles: live(cycles),
    transactions: live(transactions),
    profile: live(profile),
    wallets: live(wallets),
  ),
  'Reminders': () => RemindersScreen(
    profile: live(profile),
    requestPermission: () async => true,
    sendTest: () async => true,
    onSetEnabled: (_) {},
    onSetKind: (_, _) {},
    onSetPriorities: (_) {},
  ),
  'Categories': () =>
      CategoriesScreen(profile: live(<String, dynamic>{}), onSave: (_) {}),
  'Help': () => const HelpScreen(),
};

/// Everything a person can tap.
Finder tappables() => find.byWidgetPredicate(
  (w) =>
      (w is ButtonStyleButton && w.onPressed != null) ||
      (w is IconButton && w.onPressed != null) ||
      (w is InkWell && w.onTap != null) ||
      (w is ListTile && w.onTap != null) ||
      (w is Switch && w.onChanged != null) ||
      (w is Checkbox && w.onChanged != null) ||
      (w is PopupMenuButton) ||
      (w is GestureDetector && w.onTap != null),
);

String describe(Element element) {
  final widget = element.widget;
  final texts = <String>[];
  element.visitChildElements((child) => _collectText(child, texts));
  final tooltip = widget is IconButton ? widget.tooltip : null;
  final label = tooltip ?? (texts.isEmpty ? '' : texts.first);
  return '${widget.runtimeType}${label.isEmpty ? '' : ' "$label"'}';
}

void _collectText(Element element, List<String> texts) {
  if (texts.length > 2) return;
  final w = element.widget;
  if (w is Text && (w.data ?? '').trim().isNotEmpty) {
    texts.add(w.data!.trim().replaceAll('\n', ' '));
  }
  element.visitChildElements((child) => _collectText(child, texts));
}

/// Firebase is not running in tests; a tap that opens a screen without
/// made-up records behind it reaches for it. Those are not app bugs.
bool needsFirebase(Object error) {
  final text = '$error';
  return text.contains('Firebase') ||
      text.contains('no-app') ||
      text.contains('FirebaseApp');
}

void main() {
  final findings = <String>[];
  final skipped = <String>{};

  Future<void> show(
    WidgetTester tester,
    Widget Function() build, {
    required bool dark,
    double textScale = 1,
  }) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpWidget(
      ChangeNotifierProvider(
        create: (_) => AppSettingsProvider(),
        child: MaterialApp(
          theme: dark ? AppTheme.dark : AppTheme.light,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(textScale)),
            child: child!,
          ),
          home: build(),
        ),
      ),
    );
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  // The app's own lines behind each error since the last record, from the
  // full report, which the error itself leaves out.
  final sources = <String>{};

  void record(String where, Object? error) {
    final at = sources.join(', ');
    sources.clear();
    if (error == null) return;
    if (needsFirebase(error)) {
      skipped.add(where);
      return;
    }
    final first = '$error'.split('\n').where((l) => l.trim().isNotEmpty);
    findings.add('$where  [$at]\n    ${first.take(2).join('\n    ')}');
  }

  for (final newUser in [false, true]) {
    for (final entry in screens.entries) {
      final name = newUser ? '${entry.key} [new user]' : entry.key;
      testWidgets('tap everything: $name', (tester) async {
        empty = newUser;
        // A small phone: 360 x 690.
        tester.view.physicalSize = const Size(720, 1380);
        tester.view.devicePixelRatio = 2;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final original = FlutterError.onError;
        FlutterError.onError = (details) {
          sources.addAll(
            RegExp(
              r'lib/frontend/[a-z_/]+\.dart:\d+',
            ).allMatches(details.toString()).map((m) => m[0]!).take(2),
          );
          original?.call(details);
        };

        for (final dark in [false, true]) {
          final mode = dark ? 'dark' : 'light';
          await show(tester, entry.value, dark: dark);
          record('$name ($mode): opening', tester.takeException());
          final count = tappables().evaluate().length;

          for (var i = 0; i < count; i++) {
            await show(tester, entry.value, dark: dark);
            tester.takeException();
            final targets = tappables().evaluate().toList();
            if (i >= targets.length) break;
            final element = targets[i];
            final what = describe(element);
            final target = find.byElementPredicate((e) => e == element);
            try {
              await tester.ensureVisible(target);
              await tester.pump();
              await tester.tap(target, warnIfMissed: false);
              for (var f = 0; f < 6; f++) {
                await tester.pump(const Duration(milliseconds: 100));
              }
            } catch (error) {
              record('$name ($mode): tap $what', error);
            }
            record('$name ($mode): tap $what', tester.takeException());
          }
        }

        // Large text, as many phones are set: does anything overflow?
        await show(tester, entry.value, dark: false, textScale: 1.3);
        record('$name (text 130%): opening', tester.takeException());

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump(const Duration(minutes: 1));
        FlutterError.onError = original;
      });
    }
  }

  tearDownAll(() {
    // ignore: avoid_print
    print(
      '\n===== AUDIT: ${findings.length} findings =====\n'
      '${findings.toSet().join('\n')}\n'
      '===== needs Firebase (not covered here): ${skipped.length} =====\n'
      '${skipped.take(40).join('\n')}',
    );
  });
}
