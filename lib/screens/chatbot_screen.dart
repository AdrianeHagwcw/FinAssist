import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../models/chat_answers.dart';
import '../models/chat_action.dart';
import '../models/financial_topic_validator.dart';
import '../models/financial_ai_guardrails.dart';
import '../models/finance_snapshot.dart';
import '../models/financial_insights.dart';
import '../screens/add_expense_screen.dart';
import '../screens/income_waterfall_screen.dart';
import '../services/finance_snapshot_service.dart';
import '../services/financial_ai_service.dart';
import '../services/wallet_service.dart';
import '../theme/app_buttons.dart';
import '../theme/app_colors.dart';
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
              ? 'Sure — I can start an expense for you. What was it for? '
                    'Please choose its category and the wallet to deduct it '
                    'from. I have put the amount in the expense form; nothing '
                    'will be saved until you review it and tap Save Expense.'
              : 'Sure — I can start an expense for you. I have filled in the '
                    'amount and description. Please choose its category and '
                    'the wallet to deduct it from, then review and tap Save '
                    'Expense. Nothing is saved before you confirm.',
        ChatActionType.income ||
        ChatActionType.transfer ||
        ChatActionType.savingsGoal =>
          'I can prepare this in FinAssist. Review and edit the details in '
              'the existing form, then save it yourself. Nothing is saved '
              'until you confirm.',
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
              );
              return groundedPriceAnswer!.text;
            }
            if (usesReportSavingsSuggestions) {
              final insights = calculateFinancialInsights(
                records.transactions,
                now: records.now,
                spendingBudget: records.periodBudget,
              );
              final suggestions = await assistant.explainInsights(insights);
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
            answer =
                'Your records changed while I was answering. '
                'Please ask again so I can use the updated information.';
          }
        } on FinancialAssistantFailure catch (error) {
          debugPrint(
            'FinAssist Gemini chat failed; using rule-based reply: '
            '${error.message}',
          );
          answer = productPriceQuery != null
              ? 'I could not find a reliable current price right now. '
                    'Please try again in a moment. I will not guess the price.'
              : isFinancialFollowUp(text)
              ? 'I want to answer accurately. Please clarify whether you want '
                    'me to use your recorded income, expenses, balance, bills, '
                    'or a savings target. Include the amount and time period '
                    'you mean.'
              : '${error.transient ? 'Gemini is temporarily busy. ' : 'AI is unavailable right now. '}'
                    'This answer uses the app\'s local guidance and available records.\n\n'
                    '${localReply.text}';
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
      setState(() {
        _messages.add({
          'message':
              'I could not get a Gemini response just now. Your saved '
              'financial records were not changed. Please try again later.',
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
          IconButton(
            tooltip: 'More options',
            icon: const Icon(Icons.more_vert),
            onPressed: () {
              _showOptions();
            },
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
                  ],
                );
              },
            ),
          ),

          // ===================================================
          // SUGGESTED QUESTIONS
          // ===================================================
          if (_messages.length == 1) _suggestedQuestions(),

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

  Widget _messageBubble({required String message, required bool isUser}) {
    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,

      child: Container(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.78,
        ),

        margin: const EdgeInsets.only(bottom: 12),

        padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 12),

        decoration: BoxDecoration(
          color: isUser ? primaryBlue : context.appColors.card,

          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(16),
            topRight: const Radius.circular(16),

            bottomLeft: isUser
                ? const Radius.circular(16)
                : const Radius.circular(4),

            bottomRight: isUser
                ? const Radius.circular(4)
                : const Radius.circular(16),
          ),

          boxShadow: isUser
              ? null
              : [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.04),
                    blurRadius: 4,
                    offset: const Offset(0, 2),
                  ),
                ],
        ),

        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (!isUser) ...[
              Image.asset(
                'assets/icons/assistant-robot-192.png',
                width: 20,
                height: 20,
              ),

              const SizedBox(width: 8),
            ],

            Flexible(
              child: Text(
                message,
                style: TextStyle(
                  fontSize: 14,
                  height: 1.4,
                  color: isUser ? Colors.white : context.appColors.textBody,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // =========================================================
  // SUGGESTED QUESTIONS
  // =========================================================

  Widget _suggestedQuestions() {
    const questions = suggestedQuestions;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(15, 0, 15, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Try asking:',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              for (final question in questions)
                ActionChip(
                  label: Text(question),
                  backgroundColor: context.appColors.primaryTint,
                  side: BorderSide.none,
                  labelStyle: TextStyle(
                    color: context.appColors.primaryText,
                    fontSize: 11,
                  ),
                  onPressed: () => _sendMessage(question),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _quickActionChoices(List<String> choices) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
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
                fontSize: 12,
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
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
        decoration: BoxDecoration(color: context.appColors.card),

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

                      hintStyle: const TextStyle(
                        fontSize: 13,
                        color: Colors.grey,
                      ),

                      filled: true,

                      fillColor: context.appColors.inputFill,

                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(25),

                        borderSide: BorderSide.none,
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
                  width: 45,
                  height: 45,
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

    return Row(
      children: [
        Icon(
          offline ? Icons.cloud_off_outlined : Icons.info_outline,
          size: 14,
          color: Colors.grey,
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            '$status Answers depend on your inputs being accurate and complete.',
            style: const TextStyle(fontSize: 11, color: Colors.grey),
          ),
        ),
      ],
    );
  }

  Widget _typingIndicator() => Align(
    alignment: Alignment.centerLeft,
    child: Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 12),
      decoration: BoxDecoration(
        color: context.appColors.card,
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(16),
          topRight: Radius.circular(16),
          bottomRight: Radius.circular(16),
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
  );

  // =========================================================
  // OPTIONS MENU
  // =========================================================

  void _showOptions() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),

      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 10),

              ListTile(
                leading: const Icon(Icons.delete_outline, color: Colors.red),
                title: const Text('Clear conversation'),
                onTap: () {
                  Navigator.pop(context);

                  setState(() {
                    _conversationEpoch++;
                    _isSending = false;
                    _messages.clear();
                    _pending = null;
                    _messages.add({
                      'message':
                          'Hello! I\'m Fin AI. How can I help you with your finances today?',
                      'isUser': false,
                    });
                  });
                },
              ),

              ListTile(
                leading: const Icon(Icons.info_outline, color: primaryBlue),
                title: const Text('About FinAssist AI'),
                onTap: () {
                  Navigator.pop(context);

                  showAboutDialog(
                    context: context,
                    applicationName: 'FinAssist',
                    applicationVersion: '1.0.0',
                    applicationIcon: Image.asset(
                      'assets/icons/assistant-robot-192.png',
                      width: 40,
                      height: 40,
                    ),
                    children: const [
                      Text(
                        'FinAssist is an AI-driven financial assistant designed to help users understand and manage their personal finances.',
                      ),
                    ],
                  );
                },
              ),

              const SizedBox(height: 10),
            ],
          ),
        );
      },
    );
  }
}
