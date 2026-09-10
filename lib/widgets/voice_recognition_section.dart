import 'package:flutter/material.dart';
import 'package:speech_to_text/speech_to_text.dart' as speech;

class VoiceRecognitionSection extends StatefulWidget {
  const VoiceRecognitionSection({
    required this.onTextRecognized,
    this.autoStart = false,
    super.key,
  });

  final ValueChanged<String> onTextRecognized;
  final bool autoStart;

  @override
  State<VoiceRecognitionSection> createState() =>
      _VoiceRecognitionSectionState();
}

class _VoiceRecognitionSectionState extends State<VoiceRecognitionSection> {
  final speech.SpeechToText _speech = speech.SpeechToText();
  bool _isListening = false;

  @override
  void initState() {
    super.initState();
    if (widget.autoStart) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _toggleListening();
      });
    }
  }

  Future<void> _toggleListening() async {
    if (_isListening) {
      await _speech.stop();
      if (mounted) setState(() => _isListening = false);
      return;
    }

    final available = await _speech.initialize(
      onStatus: (status) {
        if (mounted && status == 'done') {
          setState(() => _isListening = false);
        }
      },
      onError: (_) {
        if (mounted) setState(() => _isListening = false);
      },
    );

    if (!available) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Speech recognition is unavailable.')),
        );
      }
      return;
    }

    await _speech.listen(
      onResult: (result) {
        if (result.recognizedWords.isNotEmpty) {
          widget.onTextRecognized(result.recognizedWords);
        }
      },
    );

    if (mounted) setState(() => _isListening = true);
  }

  @override
  void dispose() {
    _speech.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _FeatureSection(
      title: 'Voice Recognition',
      description: 'Speak an expense description instead of typing it.',
      icon: _isListening ? Icons.mic : Icons.mic_none,
      buttonLabel: _isListening ? 'Stop listening' : 'Start speaking',
      onPressed: _toggleListening,
      isActive: _isListening,
    );
  }
}

class _FeatureSection extends StatelessWidget {
  const _FeatureSection({
    required this.title,
    required this.description,
    required this.icon,
    required this.buttonLabel,
    required this.onPressed,
    this.isActive = false,
  });

  final String title;
  final String description;
  final IconData icon;
  final String buttonLabel;
  final VoidCallback onPressed;
  final bool isActive;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Row(
        children: [
          Icon(icon, color: const Color(0xFF1976D2), size: 28),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 4),
                Text(description, style: const TextStyle(color: Colors.grey)),
              ],
            ),
          ),
          IconButton(
            tooltip: buttonLabel,
            onPressed: onPressed,
            icon: Icon(
              isActive ? Icons.stop_circle_outlined : Icons.play_arrow,
            ),
            color: const Color(0xFF1976D2),
          ),
        ],
      ),
    );
  }
}
