import 'package:flutter/material.dart';

class ChatbotScreen extends StatefulWidget {
  const ChatbotScreen({super.key});

  @override
  State<ChatbotScreen> createState() => _ChatbotScreenState();
}

class _ChatbotScreenState extends State<ChatbotScreen> {
  static const Color primaryBlue = Color(0xFF1976D2);

  final TextEditingController _messageController = TextEditingController();

  final ScrollController _scrollController = ScrollController();

  final List<Map<String, dynamic>> _messages = [
    {
      'message':
          'Hello! I\'m Fin. How can I help you with your finances today?',
      'isUser': false,
    },
  ];

  @override
  void dispose() {
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

    return 'I understand. Once FinAssist is connected to the AI service, I\'ll be able to analyze your financial data and provide more personalized insights.';
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
      backgroundColor: const Color(0xFFF6F8FC),

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

            const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'FinAssist AI',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
                ),

                Text(
                  'Your financial assistant',
                  style: TextStyle(fontSize: 11, color: Colors.white70),
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
          color: isUser ? primaryBlue : Colors.white,

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
                  color: isUser ? Colors.white : Colors.black87,
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

                    backgroundColor: const Color(0xFFEAF3FB),

                    side: BorderSide.none,

                    labelStyle: const TextStyle(
                      color: primaryBlue,
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
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        decoration: const BoxDecoration(color: Colors.white),

        child: Row(
          children: [
            // Attachment button
            IconButton(
              onPressed: () {
                // Attachment functionality later
              },
              icon: const Icon(Icons.attach_file, color: Colors.grey),
            ),

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

                  hintStyle: const TextStyle(fontSize: 13, color: Colors.grey),

                  filled: true,

                  fillColor: const Color(0xFFF2F4F7),

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
      ),
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
