import 'package:flutter/material.dart';

import '../models/expense_guess.dart';
import '../theme/app_colors.dart';
import 'category_icon.dart';
import '../utils/date_format.dart';
import '../utils/money_format.dart';

/// What was found in the words or on the receipt, shown before Use This so
/// the user knows what the new expense will start with.
class FoundDetails extends StatelessWidget {
  const FoundDetails({
    required this.guess,
    this.showStore = false,
    this.center = false,
    super.key,
  });

  final ExpenseGuess guess;

  /// Receipts show the store, which becomes the description.
  final bool showStore;
  final bool center;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    Widget asset(String name) =>
        Image.asset('assets/icons/$name', width: 18, height: 18);
    final items = <(Widget, String)>[
      if (guess.amount != null)
        (asset('icons8-banknotes-96.png'), formatPeso(guess.amount!)),
      if (guess.category != null)
        (CategoryIcon(guess.category!, size: 18), guess.category!),
      if (showStore && guess.description != null)
        (asset('icons8-receipt-96.png'), guess.description!),
      if (guess.date != null)
        (asset('icons8-calendar-96.png'), formatShortDate(guess.date!)),
    ];
    if (items.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: center
          ? CrossAxisAlignment.center
          : CrossAxisAlignment.start,
      children: [
        Text(
          'Filled in for you',
          style: TextStyle(fontSize: 12, color: colors.textBody),
        ),
        const SizedBox(height: 8),
        Wrap(
          alignment: center ? WrapAlignment.center : WrapAlignment.start,
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final (icon, label) in items)
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: colors.primaryTint,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    icon,
                    const SizedBox(width: 6),
                    Text(
                      label,
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: colors.primaryText,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ],
    );
  }
}
