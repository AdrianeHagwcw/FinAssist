import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_theme.dart';

/// One of two large filter tiles, as used at the top of Goals, Installments
/// and Debts: the chosen one solid blue, with its icon, label and count.
///
/// Each tile is a full 48 points high and read out as a selected or
/// unselected button. Keeping one widget means the three screens can never
/// drift apart in wording or size.
class SegmentedFilterTile extends StatelessWidget {
  const SegmentedFilterTile({
    required this.iconAsset,
    required this.label,
    required this.count,
    required this.selected,
    required this.semanticsLabel,
    required this.onTap,
    super.key,
  });

  final String iconAsset;
  final String label;
  final int count;
  final bool selected;

  /// What a screen reader says, such as "Active goals, 3".
  final String semanticsLabel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final foreground = selected ? Colors.white : colors.textBody;

    return Semantics(
      button: true,
      selected: selected,
      label: semanticsLabel,
      excludeSemantics: true,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            constraints: const BoxConstraints(minHeight: 48),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
            decoration: BoxDecoration(
              color: selected ? appPrimaryBlue : colors.card,
              border: Border.all(
                color: selected ? appPrimaryBlue : colors.border,
              ),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Image.asset(iconAsset, width: 18, height: 18),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: selected ? FontWeight.bold : FontWeight.w500,
                      color: foreground,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                // How many, in a badge of its own rather than in brackets.
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: selected
                        ? Colors.white.withValues(alpha: 0.25)
                        : colors.primaryTint,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '$count',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: selected ? Colors.white : colors.primaryText,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
