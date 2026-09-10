import 'package:flutter/material.dart';

import '../widgets/voice_recognition_section.dart';

class VoiceRecognitionScreen extends StatefulWidget {
  const VoiceRecognitionScreen({this.autoStart = false, super.key});

  final bool autoStart;

  @override
  State<VoiceRecognitionScreen> createState() => _VoiceRecognitionScreenState();
}

class _VoiceRecognitionScreenState extends State<VoiceRecognitionScreen> {
  String _recognizedText = '';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Voice Recognition'),
        backgroundColor: const Color(0xFF1976D2),
        foregroundColor: Colors.white,
      ),
      backgroundColor: const Color(0xFFF6F8FC),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Offstage(
              child: VoiceRecognitionSection(
                autoStart: widget.autoStart,
                onTextRecognized: (text) =>
                    setState(() => _recognizedText = text),
              ),
            ),
            const Text(
              'Voice Result',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                ),
                child: Text(
                  _recognizedText.isEmpty
                      ? 'Your spoken expense description will appear here.'
                      : _recognizedText,
                  style: TextStyle(
                    color: _recognizedText.isEmpty
                        ? Colors.grey
                        : Colors.black87,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
