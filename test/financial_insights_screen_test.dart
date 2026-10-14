import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:testapp/models/app_transaction.dart';
import 'package:testapp/models/finance_snapshot.dart';
import 'package:testapp/models/financial_insights.dart';
import 'package:testapp/providers/app_settings_provider.dart';
import 'package:testapp/screens/reports_screen.dart';
import 'package:testapp/services/financial_ai_service.dart';
import 'package:testapp/theme/app_theme.dart';

class _FakeFinancialAssistant implements FinancialAssistant {
  int insightRequests = 0;
  bool fail = false;

  @override
  Future<String> answerQuestion({
    required String question,
    required FinanceSnapshot? records,
    required List<FinancialChatTurn> history,
    String? verifiedGoalPlan,
  }) async => '';

  @override
  Future<List<String>> explainInsights(FinancialInsights insights) async {
    insightRequests++;
    if (fail) {
      throw const FinancialAssistantFailure('simulated Gemini failure');
    }
    return const [
      'Review optional recurring costs before changing essentials.',
    ];
  }
}

final _transactions = [
  AppTransaction(
    id: 'income',
    type: TransactionType.income,
    amount: 1000,
    label: 'Salary',
    date: DateTime(2026, 10, 1),
  ),
  AppTransaction(
    id: 'current',
    type: TransactionType.expense,
    amount: 200,
    label: 'Food',
    date: DateTime(2026, 10, 8),
  ),
  AppTransaction(
    id: 'previous',
    type: TransactionType.expense,
    amount: 300,
    label: 'Food',
    date: DateTime(2026, 9, 8),
  ),
];

Future<void> _pumpReports(
  WidgetTester tester, {
  required _FakeFinancialAssistant assistant,
}) async {
  tester.view.physicalSize = const Size(800, 3000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    ChangeNotifierProvider(
      create: (_) => AppSettingsProvider(),
      child: MaterialApp(
        theme: AppTheme.light,
        home: ReportsScreen(
          transactions: Stream.value(_transactions),
          contributions: Stream.value(const []),
          records: Stream.value(
            FinanceSnapshot(
              now: DateTime(2026, 10, 14),
              transactions: _transactions,
            ),
          ),
          today: DateTime(2026, 10, 14),
          assistant: assistant,
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pump();
}

void main() {
  testWidgets('shows verified metrics and unavailable budget/forecast states', (
    tester,
  ) async {
    await _pumpReports(tester, assistant: _FakeFinancialAssistant());

    expect(find.textContaining('Net cash flow this month'), findsOneWidget);
    expect(
      find.textContaining('Net cash-flow savings rate: 80.0%'),
      findsOneWidget,
    );
    expect(
      find.textContaining('Budget utilization: unavailable'),
      findsOneWidget,
    );
    expect(
      find.textContaining('Spending forecast unavailable'),
      findsOneWidget,
    );
  });

  testWidgets('requests personalized suggestions only when tapped', (
    tester,
  ) async {
    final assistant = _FakeFinancialAssistant();
    await _pumpReports(tester, assistant: assistant);

    expect(assistant.insightRequests, 0);
    await tester.tap(find.text('Get AI saving suggestions'));
    await tester.pump();
    await tester.pump();

    expect(assistant.insightRequests, 1);
    expect(
      find.textContaining('Review optional recurring costs'),
      findsOneWidget,
    );
  });

  testWidgets('surfaces suggestion failures without hiding verified metrics', (
    tester,
  ) async {
    final assistant = _FakeFinancialAssistant()..fail = true;
    await _pumpReports(tester, assistant: assistant);

    await tester.tap(find.text('Get AI saving suggestions'));
    await tester.pump();
    await tester.pump();

    expect(
      find.textContaining('Gemini suggestions are unavailable right now'),
      findsOneWidget,
    );
    expect(find.textContaining('Net cash flow this month'), findsOneWidget);
  });
}
