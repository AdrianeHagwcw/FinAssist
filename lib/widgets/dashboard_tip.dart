import 'package:flutter/material.dart';

import '../models/dashboard_tip.dart';
import '../theme/app_colors.dart';

/// Home's tip: a short rule-based line, with no AI service and no connection.
class DashboardTipCard extends StatelessWidget {
  const DashboardTipCard({
    required this.tip,
    required this.onOpenHistory,
    super.key,
  });

  final DashboardTip tip;
  final VoidCallback onOpenHistory;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    return Material(
      color: colors.primaryTint,
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.lightbulb_outline, color: colors.primaryText),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    tip.title,
                    style: TextStyle(
                      color: colors.textPrimary,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    tip.message,
                    style: TextStyle(color: colors.textBody, height: 1.5),
                  ),
                  if (tip.showHistory)
                    TextButton(
                      onPressed: onOpenHistory,
                      style: TextButton.styleFrom(
                        foregroundColor: colors.primaryText,
                        padding: EdgeInsets.zero,
                      ),
                      child: const Text('View pay-cycle history'),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
