import 'package:flutter/material.dart';

import '../models/goal.dart';
import '../models/wallet.dart';
import '../services/goal_service.dart';
import '../services/wallet_service.dart';
import '../theme/app_buttons.dart';
import '../theme/app_colors.dart';
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
Future<void> showGoalFormSheet(
  BuildContext context, {
  Goal? existing,
  int nextPriority = 0,
  String? initialName,
}) {
  return _showSheet(
    context,
    GoalFormSheet(
      existing: existing,
      nextPriority: nextPriority,
      initialName: initialName,
    ),
  );
}

/// Sets money aside for a goal, or takes it back out when [takeOut] is true.
Future<void> showContributionSheet(
  BuildContext context,
  Goal goal, {
  bool takeOut = false,
}) {
  return _showSheet(context, ContributionSheet(goal: goal, takeOut: takeOut));
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

class GoalFormSheet extends StatefulWidget {
  const GoalFormSheet({
    this.existing,
    this.nextPriority = 0,
    this.initialName,
    this.onSave,
    super.key,
  });

  final Goal? existing;
  final int nextPriority;

  /// A name to start with, such as one picked from the savings guide.
  final String? initialName;

  /// Replaces saving. Used by tests.
  final void Function(String name, double target, DateTime? date)? onSave;

  @override
  State<GoalFormSheet> createState() => _GoalFormSheetState();
}

class _GoalFormSheetState extends State<GoalFormSheet> {
  late final _nameController = TextEditingController(
    text: widget.existing?.name ?? widget.initialName ?? '',
  );
  late final _targetController = TextEditingController(
    text: widget.existing == null
        ? ''
        : widget.existing!.targetAmount.toStringAsFixed(2),
  );
  late DateTime? _date = widget.existing?.targetDate;
  String? _error;

  @override
  void dispose() {
    _nameController.dispose();
    _targetController.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _date ?? DateTime(now.year, now.month + 3, now.day),
      firstDate: DateTime(now.year, now.month, now.day),
      lastDate: DateTime(now.year + 20),
    );
    if (picked != null) setState(() => _date = picked);
  }

  void _save() {
    final name = _nameController.text.trim();
    final target = double.tryParse(
      _targetController.text.trim().replaceAll(',', ''),
    );

    if (name.isEmpty) {
      setState(() => _error = 'Give the goal a name.');
      return;
    }
    if (target == null || target <= 0) {
      setState(() => _error = 'Enter how much you want to save.');
      return;
    }

    if (widget.onSave != null) {
      widget.onSave!(name, target, _date);
    } else if (widget.existing == null) {
      GoalService.addGoal(
        name: name,
        targetAmount: target,
        targetDate: _date,
        priority: widget.nextPriority,
      );
    } else {
      GoalService.updateGoal(
        widget.existing!,
        name: name,
        targetAmount: target,
        targetDate: _date,
      );
    }

    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _SheetHeader(widget.existing == null ? 'New Goal' : 'Edit Goal'),
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
                  onPressed: _save,
                  style: confirmButtonStyle(),
                  child: Text(
                    widget.existing == null ? 'Add Goal' : 'Save Changes',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ],
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
        : widget.goal.remaining.toStringAsFixed(2),
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

    Navigator.pop(context);
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
