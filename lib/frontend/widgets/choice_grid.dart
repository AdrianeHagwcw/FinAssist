import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// Choices in tiles of a fixed size, [columns] to a row, so choosing one
/// never moves the others, as chips that grow a tick would. The chosen one
/// is outlined and tinted blue.
class ChoiceGrid<T> extends StatelessWidget {
  const ChoiceGrid({
    required this.options,
    required this.selected,
    required this.label,
    required this.onPick,
    this.keyOf,
    this.columns = 2,
    super.key,
  });

  final List<T> options;
  final T selected;
  final String Function(T option) label;
  final ValueChanged<T> onPick;

  /// A key for each tile, for tests.
  final String Function(T option)? keyOf;
  final int columns;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    Widget tile(T option) {
      final isSelected = option == selected;
      final shape = RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: isSelected ? colors.primaryText : colors.border,
          width: isSelected ? 1.5 : 1,
        ),
      );
      return Semantics(
        button: true,
        selected: isSelected,
        child: Material(
          key: keyOf == null ? null : Key(keyOf!(option)),
          color: isSelected ? colors.primaryTint : colors.pageBackground,
          shape: shape,
          child: InkWell(
            customBorder: shape,
            onTap: () => onPick(option),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 48),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 6,
                  vertical: 10,
                ),
                child: Center(
                  child: Text(
                    label(option),
                    textAlign: TextAlign.center,
                    // The same weight chosen or not, so the text never
                    // rewraps.
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: isSelected ? colors.primaryText : colors.textBody,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    }

    return Column(
      children: [
        for (var start = 0; start < options.length; start += columns)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var column = 0; column < columns; column++) ...[
                    if (column > 0) const SizedBox(width: 8),
                    Expanded(
                      child: start + column < options.length
                          ? tile(options[start + column])
                          : const SizedBox.shrink(),
                    ),
                  ],
                ],
              ),
            ),
          ),
      ],
    );
  }
}
