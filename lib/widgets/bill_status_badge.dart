import 'package:flutter/material.dart';

import '../models/bill.dart';
import '../theme/app_colors.dart';

/// The colour a bill reads in: red overdue, amber due soon, green paid, grey
/// for anything not asking for attention yet.
Color billUrgencyColor(BuildContext context, BillUrgency urgency) {
  switch (urgency) {
    case BillUrgency.overdue:
      return Colors.red;
    case BillUrgency.dueSoon:
      return Colors.amber.shade700;
    case BillUrgency.paid:
      return Colors.green;
    case BillUrgency.skipped:
    case BillUrgency.moved:
    case BillUrgency.upcoming:
      return context.isDarkMode ? Colors.grey.shade500 : Colors.grey;
  }
}

String billUrgencyLabel(BillUrgency urgency) {
  switch (urgency) {
    case BillUrgency.overdue:
      return 'Overdue';
    case BillUrgency.dueSoon:
      return 'Due soon';
    case BillUrgency.paid:
      return 'Paid';
    case BillUrgency.skipped:
      return 'Skipped';
    case BillUrgency.moved:
      return 'Moved to next';
    case BillUrgency.upcoming:
      return 'Upcoming';
  }
}

IconData billUrgencyIcon(BillUrgency urgency) {
  switch (urgency) {
    case BillUrgency.paid:
      return Icons.check_circle;
    case BillUrgency.skipped:
      return Icons.cancel;
    case BillUrgency.moved:
      return Icons.redo;
    case BillUrgency.overdue:
      return Icons.error;
    case BillUrgency.dueSoon:
    case BillUrgency.upcoming:
      return Icons.schedule;
  }
}

/// Paid / Skipped / Moved to next / Overdue / Due soon / Upcoming, as a
/// coloured pill.
///
/// A part-paid bill says so, because "Unpaid" would be wrong and "Paid" would
/// be worse.
class BillStatusBadge extends StatelessWidget {
  const BillStatusBadge({required this.instance, this.now, super.key});

  final BillInstance instance;

  /// Injectable so tests don't depend on the clock.
  final DateTime? now;

  @override
  Widget build(BuildContext context) {
    final urgency = instance.urgency(now: now);
    final color = billUrgencyColor(context, urgency);
    final label =
        instance.status == BillStatus.partial && urgency != BillUrgency.moved
        ? 'Partly paid'
        : billUrgencyLabel(urgency);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.13),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(billUrgencyIcon(urgency), size: 13, color: color),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}
