import 'dart:async';

import 'package:flutter/material.dart';

import '../models/voice_command.dart';
import '../models/wallet.dart';
import '../services/speech_input.dart';
import '../theme/app_buttons.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../utils/category_options.dart';
import '../utils/money_format.dart';
import '../widgets/found_details.dart';
import 'add_expense_screen.dart';
import 'income_waterfall_screen.dart';

/// Voice Entry: recognize a finance command, check what was heard, then open
/// the matching app flow. Nothing is saved here; the destination form is where
/// the user checks everything and saves.
class VoiceRecognitionScreen extends StatefulWidget {
  const VoiceRecognitionScreen({
    this.autoStart = false,
    this.input,
    this.wallets,
    this.onNavigate,
    this.onIncomeSaved,
    this.incomeScreenBuilder,
    super.key,
  });

  /// Starts listening as soon as the screen opens, as from Home's shortcut.
  final bool autoStart;

  /// Stands in for the microphone. Used by tests.
  final SpeechInput? input;

  /// Replaces the live wallet list on the expense form. Used by tests.
  final Stream<List<Wallet>>? wallets;

  /// Lets the app shell switch tabs or open another section.
  final ValueChanged<VoiceDestination>? onNavigate;

  /// Refreshes the home balance after voice-started income is saved.
  final VoidCallback? onIncomeSaved;

  /// Replaces the income destination in tests without Firebase.
  final IncomeWaterfallScreen Function({
    double? initialAmount,
    String? initialSource,
  })?
  incomeScreenBuilder;

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
    _holdTimer?.cancel();
    _pulse.dispose();
    super.dispose();
  }

  Future<void> _listen({bool stopOnSilence = true}) async {
    setState(() {
      _step = _Step.listening;
      _words = '';
      _problem = null;
    });
    _pulse.repeat();

    SpeechProblem? problem;
    try {
      problem = await _input.start(
        onWords: _onWords,
        onStopped: _onStopped,
        stopOnSilence: stopOnSilence,
      );
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

  /// A press shorter than this is a tap, which leaves listening on until the
  /// next tap. Anything longer is a hold, which ends when the finger lifts.
  /// Holding suits most people; tapping keeps the screen usable for anyone
  /// who cannot hold a button down, and is how a screen reader works it.
  static const _holdThreshold = Duration(milliseconds: 400);

  /// Whether this press started a listen. A press that only turned off a
  /// listen an earlier tap had left on has nothing to end on the way up.
  bool _pressBeganListening = false;

  /// Set once the press has lasted long enough to be a hold rather than a
  /// tap. A timer rather than a reading of the clock, so it keeps the same
  /// time as the rest of the screen and a test can move it along.
  bool _heldLongEnough = false;
  Timer? _holdTimer;

  /// Whether the mic is held right now, so the screen can say to let go
  /// rather than to tap again.
  bool _holding = false;

  void _onMicPressStart() {
    if (_step == _Step.listening) {
      // An earlier tap left listening on; this press turns it off.
      _pressBeganListening = false;
      _stop();
      return;
    }
    _pressBeganListening = true;
    _heldLongEnough = false;
    _holdTimer?.cancel();
    _holdTimer = Timer(_holdThreshold, () => _heldLongEnough = true);
    setState(() => _holding = true);
    // Letting go ends this listen, so a pause for thought must not.
    _listen(stopOnSilence: false);
  }

  void _onMicPressEnd() {
    _holdTimer?.cancel();
    _holdTimer = null;
    final held = _heldLongEnough;
    final began = _pressBeganListening;
    _heldLongEnough = false;
    _pressBeganListening = false;
    if (_holding) setState(() => _holding = false);
    if (began && held && _step == _Step.listening) _stop();
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

  VoiceCommand _command(Iterable<String> categories) =>
      interpretVoiceCommand(_words, categories: categories);

  void _cancelCommand() {
    setState(() {
      _words = '';
      _step = _Step.ready;
      _problem = null;
    });
  }

  /// Sends the recognized command to its existing app flow. Data-entry flows
  /// still require the user to check and save their details.
  Future<void> _useWords() async {
    final command = _command(availableCategoriesOf(context));
    switch (command.type) {
      case VoiceCommandType.expense:
        final guess = command.expense;
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (context) => AddExpenseScreen(
              initialAmount: guess.amount,
              initialCategory: guess.category,
              initialDescription: guess.description,
              wallets: widget.wallets,
            ),
          ),
        );
        return;
      case VoiceCommandType.income:
        final saved = await Navigator.pushReplacement<bool, void>(
          context,
          MaterialPageRoute(
            builder: (context) =>
                widget.incomeScreenBuilder?.call(
                  initialAmount: command.amount,
                  initialSource: command.incomeSource,
                ) ??
                IncomeWaterfallScreen(
                  initialAmount: command.amount,
                  initialSource: command.incomeSource,
                ),
          ),
        );
        if (saved == true && mounted) widget.onIncomeSaved?.call();
        return;
      case VoiceCommandType.navigation:
        final destination = command.destination;
        final onNavigate = widget.onNavigate;
        if (destination == null || onNavigate == null) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('This section is not available here.'),
            ),
          );
          return;
        }
        Navigator.pop(context);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          onNavigate(destination);
        });
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final listening = _step == _Step.listening;
    final command = _command(categoryOptions(context));
    final (title, message) = _texts(command);

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
                        if (_step == _Step.heard) ...[
                          _WordsCard(words: _words),
                          const SizedBox(height: 16),
                          _commandDetails(command),
                        ] else ...[
                          _MicButton(
                            listening: listening,
                            pulse: _pulse,
                            onPressStart: _onMicPressStart,
                            onPressEnd: _onMicPressEnd,
                            onToggle: listening ? _stop : () => _listen(),
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
                        onPressed: command.type == VoiceCommandType.navigation
                            ? _cancelCommand
                            : _listen,
                        style: openOutlineStyle(context, height: 52),
                        icon: Icon(
                          command.type == VoiceCommandType.navigation
                              ? Icons.close
                              : Icons.mic_none,
                        ),
                        label: Text(
                          command.type == VoiceCommandType.navigation
                              ? 'No, cancel'
                              : 'Try Again',
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: _useWords,
                        style: openButtonStyle(),
                        icon: Icon(
                          command.type == VoiceCommandType.navigation
                              ? command.destination ==
                                        VoiceDestination.scanReceipt
                                    ? Icons.document_scanner_outlined
                                    : Icons.open_in_new
                              : Icons.edit_note,
                        ),
                        label: Text(_actionLabel(command)),
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

  Widget _commandDetails(VoiceCommand command) {
    switch (command.type) {
      case VoiceCommandType.expense:
        return FoundDetails(guess: command.expense, center: true);
      case VoiceCommandType.income:
        return _CommandDetails(
          title: 'Ready to add income',
          detail: [
            if (command.amount != null) formatPeso(command.amount!),
            command.incomeSource ?? 'Income',
          ].join(' · '),
        );
      case VoiceCommandType.navigation:
        return _CommandDetails(
          title: command.destination == VoiceDestination.scanReceipt
              ? 'Would you like to scan a receipt?'
              : 'Would you like to open this section?',
          detail: _destinationLabel(command.destination),
        );
    }
  }

  String _actionLabel(VoiceCommand command) => switch (command.type) {
    VoiceCommandType.expense => 'Use This',
    VoiceCommandType.income => 'Continue',
    VoiceCommandType.navigation =>
      command.destination == VoiceDestination.scanReceipt
          ? 'Yes, Scan Receipt'
          : 'Yes, Open',
  };

  String _destinationLabel(VoiceDestination? destination) =>
      switch (destination) {
        VoiceDestination.home => 'Home',
        VoiceDestination.transactions => 'Transactions',
        VoiceDestination.bills => 'Bill Planner',
        VoiceDestination.wallet => 'Wallets',
        VoiceDestination.savings => 'Savings',
        VoiceDestination.debts => 'Debts',
        VoiceDestination.goals => 'Goals',
        VoiceDestination.reports => 'Reports',
        VoiceDestination.settings => 'Settings',
        VoiceDestination.scanReceipt => 'Scan Receipt',
        VoiceDestination.assistant => 'AI Assistant',
        VoiceDestination.expenseCategories => 'Expense Categories',
        VoiceDestination.financialPreferences =>
          'Income & Leftover Preferences',
        VoiceDestination.payCycleHistory => 'Pay-cycle History',
        VoiceDestination.reminders => 'Reminders',
        VoiceDestination.help => 'Help & Support',
        null => 'the selected section',
      };

  (String, String) _texts(VoiceCommand command) {
    return switch (_step) {
      _Step.ready => (
        'Say what you want to do',
        'Hold the mic and speak, then let go. You check the words before '
            'anything is saved or a section is opened.',
      ),
      _Step.listening => (
        'Listening…',
        _holding
            ? 'Keep holding, and let go when you are done.'
            : 'Speak now. Tap the mic again when you are done.',
      ),
      _Step.heard => (
        'Is this right?',
        switch (command.type) {
          VoiceCommandType.expense =>
            'Use This starts a new expense from what you said. You check '
                'everything before saving.',
          VoiceCommandType.income =>
            'Continue opens Add Income with these details filled in. Check '
                'everything before saving.',
          VoiceCommandType.navigation =>
            command.destination == VoiceDestination.scanReceipt
                ? 'Choose Yes to open the scanner, or No to cancel.'
                : 'Choose Yes to open ${_destinationLabel(command.destination)}, '
                      'or No to cancel.',
        },
      ),
      _Step.nothingHeard => (
        "Didn't catch that",
        'Hold the mic and try again, a little closer to the phone.',
      ),
      _Step.problem => switch (_problem) {
        SpeechProblem.noPermission => (
          'The microphone is off',
          "Allow the microphone for FinAssist in your phone's Settings, then "
              'hold the mic to try again.',
        ),
        SpeechProblem.unavailable => (
          "Voice entry isn't available",
          "Your phone can't turn speech into text right now. Try updating "
              'Speech Services by Google in the Play Store, or type the '
              'expense instead.',
        ),
        SpeechProblem.offline => (
          'No connection',
          'Speech recognition on this phone needs the internet. Try again when '
              "you're online, or type the expense instead.",
        ),
        _ => (
          'Something went wrong',
          'Voice entry stopped unexpectedly. Hold the mic to try again.',
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
    required this.onPressStart,
    required this.onPressEnd,
    required this.onToggle,
  });

  final bool listening;
  final Animation<double> pulse;

  /// The finger going down on the mic, and lifting off it. Held down is how
  /// speaking is meant to work, so these carry the press rather than a tap.
  final VoidCallback onPressStart;
  final VoidCallback onPressEnd;

  /// Starts or stops listening in one go. Only a screen reader reaches this;
  /// a finger goes through the press callbacks instead.
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final label = listening ? 'Stop listening' : 'Hold to speak';
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
          Semantics(
            button: true,
            label: label,
            onTap: onToggle,
            child: Tooltip(
              message: label,
              // Holding the mic is the whole gesture, so a long press must
              // not be taken as a request for the tooltip.
              triggerMode: TooltipTriggerMode.manual,
              // Raw touches rather than a tap: a tap is cancelled once the
              // finger drifts a few millimetres, which a thumb held on a
              // real phone while talking always does.
              child: Listener(
                onPointerDown: (_) => onPressStart(),
                onPointerUp: (_) => onPressEnd(),
                onPointerCancel: (_) => onPressEnd(),
                child: Container(
                  width: 96,
                  height: 96,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    color: appPrimaryBlue,
                  ),
                  child: Icon(
                    listening ? Icons.stop_rounded : Icons.mic,
                    size: 44,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
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
        for (final example in [
          '“Lunch at Jollibee, 150 pesos”',
          '“Add salary 500”',
          '“Open wallets”',
          '“Scan receipt”',
        ])
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text(
              example,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 17,
                fontStyle: FontStyle.italic,
                color: colors.textPrimary,
              ),
            ),
          ),
      ],
    );
  }
}

class _CommandDetails extends StatelessWidget {
  const _CommandDetails({required this.title, required this.detail});

  final String title;
  final String detail;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Column(
      children: [
        Text(title, style: TextStyle(fontSize: 12, color: colors.textBody)),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          decoration: BoxDecoration(
            color: colors.primaryTint,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(
            detail,
            style: TextStyle(
              fontWeight: FontWeight.w600,
              color: colors.primaryText,
            ),
          ),
        ),
      ],
    );
  }
}
