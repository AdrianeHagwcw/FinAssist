import 'package:flutter/material.dart';

import '../services/user_profile_service.dart';
import '../utils/categories.dart';
import 'category_icon.dart';
import '../theme/app_buttons.dart';
import 'dialog_kit.dart';

/// How often a category budget resets.
enum BudgetPeriod {
  daily('daily', 'Daily', 'Resets every day.'),
  weekly('weekly', 'Weekly', 'Resets every Monday.'),
  monthly('monthly', 'Monthly', 'Resets on the 1st of the month.');

  const BudgetPeriod(this.value, this.label, this.explanation);

  /// What is stored in Firestore.
  final String value;
  final String label;
  final String explanation;

  static BudgetPeriod fromValue(String? value) {
    return BudgetPeriod.values.firstWhere(
      (period) => period.value == value,
      orElse: () => BudgetPeriod.daily,
    );
  }
}

/// Sets a spending limit for one category.
///
/// Returns true when it was saved, so the caller can refresh.
Future<bool> showCategoryBudgetDialog(
  BuildContext context, {
  String? category,
  double? amount,
  String? period,
}) async {
  final saved = await showDialog<bool>(
    context: context,
    builder: (context) => CategoryBudgetDialog(
      category: category,
      amount: amount,
      period: period,
    ),
  );

  return saved ?? false;
}

class CategoryBudgetDialog extends StatefulWidget {
  const CategoryBudgetDialog({
    this.category,
    this.amount,
    this.period,
    this.onSave,
    super.key,
  });

  /// The budget being edited, or null when adding a new one.
  final String? category;
  final double? amount;
  final String? period;

  /// Saves the budget. Tests pass a fake instead of Firestore.
  final Future<void> Function({
    required String category,
    required double amount,
    required String period,
  })?
  onSave;

  bool get isEditing => category != null;

  @override
  State<CategoryBudgetDialog> createState() => _CategoryBudgetDialogState();
}

class _CategoryBudgetDialogState extends State<CategoryBudgetDialog> {
  // Owned by this State, so it outlives the dialog's closing animation.
  late final _amountController = TextEditingController(
    text: widget.amount == null ? '' : widget.amount!.toStringAsFixed(2),
  );

  late String _category = widget.category ?? expenseCategories.first;
  late BudgetPeriod _period = BudgetPeriod.fromValue(widget.period);
  bool _isSaving = false;

  @override
  void dispose() {
    _amountController.dispose();
    super.dispose();
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _save() async {
    final amount = double.tryParse(
      _amountController.text.trim().replaceAll(',', ''),
    );

    if (amount == null || amount <= 0) {
      _showMessage('Enter a valid positive amount.');
      return;
    }

    setState(() => _isSaving = true);

    try {
      await (widget.onSave ?? UserProfileService.saveCategoryBudget)(
        category: _category,
        amount: amount,
        period: _period.value,
      );

      if (!mounted) return;

      Navigator.pop(context, true);
    } catch (_) {
      if (!mounted) return;

      setState(() => _isSaving = false);
      _showMessage('Category budget could not be saved.');
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: dialogShape,
      title: DialogTitle(
        text: widget.isEditing ? 'Edit Budget' : 'Category Budget',
        iconAsset: 'assets/icons/icons8-pie-chart-96.png',
      ),
      content: SizedBox(
        width: double.maxFinite,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              DropdownButtonFormField<String>(
                initialValue: _category,
                isExpanded: true,
                decoration: dialogFieldDecoration(context, 'Category'),
                items: [
                  for (final category in expenseCategories)
                    DropdownMenuItem(
                      value: category,
                      child: Row(
                        children: [
                          CategoryIcon(category, size: 20),
                          const SizedBox(width: 10),
                          Text(category),
                        ],
                      ),
                    ),
                ],
                // Changing the category of a saved budget would leave the old
                // one behind, so it is fixed once saved.
                onChanged: _isSaving || widget.isEditing
                    ? null
                    : (value) => setState(() => _category = value ?? _category),
              ),
              const SizedBox(height: 16),
              AmountField(
                controller: _amountController,
                label: 'Limit',
                enabled: !_isSaving,
                onSubmitted: _save,
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<BudgetPeriod>(
                initialValue: _period,
                isExpanded: true,
                decoration: dialogFieldDecoration(context, 'How often'),
                items: [
                  for (final period in BudgetPeriod.values)
                    DropdownMenuItem(value: period, child: Text(period.label)),
                ],
                onChanged: _isSaving
                    ? null
                    : (value) => setState(() => _period = value ?? _period),
              ),
              const SizedBox(height: 8),
              Text(
                _period.explanation,
                style: const TextStyle(fontSize: 12, color: Colors.grey),
              ),
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
