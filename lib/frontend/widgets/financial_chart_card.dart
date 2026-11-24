import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:material_ui/material_ui.dart';

import '../../backend/models/financial_chart.dart';
import '../../backend/utils/money_format.dart';
import '../theme/app_colors.dart';

class FinancialChartCard extends StatelessWidget {
  const FinancialChartCard({required this.data, super.key});

  final FinancialChartData data;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(left: 38, right: 8, bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colors.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: colors.border),
      ),
      child: data.available
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  data.title,
                  style: TextStyle(
                    color: colors.textPrimary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  data.periodLabel,
                  style: TextStyle(fontSize: 11, color: colors.textBody),
                ),
                const SizedBox(height: 12),
                SizedBox(height: 210, child: _chart(context)),
                const SizedBox(height: 8),
                _legend(context),
              ],
            )
          : Text(
              '${data.title}\n\n${data.unavailableReason}',
              style: TextStyle(color: colors.textBody, height: 1.4),
            ),
    );
  }

  Widget _chart(BuildContext context) => switch (data.type) {
    FinancialChartType.bar => _barChart(context),
    FinancialChartType.pie => _pieChart(context),
    FinancialChartType.line => _lineChart(context),
    FinancialChartType.progress => _progressChart(context),
  };

  Widget _barChart(BuildContext context) {
    final colors = context.appColors;
    final values = data.series.values.first;
    final maxValue = values.fold<double>(0, math.max);
    final interval = _interval(maxValue);
    return BarChart(
      BarChartData(
        minY: 0,
        maxY: interval * 5,
        alignment: BarChartAlignment.spaceAround,
        gridData: FlGridData(
          drawVerticalLine: false,
          horizontalInterval: interval,
          getDrawingHorizontalLine: (_) =>
              FlLine(color: colors.border, strokeWidth: 1),
        ),
        borderData: FlBorderData(
          border: Border(bottom: BorderSide(color: colors.border)),
        ),
        barGroups: [
          for (var i = 0; i < values.length; i++)
            BarChartGroupData(
              x: i,
              barRods: [
                BarChartRodData(
                  toY: values[i],
                  color: _color(i),
                  width: math.min(28, 180 / values.length),
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(4),
                  ),
                ),
              ],
            ),
        ],
        titlesData: _titles(context, leftInterval: interval, bottom: true),
        barTouchData: BarTouchData(enabled: false),
      ),
    );
  }

  Widget _pieChart(BuildContext context) {
    final values = data.series.values.first;
    final total = values.fold<double>(0, (a, b) => a + b);
    return PieChart(
      PieChartData(
        sectionsSpace: 2,
        centerSpaceRadius: 28,
        sections: [
          for (var i = 0; i < values.length; i++)
            PieChartSectionData(
              value: values[i],
              color: _color(i),
              title: total == 0 ? '' : '${(values[i] / total * 100).round()}%',
              radius: 72,
              titleStyle: const TextStyle(
                color: Colors.white,
                fontSize: 11,
                fontWeight: FontWeight.bold,
              ),
            ),
        ],
      ),
    );
  }

  Widget _lineChart(BuildContext context) {
    final colors = context.appColors;
    final allValues = data.series.values.expand((values) => values);
    final maxValue = allValues.fold<double>(0, math.max);
    final interval = _interval(maxValue);
    return LineChart(
      LineChartData(
        minY: 0,
        maxY: interval * 5,
        gridData: FlGridData(
          drawVerticalLine: false,
          horizontalInterval: interval,
          getDrawingHorizontalLine: (_) =>
              FlLine(color: colors.border, strokeWidth: 1),
        ),
        borderData: FlBorderData(
          border: Border(bottom: BorderSide(color: colors.border)),
        ),
        lineBarsData: [
          for (
            var seriesIndex = 0;
            seriesIndex < data.series.length;
            seriesIndex++
          )
            LineChartBarData(
              spots: [
                for (
                  var i = 0;
                  i < data.series.values.elementAt(seriesIndex).length;
                  i++
                )
                  FlSpot(
                    i.toDouble(),
                    data.series.values.elementAt(seriesIndex)[i],
                  ),
              ],
              color: _color(seriesIndex),
              barWidth: 3,
              dotData: const FlDotData(show: true),
            ),
        ],
        titlesData: _titles(context, leftInterval: interval, bottom: true),
      ),
    );
  }

  Widget _progressChart(BuildContext context) {
    final values = data.series.values.first;
    return BarChart(
      BarChartData(
        minY: 0,
        maxY: 100,
        barGroups: [
          for (var i = 0; i < values.length; i++)
            BarChartGroupData(
              x: i,
              barRods: [
                BarChartRodData(
                  toY: values[i].clamp(0, 100),
                  color: _color(i),
                  width: math.min(28, 180 / values.length),
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(4),
                  ),
                ),
              ],
            ),
        ],
        titlesData: _titles(context, leftInterval: 25, bottom: true),
        gridData: FlGridData(
          drawVerticalLine: false,
          horizontalInterval: 25,
          getDrawingHorizontalLine: (_) =>
              FlLine(color: context.appColors.border, strokeWidth: 1),
        ),
        borderData: FlBorderData(
          border: Border(bottom: BorderSide(color: context.appColors.border)),
        ),
        barTouchData: BarTouchData(enabled: false),
      ),
    );
  }

  FlTitlesData _titles(
    BuildContext context, {
    required double leftInterval,
    required bool bottom,
  }) {
    final colors = context.appColors;
    return FlTitlesData(
      topTitles: const AxisTitles(),
      rightTitles: const AxisTitles(),
      leftTitles: AxisTitles(
        sideTitles: SideTitles(
          showTitles: true,
          reservedSize: 42,
          interval: leftInterval,
          getTitlesWidget: (value, meta) => Text(
            data.type == FinancialChartType.progress
                ? '${value.round()}%'
                : formatPesoCompact(value),
            style: TextStyle(fontSize: 9, color: colors.textBody),
          ),
        ),
      ),
      bottomTitles: AxisTitles(
        sideTitles: SideTitles(
          showTitles: bottom,
          reservedSize: 30,
          getTitlesWidget: (value, meta) {
            final index = value.round();
            if (index < 0 || index >= data.labels.length) {
              return const SizedBox.shrink();
            }
            return SideTitleWidget(
              meta: meta,
              child: Text(
                data.labels[index],
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 9, color: colors.textBody),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _legend(BuildContext context) {
    final colors = context.appColors;
    final legendLabels = data.type == FinancialChartType.pie
        ? data.labels
        : data.series.length == 1 &&
              data.labels.length == data.series.values.first.length
        ? data.labels
        : data.series.keys.toList();
    return Wrap(
      spacing: 12,
      runSpacing: 4,
      children: [
        for (var i = 0; i < legendLabels.length; i++)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 9,
                height: 9,
                decoration: BoxDecoration(
                  color: _color(i),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 4),
              Text(
                legendLabels[i],
                style: TextStyle(fontSize: 10, color: colors.textBody),
              ),
            ],
          ),
      ],
    );
  }

  double _interval(double maxValue) {
    if (maxValue <= 0) return 1;
    final raw = maxValue / 4;
    final magnitude = math.pow(10, (math.log(raw) / math.ln10).floor());
    return math.max(1, (raw / magnitude).ceil() * magnitude).toDouble();
  }

  Color _color(int index) {
    const colors = [
      Color(0xff3d8bfd),
      Color(0xff43b581),
      Color(0xffffb454),
      Color(0xffe76f51),
      Color(0xff9b72cf),
      Color(0xff2a9d8f),
    ];
    return colors[index % colors.length];
  }
}
