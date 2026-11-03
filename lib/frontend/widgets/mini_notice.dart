import 'package:flutter/material.dart';

import '../theme/app_buttons.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';

/// A small screen over the app to say something, instead of a line along
/// the bottom that is gone before it can be read: an arrow back at its
/// upper left, an icon in its tint, the heading, what it means — and a
/// button straight on to the next thing when there is one.
///
/// Returns the value the action button was given, or null when the notice
/// was dismissed with the arrow.
Future<T?> showMiniNotice<T>(
  BuildContext context, {
  required String title,
  required String message,
  IconData icon = Icons.check_circle_outline,

  /// Green for something good that has happened, blue for plain
  /// information: the same colours committing and opening carry everywhere.
  bool good = true,
  String? actionLabel,
  T? actionValue,
}) {
  return showModalBottomSheet<T>(
    context: context,
    useSafeArea: true,
    backgroundColor: context.appColors.card,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (sheetContext) => _MiniNotice<T>(
      key: const Key('mini-notice'),
      title: title,
      message: message,
      icon: icon,
      good: good,
      actionLabel: actionLabel,
      actionValue: actionValue,
    ),
  );
}

class _MiniNotice<T> extends StatelessWidget {
  const _MiniNotice({
    super.key,
    required this.title,
    required this.message,
    required this.icon,
    required this.good,
    this.actionLabel,
    this.actionValue,
  });

  final String title;
  final String message;
  final IconData icon;
  final bool good;
  final String? actionLabel;
  final T? actionValue;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    // Green when the news is good, blue when it is only being said.
    final accent = good ? appConfirmGreen : appPrimaryBlue;

    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 6, 24, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // The way out, the way any screen is left: an arrow at the upper
          // left, needing nothing read.
          Align(
            alignment: Alignment.centerLeft,
            child: IconButton(
              key: const Key('mini-notice-back'),
              onPressed: () => Navigator.pop(context),
              tooltip: 'Back',
              icon: const Icon(Icons.arrow_back),
            ),
          ),
          const SizedBox(height: 4),
          Container(
            width: 64,
            height: 64,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 32, color: accent),
          ),
          const SizedBox(height: 16),
          Text(
            title,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: colors.textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            message,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 14,
              height: 1.45,
              color: colors.textBody,
            ),
          ),
          if (actionLabel != null) ...[
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton(
                key: const Key('mini-notice-action'),
                // Pops with its value; the screen that opened the notice
                // carries on from there.
                onPressed: () => Navigator.pop(context, actionValue),
                style: openButtonStyle(),
                child: Text(
                  actionLabel!,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
