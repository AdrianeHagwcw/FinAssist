import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import '../models/wallet.dart';
import '../services/receipt_reader.dart';
import '../theme/app_buttons.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import 'add_expense_screen.dart';

/// Scan Receipt: take or pick a photo of a receipt, check the text read from
/// it, then carry the text into a new expense. Nothing is saved here; the
/// expense form is where the amount is added and the expense is saved.
class OcrScreen extends StatefulWidget {
  const OcrScreen({this.reader, this.wallets, super.key});

  /// Stands in for the camera and the text reading. Used by tests.
  final ReceiptReader? reader;

  /// Replaces the live wallet list on the expense form. Used by tests.
  final Stream<List<Wallet>>? wallets;

  @override
  State<OcrScreen> createState() => _OcrScreenState();
}

enum _Step { ready, reading, found, nothingFound, noCamera, failed }

class _OcrScreenState extends State<OcrScreen> {
  late final ReceiptReader _reader = widget.reader ?? ReceiptReader();

  _Step _step = _Step.ready;
  String _text = '';

  /// Where the last photo came from, so Retake goes back to the same place.
  ImageSource _source = ImageSource.camera;

  @override
  void dispose() {
    _reader.close();
    super.dispose();
  }

  Future<void> _scan(ImageSource source) async {
    _source = source;
    try {
      final path = await _reader.pickPhoto(source);
      // Backing out of the camera or gallery changes nothing.
      if (path == null || !mounted) return;

      setState(() => _step = _Step.reading);
      final text = await _reader.readText(path);
      if (!mounted) return;
      setState(() {
        _text = text;
        _step = text.isEmpty ? _Step.nothingFound : _Step.found;
      });
    } on PlatformException catch (error) {
      if (!mounted) return;
      setState(() {
        _step = error.code == 'camera_access_denied'
            ? _Step.noCamera
            : _Step.failed;
      });
    } catch (_) {
      if (mounted) setState(() => _step = _Step.failed);
    }
  }

  /// Opens a new expense with the receipt's text in its notes. The scan is
  /// finished, so saving or leaving the form goes back to where it began.
  void _useText() {
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (context) =>
            AddExpenseScreen(initialNotes: _text, wallets: widget.wallets),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Scan Receipt'),
        backgroundColor: appPrimaryBlue,
        foregroundColor: Colors.white,
      ),
      backgroundColor: context.appColors.pageBackground,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: switch (_step) {
            _Step.reading => const _Reading(),
            _Step.found => _found(),
            _ => _start(),
          },
        ),
      ),
    );
  }

  /// Before a scan, or after one that found nothing: what to do, and how.
  Widget _start() {
    final (title, message) = switch (_step) {
      _Step.nothingFound => (
        'No text found',
        'Make sure the whole receipt is in the photo, flat and in good light, '
            'then try again.',
      ),
      _Step.noCamera => (
        "Can't use the camera",
        "Allow the camera for FinAssist in your phone's Settings, or choose a "
            'photo from your gallery.',
      ),
      _Step.failed => (
        "Couldn't read that photo",
        'Try again, or choose a clearer photo from your gallery.',
      ),
      _ => (
        'Scan a receipt',
        'Take a photo and FinAssist reads the text for you. You check it, '
            'then add the expense.',
      ),
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _Intro(
                  title: title,
                  message: message,
                  problem: _step != _Step.ready,
                ),
                const SizedBox(height: 16),
                const _Tips(),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        ElevatedButton.icon(
          onPressed: () => _scan(ImageSource.camera),
          style: openButtonStyle(),
          icon: const Icon(Icons.photo_camera_outlined),
          label: const Text('Take Photo'),
        ),
        const SizedBox(height: 10),
        OutlinedButton.icon(
          onPressed: () => _scan(ImageSource.gallery),
          style: openOutlineStyle(context, height: 52),
          icon: const Icon(Icons.photo_library_outlined),
          label: const Text('Choose from Gallery'),
        ),
      ],
    );
  }

  /// The text that was read, to check before it goes into an expense.
  Widget _found() {
    final colors = context.appColors;
    final fromCamera = _source == ImageSource.camera;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Check the text',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: colors.textPrimary,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'It goes into the notes of a new expense. You add the amount and '
          'category, then save.',
          style: TextStyle(color: colors.textBody, height: 1.4),
        ),
        const SizedBox(height: 14),
        Expanded(
          child: Container(
            decoration: _cardDecoration(colors),
            child: Scrollbar(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: SelectableText(
                  _text,
                  style: TextStyle(color: colors.textBody, height: 1.45),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () => _scan(_source),
                style: openOutlineStyle(context, height: 52),
                icon: Icon(
                  fromCamera
                      ? Icons.photo_camera_outlined
                      : Icons.photo_library_outlined,
                ),
                label: Text(fromCamera ? 'Retake' : 'Choose Another'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: ElevatedButton.icon(
                onPressed: _useText,
                style: openButtonStyle(),
                icon: const Icon(Icons.edit_note),
                label: const Text('Use This'),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

BoxDecoration _cardDecoration(AppColors colors) {
  return BoxDecoration(
    color: colors.card,
    borderRadius: BorderRadius.circular(16),
    border: Border.all(color: colors.border),
  );
}

/// The heading card: the camera before a scan, a warning after a failed one.
class _Intro extends StatelessWidget {
  const _Intro({
    required this.title,
    required this.message,
    required this.problem,
  });

  final String title;
  final String message;
  final bool problem;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final warning = context.isDarkMode
        ? Colors.orange.shade300
        : Colors.orange.shade800;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: _cardDecoration(colors),
      child: Column(
        children: [
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              color: problem
                  ? warning.withValues(alpha: 0.14)
                  : colors.primaryTint,
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: problem
                ? Icon(Icons.info_outline, size: 36, color: warning)
                : Image.asset(
                    'assets/icons/icons8-camera-96.png',
                    width: 40,
                    height: 40,
                  ),
          ),
          const SizedBox(height: 16),
          Text(
            title,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: colors.textPrimary,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            message,
            textAlign: TextAlign.center,
            style: TextStyle(color: colors.textBody, height: 1.4),
          ),
        ],
      ),
    );
  }
}

/// Three short tips for a photo that reads well.
class _Tips extends StatelessWidget {
  const _Tips();

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    Widget tip(IconData icon, String text) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Row(
          children: [
            Icon(icon, size: 20, color: appPrimaryBlue),
            const SizedBox(width: 12),
            Expanded(
              child: Text(text, style: TextStyle(color: colors.textBody)),
            ),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      decoration: _cardDecoration(colors),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'For a clear scan',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: colors.textPrimary,
            ),
          ),
          const SizedBox(height: 12),
          tip(Icons.crop_free, 'Fit the whole receipt in the photo'),
          tip(Icons.wb_sunny_outlined, 'Use good light, without shadows'),
          tip(Icons.pan_tool_outlined, 'Lay it flat and hold the phone still'),
        ],
      ),
    );
  }
}

/// Shown while the text is being read.
class _Reading extends StatelessWidget {
  const _Reading();

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(
            width: 48,
            height: 48,
            child: CircularProgressIndicator(color: appPrimaryBlue),
          ),
          const SizedBox(height: 20),
          Text(
            'Reading your receipt…',
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.bold,
              color: colors.textPrimary,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'This happens on your phone, so no connection is needed.',
            textAlign: TextAlign.center,
            style: TextStyle(color: colors.textBody),
          ),
        ],
      ),
    );
  }
}
