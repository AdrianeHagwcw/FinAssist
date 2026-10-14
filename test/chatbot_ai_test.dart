import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:testapp/models/chat_action.dart';
import 'package:testapp/models/finance_snapshot.dart';
import 'package:testapp/models/financial_topic_validator.dart';
import 'package:testapp/models/wallet.dart';
import 'package:testapp/screens/chatbot_screen.dart';
import 'package:testapp/services/financial_ai_service.dart';
import 'package:testapp/theme/app_theme.dart';

class _FakeFinancialAssistant implements FinancialAssistant {
  int questionsAsked = 0;
  String? receivedVerifiedGoalPlan;
  List<FinancialChatTurn>? receivedHistory;
  Completer<String>? pendingAnswer;
  bool fail = false;

  @override
  Future<String> answerQuestion({
    required String question,
    required FinanceSnapshot? records,
    required List<FinancialChatTurn> history,
    String? verifiedGoalPlan,
  }) async {
    questionsAsked++;
    receivedVerifiedGoalPlan = verifiedGoalPlan;
    receivedHistory = history;
    if (fail) {
      throw const FinancialAssistantFailure('simulated Gemini failure');
    }
    final pending = pendingAnswer;
    if (pending != null) return pending.future;
    return 'Compound interest can help savings grow over time.';
  }

  @override
  Future<List<String>> explainInsights(_) async => const [];
}

Future<void> _pumpChat(
  WidgetTester tester, {
  required _FakeFinancialAssistant assistant,
  bool isOnline = true,
  Future<bool> Function(ChatAction action)? onAction,
  FinanceSnapshot? records,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light,
      home: ChatbotScreen(
        assistant: assistant,
        onAction: onAction,
        onlineStatus: Stream.value(isOnline),
        records: Stream.value(
          records ?? FinanceSnapshot(now: DateTime(2026, 10, 14)),
        ),
      ),
    ),
  );
  await tester.pump();
}

Future<void> _ask(WidgetTester tester, String question) async {
  await tester.enterText(find.byType(TextField), question);
  await tester.testTextInput.receiveAction(TextInputAction.send);
  await tester.pump();
}

void main() {
  testWidgets('rejects unrelated questions without calling Gemini', (
    tester,
  ) async {
    final assistant = _FakeFinancialAssistant();
    await _pumpChat(tester, assistant: assistant);

    await _ask(tester, 'What is the weather tomorrow?');

    expect(assistant.questionsAsked, 0);
    expect(
      find.textContaining('I can only help with money questions'),
      findsOneWidget,
    );
  });

  testWidgets('sends an in-scope question and displays the Gemini reply', (
    tester,
  ) async {
    final assistant = _FakeFinancialAssistant();
    await _pumpChat(tester, assistant: assistant);

    await _ask(tester, 'How do I save more?');

    expect(assistant.questionsAsked, 1);
    expect(
      find.textContaining('Compound interest can help savings grow'),
      findsOneWidget,
    );
    expect(
      find.textContaining('Start by recording every expense'),
      findsNothing,
    );
  });

  testWidgets('prepares transfers locally and opens review only when tapped', (
    tester,
  ) async {
    final assistant = _FakeFinancialAssistant();
    var actionsOpened = 0;
    await _pumpChat(
      tester,
      assistant: assistant,
      onAction: (action) async {
        expect(action.type, ChatActionType.transfer);
        expect(action.amount, 500);
        actionsOpened++;
        return false;
      },
    );

    await _ask(tester, 'Transfer ₱500 from salary to savings');

    expect(assistant.questionsAsked, 0);
    expect(actionsOpened, 0);
    expect(find.text('Review transfer'), findsOneWidget);

    await tester.tap(find.text('Review transfer'));
    await tester.pump();

    expect(actionsOpened, 1);
    expect(find.text('Transfer saved.'), findsNothing);
  });

  testWidgets(
    'clarifies missing expense details instead of reporting spending',
    (tester) async {
      final assistant = _FakeFinancialAssistant();
      ChatAction? proposedAction;
      await _pumpChat(
        tester,
        assistant: assistant,
        onAction: (action) async {
          proposedAction = action;
          return false;
        },
      );

      await _ask(tester, 'I want to add 500 in the expenses');

      expect(assistant.questionsAsked, 0);
      expect(proposedAction, isNull);
      expect(find.text('Complete expense details'), findsOneWidget);
      expect(find.textContaining('What was it for?'), findsOneWidget);
      expect(find.textContaining('wallet to deduct it from'), findsOneWidget);
      expect(find.textContaining("You've spent"), findsNothing);

      await tester.tap(find.text('Complete expense details'));
      await tester.pump();

      expect(proposedAction?.type, ChatActionType.expense);
      expect(proposedAction?.amount, 500);
      expect(proposedAction?.description, isNull);
    },
  );

  testWidgets('routes salary income into the requested wallet', (tester) async {
    final assistant = _FakeFinancialAssistant();
    ChatAction? proposedAction;
    await _pumpChat(
      tester,
      assistant: assistant,
      records: FinanceSnapshot(
        now: DateTime(2026, 10, 14),
        wallets: [
          Wallet(
            id: 'eastwest',
            name: 'EastWest Bank',
            type: WalletType.bank,
            balance: 1000,
            startingBalance: 1000,
            receivesIncome: false,
            archived: false,
            sortOrder: 0,
          ),
        ],
      ),
      onAction: (action) async {
        proposedAction = action;
        return false;
      },
    );

    await _ask(tester, 'Add 500 into salary in Eastbank wallet');

    expect(proposedAction, isNull);
    expect(assistant.questionsAsked, 0);
    expect(find.text('Review income'), findsOneWidget);

    await tester.tap(find.text('Review income'));
    await tester.pump();

    expect(proposedAction?.type, ChatActionType.income);
    expect(proposedAction?.amount, 500);
    expect(proposedAction?.initialSource, 'Salary');
    expect(proposedAction?.incomeWalletId, 'eastwest');
  });

  testWidgets('combines Gemini advice with a verified purchase savings plan', (
    tester,
  ) async {
    final assistant = _FakeFinancialAssistant();
    await _pumpChat(tester, assistant: assistant);

    await _ask(
      tester,
      'I want to buy a house worth 4999999 in the next 2 years '
      'how should i save my money?',
    );

    expect(assistant.questionsAsked, 1);
    expect(
      find.textContaining('Compound interest can help savings grow'),
      findsOneWidget,
    );
    expect(
      find.textContaining('₱208,333.30 per month for 24 months'),
      findsOneWidget,
    );
    expect(find.textContaining('Compare the target'), findsOneWidget);
  });

  testWidgets('routes a Taglish house-saving question to Gemini', (
    tester,
  ) async {
    final assistant = _FakeFinancialAssistant();
    await _pumpChat(tester, assistant: assistant);
    const question =
        'gusto kong bumili ng bahay worth 5000000 in the next 2 years '
        'magkano ang dapat kong I save everyday para makabili ng bahay?';

    expect(isFinancialTopic(question), isTrue);
    await _ask(tester, question);

    expect(assistant.questionsAsked, 1);
    expect(assistant.receivedVerifiedGoalPlan, contains('₱6,839.95 araw-araw'));
    expect(find.textContaining('₱6,839.95 araw-araw'), findsOneWidget);
  });

  testWidgets('routes a Taglish multi-purchase affordability follow-up', (
    tester,
  ) async {
    final assistant = _FakeFinancialAssistant();
    await _pumpChat(tester, assistant: assistant);

    await _ask(
      tester,
      'gusto kong bumili ng bahay worth 5000000 in the next 2 years '
      'magkano ang dapat kong I save everyday para makabili ng bahay?',
    );
    const followUp =
        'pero gusto ko ring bumili ng cellphones, computers and etx sa '
        'tingin mo ba kaya kong mabili lahat ng bagay na to in the next 5 years';

    expect(isFinancialTopic(followUp), isTrue);
    await _ask(tester, followUp);

    expect(assistant.questionsAsked, 2);
    expect(
      assistant.receivedHistory!.any(
        (turn) => turn.isUser && turn.text.contains('bumili ng bahay worth'),
      ),
      isTrue,
    );
    expect(
      find.textContaining('I can only help with money questions'),
      findsNothing,
    );
  });

  testWidgets('uses the verified purchase savings plan while offline', (
    tester,
  ) async {
    final assistant = _FakeFinancialAssistant();
    await _pumpChat(tester, assistant: assistant, isOnline: false);

    await _ask(
      tester,
      'I want to buy a house worth 4999999 in the next 2 years '
      'how should i save my money?',
    );

    expect(assistant.questionsAsked, 0);
    expect(
      find.textContaining('₱208,333.30 per month for 24 months'),
      findsOneWidget,
    );
    expect(find.textContaining('Compare the target'), findsOneWidget);
  });

  testWidgets('uses rule-based answers when offline', (tester) async {
    final assistant = _FakeFinancialAssistant();
    await _pumpChat(tester, assistant: assistant, isOnline: false);

    await _ask(tester, 'How do I save more?');

    expect(assistant.questionsAsked, 0);
    expect(
      find.textContaining('Start by recording every expense'),
      findsOneWidget,
    );
  });

  testWidgets('falls back to rule-based answers when Gemini fails', (
    tester,
  ) async {
    final assistant = _FakeFinancialAssistant()
      ..pendingAnswer = Completer<String>()
      ..fail = false;
    await _pumpChat(tester, assistant: assistant);

    await _ask(tester, 'How do I save more?');
    expect(find.text('Fin is thinking…'), findsOneWidget);
    assistant.pendingAnswer!.completeError(
      const FinancialAssistantFailure('simulated Gemini failure'),
    );
    await tester.pump();

    expect(
      find.textContaining('Start by recording every expense'),
      findsOneWidget,
    );
    expect(
      find.textContaining('I could not get a Gemini response just now'),
      findsNothing,
    );
  });

  testWidgets('validates an empty question', (tester) async {
    final assistant = _FakeFinancialAssistant();
    await _pumpChat(tester, assistant: assistant);

    await tester.tap(find.byTooltip('Send message'));
    await tester.pump();

    expect(find.text('Type a financial question first.'), findsOneWidget);
    expect(assistant.questionsAsked, 0);
  });
}
