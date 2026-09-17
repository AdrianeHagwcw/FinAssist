import 'package:flutter/material.dart';

import '../models/goal.dart';
import '../models/wallet.dart';
import '../services/goal_service.dart';
import '../services/wallet_service.dart';
import '../theme/app_buttons.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../utils/date_format.dart';
import '../utils/money_format.dart';
import 'dialog_kit.dart';
import 'wallet_picker.dart';

Future<T?> _showSheet<T>(BuildContext context, Widget child) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
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
}) async {
  final saved = await _showSheet<bool>(
    context,
    GoalFormSheet(
      existing: existing,
      nextPriority: nextPriority,
      initialName: initialName,
      initialKind: initialKind,
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

/// The + button's "Save to Goal": picks a goal, then sets money aside for it.
/// With one goal it goes straight to that goal; with none it offers to make
/// one. Returns true when something was saved.
Future<bool> showSaveToGoal(BuildContext context) async {
  final List<Goal> goals;
  try {
    goals = (await GoalService.watchGoals().first)
        .where((goal) => goal.status == GoalStatus.active && !goal.isReached)
        .toList();
  } catch (_) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Your goals could not be loaded.')),
      );
    }
    return false;
  }
  if (!context.mounted) return false;

  final picked = goals.length == 1
      ? goals.first
      : await _showSheet<Object>(context, GoalPickerSheet(goals: goals));
  if (!context.mounted || picked == null) return false;

  if (picked == GoalPickerSheet.newGoal) {
    return showGoalFormSheet(context, nextPriority: goals.length);
  }

  final goal = picked as Goal;
  final saved = await showContributionSheet(context, goal);
  if (saved && context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Saved toward ${goal.name}.'),
        backgroundColor: appConfirmGreen,
      ),
    );
  }
  return saved;
}

/// Lists the goals still being saved toward, to choose one to add to.
class GoalPickerSheet extends StatelessWidget {
  const GoalPickerSheet({required this.goals, super.key});

  final List<Goal> goals;

  /// Popped instead of a goal when the user wants to make a new one.
  static const Object newGoal = 'new goal';

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.8,
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const _SheetHeader('Save to which goal?'),
              if (goals.isEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: Text(
                    'You have no goals to save toward yet. Make one, and '
                    'you can start setting money aside for it.',
                    style: TextStyle(color: colors.textBody, height: 1.4),
                  ),
                ),
              for (final goal in goals) ...[
                Material(
                  color: colors.card,
                  borderRadius: BorderRadius.circular(12),
                  child: InkWell(
                    onTap: () => Navigator.pop(context, goal),
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: colors.border),
                      ),
                      child: Row(
                        children: [
                          Icon(goal.kind.icon, color: appPrimaryBlue),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  goal.name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontWeight: FontWeight.w600,
                                    color: colors.textPrimary,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(3),
                                  child: LinearProgressIndicator(
                                    value: goal.progress,
                                    minHeight: 5,
                                    backgroundColor: colors.track,
                                    color: appPrimaryBlue,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  '${formatPeso(goal.shownSaved)} of '
                                  '${formatPeso(goal.targetAmount)}',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: colors.textBody,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Icon(Icons.chevron_right, color: colors.textBody),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
              ],
              const SizedBox(height: 6),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () => Navigator.pop(context, newGoal),
                  style: openOutlineStyle(context),
                  icon: const Icon(Icons.add),
                  label: const Text('New Goal'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
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
        const SizedBox(height: 16),
        Text(
          title,
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: colors.textPrimary,
          ),
        ),
        const SizedBox(height: 16),
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
    required this.note,
  });

  final String name;
  final GoalKind kind;
  final double targetAmount;
  final double alreadySaved;
  final DateTime? targetDate;
  final ContributionFrequency frequency;
  final double? planAmount;
  final String? walletId;
  final String? note;
}

class GoalFormSheet extends StatefulWidget {
  const GoalFormSheet({
    this.existing,
    this.nextPriority = 0,
    this.initialName,
    this.initialKind = GoalKind.regular,
    this.wallets,
    this.today,
    this.onSave,
    super.key,
  });

  final Goal? existing;
  final int nextPriority;

  /// A name to start with, such as one picked from the savings guide.
  final String? initialName;
  final GoalKind initialKind;

  /// Replaces the live wallet list. Used by tests.
  final Stream<List<Wallet>>? wallets;
  final DateTime? today;

  /// Replaces saving. Used by tests.
  final void Function(GoalDraft draft)? onSave;

  @override
  State<GoalFormSheet> createState() => _GoalFormSheetState();
}

class _GoalFormSheetState extends State<GoalFormSheet> {
  late final Goal? _existing = widget.existing;
  late final DateTime _today = widget.today ?? DateTime.now();

  late final Stream<List<Wallet>> _wallets =
      widget.wallets ?? WalletService.watchWallets();

  late final _nameController = TextEditingController(
    text: _existing?.name ?? widget.initialName ?? '',
  );
  late final _targetController = TextEditingController(
    text: _existing == null ? '' : formatAmountInput(_existing.targetAmount),
  );
  final _savedController = TextEditingController();
  late final _planController = TextEditingController(
    text: _existing?.planAmount == null
        ? ''
        : formatAmountInput(_existing!.planAmount!),
  );
  late final _noteController = TextEditingController(
    text: _existing?.note ?? '',
  );

  late GoalKind _kind = _existing?.kind ?? widget.initialKind;
  late ContributionFrequency _frequency =
      _existing?.frequency ?? ContributionFrequency.monthly;
  late DateTime? _date = _existing?.targetDate;
  late String? _walletId = _existing?.walletId;
  String? _error;

  bool get _isEditing => _existing != null;

  @override
  void initState() {
    super.initState();
    // The preview and suggestion follow every keystroke.
    for (final controller in [
      _nameController,
      _targetController,
      _savedController,
      _planController,
    ]) {
      controller.addListener(_refresh);
    }
  }

  void _refresh() => setState(() {});

  @override
  void dispose() {
    for (final controller in [
      _nameController,
      _targetController,
      _savedController,
      _planController,
      _noteController,
    ]) {
      controller
        ..removeListener(_refresh)
        ..dispose();
    }
    super.dispose();
  }

  double _number(TextEditingController controller) =>
      double.tryParse(controller.text.trim().replaceAll(',', '')) ?? 0;

  /// Still to save, counting what is already saved.
  double get _remaining {
    final saved = _isEditing
        ? _existing!.shownSaved
        : _number(_savedController);
    final left = _number(_targetController) - saved;
    return left > 0 ? left : 0;
  }

  double? get _needed => neededPerContribution(
    remaining: _remaining,
    targetDate: _date,
    frequency: _frequency,
    now: _today,
  );

  double? get _planAmount {
    final amount = _number(_planController);
    return amount > 0 ? amount : null;
  }

  /// The one line that tells the user what their numbers mean.
  String? get _hint {
    if (_number(_targetController) <= 0) return null;
    if (_remaining <= 0) return 'Already reached with what you have saved.';

    final needed = _needed;
    if (needed != null) {
      final plan = _planAmount;
      final base =
          'Save ${formatPeso(needed)} ${_frequency.per} to reach it by '
          '${formatShortDate(_date!)}.';
      if (plan == null || plan + 0.005 >= needed) return base;
      return '$base Your planned ${formatPeso(plan)} is not enough to make '
          'that date.';
    }

    final reached = reachedByPlan(
      remaining: _remaining,
      amount: _planAmount,
      frequency: _frequency,
      now: _today,
    );
    if (reached != null) {
      return 'At ${formatPeso(_planAmount!)} ${_frequency.per} you reach it '
          'around ${formatShortDate(reached)}.';
    }

    return 'Add a target date or an amount to see how long it takes.';
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date ?? DateTime(_today.year, _today.month + 6, _today.day),
      firstDate: DateTime(_today.year, _today.month, _today.day),
      lastDate: DateTime(_today.year + 20),
    );
    if (picked != null) setState(() => _date = picked);
  }

  void _save(List<Wallet> wallets) {
    final name = _nameController.text.trim();
    final target = _number(_targetController);
    final saved = _isEditing ? 0.0 : _number(_savedController);
    final walletId = _walletId ?? defaultWalletId(wallets);

    final String? problem;
    if (name.isEmpty) {
      problem = 'Give the goal a name.';
    } else if (target <= 0) {
      problem = 'Enter how much you want to save.';
    } else if (saved > 0 && walletId == null) {
      problem = 'Add a wallet first, so your savings have somewhere to be.';
    } else {
      problem = null;
    }

    if (problem != null) {
      setState(() => _error = problem);
      return;
    }

    final draft = GoalDraft(
      name: name,
      kind: _kind,
      targetAmount: target,
      alreadySaved: saved,
      targetDate: _date,
      frequency: _frequency,
      planAmount: _planAmount,
      walletId: walletId,
      note: _noteController.text,
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
        planAmount: draft.planAmount,
        walletId: draft.walletId,
        note: draft.note,
        alreadySaved: draft.alreadySaved,
      );
    }

    Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final hint = _hint;

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

              return Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _SheetHeader(_isEditing ? 'Edit Goal' : 'New Savings Goal'),
                  _GoalPreview(
                    name: _nameController.text.trim(),
                    kind: _kind,
                    target: _number(_targetController),
                    needed: _needed,
                    frequency: _frequency,
                  ),
                  sectionTitle('Goal type'),
                  Wrap(
                    spacing: 8,
                    children: [
                      for (final kind in GoalKind.values)
                        ChoiceChip(
                          avatar: Icon(kind.icon, size: 18),
                          label: Text(kind.label),
                          selected: _kind == kind,
                          onSelected: (_) => setState(() => _kind = kind),
                        ),
                    ],
                  ),
                  sectionTitle('Details'),
                  TextField(
                    controller: _nameController,
                    textCapitalization: TextCapitalization.sentences,
                    maxLength: 40,
                    decoration: dialogFieldDecoration(
                      context,
                      'What are you saving for?',
                      hint: 'e.g. New laptop, Emergency fund',
                    ),
                  ),
                  const SizedBox(height: 8),
                  AmountField(
                    controller: _targetController,
                    label: 'Target amount',
                    autofocus: false,
                  ),
                  if (!_isEditing) ...[
                    const SizedBox(height: 16),
                    TextField(
                      controller: _savedController,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: dialogFieldDecoration(
                        context,
                        'Already saved (optional)',
                        helper:
                            'What you have put aside so far, so you '
                            'start above zero.',
                      ).copyWith(prefixText: '₱ ', hintText: '0.00'),
                    ),
                  ],
                  const SizedBox(height: 16),
                  InkWell(
                    onTap: _pickDate,
                    borderRadius: BorderRadius.circular(12),
                    child: InputDecorator(
                      decoration: dialogFieldDecoration(
                        context,
                        'Target date (optional)',
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              _date == null
                                  ? 'No deadline'
                                  : formatShortDate(_date!),
                            ),
                          ),
                          if (_date != null)
                            IconButton(
                              tooltip: 'Remove deadline',
                              visualDensity: VisualDensity.compact,
                              icon: const Icon(Icons.close, size: 18),
                              onPressed: () => setState(() => _date = null),
                            )
                          else
                            const Icon(Icons.calendar_today, size: 18),
                        ],
                      ),
                    ),
                  ),
                  sectionTitle('Saving plan'),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final frequency in ContributionFrequency.values)
                        ChoiceChip(
                          label: Text(frequency.label),
                          selected: _frequency == frequency,
                          onSelected: (_) =>
                              setState(() => _frequency = frequency),
                        ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _planController,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: dialogFieldDecoration(
                      context,
                      'Amount each time (optional)',
                    ).copyWith(prefixText: '₱ ', hintText: '0.00'),
                  ),
                  if (hint != null) ...[
                    const SizedBox(height: 12),
                    DialogNote(text: hint),
                  ],
                  if (wallets.isNotEmpty) ...[
                    sectionTitle('Wallet'),
                    WalletPicker(
                      wallets: wallets,
                      selectedId: _walletId ?? defaultWalletId(wallets),
                      label: 'Usually kept in',
                      onChanged: (value) => setState(() => _walletId = value),
                    ),
                  ],
                  const SizedBox(height: 16),
                  TextField(
                    controller: _noteController,
                    maxLength: 80,
                    decoration: dialogFieldDecoration(
                      context,
                      'Notes (optional)',
                    ),
                  ),
                  if (_error != null) ...[
                    Text(
                      _error!,
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
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

/// A live preview of the goal: its name, target, and what to save each time.
class _GoalPreview extends StatelessWidget {
  const _GoalPreview({
    required this.name,
    required this.kind,
    required this.target,
    required this.needed,
    required this.frequency,
  });

  final String name;
  final GoalKind kind;
  final double target;
  final double? needed;
  final ContributionFrequency frequency;

  @override
  Widget build(BuildContext context) {
    Widget chip(String value, String label) => Expanded(
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
            Text(
              label,
              style: const TextStyle(color: Colors.white70, fontSize: 11),
            ),
          ],
        ),
      ),
    );

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: appPrimaryBlue,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(kind.icon, color: Colors.white),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  name.isEmpty ? 'New goal' : name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              chip(target > 0 ? formatPeso(target) : '—', 'Target'),
              const SizedBox(width: 8),
              chip(
                needed == null ? '—' : formatPeso(needed!),
                'Need ${frequency.per}',
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class ContributionSheet extends StatefulWidget {
  const ContributionSheet({
    required this.goal,
    this.takeOut = false,
    this.wallets,
    this.onSave,
    super.key,
  });

  final Goal goal;

  /// Taking money back out of the goal instead of setting more aside.
  final bool takeOut;

  /// Replaces the live wallet list. Used by tests.
  final Stream<List<Wallet>>? wallets;

  /// Replaces saving; the amount is negative when taking out. Used by tests.
  final void Function(double amount, String walletId)? onSave;

  @override
  State<ContributionSheet> createState() => _ContributionSheetState();
}

class _ContributionSheetState extends State<ContributionSheet> {
  late final Stream<List<Wallet>> _wallets =
      widget.wallets ?? WalletService.watchWallets();

  late final _amountController = TextEditingController(
    // Suggests finishing the goal, which is the most common thing to do.
    text: widget.takeOut || widget.goal.remaining <= 0
        ? ''
        : formatAmountInput(widget.goal.remaining),
  );
  String? _walletId;
  String? _error;

  @override
  void dispose() {
    _amountController.dispose();
    super.dispose();
  }

  void _save(List<Wallet> wallets) {
    final amount = double.tryParse(
      _amountController.text.trim().replaceAll(',', ''),
    );
    final walletId = _walletId ?? defaultWalletId(wallets);
    final goal = widget.goal;

    final problem = amount == null || amount <= 0
        ? 'Enter an amount.'
        : walletId == null
        ? 'Add a wallet first.'
        : widget.takeOut && amount > goal.shownSaved + 0.005
        ? 'Only ${formatPeso(goal.shownSaved)} is set aside for this goal.'
        : null;

    if (problem != null) {
      setState(() => _error = problem);
      return;
    }

    final signed = widget.takeOut ? -amount! : amount!;

    if (widget.onSave != null) {
      widget.onSave!(signed, walletId!);
    } else {
      GoalService.contribute(goal, amount: signed, walletId: walletId!);
    }

    Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final goal = widget.goal;

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
          child: StreamBuilder<List<Wallet>>(
            stream: _wallets,
            builder: (context, snapshot) {
              final wallets = snapshot.data ?? const <Wallet>[];

              return Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _SheetHeader(
                    widget.takeOut
                        ? 'Take money out of ${goal.name}'
                        : 'Save toward ${goal.name}',
                  ),
                  DialogNote(
                    text: widget.takeOut
                        ? 'It becomes spendable again. Nothing moves between '
                              'wallets.'
                        : 'The money stays in the wallet you choose, marked as '
                              'set aside, so it stops counting as money you '
                              'can spend.',
                  ),
                  const SizedBox(height: 16),
                  AmountField(
                    controller: _amountController,
                    label: widget.takeOut ? 'Amount to take out' : 'Amount',
                  ),
                  const SizedBox(height: 16),
                  if (wallets.isNotEmpty)
                    WalletPicker(
                      wallets: wallets,
                      selectedId: _walletId ?? defaultWalletId(wallets),
                      label: widget.takeOut
                          ? 'From which wallet?'
                          : 'Kept in which wallet?',
                      onChanged: (value) => setState(() => _walletId = value),
                    ),
                  if (_error != null) ...[
                    const SizedBox(height: 10),
                    Text(
                      _error!,
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
                      onPressed: () => _save(wallets),
                      style: widget.takeOut
                          ? dangerButtonStyle()
                          : confirmButtonStyle(),
                      child: Text(
                        widget.takeOut ? 'Take It Out' : 'Set Aside',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}
