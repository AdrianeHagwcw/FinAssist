import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import '../models/expense_guess.dart';
import '../models/wallet.dart';
import '../services/receipt_reader.dart';
import '../theme/app_buttons.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../utils/category_options.dart';
import '../widgets/found_details.dart';
import 'add_expense_screen.dart';

/// Scan Receipt: take or pick a photo of a receipt, check the text read from
/// it and what was found in it, then carry it into a new expense. A receipt
/// too long for one photo is taken in parts and read as one. Nothing is
/// saved here; the expense form is where the user checks everything and
/// saves.
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

/// What a new photo is for.
enum _Photo { newReceipt, nextPart, redoLast }

class _OcrScreenState extends State<OcrScreen> {
  late final ReceiptReader _reader = widget.reader ?? ReceiptReader();

  _Step _step = _Step.ready;

  /// The text of each photo, top of the receipt first.
  final List<String> _parts = [];

  /// Which part came from the latest photo, so Retake redoes that one even
  /// when it was placed before others.
  int? _latest;

  /// The receipt's text: every part in order, without the lines repeated
  /// where one photo overlaps the next.
  String get _text => joinReceiptParts(_parts);

  /// Where the last photo came from, so Retake goes back to the same place.
  ImageSource _source = ImageSource.camera;

  @override
  void dispose() {
    _reader.close();
    super.dispose();
  }

  /// Reads a photo from [source] as a new receipt, as the receipt's next
  /// part, or in place of its last part.
  Future<void> _scan(
    ImageSource source, {
    _Photo use = _Photo.newReceipt,
  }) async {
    _source = source;
    // A photo added to a receipt that goes wrong leaves the parts read so
    // far, and says so, instead of starting over.
    final adding = use != _Photo.newReceipt;
    try {
      final path = await _reader.pickPhoto(source);
      // Backing out of the camera or gallery changes nothing.
      if (path == null || !mounted) return;

      setState(() => _step = _Step.reading);
      final text = await _reader.readText(path);
      if (!mounted) return;

      if (text.isEmpty) {
        if (adding) {
          setState(() => _step = _Step.found);
          _tell('No text found in that photo, so nothing changed.');
        } else {
          setState(() {
            _parts.clear();
            _step = _Step.nothingFound;
          });
        }
        return;
      }

      final redo = _latest ?? _parts.length - 1;
      // A photo of some other receipt, added by mistake, is asked about
      // first: each receipt is its own expense.
      if (adding) {
        final others = [
          for (var i = 0; i < _parts.length; i++)
            if (use == _Photo.nextPart || i != redo) _parts[i],
        ];
        final reason = anotherReceiptReason(others, text);
        if (reason != null) {
          setState(() => _step = _Step.found);
          if (!await _addAnyway(reason) || !mounted) return;
        }
      }

      final at = switch (use) {
        _Photo.newReceipt => 0,
        _Photo.nextPart => placeForPart(_parts, text),
        _Photo.redoLast => redo,
      };
      setState(() {
        switch (use) {
          case _Photo.newReceipt:
            _parts
              ..clear()
              ..add(text);
          case _Photo.nextPart:
            _parts.insert(at, text);
          case _Photo.redoLast:
            _parts[at] = text;
        }
        _latest = at;
        _step = _Step.found;
      });
      // Photos taken out of order are put in order, and the user is told.
      if (use == _Photo.nextPart && at < _parts.length - 1) {
        _tell(
          'Added as part ${at + 1}, where it fits. Use the arrows to change '
          'the order.',
        );
      }
    } on PlatformException catch (error) {
      if (!mounted) return;
      final noCamera = error.code == 'camera_access_denied';
      if (adding) {
        setState(() => _step = _Step.found);
        _tell(
          noCamera
              ? "Can't use the camera. Allow it for FinAssist in your phone's "
                    'Settings.'
              : "Couldn't read that photo. Try again.",
        );
      } else {
        setState(() => _step = noCamera ? _Step.noCamera : _Step.failed);
      }
    } catch (_) {
      if (!mounted) return;
      if (adding) {
        setState(() => _step = _Step.found);
        _tell("Couldn't read that photo. Try again.");
      } else {
        setState(() => _step = _Step.failed);
      }
    }
  }

  /// Asks before adding a photo that looks like it is from another receipt.
  Future<bool> _addAnyway(String reason) async {
    final add = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('A different receipt?'),
        content: Text(
          '$reason Each receipt is its own expense, so add only parts of '
          'this one.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            style: cancelTextStyle(context),
            child: const Text("Don't Add"),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: confirmTextStyle(context),
            child: const Text('Add Anyway'),
          ),
        ],
      ),
    );
    return add == true;
  }

  void _removePart(int index) {
    setState(() {
      _parts.removeAt(index);
      final latest = _latest;
      if (latest == index) {
        _latest = null;
      } else if (latest != null && latest > index) {
        _latest = latest - 1;
      }
    });
  }

  void _movePartUp(int index) {
    setState(() {
      _parts.insert(index - 1, _parts.removeAt(index));
      if (_latest == index) {
        _latest = index - 1;
      } else if (_latest == index - 1) {
        _latest = index;
      }
    });
  }

  void _tell(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  /// The receipt's text, turned into the total, store, category and date,
  /// suggesting only from [categories].
  ExpenseGuess _guess(List<String> categories) =>
      guessFromReceipt(_text, categories: categories);

  /// Opens a new expense started from the receipt, with its text in the
  /// notes. The scan is finished, so saving or leaving the form goes back to
  /// where it began.
  void _useText() {
    final guess = _guess(availableCategoriesOf(context));

    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (context) => AddExpenseScreen(
          initialAmount: guess.amount,
          initialCategory: guess.category,
          initialDescription: guess.description,
          initialDate: guess.date == null
              ? null
              : Timestamp.fromDate(guess.date!),
          initialNotes: _text,
          wallets: widget.wallets,
        ),
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
          'Use This starts a new expense from this receipt, with its text in '
          'the notes. You check everything before saving.',
          style: TextStyle(color: colors.textBody, height: 1.4),
        ),
        const SizedBox(height: 14),
        FoundDetails(guess: _guess(categoryOptions(context)), showStore: true),
        const SizedBox(height: 14),
        Expanded(
          child: Container(
            decoration: _cardDecoration(colors),
            child: Scrollbar(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (var i = 0; i < _parts.length; i++) ...[
                      if (i > 0) Divider(height: 24, color: colors.border),
                      if (_parts.length > 1)
                        _PartHeading(
                          number: i + 1,
                          onMoveUp: i == 0 ? null : () => _movePartUp(i),
                          onRemove: () => _removePart(i),
                        ),
                      SelectableText(
                        _parts[i],
                        style: TextStyle(color: colors.textBody, height: 1.45),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 16),
        OutlinedButton.icon(
          onPressed: () => _scan(_source, use: _Photo.nextPart),
          style: openOutlineStyle(context, height: 52),
          icon: Icon(
            fromCamera
                ? Icons.add_a_photo_outlined
                : Icons.add_photo_alternate_outlined,
          ),
          label: const Text('Add Next Part'),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                // With several parts, the one from the latest photo.
                onPressed: () => _scan(_source, use: _Photo.redoLast),
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

/// The name over one part of a long receipt, with ways to move it up and
/// to take it out.
class _PartHeading extends StatelessWidget {
  const _PartHeading({
    required this.number,
    required this.onMoveUp,
    required this.onRemove,
  });

  final int number;

  /// Null for the first part.
  final VoidCallback? onMoveUp;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    return Row(
      children: [
        Expanded(
          child: Text(
            'Part $number',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: colors.textPrimary,
            ),
          ),
        ),
        if (onMoveUp != null)
          IconButton(
            tooltip: 'Move part $number up',
            onPressed: onMoveUp,
            color: colors.textBody,
            icon: const Icon(Icons.arrow_upward, size: 20),
          ),
        IconButton(
          tooltip: 'Remove part $number',
          onPressed: onRemove,
          color: colors.textBody,
          icon: const Icon(Icons.close, size: 20),
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

    Widget tip(String icon, String text) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Row(
          children: [
            Image.asset('assets/icons/$icon', width: 22, height: 22),
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
          tip(
            'icons8-camera-96.png',
            'Fit it all in, or take a long one in parts',
          ),
          tip('icons8-idea-96.png', 'Use good light, without shadows'),
          tip(
            'icons8-mobile-payment-96.png',
            'Lay it flat and hold the phone still',
          ),
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
