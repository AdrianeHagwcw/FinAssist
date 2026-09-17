import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../utils/categories.dart';
import 'money_text.dart';

/// Spending per category as a donut, with the total in the middle.
///
/// Slices are separated by a thin gap in the card's color, and each keeps its
/// category's color on every screen. The legend beside or below it carries
/// the names, so color is never the only way to tell slices apart.
class SpendingDonut extends StatelessWidget {
  const SpendingDonut({
    required this.spending,
    this.size = 180,
    this.onTapCategory,
    super.key,
  });

  /// Category totals, largest first.
  final List<MapEntry<String, double>> spending;
  final double size;
  final ValueChanged<String>? onTapCategory;

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    final colors = context.appColors;
    final total = spending.fold<double>(0, (sum, e) => sum + e.value);
    final thickness = size * 0.16;

    return Semantics(
      label:
          'Spending by category: '
          '${spending.map((e) => e.key).join(', ')}',
      child: SizedBox(
        width: size,
        height: size,
        child: Stack(
          alignment: Alignment.center,
          children: [
            PieChart(
              PieChartData(
                startDegreeOffset: -90,
                sectionsSpace: spending.length > 1 ? 2 : 0,
                centerSpaceRadius: size / 2 - thickness,
                sections: [
                  for (final entry in spending)
                    PieChartSectionData(
                      value: entry.value,
                      color: categoryColor(entry.key, brightness: brightness),
                      radius: thickness,
                      showTitle: false,
                    ),
                ],
                pieTouchData: PieTouchData(
                  enabled: onTapCategory != null,
                  touchCallback: (event, response) {
                    final index = response?.touchedSection?.touchedSectionIndex;
                    if (event is! FlTapUpEvent ||
                        index == null ||
                        index < 0 ||
                        index >= spending.length) {
                      return;
                    }
                    onTapCategory?.call(spending[index].key);
                  },
                ),
              ),
              duration: Duration.zero,
            ),
            Padding(
              padding: EdgeInsets.all(thickness + 8),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Spent',
                      style: TextStyle(fontSize: 12, color: colors.textBody),
                    ),
                    MoneyText(
                      total,
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: colors.textPrimary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The largest [limit] categories, with the rest summed into one entry whose
/// key is null. With no limit, or nothing past it, the list is unchanged.
List<MapEntry<String?, double>> foldSpending(
  List<MapEntry<String, double>> spending,
  int? limit,
) {
  if (limit == null || spending.length <= limit) {
    return [for (final entry in spending) MapEntry(entry.key, entry.value)];
  }

  final rest = spending
      .skip(limit)
      .fold<double>(0, (sum, entry) => sum + entry.value);
  return [
    for (final entry in spending.take(limit)) MapEntry(entry.key, entry.value),
    MapEntry(null, rest),
  ];
}

/// The color for a folded entry: its category's, or a quiet neutral for the
/// summed rest, so it can't be mistaken for a category.
Color _entryColor(BuildContext context, String? category) {
  if (category == null) return context.appColors.border;
  return categoryColor(category, brightness: Theme.of(context).brightness);
}

/// Spending as one thin bar split by category, largest first.
class SpendingBar extends StatelessWidget {
  const SpendingBar({required this.spending, this.limit, super.key});

  final List<MapEntry<String, double>> spending;

  /// Categories past this are drawn as one neutral segment.
  final int? limit;

  @override
  Widget build(BuildContext context) {
    final entries = foldSpending(
      spending,
      limit,
    ).where((entry) => entry.value > 0).toList();
    final total = entries.fold<double>(0, (sum, e) => sum + e.value);
    if (total <= 0) return const SizedBox(height: 10);

    return ClipRRect(
      borderRadius: BorderRadius.circular(5),
      child: SizedBox(
        height: 10,
        child: Row(
          // Stretch, or the segments take their natural height, which is
          // nothing, and the bar never shows.
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var i = 0; i < entries.length; i++) ...[
              if (i > 0)
                SizedBox(
                  width: 2,
                  child: ColoredBox(color: context.appColors.card),
                ),
              Expanded(
                // Flex needs whole numbers; tenths of a percent are plenty.
                flex: ((entries[i].value / total) * 1000).round().clamp(
                  1,
                  1000,
                ),
                child: ColoredBox(color: _entryColor(context, entries[i].key)),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// One row per category: a color key, the name, its share and the amount.
///
/// Kept plain on purpose. The color key ties a row to the chart; icons would
/// add a second, clashing set of colors.
class SpendingLegend extends StatelessWidget {
  const SpendingLegend({
    required this.spending,
    this.limit,
    this.onTapCategory,
    super.key,
  });

  final List<MapEntry<String, double>> spending;

  /// Shows only the largest few, with the rest summed into one line.
  final int? limit;
  final ValueChanged<String>? onTapCategory;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final entries = foldSpending(spending, limit);
    final total = spending.fold<double>(0, (sum, e) => sum + e.value);
    final restCount = limit == null || spending.length <= limit!
        ? 0
        : spending.length - limit!;

    return Column(
      children: [
        for (final entry in entries)
          _row(
            context,
            label: entry.key ?? '$restCount more',
            amount: entry.value,
            share: total <= 0 ? 0 : entry.value / total,
            swatch: _entryColor(context, entry.key),
            labelColor: entry.key == null
                ? colors.textBody
                : colors.textPrimary,
            onTap: entry.key == null || onTapCategory == null
                ? null
                : () => onTapCategory!(entry.key!),
          ),
      ],
    );
  }

  Widget _row(
    BuildContext context, {
    required String label,
    required double amount,
    required double share,
    required Color swatch,
    required Color labelColor,
    VoidCallback? onTap,
  }) {
    final colors = context.appColors;

    final content = Padding(
      padding: const EdgeInsets.symmetric(vertical: 9),
      child: Row(
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              color: swatch,
              borderRadius: BorderRadius.circular(3),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 14, color: labelColor),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 40,
            child: Text(
              '${(share * 100).round()}%',
              textAlign: TextAlign.right,
              style: TextStyle(fontSize: 13, color: colors.textBody),
            ),
          ),
          const SizedBox(width: 12),
          MoneyText(
            amount,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: colors.textPrimary,
            ),
          ),
          if (onTap != null) ...[
            const SizedBox(width: 4),
            Icon(Icons.chevron_right, size: 18, color: colors.textBody),
          ],
        ],
      ),
    );

    if (onTap == null) return content;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: content,
    );
  }
}
