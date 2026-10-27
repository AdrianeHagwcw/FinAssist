import 'package:flutter/material.dart';

import '../../backend/models/wallet.dart';
import '../theme/app_buttons.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../../backend/utils/date_format.dart';
import '../../backend/utils/money_format.dart';

/// The card for one saved item, used by setup's savings, bills and goals and
/// by the Savings screen, so they all read the same way: an icon for what it
/// is, the name with its main amount, a blue pencil and a red trash, then the
/// details.
class ItemCard extends StatelessWidget {
  const ItemCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onEdit,
    this.onDelete,
    this.details = const [],
    this.deleteKey,
    super.key,
  });

  /// Shown at 32 by 32.
  final Widget icon;
  final String title;
  final String subtitle;

  /// Null while it cannot be edited yet, which greys the pencil out.
  final VoidCallback? onEdit;

  /// Left out where an item is not deleted from this screen.
  final VoidCallback? onDelete;
  final List<Widget> details;
  final Key? deleteKey;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.fromLTRB(14, 12, 4, 14),
      decoration: BoxDecoration(
        color: colors.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              SizedBox(width: 32, height: 32, child: icon),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: colors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: TextStyle(fontSize: 13, color: colors.textBody),
                    ),
                  ],
                ),
              ),
              // One Edit for everything about it.
              IconButton(
                tooltip: 'Edit $title',
                onPressed: onEdit,
                // The same blue as the progress bar and Next.
                color: appPrimaryBlue,
                icon: const Icon(Icons.edit_outlined, size: 20),
              ),
              // Red, so it reads as deleting before it is tapped; a warning
              // still comes first.
              if (onDelete != null)
                IconButton(
                  key: deleteKey,
                  tooltip: 'Delete $title',
                  onPressed: onDelete,
                  color: dangerColorOn(context),
                  icon: const Icon(Icons.delete_outline, size: 20),
                ),
            ],
          ),
          if (details.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 10, right: 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: details,
              ),
            ),
        ],
      ),
    );
  }
}

/// One fact on an [ItemCard], the label on the left and its value on the
/// right, sized like the account rows on a goal card.
class ItemCardDetail extends StatelessWidget {
  const ItemCardDetail(this.label, this.value, {super.key});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(fontSize: 14, color: colors.textBody),
            ),
          ),
          const SizedBox(width: 12),
          Text(
            value,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: colors.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}

/// A small line under an [ItemCard]'s details, with the same icon and size
/// as a goal's interest guess.
class ItemCardNote extends StatelessWidget {
  const ItemCardNote(this.icon, this.text, {super.key});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: colors.textBody),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              text,
              style: TextStyle(fontSize: 12, color: colors.textBody),
            ),
          ),
        ],
      ),
    );
  }
}

/// "₱25,000 saved", with the kind first when the name is not just the kind.
String savingsRecordSubtitle({
  required String name,
  required SavingsKind kind,
  required double balance,
}) => name == kind.label
    ? '${formatPeso(balance)} saved'
    : '${kind.label} · ${formatPeso(balance)} saved';

/// The facts on a savings card, the same in setup and on the Savings screen:
/// the interest, when it started and ends, what goals hold, and a guess at
/// what it may earn. Only what applies to [kind] is shown.
List<Widget> savingsRecordDetails({
  required SavingsKind kind,
  required double balance,
  double? rate,
  DateTime? start,
  DateTime? end,
  double? interestUntilEnd,
  double promised = 0,
  DateTime? today,
  InterestPayout? payout,
}) {
  final now = today ?? DateTime.now();
  final ended = end != null && calendarDaysBetween(end, now) >= 0;

  return [
    if (kind == SavingsKind.demandDeposit) ...[
      const ItemCardDetail('Interest', 'None'),
      const ItemCardDetail('Take money out', 'Anytime'),
    ] else if (rate != null)
      ItemCardDetail('Interest', '${percentText(rate)} a year'),
    if (kind == SavingsKind.savingsDeposit &&
        payout != null &&
        rate != null &&
        rate > 0)
      ItemCardDetail('Paid', payout.label.toLowerCase()),
    if (start != null) ItemCardDetail('Started', formatShortDate(start)),
    if (end != null)
      ItemCardDetail(ended ? 'Ended' : 'Ends', formatShortDate(end)),
    if (promised > 0.005) ...[
      ItemCardDetail('Set aside for goals', formatPeso(promised)),
      ItemCardDetail(
        'Free to use',
        formatPeso(balance - promised > 0 ? balance - promised : 0),
      ),
    ],
    if (kind == SavingsKind.timeDeposit &&
        end != null &&
        interestUntilEnd != null &&
        interestUntilEnd > 0)
      // Paid with the money at the end, so it is added then, when the user
      // says what came back.
      ItemCardNote(
        Icons.trending_up,
        '${ended ? 'May have earned' : 'May earn'} about '
        '${formatPeso(afterTax(interestUntilEnd))} after tax by '
        '${formatShortDate(end)}. It is added when you say what you got back.',
      )
    else if (kind == SavingsKind.savingsDeposit && rate != null && rate > 0)
      ItemCardNote(
        Icons.trending_up,
        'May earn about ${formatPeso(afterTax(balance * rate / 100))} a year '
        'after tax. Add it as income when your bank pays it.',
      ),
  ];
}

/// 3 as "3%", 2.5 as "2.5%".
String percentText(double rate) =>
    '${rate == rate.truncateToDouble() ? rate.toInt() : rate}%';
