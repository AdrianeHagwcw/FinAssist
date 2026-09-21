import 'dart:async';

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/app_transaction.dart';
import '../models/finance_snapshot.dart';
import '../models/goal.dart';
import '../models/money_tips.dart';
import '../models/report.dart';
import '../models/transaction_filter.dart';
import '../providers/app_settings_provider.dart';
import '../services/finance_snapshot_service.dart';
import '../services/goal_service.dart';
import '../services/wallet_service.dart';
import '../theme/app_buttons.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../utils/money_format.dart';
import '../widgets/money_text.dart';
import '../widgets/spending_chart.dart';
import 'transactions_screen.dart';

/// Summaries, a category breakdown and a trend, all worked out from the
/// user's own transactions across every wallet.
class ReportsScreen extends StatefulWidget {
  const ReportsScreen({
    this.transactions,
    this.contributions,
    this.records,
    this.today,
    this.onOpenCategory,
    super.key,
  });

  /// Replaces the live transactions. Used by tests.
  final Stream<List<AppTransaction>>? transactions;

  /// Replaces the live goal contributions. Used by tests.
  final Stream<List<GoalContribution>>? contributions;

  /// The user's records, for the Financial tips. Tests pass their own.
  final Stream<FinanceSnapshot>? records;

  /// Replaces the clock. Used by tests.
  final DateTime? today;

  /// Replaces opening Transactions for a category. Used by tests.
  final void Function(TransactionFilter filter)? onOpenCategory;

  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen> {
  late final Stream<List<AppTransaction>> _transactions =
      widget.transactions ?? WalletService.watchTransactions();

  late final Stream<List<GoalContribution>> _contributions =
      widget.contributions ?? GoalService.watchAllContributions();

  DateTime get _now => widget.today ?? DateTime.now();

  /// Categories the reader has tapped out of the spending breakdown, so the
  /// rest can be read on its own. This is how the screen is being looked at,
  /// not anything about the account, so it is held here and never saved.
  final Set<String> _setAside = <String>{};

  /// Leaves a category out of the breakdown, or counts it again.
  void _toggleCategory(String category) {
    setState(() {
      if (!_setAside.remove(category)) _setAside.add(category);
    });
  }

  /// Kept here rather than read in the list, which drops sections scrolled
  /// out of view.
  FinanceSnapshot? _records;
  StreamSubscription<FinanceSnapshot>? _recordsSubscription;

  @override
  void initState() {
    super.initState();
    _recordsSubscription = (widget.records ?? watchFinanceSnapshot()).listen((
      records,
    ) {
      if (mounted) setState(() => _records = records);
    }, onError: (Object _) {});
  }

  @override
  void dispose() {
    _recordsSubscription?.cancel();
    super.dispose();
  }

  ReportRange _range = ReportRange.month;
  late ReportPeriod _period = ReportPeriod.monthOf(_now);

  void _selectRange(ReportRange range) async {
    if (range == ReportRange.custom) {
      final picked = await showDateRangePicker(
        context: context,
        firstDate: DateTime(2020),
        lastDate: DateTime(_now.year, _now.month, _now.day),
        initialDateRange: DateTimeRange(
          start: _period.start,
          end: _period.end.isAfter(_now) ? _dayOf(_now) : _period.end,
        ),
      );
      if (picked == null || !mounted) return;

      setState(() {
        _range = ReportRange.custom;
        _period = ReportPeriod(_dayOf(picked.start), _dayOf(picked.end));
      });
      return;
    }

    setState(() {
      _range = range;
      _period = range == ReportRange.week
          ? ReportPeriod.weekOf(_now)
          : ReportPeriod.monthOf(_now);
    });
  }

  /// Steps to the week or month before or after. Never past the current one.
  void _step(int direction) {
    setState(() {
      if (direction < 0) {
        _period = _period.previous(_range);
      } else {
        final next = _range == ReportRange.week
            ? ReportPeriod.weekOf(_period.end.add(const Duration(days: 1)))
            : ReportPeriod.monthOf(
                DateTime(_period.start.year, _period.start.month + 1),
              );
        _period = next;
      }
    });
  }

  bool get _isCurrent => _period.contains(_now);

  void _openCategory(String category) {
    final filter = TransactionFilter(
      type: TransactionType.expense,
      category: category,
      from: _period.start,
      to: _period.end,
    );

    if (widget.onOpenCategory != null) {
      widget.onOpenCategory!(filter);
      return;
    }

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) =>
            TransactionsScreen(initialFilter: filter, showLegacyImport: false),
      ),
    );
  }

  String _trendSubtitle(int count) {
    final unit = _range == ReportRange.week ? 'week' : 'month';
    final span = count == 1
        ? 'This $unit, since your records start here'
        : 'The last $count ${unit}s';
    return '$span. Tap a bar for its exact amount.';
  }

  static DateTime _dayOf(DateTime date) =>
      DateTime(date.year, date.month, date.day);

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    return Scaffold(
      backgroundColor: colors.pageBackground,
      appBar: AppBar(
        title: const Text(
          'Reports',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
        ),
        centerTitle: true,
        backgroundColor: appPrimaryBlue,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: StreamBuilder<List<AppTransaction>>(
        stream: _transactions,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return const _Message(
              icon: Icons.cloud_off_outlined,
              title: 'Reports could not load',
              body: 'Check your connection and open Reports again.',
            );
          }

          final transactions = snapshot.data;
          if (transactions == null) {
            return const Center(child: CircularProgressIndicator());
          }

          if (transactions.isEmpty) {
            return const _Message(
              icon: Icons.insert_chart_outlined,
              title: 'Nothing to report yet',
              body:
                  'Log an expense or add income, and your summaries and '
                  'charts will show up here.',
            );
          }

          return StreamBuilder<List<GoalContribution>>(
            stream: _contributions,
            builder: (context, contributionSnapshot) {
              final contributions =
                  contributionSnapshot.data ?? const <GoalContribution>[];

              return _buildReport(context, transactions, contributions);
            },
          );
        },
      ),
    );
  }

  Widget _buildReport(
    BuildContext context,
    List<AppTransaction> transactions,
    List<GoalContribution> contributions,
  ) {
    final colors = context.appColors;
    final inPeriod = transactionsIn(transactions, _period);
    final summary = summarize(transactions, contributions, _period);
    final spending = spendingByCategory(inPeriod);
    final counted = [
      for (final entry in spending)
        if (!_setAside.contains(entry.key)) entry,
    ];
    final points = trend(
      transactions,
      range: _range,
      end: _period.end.isAfter(_now) ? _now : _period.end,
    );
    final insights = insightsFor(transactions, period: _period, range: _range);

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      children: [
        SegmentedButton<ReportRange>(
          segments: [
            for (final range in ReportRange.values)
              ButtonSegment(value: range, label: Text(range.label)),
          ],
          selected: {_range},
          showSelectedIcon: false,
          onSelectionChanged: (selection) => _selectRange(selection.first),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            if (_range != ReportRange.custom)
              IconButton(
                tooltip: 'Earlier',
                onPressed: () => _step(-1),
                icon: const Icon(Icons.chevron_left),
              )
            else
              const SizedBox(width: 48),
            Expanded(
              child: Text(
                _period.label,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: colors.textPrimary,
                ),
              ),
            ),
            if (_range != ReportRange.custom)
              IconButton(
                tooltip: 'Later',
                onPressed: _isCurrent ? null : () => _step(1),
                icon: const Icon(Icons.chevron_right),
              )
            else
              IconButton(
                tooltip: 'Change dates',
                onPressed: () => _selectRange(ReportRange.custom),
                icon: const Icon(Icons.edit_calendar_outlined),
              ),
          ],
        ),
        const SizedBox(height: 8),
        _SummaryGrid(summary: summary),
        const SizedBox(height: 16),
        _Section(
          title: 'Spending by category',
          subtitle: spending.isEmpty
              ? null
              : counted.length == spending.length
              ? 'Tap one to leave it out. The arrow opens its expenses.'
              : 'Counting ${counted.length} of ${spending.length}. '
                    'Tap a crossed-out one to count it again.',
          child: spending.isEmpty
              ? const _EmptyNote('No spending in this period.')
              : Column(
                  children: [
                    if (counted.isEmpty)
                      const _EmptyNote('Every category is left out.')
                    else
                      SpendingDonut(
                        spending: counted,
                        onTapCategory: _openCategory,
                      ),
                    const SizedBox(height: 12),
                    SpendingLegend(
                      spending: spending,
                      hidden: _setAside,
                      onToggleCategory: _toggleCategory,
                      onTapCategory: _openCategory,
                    ),
                    if (_setAside.isNotEmpty)
                      Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton(
                          onPressed: () => setState(_setAside.clear),
                          child: const Text('Count all again'),
                        ),
                      ),
                  ],
                ),
        ),
        const SizedBox(height: 16),
        _Section(
          title: 'Money in vs. money out',
          subtitle: _trendSubtitle(points.length),
          child: _TrendChart(points: points),
        ),
        const SizedBox(height: 16),
        _Section(
          title: 'Insights',
          child: insights.isEmpty
              ? const _EmptyNote(
                  'Insights show up once there is some spending to look at.',
                )
              : Column(
                  children: [
                    for (final line in insights)
                      _Line(icon: Icons.lightbulb_outline, text: line),
                  ],
                ),
        ),
        const SizedBox(height: 16),
        _Section(
          title: 'Financial tips',
          subtitle: 'From your recent spending.',
          child: _records == null
              ? const _EmptyNote(
                  'Tips show up once your records load.',
                  icon: Icons.tips_and_updates_outlined,
                )
              : Column(
                  children: [
                    for (final tip in moneyTipsFor(_records!.at(_now)))
                      _Line(icon: Icons.tips_and_updates_outlined, text: tip),
                  ],
                ),
        ),
      ],
    );
  }
}

class _SummaryGrid extends StatelessWidget {
  const _SummaryGrid({required this.summary});

  final ReportSummary summary;

  @override
  Widget build(BuildContext context) {
    final green = confirmColorOn(context);
    final red = dangerColorOn(context);
    final net = summary.netChange;

    Widget tile(String label, double amount, Color color, {String? sign}) {
      return Expanded(
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: context.appColors.card,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: context.appColors.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  color: context.appColors.textBody,
                ),
              ),
              const SizedBox(height: 4),
              MoneyText(
                amount,
                sign: sign,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: color,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Column(
      children: [
        Row(
          children: [
            tile('Income', summary.income, green),
            const SizedBox(width: 10),
            tile('Expenses', summary.expenses, red),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            tile(
              'Saved to goals',
              summary.saved,
              context.appColors.primaryText,
            ),
            const SizedBox(width: 10),
            tile(
              'Net change',
              net.abs(),
              net < -0.005 ? red : green,
              sign: net < -0.005 ? '-' : '+',
            ),
          ],
        ),
      ],
    );
  }
}

/// Money in and money out for each recent period, side by side on one peso
/// axis. Bars rather than lines: each is a separate total, and a line would
/// suggest money moved steadily between them.
class _TrendChart extends StatelessWidget {
  const _TrendChart({required this.points});

  final List<TrendPoint> points;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final masked = context.select<AppSettingsProvider, bool>(
      (settings) => settings.amountsMasked,
    );
    final green = confirmColorOn(context);
    final red = dangerColorOn(context);

    var highest = 0.0;
    for (final point in points) {
      if (point.moneyIn > highest) highest = point.moneyIn;
      if (point.moneyOut > highest) highest = point.moneyOut;
    }

    if (highest <= 0) {
      return const _EmptyNote('No money in or out in these periods yet.');
    }

    // Four or five round gridlines, with room above the tallest bar so it
    // never touches the top.
    final step = _niceStep(highest / 4);
    final maxY = step * (highest * 1.1 / step).ceil();
    final barWidth = points.length > 4 ? 12.0 : 18.0;

    Widget key(String label, Color color) => Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(3),
          ),
        ),
        const SizedBox(width: 6),
        Text(label, style: TextStyle(fontSize: 12, color: colors.textBody)),
      ],
    );

    BarChartRodData rod(double value, Color color) => BarChartRodData(
      toY: value,
      color: color,
      width: barWidth,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
    );

    return Column(
      children: [
        Row(
          children: [
            key('Money in', green),
            const SizedBox(width: 16),
            key('Money out', red),
          ],
        ),
        const SizedBox(height: 16),
        SizedBox(
          height: 200,
          child: BarChart(
            BarChartData(
              minY: 0,
              maxY: maxY,
              alignment: BarChartAlignment.spaceAround,
              barGroups: [
                for (var i = 0; i < points.length; i++)
                  BarChartGroupData(
                    x: i,
                    barsSpace: 2,
                    barRods: [
                      rod(points[i].moneyIn, green),
                      rod(points[i].moneyOut, red),
                    ],
                  ),
              ],
              gridData: FlGridData(
                drawVerticalLine: false,
                horizontalInterval: step,
                getDrawingHorizontalLine: (_) =>
                    FlLine(color: colors.border, strokeWidth: 1),
              ),
              borderData: FlBorderData(
                show: true,
                border: Border(bottom: BorderSide(color: colors.border)),
              ),
              titlesData: FlTitlesData(
                topTitles: const AxisTitles(),
                rightTitles: const AxisTitles(),
                leftTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: !masked,
                    reservedSize: 44,
                    interval: step,
                    getTitlesWidget: (value, meta) => SideTitleWidget(
                      meta: meta,
                      child: Text(
                        formatPesoCompact(value),
                        style: TextStyle(fontSize: 10, color: colors.textBody),
                      ),
                    ),
                  ),
                ),
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 26,
                    getTitlesWidget: (value, meta) {
                      final index = value.round();
                      if (index < 0 || index >= points.length) {
                        return const SizedBox.shrink();
                      }
                      return SideTitleWidget(
                        meta: meta,
                        child: Text(
                          points[index].label,
                          style: TextStyle(
                            fontSize: 10,
                            color: colors.textBody,
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
              barTouchData: BarTouchData(
                touchTooltipData: BarTouchTooltipData(
                  fitInsideHorizontally: true,
                  fitInsideVertically: true,
                  tooltipBorderRadius: BorderRadius.circular(8),
                  tooltipBorder: BorderSide(color: colors.border),
                  getTooltipColor: (_) => colors.card,
                  getTooltipItem: (group, groupIndex, rod, rodIndex) =>
                      BarTooltipItem(
                        '${points[groupIndex].label} · '
                        '${rodIndex == 0 ? 'In' : 'Out'}\n'
                        '${formatPeso(rod.toY, masked: masked)}',
                        TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: colors.textPrimary,
                        ),
                      ),
                ),
              ),
            ),
            duration: Duration.zero,
          ),
        ),
      ],
    );
  }

  /// 1, 2 or 5 times a power of ten, at least [rough].
  static double _niceStep(double rough) {
    if (rough <= 0) return 1;
    var magnitude = 1.0;
    while (magnitude * 10 <= rough) {
      magnitude *= 10;
    }
    while (magnitude > rough) {
      magnitude /= 10;
    }
    for (final factor in [1, 2, 5, 10]) {
      if (magnitude * factor >= rough) return magnitude * factor;
    }
    return magnitude * 10;
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.child, this.subtitle});

  final String title;
  final String? subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: colors.textPrimary,
            ),
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 2),
            Text(
              subtitle!,
              style: TextStyle(fontSize: 12, color: colors.textBody),
            ),
          ],
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}

/// One line of Insights or Financial tips: an icon and a sentence.
class _Line extends StatelessWidget {
  const _Line({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: appPrimaryBlue),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: TextStyle(color: context.appColors.textBody, height: 1.4),
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyNote extends StatelessWidget {
  const _EmptyNote(this.text, {this.icon});

  final String text;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    return Row(
      children: [
        if (icon != null) ...[
          Icon(icon, color: colors.textBody),
          const SizedBox(width: 10),
        ],
        Expanded(
          child: Text(
            text,
            style: TextStyle(color: colors.textBody, height: 1.4),
          ),
        ),
      ],
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({required this.icon, required this.title, required this.body});

  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 56, color: appPrimaryBlue),
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
              body,
              textAlign: TextAlign.center,
              style: TextStyle(color: colors.textBody, height: 1.4),
            ),
          ],
        ),
      ),
    );
  }
}
