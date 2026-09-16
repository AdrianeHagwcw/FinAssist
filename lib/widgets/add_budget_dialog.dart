import 'package:flutter/material.dart';

import '../services/user_profile_service.dart';
import '../utils/money_format.dart';
import '../theme/app_buttons.dart';
import 'dialog_kit.dart';

/// How a new amount changes the daily limit.
enum _BudgetMode {
  replace('Replace it', 'The new amount becomes your daily limit.'),
  add('Add to it', 'The new amount is added to your current limit.');

  const _BudgetMode(this.label, this.explanation);

  final String label;
  final String explanation;
}

/// Sets or tops up the daily spending limit.
///
/// Returns true when the limit was changed, so the caller can refresh.
Future<bool> showAddBudgetDialog(
  BuildContext context, {
  required double currentBudget,
}) async {
  final saved = await showDialog<bool>(
    context: context,
    builder: (context) => AddBudgetDialog(currentBudget: currentBudget),
  );

  return saved ?? false;
}

class AddBudgetDialog extends StatefulWidget {
  const AddBudgetDialog({required this.currentBudget, this.onSave, super.key});

  final double currentBudget;

  /// Saves the new limit. Tests pass a fake instead of Firestore.
  final Future<void> Function(double budget)? onSave;

  @override
  State<AddBudgetDialog> createState() => _AddBudgetDialogState();
}

class _AddBudgetDialogState extends State<AddBudgetDialog> {
  // Owned by this State, so it outlives the dialog's closing animation.
  final _amountController = TextEditingController();

  _BudgetMode _mode = _BudgetMode.replace;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    // Keeps the "New daily limit" preview in step with what is typed.
    _amountController.addListener(_onAmountChanged);
  }

  void _onAmountChanged() => setState(() {});

  @override
  void dispose() {
    _amountController
      ..removeListener(_onAmountChanged)
      ..dispose();
    super.dispose();
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  double? get _amount =>
      double.tryParse(_amountController.text.trim().replaceAll(',', ''));

  /// What the limit will be once this is saved.
  double get _resultingBudget {
    final amount = _amount ?? 0;

    return _mode == _BudgetMode.add ? widget.currentBudget + amount : amount;
  }

  Future<void> _save() async {
    final amount = _amount;

    if (amount == null || amount <= 0) {
      _showMessage('Enter a valid positive budget amount.');
      return;
    }

    setState(() => _isSaving = true);

    try {
      await (widget.onSave ?? UserProfileService.updateBudget)(
        _resultingBudget,
      );

      if (!mounted) return;

      Navigator.pop(context, true);
    } catch (_) {
      if (!mounted) return;

      setState(() => _isSaving = false);
      _showMessage('Budget could not be saved.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final amount = _amount;

    return AlertDialog(
      shape: dialogShape,
      title: const DialogTitle(
        text: 'Daily Limit',
        iconAsset: 'assets/icons/icons8-calendar-96.png',
      ),
      content: SizedBox(
        width: double.maxFinite,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              DialogNote(
                text: widget.currentBudget > 0
                    ? 'Your limit right now is '
                          '${formatPeso(widget.currentBudget)} a day.'
                    : 'You have no daily limit set yet.',
              ),
              const SizedBox(height: 16),
              AmountField(
                controller: _amountController,
                label: 'Amount',
                enabled: !_isSaving,
                onSubmitted: _save,
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<_BudgetMode>(
                initialValue: _mode,
                isExpanded: true,
                decoration: dialogFieldDecoration(
                  context,
                  'What should it do?',
                ),
                items: [
                  for (final mode in _BudgetMode.values)
                    DropdownMenuItem(value: mode, child: Text(mode.label)),
                ],
                onChanged: _isSaving
                    ? null
                    : (value) => setState(() => _mode = value ?? _mode),
              ),
              const SizedBox(height: 8),
              Text(
                _mode.explanation,
                style: const TextStyle(fontSize: 12, color: Colors.grey),
              ),
              if (amount != null && amount > 0) ...[
                const SizedBox(height: 14),
                Text(
                  'New daily limit: ${formatPeso(_resultingBudget)}',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isSaving ? null : () => Navigator.pop(context, false),
          style: cancelTextStyle(context),
          child: const Text('Cancel'),
        ),
        DialogSaveButton(onPressed: _save, isSaving: _isSaving),
      ],
    );
  }
}
