import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import 'quick_action_tile.dart';

/// One shortcut in the "+" quick-add grid.
class QuickAddAction {
  const QuickAddAction({
    required this.icon,
    required this.label,
    required this.color,
    required this.onSelected,
    this.iconAsset,
  });

  /// Material icon shown in the grid, unless [iconAsset] is given.
  final IconData icon;

  /// Optional image icon from the assets folder, used instead of [icon].
  final String? iconAsset;
  final String label;
  final Color color;
  final VoidCallback onSelected;
}

/// Opens the quick-add bottom sheet. The sheet closes before the chosen
/// action runs, so the action can open its own screen or dialog.
Future<void> showQuickAddSheet(
  BuildContext context,
  List<QuickAddAction> actions,
) async {
  final chosen = await showModalBottomSheet<QuickAddAction>(
    context: context,
    backgroundColor: context.appColors.pageBackground,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (sheetContext) => QuickAddSheet(
      actions: actions,
      onSelected: (action) => Navigator.pop(sheetContext, action),
    ),
  );

  chosen?.onSelected();
}

/// Grid of quick-add shortcuts, three per row.
class QuickAddSheet extends StatelessWidget {
  const QuickAddSheet({
    required this.actions,
    required this.onSelected,
    super.key,
  });

  final List<QuickAddAction> actions;
  final ValueChanged<QuickAddAction> onSelected;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: context.appColors.border,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Quick Add',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: context.appColors.textPrimary,
              ),
            ),
            const SizedBox(height: 16),
            GridView.count(
              crossAxisCount: 3,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              childAspectRatio: 1.05,
              children: [
                for (final action in actions)
                  QuickActionTile(
                    icon: action.iconAsset == null
                        ? Icon(action.icon)
                        : Image.asset(action.iconAsset!, width: 27, height: 27),
                    title: action.label,
                    iconColor: action.color,
                    onTap: () => onSelected(action),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
