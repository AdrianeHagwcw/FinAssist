import 'package:flutter/material.dart';

import '../models/finance_snapshot.dart';
import '../models/savings_suggestion.dart';
import '../theme/app_colors.dart';
import '../utils/money_format.dart';

class SavingsSuggestionCard extends StatelessWidget {
  const SavingsSuggestionCard({
    required this.records,
    required this.onTransfer,
    super.key,
  });

  final FinanceSnapshot records;
  final void Function(double amount) onTransfer;

  @override
  Widget build(BuildContext context) {
    final suggestion = SavingsSuggestion.from(records);
    final irregular =
        records.incomeFrequency == null ||
        records.incomeFrequency == 'Irregular';
    return Card(
      margin: const EdgeInsets.only(bottom: 20),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Suggested to save',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: context.appColors.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            if (!suggestion.hasHistory)
              const Text(
                'Record everyday spending on at least 7 different days '
                'in the last 30 days so FinAssist can estimate what to keep for daily needs.',
              )
            else ...[
              Text(
                formatPeso(suggestion.amount),
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'After bills, installment payments and money already saved, '
                '${formatPeso(suggestion.available)} is available. We allow '
                '${formatPeso(suggestion.dailyCosts)} for everyday spending '
                '${irregular ? 'through the end of this month' : 'until your next expected income'}, '
                'based on your recent records.',
              ),
              const SizedBox(height: 8),
              Text(
                suggestion.amount > 0
                    ? 'The suggestion is 10% of what remains, leaving 90% as a buffer. '
                          'Check for any missing expenses before saving. You choose the amount.'
                    : 'There is no extra amount to suggest right now. Keep this money '
                          'for your daily needs and payments.',
              ),
              if (suggestion.amount > 0) ...[
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: () => onTransfer(suggestion.amount),
                  icon: const Icon(Icons.savings_outlined),
                  label: const Text('Review savings transfer'),
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }
}
