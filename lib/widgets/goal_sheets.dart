import 'dart:async';

import 'package:flutter/material.dart';

import '../models/goal.dart';
import '../models/wallet.dart';
import '../services/goal_service.dart';
import '../services/wallet_service.dart';
import '../theme/app_buttons.dart';
import '../theme/app_colors.dart';
import '../utils/date_format.dart';
import '../utils/money_format.dart';
import '../utils/text_limits.dart';
import 'check_after_save.dart';
import 'dialog_kit.dart';
import 'goal_funding_picker.dart';

Future<T?> _showSheet<T>(BuildContext context, Widget child) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: context.appColors.card,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (context) => child,
  );
}

/// Adds a goal, or edits [existing]. [nextPriority] places a new goal last.
/// Returns true when it was saved.
Future<bool> showGoalFormSheet(
  BuildContext context, {
  Goal? existing,
  int nextPriority = 0,
  String? initialName,
  GoalKind initialKind = GoalKind.regular,
  double? initialTarget,
  DateTime? initialDate,
}) async {
  final saved = await _showSheet<bool>(
    context,
    GoalFormSheet(
      existing: existing,
      nextPriority: nextPriority,
      initialName: initialName,
      initialKind: initialKind,
      initialTarget: initialTarget,
      initialDate: initialDate,
    ),
  );
  return saved ?? false;
}

/// Sets money aside for a goal, or takes it back out when [takeOut] is true.
/// Returns true when money was set aside or taken out.
Future<bool> showContributionSheet(
  BuildContext context,
  Goal goal, {
  bool takeOut = false,
}) async {
  final saved = await _showSheet<bool>(
    context,
    ContributionSheet(goal: goal, takeOut: takeOut),
  );
  return saved ?? false;
}

/// The pull handle and title every goal sheet starts with.
class _SheetHeader extends StatelessWidget {
  const _SheetHeader(this.title);

  final String title;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Center(
          child: Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: colors.border,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: Text(
                title,
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: colors.textPrimary,
                ),
              ),
            ),
            // A visible way out: dragging a long sheet down only works from
            // the very top of it.
            IconButton(
              tooltip: 'Close',
              onPressed: () => Navigator.maybePop(context),
              icon: const Icon(Icons.close),
            ),
          ],
        ),
        const SizedBox(height: 8),
      ],
    );
  }
}

/// What the goal form would save, handed to tests instead of Firestore.
class GoalDraft {
  const GoalDraft({
    required this.name,
    required this.kind,
    required this.targetAmount,
    required this.alreadySaved,
    required this.targetDate,
    required this.frequency,
    required this.planAmount,
    required this.walletId,
    required this.fundingSource,
    required this.note,
    this.customInterval,
    this.savedByWallet = const {},
  });

  final String name;
  final GoalKind kind;
  final double targetAmount;

  /// Everything in [savedByWallet] together.
  final double alreadySaved;
  final DateTime? targetDate;
  final ContributionFrequency frequency;

  /// The rhythm typed under Custom; null for the presets.
  final SavingInterval? customInterval;
  final double? planAmount;
  final String? walletId;
  final GoalFundingSource? fundingSource;
  final String? note;

  /// Money already saved, by the wallet it is in.
  final Map<String, double> savedByWallet;
}

class GoalFormSheet extends StatefulWidget {
  const GoalFormSheet({
    this.existing,
    this.nextPriority = 0,
    this.initialName,
    this.initialKind = GoalKind.regular,
    this.initialTarget,
    this.initialDate,
    this.wallets,
    this.goals,
    this.today,
    this.allowAlreadySaved = true,
    this.editsFunding = false,
    this.initialFunding = const {},
    this.onRelease,
    this.onSave,
    super.key,
  });

  final Goal? existing;
  final int nextPriority;

  /// A name to start with, such as one picked from the savings guide.
  final String? initialName;
  final GoalKind initialKind;

  /// A target and date to start with, such as a price the assistant was
  /// asked about.
  final double? initialTarget;
  final DateTime? initialDate;

  /// Replaces the live wallet list. Used by tests.
  final Stream<List<Wallet>>? wallets;

  /// Replaces the live goals, read to see what they already claim. Used by
  /// tests.
  final Stream<List<Goal>>? goals;
  final DateTime? today;
  final bool allowAlreadySaved;

  /// Whether editing changes the money set aside too. Only setup does: one
  /// Edit there covers the goal and its money. After setup, money moves in
  /// and out of a goal through contributions, so its history stays right.
  final bool editsFunding;

  /// What is set aside already, by wallet id, when [editsFunding].
  final Map<String, double> initialFunding;

  /// Takes everything set aside back out. Shown as a red button under Save
  /// when there is something to release; the sheet closes first.
  final VoidCallback? onRelease;

  /// Replaces saving. Used by tests.
  final void Function(GoalDraft draft)? onSave;

  @override
  State<GoalFormSheet> createState() => _GoalFormSheetState();
}

class _GoalFormSheetState extends State<GoalFormSheet> with CheckAfterSave {
  late final Goal? _existing = widget.existing;
  late final DateTime _today = widget.today ?? DateTime.now();

  late final Stream<List<Wallet>> _wallets =
      widget.wallets ?? WalletService.watchWallets();

  StreamSubscription<List<Goal>>? _goalsSub;
  List<Goal> _goals = const [];

  /// Whether this sheet sets the money already saved: a new goal, or one
  /// being edited in setup.
  bool get _editsFunding =>
      widget.allowAlreadySaved && (!_isEditing || widget.editsFunding);

  /// Only an amount already saved has to be checked against the goals, so
  /// nothing else pays the cost of reading them.
  bool get _needsGoals => _editsFunding;

  /// Money already saved, by the wallet it is in: cash, accounts, or both.
  late Map<String, double> _funding = widget.initialFunding;

  late final _nameController = TextEditingController(
    text: _existing?.name ?? widget.initialName ?? '',
  );
  late final _targetController = TextEditingController(
    text: _existing != null
        ? formatAmountInput(_existing.targetAmount)
        : widget.initialTarget == null
        ? ''
        : formatAmountInput(widget.initialTarget!),
  );
  // A goal is planned by the calendar: the finish date decides how much a
  // month, shown on its card once it is set up. Goals saved with a rhythm or
  // an amount each time before keep them.
  late final ContributionFrequency _frequency =
      _existing?.frequency ?? ContributionFrequency.monthly;
  late final SavingInterval? _custom = _existing?.customInterval;
  late final double? _planAmount = _existing?.planAmount;
  late DateTime? _date = _existing?.targetDate ?? widget.initialDate;

  bool get _isEditing => _existing != null;

  /// What the goal is for, read from its name instead of asked: it only
  /// changes the icon and the money tips, so a name that mentions an
  /// emergency makes an emergency fund. A kind given by the savings guide,
  /// or saved on the goal before, is kept.
  GoalKind get _kind {
    final given = _existing?.kind ?? widget.initialKind;
    if (given != GoalKind.regular) return given;
    return _nameController.text.toLowerCase().contains('emergency')
        ? GoalKind.emergencyFund
        : GoalKind.regular;
  }

  @override
  void initState() {
    super.initState();
    // The preview and suggestion follow every keystroke.
    for (final controller in [_nameController, _targetController]) {
      controller.addListener(_refresh);
    }
    if (_needsGoals) {
      final stream = widget.goals ?? GoalService.watchGoals();
      _goalsSub = stream.listen((goals) {
        if (mounted) setState(() => _goals = goals);
      });
    }
  }

  void _refresh() => setState(() {});

  @override
  void dispose() {
    _goalsSub?.cancel();
    for (final controller in [_nameController, _targetController]) {
      controller
        ..removeListener(_refresh)
        ..dispose();
    }
    super.dispose();
  }

  double _number(TextEditingController controller) =>
      double.tryParse(controller.text.trim().replaceAll(',', '')) ?? 0;

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date ?? DateTime(_today.year, _today.month + 6, _today.day),
      firstDate: DateTime(_today.year, _today.month, _today.day),
      lastDate: DateTime(_today.year + 20),
    );
    if (picked != null) setState(() => _date = picked);
  }

  /// What stops the goal being saved as it stands, or null. Shown once Save
  /// has been tapped, and gone as soon as it is fixed.
  String? _problem(List<Wallet> wallets) {
    final target = _number(_targetController);
    return itemNameProblem(
          cleanText(_nameController.text),
          maxLength: maxItemNameLength,
          empty: 'Give the goal a name.',
        ) ??
        (!isRecordableAmount(target)
            ? minimumAmountError
            : goalFundingProblem(
                amounts: _editsFunding ? _funding : const <String, double>{},
                wallets: wallets,
                otherGoals: _goals,
                target: target,
              ));
  }

  void _save(List<Wallet> wallets) {
    markTriedToSave();
    if (_problem(wallets) != null) return;

    final name = cleanText(_nameController.text);
    final target = _number(_targetController);
    final funding = _editsFunding ? _funding : const <String, double>{};
    final saved = funding.values.fold<double>(
      0,
      (total, amount) => total + amount,
    );

    final draft = GoalDraft(
      name: name,
      kind: _kind,
      targetAmount: target,
      alreadySaved: saved,
      targetDate: _date,
      frequency: _frequency,
      customInterval: _custom,
      planAmount: _planAmount,
      walletId: _isEditing && !_editsFunding
          ? _existing!.walletId
          : mainFundingWallet(funding),
      fundingSource: _isEditing && !_editsFunding
          ? _existing!.fundingSource
          : GoalFundingSource.fromTypes([
              for (final wallet in wallets)
                if (funding.containsKey(wallet.id)) wallet.type,
            ]),
      // Notes are no longer asked here; one saved before is kept.
      note: _existing?.note,
      savedByWallet: funding,
    );

    if (widget.onSave != null) {
      widget.onSave!(draft);
    } else if (_isEditing) {
      GoalService.updateGoal(
        _existing!,
        name: draft.name,
        targetAmount: draft.targetAmount,
        targetDate: draft.targetDate,
        kind: draft.kind,
        frequency: draft.frequency,
        customInterval: draft.customInterval,
        planAmount: draft.planAmount,
        walletId: draft.walletId,
        note: draft.note,
      );
    } else {
      GoalService.addGoal(
        name: draft.name,
        targetAmount: draft.targetAmount,
        targetDate: draft.targetDate,
        priority: widget.nextPriority,
        kind: draft.kind,
        frequency: draft.frequency,
        customInterval: draft.customInterval,
        planAmount: draft.planAmount,
        walletId: draft.walletId,
        fundingSource: draft.fundingSource,
        note: draft.note,
        alreadySavedByWallet: draft.savedByWallet,
      );
    }

    Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    Widget sectionTitle(String text) => Padding(
      padding: const EdgeInsets.only(top: 20, bottom: 10),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.bold,
          color: colors.textPrimary,
        ),
      ),
    );

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
          child: StreamBuilder<List<Wallet>>(
            stream: _wallets,
            builder: (context, snapshot) {
              final wallets = snapshot.data ?? const <Wallet>[];
              final error = triedToSave ? _problem(wallets) : null;

              return Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _SheetHeader(_isEditing ? 'Edit Goal' : 'New Savings Goal'),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _nameController,
                    textCapitalization: TextCapitalization.sentences,
                    maxLength: maxItemNameLength,
                    inputFormatters: const [SafeTextFormatter()],
                    // The count only matters near the limit.
                    buildCounter:
                        (
                          context, {
                          required currentLength,
                          required isFocused,
                          maxLength,
                        }) =>
                            maxLength != null && maxLength - currentLength <= 10
                            ? Text('$currentLength/$maxLength')
                            : null,
                    decoration: dialogFieldDecoration(
                      context,
                      'Goal name',
                      hint: 'e.g. New laptop',
                    ),
                  ),
                  const SizedBox(height: 16),
                  AmountField(
                    controller: _targetController,
                    label: 'Amount needed',
                    hint: 'e.g. 20,000',
                    autofocus: false,
                  ),
                  const SizedBox(height: 16),
                  InkWell(
                    onTap: _pickDate,
                    borderRadius: BorderRadius.circular(12),
                    child: InputDecorator(
                      decoration: dialogFieldDecoration(
                        context,
                        'Finish by (optional)',
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              _date == null
                                  ? 'No date'
                                  : formatShortDate(_date!),
                            ),
                          ),
                          if (_date != null)
                            IconButton(
                              tooltip: 'Remove date',
                              visualDensity: VisualDensity.compact,
                              icon: const Icon(Icons.close, size: 18),
                              onPressed: () => setState(() => _date = null),
                            )
                          else
                            Image.asset(
                              'assets/icons/icons8-calendar-96.png',
                              width: 22,
                              height: 22,
                            ),
                        ],
                      ),
                    ),
                  ),
                  if (_editsFunding) ...[
                    sectionTitle('Already saved some? (optional)'),
                    WalletSplitPicker(
                      // Keyed, so a line appearing above never resets the choice.
                      key: const ValueKey('goal-funding-picker'),
                      wallets: wallets,
                      goals: _goals,
                      target: _number(_targetController),
                      initialAmounts: widget.initialFunding,
                      onChanged: (amounts) =>
                          setState(() => _funding = amounts),
                    ),
                    if (wallets.any((wallet) => wallet.isLockedSavings)) ...[
                      const SizedBox(height: 8),
                      const DialogNote(
                        text:
                            'A time deposit can be set aside for a goal. It '
                            'counts now and is ready on its end date.',
                      ),
                    ],
                  ],
                  const SizedBox(height: 16),
                  const SizedBox(height: 4),
                  if (error != null) ...[
                    Text(
                      error,
                      style: TextStyle(
                        color: dangerColorOn(context),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 10),
                  ],
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () => _save(wallets),
                      style: confirmButtonStyle(),
                      child: Text(
                        _isEditing ? 'Save Changes' : 'Save Goal',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                  // Red and below Save: it takes the money back out, so it
                  // must never be the button the eye lands on first.
                  if (_isEditing &&
                      widget.onRelease != null &&
                      widget.initialFunding.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: () {
                          Navigator.pop(context, false);
                          widget.onRelease!();
                        },
                        style: dangerButtonStyle(),
                        child: const Text(
                          'Release what is set aside',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class ContributionSheet extends StatefulWidget {
  const ContributionSheet({
    required this.goal,
    this.takeOut = false,
    this.wallets,
    this.goals,
    this.onSave,
    super.key,
  });

  final Goal goal;

  /// Taking money back out of the goal instead of setting more aside.
  final bool takeOut;

  /// Replaces the live wallet list. Used by tests.
  final Stream<List<Wallet>>? wallets;

  /// Replaces the live goals when checking unassigned Savings wallet money.
  final Stream<List<Goal>>? goals;

  /// Replaces saving; the amount is negative when taking out. Used by tests.
  final void Function(double amount, String walletId)? onSave;

  @override
  State<ContributionSheet> createState() => _ContributionSheetState();
}

class _ContributionSheetState extends State<ContributionSheet>
    with CheckAfterSave {
  late final Stream<List<Wallet>> _wallets =
      widget.wallets ?? WalletService.watchWallets();
  late final Stream<List<Goal>> _goals =
      widget.goals ?? GoalService.watchGoals();

  /// How much comes from each account, or is taken out of each, by wallet
  /// id. Several accounts can share one, as when a goal is made.
  Map<String, double> _funding = const {};

  /// Saving toward the goal, laid out like the goal sheet: where the money
  /// is now (cash on hand, cash in bank or both), an amount for each
  /// account, and the total with what is still to save.
  Widget _saveLayout(List<Wallet> wallets, List<Goal> goals) {
    final goal = widget.goal;
    final colors = context.appColors;
    final error = triedToSave ? _fundingProblem(wallets, goals) : null;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SheetHeader('Save toward ${goal.name}'),
        Text(
          '${formatPeso(goal.shownSaved)} of ${formatPeso(goal.targetAmount)} '
          'saved · ${formatPeso(goal.remaining)} to go',
          style: TextStyle(fontSize: 14, color: colors.textMuted),
        ),
        const SizedBox(height: 10),
        const DialogNote(
          text:
              'The money stays in its account and is marked for this goal. '
              'Nothing moves.',
        ),
        const SizedBox(height: 16),
        WalletSplitPicker(
          // Keyed, so a line appearing above never resets the choice.
          key: const ValueKey('contribution-funding'),
          wallets: wallets,
          goals: goals,
          target: goal.remaining,
          onChanged: (amounts) => setState(() => _funding = amounts),
        ),
        if (error != null) ...[
          const SizedBox(height: 10),
          Text(
            error,
            style: TextStyle(
              color: dangerColorOn(context),
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
        const SizedBox(height: 20),
        SizedBox(
          width: double.infinity,
          height: 52,
          child: ElevatedButton(
            onPressed: () => _saveFromAccounts(wallets, goals),
            style: confirmButtonStyle(),
            child: const Text(
              'Set Aside',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
          ),
        ),
      ],
    );
  }

  /// What stops the amounts chosen being saved, each checked against what
  /// its account has free, or null.
  String? _fundingProblem(List<Wallet> wallets, List<Goal> goals) =>
      _funding.isEmpty
      ? 'Choose where the money is and enter an amount.'
      : goalFundingProblem(
          amounts: _funding,
          wallets: wallets,
          // Every goal's claim counts, this one's too: the money being
          // added must still be free.
          otherGoals: goals,
          target: widget.goal.remaining,
        );

  /// Saving from the accounts chosen.
  void _saveFromAccounts(List<Wallet> wallets, List<Goal> goals) {
    final goal = widget.goal;
    markTriedToSave();
    if (_fundingProblem(wallets, goals) != null) return;

    if (widget.onSave != null) {
      for (final entry in _funding.entries) {
        widget.onSave!(entry.value, entry.key);
      }
    } else {
      GoalService.contributeFromWallets(goal, _funding);
    }
    Navigator.pop(context, true);
  }

  /// What this goal holds in each account: the most each can give back.
  Map<String, double> _heldByWallet(List<Wallet> wallets) => {
    for (final wallet in goalFundingWallets(wallets))
      if (goalMoneyInWallet([widget.goal], wallet.id) > 0.005)
        wallet.id: goalMoneyInWallet([widget.goal], wallet.id),
  };

  /// What stops the money being taken out, or null.
  String? _takeOutProblem(List<Wallet> wallets, List<Goal> goals) =>
      _funding.isEmpty
      ? 'Choose where the money is and enter an amount.'
      : walletSplitProblem(
          purpose: SplitPurpose.giving,
          amounts: _funding,
          wallets: wallets,
          goals: goals,
          limits: _heldByWallet(wallets),
          tooMuchMessage: _takeOutTooMuch,
        );

  String _takeOutTooMuch(Wallet wallet, double room) =>
      'Only ${formatPeso(room)} of this goal is in ${wallet.name}.';

  void _takeOut(List<Wallet> wallets, List<Goal> goals) {
    markTriedToSave();
    if (_takeOutProblem(wallets, goals) != null) return;

    if (widget.onSave != null) {
      for (final entry in _funding.entries) {
        widget.onSave!(-entry.value, entry.key);
      }
    } else {
      GoalService.takeOutFromWallets(widget.goal, _funding);
    }
    Navigator.pop(context, true);
  }

  /// Taking money out of the goal: from which accounts, each only up to
  /// what this goal holds there. The money stays where it is.
  Widget _takeOutLayout(List<Wallet> wallets, List<Goal> goals) {
    final goal = widget.goal;
    final error = triedToSave ? _takeOutProblem(wallets, goals) : null;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SheetHeader('Take money out of ${goal.name}'),
        const DialogNote(
          text:
              'It is no longer reserved for this goal. The money stays in '
              'its current account.',
        ),
        const SizedBox(height: 16),
        WalletSplitPicker(
          key: const ValueKey('take-out-from'),
          wallets: wallets,
          goals: goals,
          purpose: SplitPurpose.giving,
          question: 'Which accounts is it in?',
          limits: _heldByWallet(wallets),
          tooMuchMessage: _takeOutTooMuch,
          totalLabel: 'Taking out',
          onChanged: (amounts) => setState(() => _funding = amounts),
        ),
        if (error != null) ...[
          const SizedBox(height: 10),
          Text(
            error,
            style: TextStyle(
              color: dangerColorOn(context),
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
        const SizedBox(height: 20),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: () => _takeOut(wallets, goals),
            style: dangerButtonStyle(),
            child: const Text(
              'Take It Out',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
          child: StreamBuilder<List<Wallet>>(
            stream: _wallets,
            builder: (context, snapshot) {
              final wallets = snapshot.data ?? const <Wallet>[];
              return StreamBuilder<List<Goal>>(
                stream: _goals,
                builder: (context, goalsSnapshot) {
                  final goals = goalsSnapshot.data ?? [widget.goal];
                  return widget.takeOut
                      ? _takeOutLayout(wallets, goals)
                      : _saveLayout(wallets, goals);
                },
              );
            },
          ),
        ),
      ),
    );
  }
}
