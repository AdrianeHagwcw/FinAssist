import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// Centered icon, title and message for screens with nothing to show yet.
class EmptyStateView extends StatelessWidget {
  const EmptyStateView({
    required this.iconAsset,
    required this.title,
    required this.message,
    super.key,
  });

  final String iconAsset;
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 96,
              height: 96,
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: context.appColors.primaryTint,
                shape: BoxShape.circle,
              ),
              child: Image.asset(iconAsset),
            ),
            const SizedBox(height: 20),
            Text(
              title,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: context.appColors.textPrimary,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 14,
                color: Colors.grey,
                height: 1.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
