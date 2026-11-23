import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_theme.dart';

/// A few choices as one row of equal parts, the chosen one solid blue like
/// the filters on Goals and Debts. Short words keep it on one line on a
/// narrow phone; longer ones shrink to fit rather than wrap.
class SegmentedChoice<T> extends StatelessWidget {
  const SegmentedChoice({
    required this.options,
    required this.selected,
    required this.onSelect,
    required this.labelOf,
    this.semanticsOf,
    this.keyOf,
    super.key,
  });

  final List<T> options;
  final T selected;
  final ValueChanged<T> onSelect;

  /// The word shown on each part.
  final String Function(T option) labelOf;

  /// What a screen reader says, when the word alone is too short.
  final String Function(T option)? semanticsOf;

  /// A key for each part, for tests.
  final Key Function(T option)? keyOf;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: colors.card,
        border: Border.all(color: colors.border),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          for (final option in options)
            Expanded(
              child: Semantics(
                button: true,
                selected: option == selected,
                label: (semanticsOf ?? labelOf)(option),
                excludeSemantics: true,
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    key: keyOf?.call(option),
                    onTap: () => onSelect(option),
                    borderRadius: BorderRadius.circular(10),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      height: 40,
                      alignment: Alignment.center,
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      decoration: BoxDecoration(
                        color: option == selected
                            ? appPrimaryBlue
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          labelOf(option),
                          maxLines: 1,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: option == selected
                                ? FontWeight.bold
                                : FontWeight.w500,
                            color: option == selected
                                ? Colors.white
                                : colors.textBody,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
