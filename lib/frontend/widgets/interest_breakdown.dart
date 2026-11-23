import 'package:flutter/material.dart';

import '../../backend/models/wallet.dart';
import '../../backend/utils/money_format.dart';
import '../theme/app_colors.dart';

/// Interest earned, the 20% tax the bank withholds, and what reaches the
/// account, as three lines that add up to the centavo.
class InterestBreakdown extends StatelessWidget {
  const InterestBreakdown(
    this.gross, {
    this.earnedLabel = 'Interest earned',
    super.key,
  });

  /// The interest before tax.
  final double gross;

  /// What the first line calls it, such as "Interest each month".
  final String earnedLabel;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    Widget line(String label, String amount, {bool strong = false}) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: strong ? FontWeight.bold : FontWeight.normal,
                color: strong ? colors.textPrimary : colors.textBody,
              ),
            ),
          ),
          Text(
            amount,
            style: TextStyle(
              fontSize: 13,
              fontWeight: strong ? FontWeight.bold : FontWeight.w600,
              color: colors.textPrimary,
            ),
          ),
        ],
      ),
    );

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        line(earnedLabel, formatPeso(roundToCentavo(gross))),
        line(
          'Tax withheld (${(interestTaxRate * 100).round()}%)',
          '− ${formatPeso(interestTax(gross))}',
        ),
        Divider(height: 12, color: colors.border),
        line('You get', formatPeso(afterTax(gross)), strong: true),
      ],
    );
  }
}
