import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';

import '../models/chat_answers.dart';
import '../models/finance_snapshot.dart';
import '../services/finance_snapshot_service.dart';
import '../theme/app_buttons.dart';
import '../theme/app_colors.dart';
import '../widgets/goal_sheets.dart';

/// Reports whether the phone has a network connection, now and on change.
Stream<bool> _deviceOnlineStatus() async* {
  final connectivity = Connectivity();
  bool isOnline(List<ConnectivityResult> results) =>
      results.any((result) => result != ConnectivityResult.none);

  yield isOnline(await connectivity.checkConnectivity());
  yield* connectivity.onConnectivityChanged.map(isOnline);
}

class ChatbotScreen extends StatefulWidget {
  const ChatbotScreen({this.onlineStatus, this.records, super.key});

  /// Online/offline updates. Tests pass their own stream.
  final Stream<bool>? onlineStatus;

  /// The user's records to answer from. Tests pass their own.
  final Stream<FinanceSnapshot>? records;

  @override
  State<ChatbotScreen> createState() => _ChatbotScreenState();
}

class _ChatbotScreenState extends State<ChatbotScreen> {
  static const Color primaryBlue = Color(0xFF1976D2);

  final TextEditingController _messageController = TextEditingController();

  final ScrollController _scrollController = ScrollController();

  bool _isOnline = true;
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
    _recordsSubscription = (widget.records ?? watchFinanceSnapshot()).listen((
      records,
    ) {
      if (mounted) setState(() => _records = records);
    }, onError: (Object _) {});
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
    final text = (tapped ?? _messageController.text).trim();

    if (text.isEmpty) {
      return;
    }

    setState(() {
      _messages.add({'message': text, 'isUser': true});

      if (tapped == null) _messageController.clear();
    });

    _scrollToBottom();

    // A short pause, so the answer reads as a reply.
    Future.delayed(const Duration(milliseconds: 700), () {
      if (!mounted) return;

      final reply = answerChat(
        text,
        records: _records?.at(DateTime.now()),
        pending: _pending,
      );
      setState(() {
        _pending = reply.pending;
        _messages.add({
          'message': reply.text,
          'isUser': false,
          'choices': reply.choices,
          'goal': reply.goal,
        });
      });

      _scrollToBottom();
    });
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
              itemCount: _messages.length,
              itemBuilder: (context, index) {
                final message = _messages[index];
                final isUser = message['isUser'] as bool;
                final choices = message['choices'] as List<String>? ?? const [];
                final goal = message['goal'] as GoalOffer?;
                // Only the latest answer's quick replies still apply.
                final isLatest = index == _messages.length - 1;

                return Column(
                  crossAxisAlignment: isUser
                      ? CrossAxisAlignment.end
                      : CrossAxisAlignment.start,
                  children: [
                    _messageBubble(message: message['message'], isUser: isUser),
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
                    if (isLatest && choices.isNotEmpty && _messages.length > 1)
                      Padding(
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
                      ),
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

                    onPressed: () => _sendMessage(questions[index]),
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
                    tooltip: 'Send message',
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
                ? "You're offline. Answers use the records saved on this "
                      'phone.'
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
