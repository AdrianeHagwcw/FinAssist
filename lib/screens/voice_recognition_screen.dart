import 'package:flutter/material.dart';

import '../models/wallet.dart';
import '../services/speech_input.dart';
import '../theme/app_buttons.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import 'add_expense_screen.dart';

/// Voice Entry: say an expense, check the words, then carry them into a new
/// expense. Nothing is saved here; the expense form is where the amount is
/// added and the expense is saved.
class VoiceRecognitionScreen extends StatefulWidget {
  const VoiceRecognitionScreen({
    this.autoStart = false,
    this.input,
    this.wallets,
    super.key,
  });

  /// Starts listening as soon as the screen opens, as from Home's shortcut.
  final bool autoStart;

  /// Stands in for the microphone. Used by tests.
  final SpeechInput? input;

  /// Replaces the live wallet list on the expense form. Used by tests.
  final Stream<List<Wallet>>? wallets;

  @override
  State<VoiceRecognitionScreen> createState() => _VoiceRecognitionScreenState();
}

enum _Step { ready, listening, heard, nothingHeard, problem }

class _VoiceRecognitionScreenState extends State<VoiceRecognitionScreen>
    with SingleTickerProviderStateMixin {
  late final SpeechInput _input = widget.input ?? SpeechInput();

  // The ring that grows out of the mic while it listens.
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  );

  _Step _step = _Step.ready;
  String _words = '';
  SpeechProblem? _problem;

  @override
  void initState() {
    super.initState();
    if (widget.autoStart) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _listen();
      });
    }
  }

  @override
  void dispose() {
    if (_step == _Step.listening) _input.stop();
    _pulse.dispose();
    super.dispose();
  }

  Future<void> _listen() async {
    setState(() {
      _step = _Step.listening;
      _words = '';
      _problem = null;
    });
    _pulse.repeat();

    SpeechProblem? problem;
    try {
      problem = await _input.start(onWords: _onWords, onStopped: _onStopped);
    } catch (_) {
      problem = SpeechProblem.failed;
    }
    if (mounted && problem != null) _finish(problem);
  }

  /// The user is done talking: keep what was heard so far.
  Future<void> _stop() async {
    _finish(null);
    await _input.stop();
  }

  void _onWords(String words) {
    if (mounted && _step == _Step.listening) setState(() => _words = words);
  }

  void _onStopped(SpeechProblem? problem) {
    if (!mounted) return;
    if (_step == _Step.listening) {
      _finish(problem);
    } else if (_step == _Step.nothingHeard && problem != null) {
      // The reason arrived after the end: say it instead of "didn't catch it".
      _finish(problem);
    }
  }

  void _finish(SpeechProblem? problem) {
    _pulse
      ..stop()
      ..reset();
    setState(() {
      _problem = problem;
      _step = _words.trim().isNotEmpty
          ? _Step.heard
          : problem != null
          ? _Step.problem
          : _Step.nothingHeard;
    });
  }

  /// Opens a new expense with the words as its description. Voice entry is
  /// finished, so saving or leaving the form goes back to where it began.
  void _useWords() {
    final words = _words.trim();
    final description = words[0].toUpperCase() + words.substring(1);

    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (context) => AddExpenseScreen(
          initialDescription: description,
          wallets: widget.wallets,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final listening = _step == _Step.listening;
    final (title, message) = _texts();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Voice Entry'),
        backgroundColor: appPrimaryBlue,
        foregroundColor: Colors.white,
      ),
      backgroundColor: colors.pageBackground,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: Center(
                  child: SingleChildScrollView(
                    child: Column(
                      children: [
                        Text(
                          title,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                            color: colors.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          message,
                          textAlign: TextAlign.center,
                          style: TextStyle(color: colors.textBody, height: 1.4),
                        ),
                        const SizedBox(height: 28),
                        if (_step == _Step.heard)
                          _WordsCard(words: _words)
                        else ...[
                          _MicButton(
                            listening: listening,
                            pulse: _pulse,
                            onPressed: listening ? _stop : _listen,
                          ),
                          const SizedBox(height: 28),
                          if (listening)
                            _WordsCard(
                              words: _words.isEmpty
                                  ? 'Your words will show here'
                                  : _words,
                              live: true,
                            )
                          else if (_step != _Step.problem)
                            const _Example(),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
              if (_step == _Step.heard) ...[
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _listen,
                        style: openOutlineStyle(context, height: 52),
                        icon: const Icon(Icons.mic_none),
                        label: const Text('Try Again'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: _useWords,
                        style: openButtonStyle(),
                        icon: const Icon(Icons.edit_note),
                        label: const Text('Use This'),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  (String, String) _texts() {
    return switch (_step) {
      _Step.ready => (
        'Say what you spent',
        'Tap the mic and speak. You check the words before anything is saved.',
      ),
      _Step.listening => (
        'Listening…',
        'Speak now. It stops when you pause, or tap to stop.',
      ),
      _Step.heard => (
        'Is this right?',
        'It becomes the description of a new expense. You add the amount and '
            'category, then save.',
      ),
      _Step.nothingHeard => (
        "Didn't catch that",
        'Tap the mic and try again, a little closer to the phone.',
      ),
      _Step.problem => switch (_problem) {
        SpeechProblem.noPermission => (
          'The microphone is off',
          "Allow the microphone for FinAssist in your phone's Settings, then "
              'tap the mic to try again.',
        ),
        SpeechProblem.unavailable => (
          "Voice entry isn't available",
          "This phone can't recognise speech in its language. You can type "
              'the expense instead.',
        ),
        SpeechProblem.offline => (
          'No connection',
          'Speech recognition on this phone needs the internet. Try again when '
              "you're online, or type the expense instead.",
        ),
        _ => (
          'Something went wrong',
          'Voice entry stopped unexpectedly. Tap the mic to try again.',
        ),
      },
    };
  }
}

/// The big round mic. While listening it shows a stop square, and a ring
/// grows out of it so it is clear the phone is listening.
class _MicButton extends StatelessWidget {
  const _MicButton({
    required this.listening,
    required this.pulse,
    required this.onPressed,
  });

  final bool listening;
  final Animation<double> pulse;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 168,
      height: 168,
      child: Stack(
        alignment: Alignment.center,
        children: [
          if (listening)
            AnimatedBuilder(
              animation: pulse,
              builder: (context, _) {
                final grown = pulse.value;
                return Container(
                  width: 96 + 72 * grown,
                  height: 96 + 72 * grown,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: appPrimaryBlue.withValues(alpha: 0.3 * (1 - grown)),
                  ),
                );
              },
            ),
          IconButton.filled(
            onPressed: onPressed,
            tooltip: listening ? 'Stop listening' : 'Start speaking',
            iconSize: 44,
            style: IconButton.styleFrom(
              backgroundColor: appPrimaryBlue,
              foregroundColor: Colors.white,
              fixedSize: const Size(96, 96),
            ),
            icon: Icon(listening ? Icons.stop_rounded : Icons.mic),
          ),
        ],
      ),
    );
  }
}

/// What was heard: live while listening, then to check.
class _WordsCard extends StatelessWidget {
  const _WordsCard({required this.words, this.live = false});

  final String words;
  final bool live;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: colors.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colors.border),
      ),
      child: Text(
        words,
        textAlign: TextAlign.center,
        style: TextStyle(
          fontSize: live ? 18 : 22,
          fontWeight: FontWeight.w600,
          color: live ? colors.textBody : colors.textPrimary,
          height: 1.35,
        ),
      ),
    );
  }
}

/// An example of what to say, so the user knows what fits.
class _Example extends StatelessWidget {
  const _Example();

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    return Column(
      children: [
        Text(
          'For example',
          style: TextStyle(fontSize: 13, color: colors.textBody),
        ),
        const SizedBox(height: 6),
        Text(
          '“Lunch at Jollibee, 150 pesos”',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 17,
            fontStyle: FontStyle.italic,
            color: colors.textPrimary,
          ),
        ),
      ],
    );
  }
}
