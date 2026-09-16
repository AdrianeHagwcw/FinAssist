import 'package:flutter/material.dart';

import '../services/user_profile_service.dart';

const _incomeSources = [
  'Allowance',
  'Salary',
  'Part-time Job',
  'Business',
  'Freelance',
  'Borrowed Money',
  'Picked-up Money',
  'Other',
];

/// Asks for an income amount and source and saves it.
///
/// Returns true when income was saved, so callers can refresh their totals.
Future<bool> showAddIncomeDialog(BuildContext context) async {
  final messenger = ScaffoldMessenger.of(context);
  final amountController = TextEditingController();
  String? selectedSource;
  var isSaving = false;
  var saved = false;

  void showMessage(String message) {
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  await showDialog<void>(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (context, setDialogState) => AlertDialog(
        title: const Text('Add Income'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: amountController,
              enabled: !isSaving,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: const InputDecoration(
                labelText: 'Income amount',
                prefixText: '₱',
              ),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: selectedSource,
              decoration: const InputDecoration(
                labelText: 'Where did this income come from?',
              ),
              items: _incomeSources
                  .map(
                    (source) =>
                        DropdownMenuItem(value: source, child: Text(source)),
                  )
                  .toList(),
              onChanged: isSaving
                  ? null
                  : (value) => setDialogState(() => selectedSource = value),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: isSaving ? null : () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: isSaving
                ? null
                : () async {
                    final amount = double.tryParse(
                      amountController.text.trim().replaceAll(',', ''),
                    );
                    if (amount == null || amount <= 0) {
                      showMessage('Enter a valid positive income amount.');
                      return;
                    }
                    if (selectedSource == null) {
                      showMessage('Select where the income came from.');
                      return;
                    }

                    setDialogState(() => isSaving = true);
                    try {
                      await UserProfileService.addOtherIncome(
                        amount: amount,
                        incomeSource: selectedSource!,
                      );
                      saved = true;
                      if (!dialogContext.mounted) return;
                      Navigator.pop(dialogContext);
                    } catch (_) {
                      setDialogState(() => isSaving = false);
                      showMessage('Income could not be saved.');
                    }
                  },
            child: isSaving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Save'),
          ),
        ],
      ),
    ),
  );
  amountController.dispose();
  return saved;
}
