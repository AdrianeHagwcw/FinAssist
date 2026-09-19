import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_theme.dart';

/// Rounded card with an icon above a short label. Used for Home's Quick
/// Actions row and the "+" quick-add grid.
class QuickActionTile extends StatelessWidget {
  const QuickActionTile({
    required this.icon,
    required this.title,
    required this.onTap,
    this.iconColor = appPrimaryBlue,
    super.key,
  });

  final Widget icon;
  final String title;
  final VoidCallback onTap;
  final Color iconColor;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,

      borderRadius: BorderRadius.circular(14),

      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),

        decoration: BoxDecoration(
          color: context.appColors.card,

          borderRadius: BorderRadius.circular(14),

          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),

              blurRadius: 8,

              offset: const Offset(0, 3),
            ),
          ],
        ),

        child: Column(
          children: [
            IconTheme(
              data: IconThemeData(color: iconColor, size: 27),
              child: icon,
            ),

            const SizedBox(height: 8),

            Text(
              title,

              textAlign: TextAlign.center,

              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
    );
  }
}
