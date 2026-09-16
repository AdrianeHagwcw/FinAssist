import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import '../theme/app_colors.dart';

/// Reports whether the phone has a network connection, now and on change.
Stream<bool> _deviceOnlineStatus() async* {
  final connectivity = Connectivity();
  bool isOnline(List<ConnectivityResult> results) =>
      results.any((result) => result != ConnectivityResult.none);

  yield isOnline(await connectivity.checkConnectivity());
  yield* connectivity.onConnectivityChanged.map(isOnline);
}

class ChatbotScreen extends StatefulWidget {
  const ChatbotScreen({this.onlineStatus, super.key});

  /// Online/offline updates. Tests pass their own stream.
  final Stream<bool>? onlineStatus;

  @override
  State<ChatbotScreen> createState() => _ChatbotScreenState();
}

class _ChatbotScreenState extends State<ChatbotScreen> {
  static const Color primaryBlue = Color(0xFF1976D2);

  final TextEditingController _messageController = TextEditingController();

  final ScrollController _scrollController = ScrollController();

  bool _isOnline = true;
  StreamSubscription<bool>? _onlineSubscription;

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
  }

  @override
  void dispose() {
    _onlineSubscription?.cancel();
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  // =========================================================
  // SEND MESSAGE
  // =========================================================

  void _sendMessage() {
    final text = _messageController.text.trim();

    if (text.isEmpty) {
      return;
    }

    setState(() {
      _messages.add({'message': text, 'isUser': true});

      _messageController.clear();
    });

    _scrollToBottom();

    // Temporary chatbot response.
    // Replace this with your AI API/backend later.
    Future.delayed(const Duration(milliseconds: 700), () {
      if (!mounted) return;

      setState(() {
        _messages.add({'message': _generateResponse(text), 'isUser': false});
      });

      _scrollToBottom();
    });
  }

  // =========================================================
  // TEMPORARY AI RESPONSE
  // =========================================================

  String _generateResponse(String message) {
    final text = message.toLowerCase();
    final isGreeting = text.contains('hello') || text.contains('hi');

    if (!isGreeting && !_looksFinancial(text)) {
      return 'Sorry, I can only help with money questions, like budgeting, '
          'expenses, bills and savings. What would you like to know about '
          'your finances?';
    }

    if (!isGreeting && !_isOnline) {
      return "You're offline right now, so I can only share general tips. "
          'Reconnect for answers based on your own records.';
    }

    if (text.contains('budget')) {
      return 'A good starting point is to create a monthly budget based on your income and regular expenses. I can help you organize your spending into categories.';
    }

    if (text.contains('save') || text.contains('saving')) {
      return 'Try setting a specific monthly savings goal. Tracking your expenses can also help you identify areas where you can save.';
    }

    if (text.contains('expense') || text.contains('spending')) {
      return 'You can check your Expenses screen to review your transactions. I can also help you understand which categories are taking up most of your budget.';
    }

    if (text.contains('food')) {
      return 'Food expenses can add up quickly. Consider setting a weekly food budget and tracking each purchase.';
    }

    if (text.contains('hello') || text.contains('hi')) {
      return 'Hello! 👋 What would you like to know about your finances?';
    }

    return 'I understand. Once FinAssist is connected to the AI service, '
        "I'll be able to analyze your financial data and give you more "
        'personalized insights.';
  }

  // Keeps the assistant on finance topics until the real model is wired in.
  static const _financeWords = [
    'money',
    'peso',
    'budget',
    'save',
    'saving',
    'savings',
    'spend',
    'spending',
    'expense',
    'expenses',
    'income',
    'salary',
    'allowance',
    'bill',
    'bills',
    'pay',
    'payment',
    'debt',
    'loan',
    'goal',
    'wallet',
    'cash',
    'gcash',
    'maya',
    'bank',
    'transfer',
    'balance',
    'afford',
    'invest',
    'price',
    'cost',
    'financial',
    'finance',
    'baon',
    'gastos',
    'ipon',
    'utang',
    'sahod',
    'bayad',
    'pera',
  ];

  bool _looksFinancial(String text) {
    return _financeWords.any((word) => text.contains(word));
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
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(
                Icons.smart_toy_outlined,
                color: primaryBlue,
                size: 25,
              ),
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
              itemCount: _messages.length,
              itemBuilder: (context, index) {
                final message = _messages[index];

                return _messageBubble(
                  message: message['message'],
                  isUser: message['isUser'],
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
              const Icon(
                Icons.smart_toy_outlined,
                color: primaryBlue,
                size: 20,
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
    final questions = [
      'How can I save more money?',
      'Help me create a budget',
      'Where am I spending the most?',
      'How are my expenses doing?',
    ];

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(15, 0, 15, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Try asking:',
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey,
              fontWeight: FontWeight.w600,
            ),
          ),

          const SizedBox(height: 8),

          SizedBox(
            height: 38,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: questions.length,
              itemBuilder: (context, index) {
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ActionChip(
                    label: Text(questions[index]),

                    backgroundColor: context.appColors.primaryTint,

                    side: BorderSide.none,

                    labelStyle: TextStyle(
                      color: context.appColors.primaryText,
                      fontSize: 11,
                    ),

                    onPressed: () {
                      _messageController.text = questions[index];

                      _sendMessage();
                    },
                  ),
                );
              },
            ),
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
                    onPressed: _sendMessage,
                    icon: const Icon(Icons.send, color: Colors.white, size: 20),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// Small line above the input: what the assistant can answer, and a
  /// heads-up when the phone has no connection.
  Widget _inputNotice() {
    final offline = !_isOnline;

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
            offline
                ? "You're offline. FinAssist AI can only share general tips "
                      'until you reconnect.'
                : 'Finance questions only, like budgeting, expenses, bills '
                      'and savings.',
            style: const TextStyle(fontSize: 11, color: Colors.grey),
          ),
        ),
      ],
    );
  }

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
                    _messages.clear();

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
                    applicationIcon: const Icon(
                      Icons.smart_toy,
                      color: primaryBlue,
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
