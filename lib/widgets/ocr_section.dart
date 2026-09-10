import 'dart:io';

import 'package:flutter/material.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image_picker/image_picker.dart';

class OcrSection extends StatefulWidget {
  const OcrSection({
    required this.onTextRecognized,
    this.autoStart = false,
    super.key,
  });

  final ValueChanged<String> onTextRecognized;
  final bool autoStart;

  @override
  State<OcrSection> createState() => _OcrSectionState();
}

class _OcrSectionState extends State<OcrSection> {
  final ImagePicker _picker = ImagePicker();
  final TextRecognizer _recognizer = TextRecognizer();
  bool _isScanning = false;

  @override
  void initState() {
    super.initState();
    if (widget.autoStart) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _scanReceipt();
      });
    }
  }

  Future<void> _scanReceipt() async {
    final image = await _picker.pickImage(source: ImageSource.camera);
    if (image == null || !mounted) return;

    setState(() => _isScanning = true);
    try {
      final inputImage = InputImage.fromFile(File(image.path));
      final result = await _recognizer.processImage(inputImage);
      final text = result.text.trim();

      if (text.isEmpty) {
        throw StateError('No readable text found on the receipt.');
      }
      widget.onTextRecognized(text);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not scan receipt: $error')),
        );
      }
    } finally {
      if (mounted) setState(() => _isScanning = false);
    }
  }

  @override
  void dispose() {
    _recognizer.close();
    super.dispose();
  }

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
          const Icon(
            Icons.document_scanner_outlined,
            color: Color(0xFF1976D2),
            size: 28,
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Receipt OCR',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                SizedBox(height: 4),
                Text(
                  'Scan a receipt and review the extracted text.',
                  style: TextStyle(color: Colors.grey),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Scan receipt',
            onPressed: _isScanning ? null : _scanReceipt,
            icon: _isScanning
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.camera_alt_outlined),
            color: const Color(0xFF1976D2),
          ),
        ],
      ),
    );
  }
}
