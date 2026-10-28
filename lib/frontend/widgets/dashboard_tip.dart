import 'package:flutter/material.dart';

import '../../backend/models/dashboard_tip.dart';
import '../theme/app_colors.dart';
import '../theme/app_icons.dart';

/// Home's tip: a short rule-based line, with no AI service and no connection.
class DashboardTipCard extends StatelessWidget {
  const DashboardTipCard({required this.tip, super.key});

  final DashboardTip tip;

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
            Image.asset(AppIcons.idea, width: 24, height: 24),
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
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
