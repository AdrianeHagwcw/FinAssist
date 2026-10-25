import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

class InfoIntroCard extends StatelessWidget {
  const InfoIntroCard({
    required this.title,
    required this.message,
    this.icon,
    super.key,
  });

  final IconData? icon;
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(20),
    decoration: BoxDecoration(
      color: context.appColors.primaryTint,
      borderRadius: BorderRadius.circular(18),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (icon != null) ...[
          Icon(icon, color: context.appColors.primaryText, size: 28),
          const SizedBox(height: 12),
        ],
        Text(
          title,
          style: Theme.of(
            context,
          ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        Text(
          message,
          style: TextStyle(color: context.appColors.textBody, height: 1.5),
        ),
      ],
    ),
  );
}
