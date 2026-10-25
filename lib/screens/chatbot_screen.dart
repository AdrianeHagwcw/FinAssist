import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../models/chat_answers.dart';
import '../models/chat_action.dart';
import '../models/chat_language.dart';
import '../models/financial_topic_validator.dart';
import '../models/financial_ai_guardrails.dart';
import '../models/finance_snapshot.dart';
import '../models/financial_insights.dart';
import '../models/goal.dart';
import '../screens/add_expense_screen.dart';
import '../screens/income_waterfall_screen.dart';
import '../services/finance_snapshot_service.dart';
import '../services/financial_ai_service.dart';
import '../services/goal_service.dart';
import '../services/wallet_service.dart';
import '../theme/app_buttons.dart';
import '../theme/app_colors.dart';
import '../widgets/dialog_kit.dart';
import '../widgets/goal_sheets.dart';
import '../widgets/transfer_sheet.dart';
import '../widgets/wallet_picker.dart';
import '../utils/money_format.dart';

/// Reports whether the phone has a network connection, now and on change.
Stream<bool> _deviceOnlineStatus() async* {
  final connectivity = Connectivity();
  bool isOnline(List<ConnectivityResult> results) =>
      results.any((result) => result != ConnectivityResult.none);

  yield isOnline(await connectivity.checkConnectivity());
  yield* connectivity.onConnectivityChanged.map(isOnline);
}

String _localizedActionMessage(
  ChatLanguage language,
  String english,
) => switch (language) {
  ChatLanguage.english => english,
  ChatLanguage.tagalog =>
    english.contains('expense amount')
        ? 'Nailagay ko na ang halaga at description ng expense. Piliin ang '
              'category at wallet na pagbabawasan, saka i-review at kumpirmahin. Walang mase-save '
              'bago mo ito kumpirmahin.'
        : english.contains('start an expense')
        ? 'Maaari akong magsimula ng expense. Para saan ito? Piliin ang '
              'category at wallet. Walang mase-save bago mo ito i-review at '
              'kumpirmahin.'
        : 'Maaari ko itong ihanda sa FinAssist. I-review at baguhin ang '
              'detalye sa form, saka ikaw ang mag-save. Walang mase-save bago '
              'mo ito kumpirmahin.',
  ChatLanguage.taglish =>
    english.contains('expense amount')
        ? 'Nailagay ko na ang expense amount at description. Piliin ang '
              'category at wallet, then i-review at i-confirm. Nothing is saved '
              'until you confirm.'
        : english.contains('start an expense')
        ? 'I can start an expense. Para saan ito? Piliin ang category at '
              'wallet na pagbabawasan. Nothing is saved until you review and confirm it.'
        : 'I can prepare this in FinAssist. I-review at i-edit ang details '
              'sa existing form, then ikaw ang mag-save. Nothing is saved until '
              'you confirm.',
};

String _localizedFailureMessage(
  ChatLanguage language,
  String english,
) => switch (language) {
  ChatLanguage.english => english,
  ChatLanguage.tagalog =>
    english.startsWith('I could not find')
        ? 'Hindi ako nakahanap ng mapagkakatiwalaang kasalukuyang presyo. '
              'Subukan muli sandali. Hindi ako manghuhula ng presyo.'
        : english.startsWith('I want to answer accurately')
        ? 'Gusto kong sumagot nang tama. Paki-linaw kung gagamitin ko ang '
              'naitalang kita, gastos, balanse, bills, o savings target. Isama '
              'ang halaga at panahong tinutukoy mo.'
        : english.startsWith('Your records changed')
        ? 'Nagbago ang iyong records habang sumasagot ako. Magtanong muli '
              'para magamit ko ang updated na impormasyon.'
        : english.contains('The following is verified FinAssist guidance')
        ? 'Hindi available ang AI ngayon. Ang sumusunod ay verified '
              'FinAssist guidance mula sa iyong saved records, hindi ito '
              'Gemini response:\n\n'
              '${english.split('The following is verified FinAssist guidance').last.split('\n\n').last}'
        : 'Hindi available ang AI ngayon. Hindi nabago ang iyong financial '
              'records. Subukan muli mamaya.',
  ChatLanguage.taglish =>
    english.startsWith('I could not find')
        ? 'Hindi ako nakahanap ng reliable na current price ngayon. '
              'Try again shortly. Hindi ako manghuhula ng presyo.'
        : english.startsWith('I want to answer accurately')
        ? 'Gusto kong accurate ang sagot. Paki-clarify kung gagamitin ko ang '
              'recorded income, expenses, balance, bills, o savings target. '
              'Isama ang amount at time period.'
        : english.startsWith('Your records changed')
        ? 'Nagbago ang records mo habang sumasagot ako. Ask again para '
              'magamit ko ang updated information.'
        : english.contains('The following is verified FinAssist guidance')
        ? 'AI unavailable ngayon. Ang sumusunod ay verified FinAssist '
              'guidance mula sa saved records mo, hindi ito Gemini response:\n\n'
              '${english.split('The following is verified FinAssist guidance').last.split('\n\n').last}'
        : 'AI unavailable ngayon. Hindi nabago ang financial records mo. '
              'Subukan muli mamaya.',
};

class ChatbotScreen extends StatefulWidget {
  const ChatbotScreen({
    this.onlineStatus,
    this.records,
    this.assistant,
    this.onAction,
    super.key,
  });

  /// Online/offline updates. Tests pass their own stream.
  final Stream<bool>? onlineStatus;

  /// The user's records to answer from. Tests pass their own.
  final Stream<FinanceSnapshot>? records;

  /// Replaces Gemini in tests.
  final FinancialAssistant? assistant;

  /// Replaces form navigation in tests; production always opens existing forms.
  final Future<bool> Function(ChatAction action)? onAction;

  @override
  State<ChatbotScreen> createState() => _ChatbotScreenState();
}

class _GoogleSearchSuggestions extends StatefulWidget {
  const _GoogleSearchSuggestions({required this.html});

  final String html;

  @override
  State<_GoogleSearchSuggestions> createState() =>
      _GoogleSearchSuggestionsState();
}

class _GoogleSearchSuggestionsState extends State<_GoogleSearchSuggestions> {
  late final WebViewController _controller;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.disabled)
      ..setNavigationDelegate(
        NavigationDelegate(
          onNavigationRequest: (request) {
            final uri = Uri.tryParse(request.url);
            if (uri?.scheme == 'https' &&
                uri?.host == 'www.google.com' &&
                uri?.path.startsWith('/search') == true) {
              return NavigationDecision.navigate;
            }
            return NavigationDecision.prevent;
          },
        ),
      )
      ..loadHtmlString(widget.html);
  }

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 64,
    width: 280,
    child: WebViewWidget(controller: _controller),
  );
}

class _ChatbotScreenState extends State<ChatbotScreen> {
  static const Color primaryBlue = Color(0xFF1976D2);

  final TextEditingController _messageController = TextEditingController();

  final ScrollController _scrollController = ScrollController();

  bool _isOnline = true;
  bool _isSending = false;
  int _conversationEpoch = 0;
  StreamSubscription<bool>? _onlineSubscription;

  /// What the answers are worked out from; null while still loading.
  FinanceSnapshot? _records;
  StreamSubscription<FinanceSnapshot>? _recordsSubscription;

  /// A "Can I buy it?" question still being worked out.
  PurchaseQuestion? _pending;

  final List<Map<String, dynamic>> _messages = [
    {
      'message':
          'Hello! I\'m Fin. How can I help you with your finances today?',
      'isUser': false,
    },
  ];

  @override
  void initState() {
    super.initState();
    _onlineSubscription = (widget.onlineStatus ?? _deviceOnlineStatus()).listen(
      (isOnline) {
        if (mounted) setState(() => _isOnline = isOnline);
      },
      onError: (Object _) {},
    );
    _recordsSubscription = (widget.records ?? watchFinanceSnapshot()).listen(
      (records) {
        if (mounted) setState(() => _records = records);
      },
      onError: (Object _) {
        if (mounted) setState(() => _records = null);
      },
    );
  }

  @override
  void dispose() {
    _onlineSubscription?.cancel();
    _recordsSubscription?.cancel();
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  // =========================================================
  // SEND MESSAGE
  // =========================================================

  /// Sends what was typed, or [tapped] when a quick reply was tapped.
  void _sendMessage([String? tapped]) {
    if (_isSending) return;
    final text = (tapped ?? _messageController.text).trim();

    if (text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Type a financial question first.')),
      );
      return;
    }
    if (text.length > 1000) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Keep your question under 1,000 characters.'),
        ),
      );
      return;
    }

    final financialTopic = isFinancialTopic(
      text,
      hasFinancialContext: _messages.last['financialContext'] == true,
    );
    final epoch = _conversationEpoch;
    setState(() {
      _messages.add({
        'message': text,
        'isUser': true,
        'financialContext': financialTopic,
      });
      _isSending = true;

      if (tapped == null) _messageController.clear();
    });

    _scrollToBottom();
    unawaited(_respond(text, financialTopic: financialTopic, epoch: epoch));
  }

  Future<void> _respond(
    String text, {
    required bool financialTopic,
    required int epoch,
  }) async {
    try {
      final records = _records?.at(DateTime.now());
      final productPriceQuery = productPriceLookupQuery(text);
      final categorizedExpenses = categorizeChatExpenses(text);
      final hasMultipleCategorizedExpenses = categorizedExpenses != null;
      final expenseBatchMessage = categorizedExpenses == null
          ? const <String, dynamic>{}
          : <String, dynamic>{'expenseBatch': categorizedExpenses};
      final action = hasMultipleCategorizedExpenses
          ? null
          : parseChatAction(text, records: records);
      final responseLanguage = chatResponseLanguage(
        text,
        history: [
          for (final message in _messages.take(_messages.length - 1))
            if (message['isUser'] == true)
              FinancialChatTurn(
                isUser: true,
                text: message['message'] as String,
              ),
        ],
      );
      final contextMessage = _messages.reversed
          .skip(1)
          .map(
            (message) => message['isUser'] == true ? message['message'] : null,
          )
          .whereType<String>()
          .firstOrNull;
      final localReply = answerChat(
        text,
        records: records,
        pending: _pending,
        contextMessage: contextMessage,
      );
      if (localReply.useLocalAnswer || action != null) {
        _messages.last['financialContext'] = true;
      }
      var usedAi = false;
      GroundedProductPriceAnswer? groundedPriceAnswer;
      var answer = switch (action?.type) {
        ChatActionType.expense =>
          action!.description == null
              ? _localizedActionMessage(
                  responseLanguage,
                  'I can start an expense for you. What was it for? Please '
                  'choose its category and the wallet to deduct it from. '
                  'Nothing will be saved '
                  'until you review and confirm it.',
                )
              : _localizedActionMessage(
                  responseLanguage,
                  'I filled in the expense amount and description. Choose its '
                  'category and wallet, then review and confirm it. '
                  'Nothing is saved before you confirm.',
                ),
        ChatActionType.income ||
        ChatActionType.transfer ||
        ChatActionType.savingsGoal => _localizedActionMessage(
          responseLanguage,
          'I can prepare this in FinAssist. Review and edit the details in '
          'the existing form, then save it yourself. Nothing is saved '
          'until you confirm.',
        ),
        null => localReply.text,
      };

      final isPurchaseFollowUp =
          _pending != null &&
          localReply.text != answerChat(text, records: records).text;
      final usesReportSavingsSuggestions =
          records != null && isSavingsSuggestionsQuestion(text);
      final needsRuleBasedFlow =
          productPriceQuery == null &&
          (action != null ||
              localReply.useLocalAnswer ||
              localReply.pending != null ||
              localReply.goal != null ||
              isPurchaseFollowUp) &&
          !usesReportSavingsSuggestions;

      if (financialTopic && !needsRuleBasedFlow && _isOnline) {
        final contextKey = productPriceQuery == null
            ? financialContextKey(records)
            : null;
        final history = [
          for (final message in _messages.take(_messages.length - 1))
            if (message['financialContext'] == true)
              FinancialChatTurn(
                isUser: message['isUser'] as bool,
                text: message['message'] as String,
              ),
        ];
        try {
          final assistant = widget.assistant ?? FirebaseFinancialAssistant();
          final geminiAnswer = await requestFinancialAssistant(() async {
            if (productPriceQuery != null) {
              groundedPriceAnswer = await assistant.lookupProductPrices(
                product: productPriceQuery,
                responseLanguage: responseLanguage,
              );
              return groundedPriceAnswer!.text;
            }
            if (usesReportSavingsSuggestions) {
              final insights = calculateFinancialInsights(
                records.transactions,
                now: records.now,
                spendingBudget: records.periodBudget,
              );
              final suggestions = await assistant.explainInsights(
                insights,
                responseLanguage: responseLanguage,
              );
              if (suggestions.isEmpty ||
                  !suggestions.every(isUsableFinancialExplanation)) {
                throw const FinancialAssistantFailure(
                  'Gemini returned unusable savings suggestions.',
                );
              }
              return suggestions.join('\n\n');
            }
            return assistant.answerQuestion(
              question: text,
              records: records,
              history: history,
              verifiedGoalPlan: localReply.isVerifiedGoalPlan
                  ? localReply.text
                  : null,
            );
          });
          if (productPriceQuery == null &&
              !isUsableFinancialExplanation(geminiAnswer)) {
            throw const FinancialAssistantFailure('Unverified AI response.');
          }
          usedAi = true;
          if (groundedPriceAnswer != null) {
            answer = geminiAnswer;
          } else if (localReply.isVerifiedGoalPlan) {
            answer =
                RegExp(
                  r"\bnot sure what you're asking\b",
                  caseSensitive: false,
                ).hasMatch(geminiAnswer)
                ? localReply.text
                : '$geminiAnswer\n\n${localReply.text}';
          } else {
            answer = geminiAnswer;
          }
          if (contextKey != null &&
              contextKey != financialContextKey(_records?.at(DateTime.now()))) {
            usedAi = false;
            answer = _localizedFailureMessage(
              responseLanguage,
              'Your records changed while I was answering. Please ask again '
              'so I can use the updated information.',
            );
          }
        } on FinancialAssistantFailure catch (error) {
          debugPrint(
            'FinAssist Gemini chat failed (${error.kind.name}); '
            'showing verified local guidance.',
          );
          answer = productPriceQuery != null
              ? _localizedFailureMessage(
                  responseLanguage,
                  'I could not find a reliable current price right now. '
                  'Please try again in a moment. I will not guess the price.',
                )
              : isFinancialFollowUp(text)
              ? _localizedFailureMessage(
                  responseLanguage,
                  'I want to answer accurately. Please clarify whether you '
                  'want me to use your recorded income, expenses, balance, '
                  'bills, or a savings target. Include the amount and time '
                  'period you mean.',
                )
              : _localizedFailureMessage(
                  responseLanguage,
                  'AI is unavailable right now: ${error.message}\n\n'
                  'The following is verified FinAssist guidance from your '
                  'saved records, not a Gemini response:\n\n'
                  '${localReply.text}',
                );
        }
      }

      if (usedAi) {
        debugPrint('FinAssist answer source: Gemini');
      } else {
        final reason = action != null
            ? 'chat action'
            : localReply.pending != null
            ? 'purchase follow-up'
            : localReply.goal != null
            ? 'verified savings goal plan'
            : !_isOnline
            ? 'offline'
            : financialTopic
            ? 'verified app data or Gemini fallback'
            : 'unsupported or non-financial question';
        debugPrint('FinAssist answer source: rule-based ($reason)');
      }

      if (!mounted || epoch != _conversationEpoch) return;
      setState(() {
        _pending = localReply.pending;
        _messages.add({
          'message': answer,
          'isUser': false,
          'choices': usedAi ? const <String>[] : localReply.choices,
          'goal': localReply.goal,
          'action': action,
          ...expenseBatchMessage,
          'priceSources': groundedPriceAnswer?.sources,
          'searchSuggestionsHtml': groundedPriceAnswer?.searchSuggestionsHtml,
          'financialContext':
              financialTopic || action != null || localReply.useLocalAnswer,
        });
      });
    } on FinancialAssistantFailure catch (error) {
      debugPrint('FinAssist Gemini chat failed: ${error.message}');
      if (!mounted || epoch != _conversationEpoch) return;
      final fallbackLanguage = chatResponseLanguage(
        text,
        history: [
          for (final message in _messages)
            if (message['isUser'] == true)
              FinancialChatTurn(
                isUser: true,
                text: message['message'] as String,
              ),
        ],
      );
      setState(() {
        _messages.add({
          'message': _localizedFailureMessage(
            fallbackLanguage,
            'AI is unavailable right now: ${error.message} Your saved '
            'financial records were not changed. Please try again later.',
          ),
          'isUser': false,
          'financialContext': financialTopic,
        });
      });
    } finally {
      if (mounted && epoch == _conversationEpoch) {
        setState(() => _isSending = false);
        _scrollToBottom();
      }
    }
  }

  Future<void> _confirmAndAddExpenseBatch(
    Map<String, dynamic> message,
    List<CategorizedChatExpense> expenses,
  ) async {
    if (expenses.any((expense) => expense.category == null)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please clarify every expense category first.'),
        ),
      );
      return;
    }

    final wallets = await WalletService.loadWallets();
    // For what each wallet has free, as everywhere else. Without them the
    // picker shows what each holds.
    List<Goal>? goals;
    try {
      goals = await GoalService.watchGoals().first;
    } catch (_) {}
    if (!mounted) return;
    if (wallets.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Add a spending wallet before adding these expenses.'),
        ),
      );
      return;
    }

    var selectedWalletId = defaultWalletId(wallets);
    final confirmedWalletId = await showDialog<String>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Add all expenses?'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Confirm that these categories are correct:'),
                const SizedBox(height: 12),
                for (final expense in expenses)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Text(
                      '${formatPeso(expense.amount)} — '
                      '${expense.description}: ${expense.category}',
                    ),
                  ),
                const SizedBox(height: 8),
                WalletPicker(
                  wallets: wallets,
                  selectedId: selectedWalletId,
                  goals: goals,
                  onChanged: (value) =>
                      setDialogState(() => selectedWalletId = value),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: selectedWalletId == null
                  ? null
                  : () => Navigator.pop(dialogContext, selectedWalletId),
              child: const Text('Add all expenses'),
            ),
          ],
        ),
      ),
    );
    if (confirmedWalletId == null || !mounted) return;

    try {
      WalletService.recordExpenseBatch(
        walletId: confirmedWalletId,
        expenses: [
          for (final expense in expenses)
            ExpenseBatchEntry(
              amount: expense.amount,
              label: expense.category!,
              note: expense.description,
            ),
        ],
      );
    } on Object catch (error, stackTrace) {
      debugPrint('FinAssist expense batch save failed: $error');
      debugPrintStack(stackTrace: stackTrace);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('The expenses could not be added. Please try again.'),
        ),
      );
      return;
    }

    setState(() {
      message['expenseBatch'] = <CategorizedChatExpense>[];
      message['message'] =
          '${message['message']}\n\nAll listed expenses were added.';
    });
    _scrollToBottom();
  }

  Future<bool> _openAction(ChatAction action) async {
    if (widget.onAction != null) return widget.onAction!(action);

    switch (action.type) {
      case ChatActionType.expense:
        final saved = await Navigator.push<bool>(
          context,
          MaterialPageRoute(
            builder: (_) => AddExpenseScreen(
              initialAmount: action.amount,
              initialDescription: action.description,
              requireCategorySelection: true,
              requireWalletSelection: true,
            ),
          ),
        );
        return saved ?? false;
      case ChatActionType.income:
        return showIncomeWaterfall(
          context,
          walletId: action.incomeWalletId,
          initialAmount: action.amount,
          initialSource: action.initialSource,
        );
      case ChatActionType.transfer:
        return showTransferSheet(
          context,
          fromWalletId: action.sourceWalletId,
          toWalletId: action.destinationWalletId,
          initialAmount: action.amount,
        );
      case ChatActionType.savingsGoal:
        return showGoalFormSheet(
          context,
          initialName: action.name,
          initialTarget: action.amount,
        );
    }
  }

  Future<void> _reviewAction(ChatAction action) async {
    final saved = await _openAction(action);
    if (!saved || !mounted) return;
    final subject = switch (action.type) {
      ChatActionType.expense => 'Expense',
      ChatActionType.income => 'Income',
      ChatActionType.transfer => 'Transfer',
      ChatActionType.savingsGoal => 'Savings goal',
    };
    setState(() {
      _messages.add({
        'message': '$subject saved.',
        'isUser': false,
        'financialContext': true,
      });
    });
    _scrollToBottom();
  }

  /// Opens the goal form filled in from the assistant's suggestion.
  Future<void> _createGoal(GoalOffer goal) async {
    final saved = await showGoalFormSheet(
      context,
      initialName: goal.name,
      initialTarget: goal.target,
      initialDate: goal.date,
    );
    if (!saved || !mounted) return;
    setState(() {
      _messages.add({
        'message':
            'Your ${goal.name} goal is saved. You can follow it in '
            'Goals.',
        'isUser': false,
      });
    });
    _scrollToBottom();
  }

  // =========================================================
  // SCROLL TO BOTTOM
  // =========================================================

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  // =========================================================
  // BUILD
  // =========================================================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.appColors.pageBackground,

      // =====================================================
      // APP BAR
      // =====================================================
      appBar: AppBar(
        backgroundColor: primaryBlue,
        foregroundColor: Colors.white,
        elevation: 0,

        title: Row(
          children: [
            // The assistant's face, straight on the blue bar.
            Image.asset(
              'assets/icons/assistant-robot-192.png',
              width: 36,
              height: 36,
            ),

            const SizedBox(width: 12),

            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'FinAssist AI',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
                ),

                Row(
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: _isOnline
                            ? Colors.greenAccent
                            : Colors.orangeAccent,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      _isOnline ? 'Online' : 'Offline',
                      style: const TextStyle(
                        fontSize: 11,
                        color: Colors.white70,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),

        actions: [
          // A small card right under the dots, the menu Android users know.
          PopupMenuButton<_ChatMenuAction>(
            tooltip: 'More options',
            icon: const Icon(Icons.more_vert),
            position: PopupMenuPosition.under,
            offset: const Offset(0, 6),
            color: context.appColors.card,
            elevation: 6,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
              side: BorderSide(color: context.appColors.border),
            ),
            onSelected: (action) => switch (action) {
              _ChatMenuAction.clear => _confirmClearConversation(),
              _ChatMenuAction.about => _showAbout(),
            },
            itemBuilder: (context) => [
              PopupMenuItem(
                value: _ChatMenuAction.clear,
                // Nothing to clear until something has been asked.
                enabled: _messages.length > 1 || _isSending,
                height: 48,
                child: _menuRow(
                  icon: Icons.delete_outline,
                  label: 'Clear conversation',
                  color: dangerColorOn(context),
                  enabled: _messages.length > 1 || _isSending,
                ),
              ),
              PopupMenuItem(
                value: _ChatMenuAction.about,
                height: 48,
                child: _menuRow(
                  icon: Icons.info_outline,
                  label: 'About Fin',
                  color: context.appColors.primaryText,
                ),
              ),
            ],
          ),
        ],
      ),

      // =====================================================
      // BODY
      // =====================================================
      body: Column(
        children: [
          // ===================================================
          // CHAT MESSAGES
          // ===================================================
          Expanded(
            child: ListView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.fromLTRB(15, 20, 15, 20),
              itemCount: _messages.length + (_isSending ? 1 : 0),
              itemBuilder: (context, index) {
                if (_isSending && index == _messages.length) {
                  return _typingIndicator();
                }
                final message = _messages[index];
                final isUser = message['isUser'] as bool;
                final choices = message['choices'] as List<String>? ?? const [];
                final goal = message['goal'] as GoalOffer?;
                final action = message['action'] as ChatAction?;
                final expenseBatch =
                    message['expenseBatch'] as List<CategorizedChatExpense>?;
                final priceSources =
                    message['priceSources'] as List<GroundedPriceSource>? ??
                    const [];
                final searchSuggestionsHtml =
                    message['searchSuggestionsHtml'] as String?;
                // Only the latest answer's quick replies still apply.
                final isLatest = index == _messages.length - 1;

                return Column(
                  crossAxisAlignment: isUser
                      ? CrossAxisAlignment.end
                      : CrossAxisAlignment.start,
                  children: [
                    _messageBubble(message: message['message'], isUser: isUser),
                    if (!isUser && priceSources.isNotEmpty)
                      _groundedPriceSources(
                        priceSources,
                        searchSuggestionsHtml,
                      ),
                    if (goal != null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: OutlinedButton.icon(
                          onPressed: () => _createGoal(goal),
                          style: openOutlineStyle(context, height: 40),
                          icon: const Icon(Icons.flag_outlined, size: 18),
                          label: const Text('Create Goal'),
                        ),
                      ),
                    if (action != null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: OutlinedButton.icon(
                          onPressed: () => _reviewAction(action),
                          style: openOutlineStyle(context, height: 40),
                          icon: const Icon(Icons.edit_note_outlined, size: 18),
                          label: Text(action.label),
                        ),
                      ),
                    if (expenseBatch != null && expenseBatch.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: OutlinedButton.icon(
                          onPressed: () =>
                              _confirmAndAddExpenseBatch(message, expenseBatch),
                          style: openOutlineStyle(context, height: 40),
                          icon: const Icon(Icons.playlist_add_check, size: 18),
                          label: Text('Add all expenses'),
                        ),
                      ),
                    if (isLatest && choices.isNotEmpty && _messages.length > 1)
                      _quickActionChoices(choices),
                    // Right under the greeting, so a new chat has no empty
                    // gap between Fin's hello and what to ask.
                    if (index == 0 && _messages.length == 1)
                      _suggestedQuestions(),
                  ],
                );
              },
            ),
          ),

          // ===================================================
          // MESSAGE INPUT
          // ===================================================
          _messageInput(),
        ],
      ),
    );
  }

  // =========================================================
  // MESSAGE BUBBLE
  // =========================================================

  Widget _groundedPriceSources(
    List<GroundedPriceSource> sources,
    String? searchSuggestionsHtml,
  ) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12, left: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Prices checked today. Seller prices and stock can change.',
            style: TextStyle(fontSize: 11, color: context.appColors.textBody),
          ),
          for (final source in sources)
            TextButton.icon(
              onPressed: () => _openPriceSource(source.url),
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                visualDensity: VisualDensity.compact,
              ),
              icon: const Icon(Icons.open_in_new, size: 14),
              label: Text(source.title, textAlign: TextAlign.left),
            ),
          if (searchSuggestionsHtml != null && searchSuggestionsHtml.isNotEmpty)
            _GoogleSearchSuggestions(html: searchSuggestionsHtml),
        ],
      ),
    );
  }

  Future<void> _openPriceSource(String value) async {
    final uri = Uri.tryParse(value);
    if (uri == null ||
        (uri.scheme != 'https' && uri.scheme != 'http') ||
        !await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open this price source.')),
      );
    }
  }

  /// Fin's face in a small circle, beside each of its messages.
  Widget _finAvatar() => Container(
    width: 30,
    height: 30,
    margin: const EdgeInsets.only(right: 8, top: 2),
    padding: const EdgeInsets.all(4),
    decoration: BoxDecoration(
      color: context.appColors.primaryTint,
      shape: BoxShape.circle,
    ),
    child: Image.asset('assets/icons/assistant-robot-192.png'),
  );

  Widget _messageBubble({required String message, required bool isUser}) {
    final colors = context.appColors;
    final bubble = Container(
      constraints: BoxConstraints(
        maxWidth: MediaQuery.of(context).size.width * 0.74,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      decoration: BoxDecoration(
        color: isUser ? primaryBlue : colors.card,
        borderRadius: BorderRadius.only(
          topLeft: const Radius.circular(18),
          topRight: const Radius.circular(18),
          bottomLeft: Radius.circular(isUser ? 18 : 4),
          bottomRight: Radius.circular(isUser ? 4 : 18),
        ),
        // A thin edge keeps a white bubble visible on a light page.
        border: isUser ? null : Border.all(color: colors.border),
      ),
      child: Text(
        message,
        style: TextStyle(
          fontSize: 15,
          height: 1.4,
          color: isUser ? Colors.white : colors.textPrimary,
        ),
      ),
    );

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        mainAxisAlignment: isUser
            ? MainAxisAlignment.end
            : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!isUser) _finAvatar(),
          Flexible(child: bubble),
        ],
      ),
    );
  }

  // =========================================================
  // SUGGESTED QUESTIONS
  // =========================================================

  /// The picture each suggested question gets: the same colored icon the
  /// app uses for that thing elsewhere, so a question about bills looks
  /// like the Bills card on Home.
  static String _suggestionIcon(String question) {
    final q = question.toLowerCase();
    if (q.contains('spend today')) {
      return 'assets/icons/icons8-banknotes-96.png';
    }
    if (q.contains('spending')) return 'assets/icons/icons8-pie-chart-96.png';
    if (q.contains('bill')) return 'assets/icons/icons8-receipt-96.png';
    if (q.contains('buy')) return 'assets/icons/icons8-cat-shopping-96.png';
    if (q.contains('formula')) return 'assets/icons/icons8-idea-96.png';
    return 'assets/icons/assistant-robot-192.png';
  }

  Widget _suggestedQuestions() {
    const questions = suggestedQuestions;
    final colors = context.appColors;

    return Padding(
      // Lined up with the bubble, past Fin's face.
      padding: const EdgeInsets.only(left: 38, top: 4, bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Try asking',
            style: TextStyle(
              fontSize: 13,
              color: colors.textMuted,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          for (final question in questions)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Material(
                color: colors.card,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                  side: BorderSide(color: colors.border),
                ),
                child: InkWell(
                  borderRadius: BorderRadius.circular(14),
                  onTap: () => _sendMessage(question),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(minHeight: 48),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 34,
                            height: 34,
                            padding: const EdgeInsets.all(6),
                            decoration: BoxDecoration(
                              color: colors.primaryTint,
                              shape: BoxShape.circle,
                            ),
                            child: Image.asset(_suggestionIcon(question)),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              question,
                              style: TextStyle(
                                fontSize: 14,
                                color: colors.textPrimary,
                              ),
                            ),
                          ),
                          Icon(
                            Icons.north_east,
                            size: 16,
                            color: colors.textMuted,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _quickActionChoices(List<String> choices) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12, left: 38),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final choice in choices)
            ActionChip(
              label: Text(choice),
              backgroundColor: context.appColors.primaryTint,
              side: BorderSide.none,
              labelStyle: TextStyle(
                color: context.appColors.primaryText,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
              onPressed: () => _sendMessage(choice),
            ),
        ],
      ),
    );
  }

  // =========================================================
  // MESSAGE INPUT
  // =========================================================

  Widget _messageInput() {
    return SafeArea(
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        decoration: BoxDecoration(
          color: context.appColors.card,
          border: Border(top: BorderSide(color: context.appColors.border)),
        ),

        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _inputNotice(),
            const SizedBox(height: 8),
            Row(
              children: [
                // Text field
                Expanded(
                  child: TextField(
                    enabled: !_isSending,
                    controller: _messageController,

                    textInputAction: TextInputAction.send,

                    onSubmitted: (_) {
                      _sendMessage();
                    },

                    decoration: InputDecoration(
                      hintText: 'Ask FinAssist something...',

                      hintStyle: TextStyle(
                        fontSize: 14,
                        color: context.appColors.textMuted,
                      ),

                      filled: true,

                      fillColor: context.appColors.inputFill,

                      // Outlined, so the box shows on a white bar.
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(25),
                        borderSide: BorderSide(
                          color: context.appColors.inputBorder,
                        ),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(25),
                        borderSide: BorderSide(
                          color: context.appColors.inputBorder,
                        ),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(25),
                        borderSide: const BorderSide(
                          color: primaryBlue,
                          width: 1.5,
                        ),
                      ),

                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 18,
                        vertical: 12,
                      ),
                    ),
                  ),
                ),

                const SizedBox(width: 8),

                // Send button
                Container(
                  width: 48,
                  height: 48,
                  decoration: const BoxDecoration(
                    color: primaryBlue,
                    shape: BoxShape.circle,
                  ),
                  child: IconButton(
                    tooltip: 'Send message',
                    onPressed: _isSending ? null : _sendMessage,
                    icon: _isSending
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.send, color: Colors.white, size: 20),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// Notice above the input: scope, offline status, and input accuracy.
  Widget _inputNotice() {
    final offline = !_isOnline;
    final status = offline
        ? "You're offline. Answers use the records saved on this phone."
        : 'Finance questions only. Gemini receives your question and a '
              'small summary of verified financial totals.';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: context.appColors.primaryTint,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: Icon(
              offline ? Icons.cloud_off_outlined : Icons.info_outline,
              size: 15,
              color: context.appColors.primaryText,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '$status Answers depend on your inputs being accurate and '
              'complete.',
              style: TextStyle(
                fontSize: 12,
                height: 1.35,
                color: context.appColors.textMuted,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Fin's face, then a bubble saying it is working on the answer.
  Widget _typingIndicator() => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _finAvatar(),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
          decoration: BoxDecoration(
            color: context.appColors.card,
            border: Border.all(color: context.appColors.border),
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(18),
              topRight: Radius.circular(18),
              bottomRight: Radius.circular(18),
              bottomLeft: Radius.circular(4),
            ),
          ),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              SizedBox(width: 10),
              Text('Fin is thinking…'),
            ],
          ),
        ),
      ],
    ),
  );

  // =========================================================
  // OPTIONS MENU
  // =========================================================

  Widget _menuRow({
    required IconData icon,
    required String label,
    required Color color,
    bool enabled = true,
  }) {
    final faded = context.appColors.textMuted.withValues(alpha: 0.6);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 20, color: enabled ? color : faded),
        const SizedBox(width: 12),
        // Wraps with large text instead of running off the menu.
        Flexible(
          child: Text(
            label,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: enabled ? color : faded,
            ),
          ),
        ),
      ],
    );
  }

  /// Asks before the chat is wiped, since it cannot be brought back.
  Future<void> _confirmClearConversation() async {
    final clear = await confirmDestructive(
      context,
      title: 'Clear this conversation?',
      message:
          "Every message here will be removed. Your money records aren't "
          'touched.',
      action: 'Clear',
    );
    if (!clear || !mounted) return;
    setState(() {
      _conversationEpoch++;
      _isSending = false;
      _messages.clear();
      _pending = null;
      _messages.add({
        'message':
            'Hello! I\'m Fin. How can I help you with your finances today?',
        'isUser': false,
      });
    });
  }

  /// What Fin is and how it answers, in plain words.
  void _showAbout() {
    final colors = context.appColors;

    // The same colored icons the rest of the app uses for each idea.
    Widget point(String iconAsset, String text) => Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Image.asset(iconAsset, width: 22, height: 22),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 14,
                height: 1.4,
                color: colors.textBody,
              ),
            ),
          ),
        ],
      ),
    );

    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        shape: dialogShape,
        icon: Container(
          width: 64,
          height: 64,
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: colors.primaryTint,
            shape: BoxShape.circle,
          ),
          child: Image.asset('assets/icons/assistant-robot-192.png'),
        ),
        title: const Text('About Fin'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                "Fin is FinAssist's money helper. Ask about your spending, "
                'bills, goals, or whether you can afford something.',
                style: TextStyle(
                  fontSize: 14,
                  height: 1.4,
                  color: colors.textPrimary,
                ),
              ),
              // Saved records: the Transactions icon.
              point(
                'assets/icons/icons8-transactions-96.png',
                'Answers come from the records you saved in FinAssist.',
              ),
              // What is shared online: the privacy shield from setup.
              point(
                'assets/icons/icons8-shield-96.png',
                'When online, Gemini receives your question and a small '
                    'summary of your totals.',
              ),
              // Said as what keeps answers right, not as a warning: the
              // same point the notice above the chat box makes.
              // Recording: the "Record what you spend" icon.
              point(
                'assets/icons/icons8-expenses-64.png',
                'Answers are based on what you record, so keep your '
                    'records complete and up to date.',
              ),
              const SizedBox(height: 14),
              Text(
                'FinAssist 1.0.0',
                style: TextStyle(fontSize: 12, color: colors.textMuted),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => showLicensePage(
              context: dialogContext,
              applicationName: 'FinAssist',
              applicationVersion: '1.0.0',
            ),
            style: TextButton.styleFrom(foregroundColor: colors.textMuted),
            child: const Text('Open-source licenses'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            style: TextButton.styleFrom(
              foregroundColor: primaryBlue,
              minimumSize: const Size(64, 44),
            ),
            child: const Text(
              'Close',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }
}

/// The choices behind the dots in the chat's top bar.
enum _ChatMenuAction { clear, about }
