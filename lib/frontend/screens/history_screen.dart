import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../backend/models/allocation.dart';
import '../../backend/models/app_transaction.dart';
import '../../backend/models/cycle_history.dart';
import '../../backend/models/wallet.dart';
import '../../backend/services/budget_service.dart';
import '../../backend/services/wallet_service.dart';
import '../../backend/utils/date_format.dart';
import '../../backend/utils/money_format.dart';
import '../../backend/utils/ph_time.dart';
import '../providers/app_settings_provider.dart';
import '../theme/app_buttons.dart';
import '../theme/app_colors.dart';
import '../theme/app_icons.dart';
import '../theme/app_theme.dart';
import '../widgets/category_icon.dart';
import '../widgets/empty_state_view.dart';
import '../widgets/money_text.dart';
import '../widgets/transaction_row.dart' show walletNameFor;
import 'leftover_review_screen.dart';

/// Cash Inflows: month by month, what actually came in, what actually went
/// out, and what is left, from the user's own records only. At a month's
/// end, the user decides what to do with what is left.
class HistoryScreen extends StatefulWidget {
  const HistoryScreen({
    this.cycles,
    this.transactions,
    this.profile,
    this.today,
    this.onReview,
    this.wallets,
    super.key,
  });
  final Stream<List<AllocationCycle>>? cycles;
  final Stream<List<AppTransaction>>? transactions;
  final Stream<Map<String, dynamic>?>? profile;
  final DateTime? today;

  /// Replaces opening the month-end decision: the income it is recorded on,
  /// what is left, and the day after the month. Used by tests.
  final void Function(AllocationCycle, double, DateTime)? onReview;

  /// Replaces the live wallets the rows name. Used by tests.
  final Stream<List<Wallet>>? wallets;
  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  late final _cycles = widget.cycles ?? BudgetService.watchHistory();
  late final _transactions =
      widget.transactions ?? WalletService.watchTransactions();
  // Archived ones too, so money in a wallet since put away still says
  // where it was.
  late final _wallets =
      widget.wallets ?? WalletService.watchWallets(includeArchived: true);

  /// Months whose Money out list is open in full.
  final _expanded = <DateTime>{};

  void _decide(MonthFlow month) {
    final undecided = newestCycles(month.undecided);
    if (undecided.isEmpty) return;
    final end = month.period.end;
    if (widget.onReview != null) {
      widget.onReview!(undecided.first, month.leftToDecide, end);
      return;
    }
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => LeftoverReviewScreen(
          cycle: undecided.first,
          leftover: month.leftToDecide,
          periodEnd: end,
          others: undecided.skip(1).toList(),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text(
        'Cash Inflows',
        style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
      ),
      centerTitle: true,
      backgroundColor: appPrimaryBlue,
      foregroundColor: Colors.white,
      elevation: 0,
    ),
    body: StreamBuilder<List<AppTransaction>>(
      stream: _transactions,
      builder: (context, transactions) => StreamBuilder<List<AllocationCycle>>(
        stream: _cycles,
        builder: (context, cycles) => StreamBuilder<List<Wallet>>(
          stream: _wallets,
          builder: (context, wallets) {
            if (transactions.hasError || cycles.hasError) {
              return const EmptyStateView(
                iconAsset: 'assets/icons/icons8-calendar-96.png',
                title: 'History is unavailable',
                message:
                    'Your records have not been changed. Reopen this screen to try again.',
              );
            }
            if (!cycles.hasData || !transactions.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            return _body(
              context,
              monthFlows(cycles.data!, transactions.data!),
              wallets.data ?? const [],
            );
          },
        ),
      ),
    ),
  );

  Widget _body(
    BuildContext context,
    List<MonthFlow> months,
    List<Wallet> wallets,
  ) {
    if (months.isEmpty) {
      return const EmptyStateView(
        iconAsset: 'assets/icons/icons8-calendar-96.png',
        title: 'Your story starts with income',
        message:
            'Use + to add income. Every month you get money shows up here: what came in, what went out, and what was left.',
      );
    }
    final now = widget.today ?? philippineNow();

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
      children: [
        Text(
          'Only what you recorded: every income and every expense, month by '
          'month.',
          style: TextStyle(fontSize: 12, color: context.appColors.textMuted),
        ),
        const SizedBox(height: 16),
        for (final month in months) ...[
          _MonthSection(
            flow: month,
            now: now,
            wallets: wallets,
            expanded: _expanded.contains(month.month),
            onToggle: () => setState(() {
              if (!_expanded.remove(month.month)) _expanded.add(month.month);
            }),
            onDecide: () => _decide(month),
          ),
          const SizedBox(height: 20),
        ],
      ],
    );
  }
}

/// One month: its totals and the decision about what is left, then every
/// income and every expense recorded in it.
class _MonthSection extends StatelessWidget {
  const _MonthSection({
    required this.flow,
    required this.now,
    required this.wallets,
    required this.expanded,
    required this.onToggle,
    required this.onDecide,
  });

  final MonthFlow flow;
  final DateTime now;
  final List<Wallet> wallets;
  final bool expanded;
  final VoidCallback onToggle;
  final VoidCallback onDecide;

  /// Expenses shown before Show all.
  static const _firstFew = 5;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final masked = context.select<AppSettingsProvider, bool>(
      (settings) => settings.amountsMasked,
    );
    final key = '${flow.month.year}-${flow.month.month}';
    final outShown = expanded || flow.moneyOut.length <= _firstFew
        ? flow.moneyOut
        : flow.moneyOut.take(_firstFew).toList();
    final decision = flow.decision;

    String subtitle(AppTransaction t) => [
      formatShortDate(philippineTime(t.date)),
      if (t.walletId != null) walletNameFor(wallets, t.walletId),
      if ((t.note ?? '').trim().isNotEmpty) t.note!.trim(),
    ].join(' · ');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '${formatMonthName(flow.month)} ${flow.month.year}',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: colors.textPrimary,
          ),
        ),
        const SizedBox(height: 10),
        Container(
          key: Key('month-$key'),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: colors.card,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: colors.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _TotalLine(
                label: 'Money in',
                amount: flow.totalIn,
                sign: '+',
                color: confirmColorOn(context),
              ),
              _TotalLine(
                label: 'Money out',
                amount: flow.totalOut,
                sign: flow.totalOut > 0 ? '-' : null,
                color: dangerColorOn(context),
              ),
              Divider(height: 20, color: colors.border),
              _TotalLine(
                label: 'Left',
                amount: flow.left.abs(),
                sign: flow.left < -0.005 ? '-' : null,
                color: flow.left < -0.005
                    ? dangerColorOn(context)
                    : colors.textPrimary,
                strong: true,
              ),
              if (flow.left < -0.005)
                Text(
                  'More went out than came in this month.',
                  style: TextStyle(fontSize: 12, color: colors.textMuted),
                ),
              if (flow.awaitingDecision(now) && flow.leftToDecide > 0) ...[
                const SizedBox(height: 12),
                ElevatedButton.icon(
                  key: Key('decide-$key'),
                  onPressed: onDecide,
                  style: openButtonStyle(height: 48),
                  icon: const Icon(Icons.arrow_forward, size: 18),
                  label: Text(
                    'Decide what to do with '
                    '${formatPeso(flow.leftToDecide, masked: masked)}',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
                if (flow.keptForGoals > 0.005) ...[
                  const SizedBox(height: 6),
                  Text(
                    'Not counting ${formatPeso(flow.keptForGoals, masked: masked)} '
                    'already saved for goals.',
                    style: TextStyle(fontSize: 12, color: colors.textMuted),
                  ),
                ],
              ] else if (flow.isDecided && decision != null) ...[
                const SizedBox(height: 8),
                Text(switch (decision.decision) {
                  LeftoverDecision.saved =>
                    'You saved ${formatPeso(decision.savedAmount, masked: masked)} '
                        'of what was left.',
                  LeftoverDecision.split =>
                    'You saved ${formatPeso(decision.savedAmount, masked: masked)} '
                        'and kept ${formatPeso(decision.spentAmount, masked: masked)} '
                        'for spending.',
                  _ => 'You kept what was left for spending.',
                }, style: TextStyle(fontSize: 13, color: colors.textBody)),
              ],
            ],
          ),
        ),
        _ListTitle('Money in', count: flow.moneyIn.length),
        _Rows(
          empty: 'Nothing came in this month.',
          rows: [
            for (final t in flow.moneyIn)
              _Row(
                icon: Image.asset(AppIcons.cashInflow),
                title: t.label,
                subtitle: subtitle(t),
                amount: t.amount,
                sign: '+',
                color: confirmColorOn(context),
              ),
          ],
        ),
        _ListTitle('Money out', count: flow.moneyOut.length),
        _Rows(
          empty: 'Nothing went out this month.',
          rows: [
            for (final t in outShown)
              _Row(
                icon: CategoryIcon(t.label, size: 24),
                title: t.label,
                subtitle: subtitle(t),
                amount: t.amount,
                sign: '-',
                color: dangerColorOn(context),
              ),
          ],
        ),
        if (flow.moneyOut.length > _firstFew)
          Center(
            child: TextButton(
              key: Key('show-all-$key'),
              onPressed: onToggle,
              style: TextButton.styleFrom(foregroundColor: colors.primaryText),
              child: Text(
                expanded ? 'Show less' : 'Show all ${flow.moneyOut.length}',
              ),
            ),
          ),
      ],
    );
  }
}

/// One total in a month's summary: a name and an amount.
class _TotalLine extends StatelessWidget {
  const _TotalLine({
    required this.label,
    required this.amount,
    required this.color,
    this.sign,
    this.strong = false,
  });

  final String label;
  final double amount;
  final Color color;
  final String? sign;
  final bool strong;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontSize: strong ? 16 : 14,
                fontWeight: strong ? FontWeight.bold : FontWeight.normal,
                color: strong ? colors.textPrimary : colors.textBody,
              ),
            ),
          ),
          MoneyText(
            amount,
            sign: sign,
            style: TextStyle(
              fontSize: strong ? 20 : 16,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

/// A heading over a month's incomes or expenses, with how many.
class _ListTitle extends StatelessWidget {
  const _ListTitle(this.text, {required this.count});

  final String text;
  final int count;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 16, 2, 8),
      child: Text(
        '$text ($count)',
        style: TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.bold,
          color: colors.textPrimary,
        ),
      ),
    );
  }
}

/// Rows in one card, with lines between them.
class _Rows extends StatelessWidget {
  const _Rows({required this.rows, required this.empty});

  final List<Widget> rows;

  /// Said when there are no rows.
  final String empty;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Container(
      decoration: BoxDecoration(
        color: colors.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colors.border),
      ),
      child: rows.isEmpty
          ? Padding(
              padding: const EdgeInsets.all(16),
              child: Text(empty, style: TextStyle(color: colors.textBody)),
            )
          : Column(
              children: [
                for (var i = 0; i < rows.length; i++) ...[
                  if (i > 0)
                    Divider(height: 1, indent: 64, color: colors.border),
                  rows[i],
                ],
              ],
            ),
    );
  }
}

/// One record: what it was, when and where, and its amount.
class _Row extends StatelessWidget {
  const _Row({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.amount,
    required this.sign,
    required this.color,
  });

  final Widget icon;
  final String title;
  final String subtitle;
  final double amount;
  final String sign;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            padding: const EdgeInsets.all(7),
            decoration: BoxDecoration(
              color: colors.primaryTint,
              borderRadius: BorderRadius.circular(10),
            ),
            child: icon,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: colors.textPrimary,
                  ),
                ),
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12, color: colors.textMuted),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          MoneyText(
            amount,
            sign: sign,
            style: TextStyle(fontWeight: FontWeight.bold, color: color),
          ),
        ],
      ),
    );
  }
}
