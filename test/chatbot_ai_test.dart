import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:testapp/backend/models/chat_action.dart';
import 'package:testapp/backend/models/chat_answers.dart';
import 'package:testapp/backend/models/chat_language.dart';
import 'package:testapp/backend/models/finance_snapshot.dart';
import 'package:testapp/backend/models/financial_topic_validator.dart';
import 'package:testapp/backend/models/wallet.dart';
import 'package:testapp/frontend/screens/chatbot_screen.dart';
import 'package:testapp/backend/services/financial_ai_service.dart';
import 'package:testapp/frontend/theme/app_theme.dart';

class _FakeFinancialAssistant implements FinancialAssistant {
  int questionsAsked = 0;
  String? receivedVerifiedGoalPlan;
  List<FinancialChatTurn>? receivedHistory;
  Completer<String>? pendingAnswer;
  bool fail = false;
  ChatLanguage? receivedLanguage;
  final translated = <String>[];
  int productPriceRequests = 0;
  String? requestedProduct;
  String response = 'Compound interest can help savings grow over time.';
  List<String> insightsResponse = const [
    'Protect essential expenses before choosing an optional savings contribution.',
  ];

  @override
  Future<String> answerQuestion({
    required String question,
    required FinanceSnapshot? records,
    required List<FinancialChatTurn> history,
    String? verifiedGoalPlan,
    ChatLanguage? responseLanguage,
  }) async {
    questionsAsked++;
    receivedLanguage = responseLanguage;
    receivedVerifiedGoalPlan = verifiedGoalPlan;
    receivedHistory = history;
    if (fail) {
      throw const FinancialAssistantFailure('simulated Gemini failure');
    }
    final pending = pendingAnswer;
    if (pending != null) return pending.future;
    return response;
  }

  @override
  Future<String> translateReply(
    String text, {
    required ChatLanguage language,
  }) async {
    translated.add(text);
    return 'Sa ${language.label}: $text';
  }

  @override
  Future<List<String>> explainInsights(
    _, {
    ChatLanguage? responseLanguage,
  }) async => insightsResponse;

  @override
  Future<GroundedProductPriceAnswer> lookupProductPrices({
    required String product,
    ChatLanguage? responseLanguage,
  }) async {
    productPriceRequests++;
    requestedProduct = product;
    return GroundedProductPriceAnswer(
      text: 'AirPods Pro listings show prices from ₱9,990.',
      sources: const [
        GroundedPriceSource(
          title: 'Apple Philippines',
          url: 'https://www.apple.com/ph/',
        ),
      ],
      searchSuggestionsHtml: '',
    );
  }
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
  for (final question in [
    'How much can I spend today?',
    'May bills ba ako this week?',
    'What is my wallet balance?',
    'Safe to Spend formula',
    'How much income have I recorded?',
  ]) {
    testWidgets('preserves the app answer: $question', (tester) async {
      final assistant = _FakeFinancialAssistant()
        ..response = 'You can afford anything with 999999 pesos.';
      await _pumpChat(tester, assistant: assistant);
      await _ask(tester, question);
      expect(assistant.questionsAsked, 0);
      expect(find.textContaining('999999'), findsNothing);
    });
  }

  testWidgets(
    'understands short follow-ups but does not inherit unrelated topics',
    (tester) async {
      final assistant = _FakeFinancialAssistant();
      await _pumpChat(tester, assistant: assistant);
      await _ask(tester, 'How do I save more?');
      await _ask(tester, 'Bakit?');
      expect(assistant.questionsAsked, 2);
      expect(
        assistant.receivedHistory!.any(
          (turn) => turn.text == 'How do I save more?',
        ),
        isTrue,
      );
      await _ask(tester, 'What is the weather tomorrow?');
      await _ask(tester, 'Why?');
      expect(assistant.questionsAsked, 2);
    },
  );

  testWidgets('rejects invented amounts and keeps the verified goal plan', (
    tester,
  ) async {
    final assistant = _FakeFinancialAssistant()
      ..response = 'Save 999999 pesos per day. You can afford it.';
    await _pumpChat(tester, assistant: assistant);
    await _ask(
      tester,
      'I want to buy a house worth 4999999 in the next 2 years how should i save my money?',
    );
    expect(assistant.questionsAsked, 1);
    expect(find.textContaining('Save 999999'), findsNothing);
    expect(
      find.textContaining('₱208,333.30 per month for 24 months'),
      findsOneWidget,
    );
    expect(find.textContaining('AI is unavailable right now'), findsOneWidget);
  });

  testWidgets(
    'times out and ignores late replies while allowing another question',
    (tester) async {
      final assistant = _FakeFinancialAssistant()
        ..pendingAnswer = Completer<String>();
      await _pumpChat(tester, assistant: assistant);
      await _ask(tester, 'How do I save more?');
      await tester.pump(financialAssistantTimeout + const Duration(seconds: 1));
      await tester.pump();
      expect(
        find.textContaining('AI is unavailable right now'),
        findsOneWidget,
      );
      expect(tester.widget<TextField>(find.byType(TextField)).enabled, isTrue);
      assistant.pendingAnswer!.complete(
        'A late answer that should not appear.',
      );
      await tester.pump();
      expect(find.textContaining('A late answer'), findsNothing);
      await _ask(tester, 'Safe to Spend formula');
      expect(assistant.questionsAsked, 1);
      await tester.pump(const Duration(seconds: 1));
    },
  );

  testWidgets('clearing conversation discards the pending AI response', (
    tester,
  ) async {
    final assistant = _FakeFinancialAssistant()
      ..pendingAnswer = Completer<String>();
    await _pumpChat(tester, assistant: assistant);
    await _ask(tester, 'How do I save more?');
    await tester.tap(find.byIcon(Icons.more_vert));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Clear conversation'));
    await tester.pumpAndSettle();
    // It asks first; Cancel keeps the chat.
    expect(find.text('Clear this conversation?'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    // The reply's quick replies can push the question above the screen.
    expect(
      find.text('How do I save more?', skipOffstage: false),
      findsOneWidget,
    );
    await tester.tap(find.byIcon(Icons.more_vert));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Clear conversation'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ElevatedButton, 'Clear'));
    await tester.pumpAndSettle();
    expect(find.text('How do I save more?'), findsNothing);
    expect(
      find.text("Hello! I'm Fin. How can I help you with your finances today?"),
      findsOneWidget,
    );
    assistant.pendingAnswer!.complete('Old conversation answer.');
    await tester.pump();
    expect(find.text('Old conversation answer.'), findsNothing);
    expect(tester.widget<TextField>(find.byType(TextField)).enabled, isTrue);
  });

  testWidgets('the menu floats under the dots; About explains Fin', (
    tester,
  ) async {
    await _pumpChat(tester, assistant: _FakeFinancialAssistant());

    await tester.tap(find.byIcon(Icons.more_vert));
    await tester.pumpAndSettle();
    // A floating menu, not a sheet from the bottom.
    expect(find.byType(BottomSheet), findsNothing);
    expect(find.text('About Fin'), findsOneWidget);
    // Nothing asked yet, so there is nothing to clear.
    final clear = tester.widget<PopupMenuItem<Object?>>(
      find.ancestor(
        of: find.text('Clear conversation'),
        matching: find.byWidgetPredicate((w) => w is PopupMenuItem),
      ),
    );
    expect(clear.enabled, isFalse);

    await tester.tap(find.text('About Fin'));
    await tester.pumpAndSettle();
    expect(
      find.textContaining("Fin is FinAssist's money helper"),
      findsOneWidget,
    );
    expect(
      find.text(
        'Answers are based on what you record, so keep your records '
        'complete and up to date.',
      ),
      findsOneWidget,
    );
    expect(find.textContaining('can be wrong'), findsNothing);
    // The app's own icons: records, the privacy shield, recording.
    for (final asset in [
      'icons8-transactions-96.png',
      'icons8-shield-96.png',
      'icons8-expenses-64.png',
    ]) {
      expect(
        find.image(AssetImage('assets/icons/$asset')),
        findsOneWidget,
        reason: asset,
      );
    }
    expect(find.text('Open-source licenses'), findsOneWidget);
    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();
    expect(
      find.textContaining("Fin is FinAssist's money helper"),
      findsNothing,
    );
  });

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
    // Gemini can't give amounts, so the app's own tips stay under it.
    expect(
      find.textContaining('Start by recording every expense'),
      findsOneWidget,
    );
  });

  testWidgets('keeps deterministic spending comparisons out of Gemini', (
    tester,
  ) async {
    final assistant = _FakeFinancialAssistant();
    await _pumpChat(tester, assistant: assistant);

    await _ask(tester, 'Compare my spending this month with last month.');

    expect(assistant.questionsAsked, 0);
    expect(find.textContaining('Missing records'), findsOneWidget);
  });

  testWidgets('looks up product prices and displays grounded sources', (
    tester,
  ) async {
    final assistant = _FakeFinancialAssistant();
    await _pumpChat(tester, assistant: assistant);

    await _ask(tester, 'How much are AirPods?');

    expect(assistant.productPriceRequests, 1);
    expect(assistant.requestedProduct, 'AirPods');
    expect(assistant.questionsAsked, 0);
    expect(find.textContaining('₱9,990'), findsOneWidget);
    expect(find.text('Apple Philippines'), findsOneWidget);
    expect(
      find.textContaining(
        'Prices checked today. Seller prices and stock can change.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('sends a Taglish financial-insights request to Gemini', (
    tester,
  ) async {
    final assistant = _FakeFinancialAssistant()
      ..response = 'Oo, susuriin ko ang mga naitala mong gastos.';
    await _pumpChat(tester, assistant: assistant);

    await _ask(
      tester,
      'kaya mo ba akong bigyan ng maayos na insights sa susunod',
    );

    expect(assistant.questionsAsked, 1);
    expect(find.textContaining('susuriin ko'), findsOneWidget);
    expect(
      find.textContaining('I can only help with money questions'),
      findsNothing,
    );
  });

  testWidgets('uses the Reports savings suggestions path in chat', (
    tester,
  ) async {
    final assistant = _FakeFinancialAssistant()
      ..insightsResponse = const [
        'Protect essential expenses before choosing an optional savings contribution.',
      ];
    await _pumpChat(tester, assistant: assistant);

    expect(
      isSavingsSuggestionsQuestion('Can you give me AI savings suggestions?'),
      isTrue,
    );
    await _ask(tester, 'Can you give me AI savings suggestions?');
    await tester.pump();

    expect(find.textContaining('Protect essential expenses'), findsOneWidget);
    expect(assistant.questionsAsked, 0);
  });

  testWidgets(
    'categorizes each multi-expense input instead of opening one form',
    (tester) async {
      final assistant = _FakeFinancialAssistant();
      var openedAction = false;
      await _pumpChat(
        tester,
        assistant: assistant,
        onAction: (_) async {
          openedAction = true;
          return false;
        },
      );

      await _ask(
        tester,
        'I spent ₱150 on lunch, ₱50 on jeepney fare, and ₱200 on mobile data. '
        'Categorize these expenses.',
      );
      await tester.pump();

      expect(openedAction, isFalse);
      expect(find.textContaining('₱150 — lunch: Food'), findsOneWidget);
      expect(
        find.textContaining('₱50 — jeepney fare: Transportation'),
        findsOneWidget,
      );
      expect(
        find.byWidgetPredicate(
          (widget) =>
              widget is Text &&
              widget.data?.contains('mobile data: Bills') == true,
        ),
        findsOneWidget,
      );
      expect(find.text('Complete expense details'), findsNothing);
      expect(assistant.questionsAsked, 0);
    },
  );

  testWidgets('answers an insights capability request locally when offline', (
    tester,
  ) async {
    final assistant = _FakeFinancialAssistant();
    await _pumpChat(tester, assistant: assistant, isOnline: false);

    await _ask(
      tester,
      'kaya mo ba akong bigyan ng maayos na insights sa susunod',
    );

    expect(assistant.questionsAsked, 0);
    // Taglish: English first, then Tagalog from the bubble's button.
    expect(
      find.textContaining('help explain your recorded spending'),
      findsOneWidget,
    );
    await tester.ensureVisible(find.text('Translate into Tagalog'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Translate into Tagalog'));
    await tester.pumpAndSettle();
    expect(find.textContaining('rekord na nasa FinAssist'), findsOneWidget);
    expect(
      find.textContaining('I can only help with money questions'),
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

    await tester.ensureVisible(find.text('Review income'));
    await tester.pump();
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
    // Taglish is answered in English first.
    expect(assistant.receivedVerifiedGoalPlan, contains('₱6,839.95 per day'));
    expect(find.textContaining('₱6,839.95 per day'), findsOneWidget);
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

  testWidgets('uses the latest Tagalog language for an AI failure fallback', (
    tester,
  ) async {
    final assistant = _FakeFinancialAssistant()..fail = true;
    await _pumpChat(tester, assistant: assistant);

    await _ask(tester, 'May payo ka ba para sa aking pera?');

    expect(
      find.textContaining('Hindi available ang AI ngayon'),
      findsOneWidget,
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

  group('answers in the language asked', () {
    testWidgets("a Tagalog question gets Fin's Tagalog, even offline", (
      tester,
    ) async {
      final assistant = _FakeFinancialAssistant();
      await _pumpChat(tester, assistant: assistant, isOnline: false);

      await _ask(tester, 'Magkano pa ang pwede kong gastusin ngayon?');
      await tester.pumpAndSettle();

      expect(
        find.textContaining('Idagdag muna ang mga wallet mo'),
        findsOneWidget,
      );
      // Only a Taglish answer can be switched.
      expect(find.text('Translate into Tagalog'), findsNothing);
      expect(find.text('Translate into English'), findsNothing);
    });

    testWidgets('a Taglish answer comes in English and switches both ways', (
      tester,
    ) async {
      final assistant = _FakeFinancialAssistant();
      await _pumpChat(tester, assistant: assistant, isOnline: false);

      await _ask(tester, 'May bills ba ako this week?');
      await tester.pumpAndSettle();
      expect(
        find.text("You don't have any unpaid bills coming up."),
        findsOneWidget,
      );

      // Fin's own Tagalog: no Gemini, so it works offline.
      await tester.tap(find.text('Translate into Tagalog'));
      await tester.pumpAndSettle();
      expect(
        find.text('Wala kang paparating na bills na hindi pa bayad.'),
        findsOneWidget,
      );
      expect(assistant.translated, isEmpty);

      await tester.tap(find.text('Translate into English'));
      await tester.pumpAndSettle();
      expect(
        find.text("You don't have any unpaid bills coming up."),
        findsOneWidget,
      );
      expect(find.text('Translate into Tagalog'), findsOneWidget);
    });

    testWidgets("every one of Fin's own answers switches, even offline", (
      tester,
    ) async {
      final assistant = _FakeFinancialAssistant();
      await _pumpChat(tester, assistant: assistant, isOnline: false);

      // A formula is one of the rarer answers.
      await _ask(tester, 'Anong formula ang ginamit sa safe to spend?');
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Here is how Safe to Spend is worked out'),
        findsOneWidget,
      );

      await tester.tap(find.text('Translate into Tagalog'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Ganito kinukuwenta ang Safe to Spend'),
        findsOneWidget,
      );
      expect(assistant.translated, isEmpty);
    });

    testWidgets('when Gemini fails, a Taglish bubble still switches offline', (
      tester,
    ) async {
      final assistant = _FakeFinancialAssistant()..fail = true;
      await _pumpChat(tester, assistant: assistant);

      await _ask(tester, 'Pahingi ng tips para makatipid this month');
      await tester.pumpAndSettle();
      expect(
        find.textContaining('AI is unavailable right now'),
        findsOneWidget,
      );
      expect(
        find.textContaining('Start by recording every expense'),
        findsOneWidget,
      );

      await tester.tap(find.text('Translate into Tagalog'));
      await tester.pumpAndSettle();
      // The notice and Fin's answer both have Tagalog in the app.
      expect(
        find.textContaining('Hindi available ang AI ngayon'),
        findsOneWidget,
      );
      expect(find.textContaining('Simulan sa pagtala'), findsOneWidget);
      expect(assistant.translated, isEmpty);
    });

    testWidgets("when Gemini fails, Fin's whole Tagalog answer stays", (
      tester,
    ) async {
      final assistant = _FakeFinancialAssistant()..fail = true;
      await _pumpChat(tester, assistant: assistant);

      await _ask(tester, 'Paano ko ibubudget ang pera ko?');
      await tester.pumpAndSettle();

      final bubble = find.textContaining('Hindi available ang AI ngayon');
      expect(bubble, findsOneWidget);
      final text = tester.widget<Text>(bubble).data!;
      // Every paragraph of it, not just the last.
      expect(text, contains('Simpleng paraan ng pag-budget'));
      expect(text, contains('Unahin ang bills'));
      expect(text, contains('Itala ang bawat gastos'));
    });

    testWidgets("only Gemini's own words are sent to be translated", (
      tester,
    ) async {
      final assistant = _FakeFinancialAssistant();
      await _pumpChat(tester, assistant: assistant);

      await _ask(tester, 'Pahingi ng tips para makatipid this month');
      await tester.pumpAndSettle();
      await tester.tap(find.text('Translate into Tagalog'));
      await tester.pumpAndSettle();

      expect(assistant.translated, [
        'Compound interest can help savings grow over time.',
      ]);
      expect(
        find.textContaining('Sa Tagalog: Compound interest'),
        findsOneWidget,
      );
      expect(find.textContaining('Simulan sa pagtala'), findsOneWidget);
    });

    testWidgets("Gemini's own words need the internet to translate", (
      tester,
    ) async {
      final assistant = _FakeFinancialAssistant();
      final online = StreamController<bool>();
      addTearDown(online.close);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: ChatbotScreen(
            assistant: assistant,
            onlineStatus: online.stream,
            records: Stream.value(FinanceSnapshot(now: DateTime(2026, 10, 14))),
          ),
        ),
      );
      online.add(true);
      await tester.pump();

      await _ask(tester, 'Pahingi ng tips para makatipid this month');
      await tester.pumpAndSettle();
      online.add(false);
      await tester.pumpAndSettle();

      await tester.tap(find.text('Translate into Tagalog'));
      await tester.pumpAndSettle();
      expect(
        find.text('Translating this one needs an internet connection.'),
        findsOneWidget,
      );
      expect(find.text('Translate into Tagalog'), findsOneWidget);
    });
  });
}
