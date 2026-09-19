import 'package:flutter/material.dart';

import '../models/bill.dart';
import '../models/reminder.dart';
import '../theme/app_buttons.dart';
import '../theme/app_colors.dart';
import 'money_text.dart';

/// Home's notice for bills that are overdue or due in the next few days.
///
/// Shows inside the app whether or not phone reminders are on, so nobody
/// misses a bill because they turned notifications off.
class DueSoonNotice extends StatelessWidget {
  const DueSoonNotice({
    required this.bills,
    required this.now,
    required this.onOpen,
    this.limit = 3,
    super.key,
  });

  final List<BillInstance> bills;
  final DateTime now;
  final ValueChanged<BillInstance> onOpen;
  final int limit;

  /// "due today", "due tomorrow", "due in 3 days" or "2 days overdue".
  static String whenLabel(DateTime dueDate, DateTime now) {
    final today = DateTime(now.year, now.month, now.day);
    final due = DateTime(dueDate.year, dueDate.month, dueDate.day);
    final days = due.difference(today).inDays;

    if (days == 0) return 'due today';
    if (days == 1) return 'due tomorrow';
    if (days > 1) return 'due in $days days';
    return days == -1 ? '1 day overdue' : '${-days} days overdue';
  }

  @override
  Widget build(BuildContext context) {
    final due = billsDueSoon(bills, now: now);
    if (due.isEmpty) return const SizedBox.shrink();

    final colors = context.appColors;
    final shown = due.take(limit).toList();
    final more = due.length - shown.length;

    return Container(
      margin: const EdgeInsets.only(top: 14),
      padding: const EdgeInsets.fromLTRB(16, 14, 8, 6),
      decoration: BoxDecoration(
        color: colors.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: colors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Image.asset('assets/icons/icons8-bell-96.png', width: 20),
              const SizedBox(width: 8),
              Text(
                'Bills due soon',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: colors.textPrimary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          for (final bill in shown)
            InkWell(
              onTap: () => onOpen(bill),
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            bill.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(color: colors.textPrimary),
                          ),
                          Text(
                            whenLabel(bill.dueDate, now),
                            style: TextStyle(
                              fontSize: 12,
                              color:
                                  bill.dueDate.isBefore(
                                    DateTime(now.year, now.month, now.day),
                                  )
                                  ? dangerColorOn(context)
                                  : colors.textBody,
                            ),
                          ),
                        ],
                      ),
                    ),
                    MoneyText(
                      bill.remaining,
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: colors.textPrimary,
                      ),
                    ),
                    TextButton(
                      onPressed: () => onOpen(bill),
                      style: TextButton.styleFrom(
                        foregroundColor: colors.primaryText,
                      ),
                      child: const Text('Pay'),
                    ),
                  ],
                ),
              ),
            ),
          if (more > 0)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                '$more more in your Bill Planner',
                style: TextStyle(fontSize: 12, color: colors.textBody),
              ),
            ),
        ],
      ),
    );
  }
}
