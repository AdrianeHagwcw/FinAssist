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
import '../widgets/choice_grid.dart';
import '../widgets/empty_state_view.dart';
import '../widgets/money_text.dart';
import '../widgets/transaction_row.dart' show walletNameFor;
import 'leftover_review_screen.dart';

/// Cash Inflows: every time money came in, month by month, and where each
/// income went: bills paid, money saved for goals, what was spent out of it
/// and what is left.
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
  final void Function(AllocationCycle, double, DateTime)? onReview;

  /// Replaces the live wallets an income's details name. Used by tests.
  final Stream<List<Wallet>>? wallets;
  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

/// One income in the list: planned when it was logged, or recorded without
/// a plan, like interest from a bank.
sealed class _Entry {
  DateTime get date;
}

class _Planned extends _Entry {
  _Planned(this.cycle, this.spent, this.left, this.payments);
  final AllocationCycle cycle;
  final double spent;
  final double left;

  /// The payments taken out of it, which [spent] adds up.
  final List<CyclePayment> payments;
  @override
  DateTime get date => cycle.receivedAt;
}

class _Unplanned extends _Entry {
  _Unplanned(this.transaction);
  final AppTransaction transaction;
  @override
  DateTime get date => transaction.date;
}

class _HistoryScreenState extends State<HistoryScreen> {
  late final _cycles = widget.cycles ?? BudgetService.watchHistory();
  late final _transactions =
      widget.transactions ?? WalletService.watchTransactions();
  bool _pendingOnly = false;

  /// The Philippine month [date] falls in.
  static DateTime _monthOf(DateTime date) {
    final ph = philippineTime(date);
    return DateTime(ph.year, ph.month);
  }

  /// Income recorded without a plan, like interest: every income record
  /// that no planned income was saved with, so the list holds everything
  /// Inflow counts.
  static List<AppTransaction> _unplanned(
    List<AllocationCycle> cycles,
    List<AppTransaction> transactions,
  ) {
    final planned = {for (final cycle in cycles) ...cycle.incomeTransactionIds};
    bool olderPlan(AppTransaction t) => cycles.any(
      (cycle) =>
          cycle.incomeTransactionIds.isEmpty &&
          cycle.receivedAt == t.date &&
          cycle.source == t.label,
    );
    return [
      for (final t in transactions)
        if (t.type == TransactionType.income &&
            !t.isDebtMovement &&
            !planned.contains(t.id) &&
            !olderPlan(t))
          t,
    ];
  }

  void _review(AllocationCycle cycle, double left) {
    final end = periodOf(cycle).end;
    if (widget.onReview != null) {
      widget.onReview!(cycle, left, end);
      return;
    }
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) =>
            LeftoverReviewScreen(cycle: cycle, leftover: left, periodEnd: end),
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
        builder: (context, cycles) {
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
          return _body(context, cycles.data!, transactions.data!);
        },
      ),
    ),
  );

  Widget _body(
    BuildContext context,
    List<AllocationCycle> cycles,
    List<AppTransaction> transactions,
  ) {
    final unplanned = _unplanned(cycles, transactions);
    if (cycles.isEmpty && unplanned.isEmpty) {
      return const EmptyStateView(
        iconAsset: 'assets/icons/icons8-calendar-96.png',
        title: 'Your story starts with income',
        message:
            'Use + to add income and plan it. Every cash inflow you log shows up here: what came in, where it went, and what was left.',
      );
    }

    final now = widget.today ?? philippineNow();
    final payments = paymentsByCycle(cycles, transactions);
    final spending = spendingByCycle(cycles, transactions);
    final entries = <_Entry>[
      for (final cycle in cycles)
        if (cycle.isResolved)
          // A decided leftover keeps what was decided.
          _Planned(
            cycle,
            (cycle.remaining - cycle.savedAmount - cycle.spentAmount).clamp(
              0.0,
              double.infinity,
            ),
            cycle.savedAmount + cycle.spentAmount,
            payments[cycle.id] ?? const [],
          )
        else
          _Planned(
            cycle,
            spending[cycle.id] ?? 0,
            (cycle.remaining - (spending[cycle.id] ?? 0)).clamp(
              0.0,
              double.infinity,
            ),
            payments[cycle.id] ?? const [],
          ),
      for (final t in unplanned) _Unplanned(t),
    ]..sort((a, b) => b.date.compareTo(a.date));

    bool pending(_Entry entry) =>
        entry is _Planned &&
        cycleStatus(entry.cycle, now) == CycleStatus.pending;
    final pendingCount = entries.where(pending).length;
    final shown = _pendingOnly ? entries.where(pending).toList() : entries;

    // Newest month first, each with what came in during it.
    final months = <DateTime, List<_Entry>>{};
    for (final entry in shown) {
      months.putIfAbsent(_monthOf(entry.date), () => []).add(entry);
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
      children: [
        ChoiceGrid<bool>(
          options: const [false, true],
          selected: _pendingOnly,
          label: (needsDecision) => needsDecision
              ? 'Needs a decision ($pendingCount)'
              : 'All (${entries.length})',
          keyOf: (needsDecision) =>
              needsDecision ? 'inflows-pending' : 'inflows-all',
          onPick: (needsDecision) =>
              setState(() => _pendingOnly = needsDecision),
        ),
        const SizedBox(height: 10),
        Text(
          'Each payment is taken from the money that came in first, so '
          'nothing is counted twice.',
          style: TextStyle(fontSize: 12, color: context.appColors.textMuted),
        ),
        const SizedBox(height: 18),
        if (shown.isEmpty)
          Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              'All caught up. Nothing needs a decision.',
              textAlign: TextAlign.center,
              style: TextStyle(color: context.appColors.textBody),
            ),
          ),
        for (final month in months.entries) ...[
          _MonthHeader(
            month: month.key,
            total: month.value.fold<double>(
              0,
              (sum, entry) => switch (entry) {
                _Planned(:final cycle) => sum + cycle.income,
                _Unplanned(:final transaction) => sum + transaction.amount,
              },
            ),
            count: month.value.length,
          ),
          for (final entry in month.value)
            switch (entry) {
              _Planned() => _IncomeCard(
                entry: entry,
                status: cycleStatus(entry.cycle, now),
                onReview: () => _review(entry.cycle, entry.left),
                onOpen: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => _IncomeDetailScreen(
                      entry: entry,
                      status: cycleStatus(entry.cycle, now),
                      transactions: transactions,
                      wallets: widget.wallets,
                      onReview: () => _review(entry.cycle, entry.left),
                    ),
                  ),
                ),
              ),
              _Unplanned(:final transaction) => _UnplannedRow(
                transaction: transaction,
              ),
            },
          const SizedBox(height: 8),
        ],
      ],
    );
  }
}

/// A month's name and what came in during it.
class _MonthHeader extends StatelessWidget {
  const _MonthHeader({
    required this.month,
    required this.total,
    required this.count,
  });

  final DateTime month;
  final double total;
  final int count;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${formatMonthName(month)} ${month.year}',
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.bold,
                    color: colors.textPrimary,
                  ),
                ),
                Text(
                  count == 1 ? '1 inflow' : '$count inflows',
                  style: TextStyle(fontSize: 12, color: colors.textMuted),
                ),
              ],
            ),
          ),
          // Named, so it is not read as one income: everything that came
          // in that month, added up.
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                'Total came in',
                style: TextStyle(fontSize: 12, color: colors.textMuted),
              ),
              MoneyText(
                total,
                sign: '+',
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.bold,
                  color: confirmColorOn(context),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// One planned income: what came in, a bar of where it went, and what the
/// user still has to decide.
class _IncomeCard extends StatelessWidget {
  const _IncomeCard({
    required this.entry,
    required this.status,
    required this.onReview,
    this.onOpen,
  });

  final _Planned entry;
  final CycleStatus status;
  final VoidCallback onReview;

  /// Opens the details: every payment that came out of it. Null on the
  /// details page itself.
  final VoidCallback? onOpen;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final masked = context.select<AppSettingsProvider, bool>(
      (settings) => settings.amountsMasked,
    );
    final cycle = entry.cycle;
    final over = entry.spent - cycle.remaining;
    final (label, color) = switch (status) {
      CycleStatus.active => ('In progress', colors.primaryText),
      CycleStatus.pending => (
        'Needs a decision',
        context.isDarkMode ? Colors.amber.shade200 : Colors.brown.shade700,
      ),
      CycleStatus.done => ('Done', confirmColorOn(context)),
      CycleStatus.declined => ('Kept for spending', colors.textBody),
    };
    final lastDay = periodOf(cycle).end.subtract(const Duration(days: 1));

    // Where it went: bills, goals, spending, and what is left. Spending past
    // what it had is said in words below, not drawn past the bar.
    final parts = <({String label, double amount, Color color})>[
      (
        label: 'Paid on bills',
        amount: cycle.toBills,
        color: colors.primaryText,
      ),
      (
        label: cycle.goalName == null
            ? 'Saved for goals'
            : 'Saved for ${cycle.goalName}',
        amount: cycle.toGoal,
        color: const Color(0xFF9C6ADE),
      ),
      (
        label: 'Spent',
        amount: over > 0.005 ? cycle.remaining : entry.spent,
        color: dangerColorOn(context),
      ),
      (label: 'Left', amount: entry.left, color: confirmColorOn(context)),
    ];
    final total = parts.fold<double>(0, (sum, part) => sum + part.amount);

    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(16),
      side: BorderSide(color: colors.border),
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: colors.card,
        shape: shape,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          key: Key('inflow-open-${cycle.id}'),
          onTap: onOpen,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: colors.primaryTint,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Image.asset(AppIcons.cashInflow),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            cycle.source,
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: colors.textPrimary,
                            ),
                          ),
                          Text(
                            'Came in ${formatShortDate(philippineTime(cycle.receivedAt))}',
                            style: TextStyle(
                              fontSize: 12,
                              color: colors.textMuted,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: .12),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        label,
                        style: TextStyle(
                          color: color,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    // Says the card opens, on the list only.
                    if (onOpen != null)
                      Padding(
                        padding: const EdgeInsets.only(left: 2, top: 3),
                        child: Icon(
                          Icons.chevron_right,
                          color: colors.textMuted,
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                MoneyText(
                  cycle.income,
                  sign: '+',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: confirmColorOn(context),
                  ),
                ),
                const SizedBox(height: 12),
                if (total > 0)
                  ClipRRect(
                    borderRadius: BorderRadius.circular(5),
                    child: SizedBox(
                      height: 10,
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          for (final part in parts)
                            if (part.amount > 0.005)
                              Expanded(
                                flex: (part.amount / total * 1000)
                                    .round()
                                    .clamp(1, 1000),
                                child: ColoredBox(color: part.color),
                              ),
                        ],
                      ),
                    ),
                  ),
                const SizedBox(height: 10),
                for (var i = 0; i < parts.length; i += 2)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      children: [
                        Expanded(child: _Key(part: parts[i])),
                        const SizedBox(width: 14),
                        Expanded(child: _Key(part: parts[i + 1])),
                      ],
                    ),
                  ),
                if (over > 0.005) ...[
                  const SizedBox(height: 6),
                  Text(
                    '${formatPeso(over, masked: masked)} more went out than this '
                    'income had',
                    key: const Key('inflow-over'),
                    style: TextStyle(
                      color: dangerColorOn(context),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
                const SizedBox(height: 10),
                switch (status) {
                  CycleStatus.active => Text(
                    'Still counting. On ${formatMonthDay(lastDay)} you decide what '
                    'to do with what is left.',
                    style: TextStyle(fontSize: 12, color: colors.textMuted),
                  ),
                  CycleStatus.pending => SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: onReview,
                      style: openButtonStyle(height: 48),
                      icon: const Icon(Icons.arrow_forward, size: 18),
                      label: const Text(
                        'Decide what is left',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                  CycleStatus.done || CycleStatus.declined => Text(
                    cycle.decision == LeftoverDecision.split
                        ? 'You saved part of what was left and kept the rest.'
                        : cycle.decision == LeftoverDecision.saved
                        ? 'You saved what was left.'
                        : 'You kept what was left for spending.',
                    style: TextStyle(fontSize: 12, color: colors.textMuted),
                  ),
                },
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// One income, in full: the card, then what is behind each of its numbers,
/// so the arithmetic can be checked line by line.
class _IncomeDetailScreen extends StatefulWidget {
  const _IncomeDetailScreen({
    required this.entry,
    required this.status,
    required this.transactions,
    required this.onReview,
    this.wallets,
  });

  final _Planned entry;
  final CycleStatus status;
  final List<AppTransaction> transactions;
  final VoidCallback onReview;
  final Stream<List<Wallet>>? wallets;

  @override
  State<_IncomeDetailScreen> createState() => _IncomeDetailScreenState();
}

class _IncomeDetailScreenState extends State<_IncomeDetailScreen> {
  // Archived ones too, so money that went into a wallet since put away
  // still says where it went.
  late final _wallets =
      widget.wallets ?? WalletService.watchWallets(includeArchived: true);

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final cycle = widget.entry.cycle;
    final byId = {for (final t in widget.transactions) t.id: t};
    final incomeRecords = [
      for (final id in cycle.incomeTransactionIds) ?byId[id],
    ];
    final billPayments = [for (final id in cycle.planPaymentIds) ?byId[id]];

    return Scaffold(
      backgroundColor: colors.pageBackground,
      appBar: AppBar(
        title: Text(
          cycle.source,
          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
        ),
        centerTitle: true,
        backgroundColor: appPrimaryBlue,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: StreamBuilder<List<Wallet>>(
        stream: _wallets,
        builder: (context, snapshot) {
          final wallets = snapshot.data ?? const <Wallet>[];
          return ListView(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
            children: [
              _IncomeCard(
                entry: widget.entry,
                status: widget.status,
                onReview: widget.onReview,
              ),
              if (incomeRecords.isNotEmpty) ...[
                const _SectionTitle('Went into'),
                _Rows(
                  rows: [
                    for (final t in incomeRecords)
                      _Row(
                        icon: Image.asset(AppIcons.cashInflow),
                        title: walletNameFor(wallets, t.walletId),
                        amount: t.amount,
                        sign: '+',
                        color: confirmColorOn(context),
                      ),
                  ],
                ),
              ],
              if (cycle.toBills > 0.005) ...[
                const _SectionTitle('Paid on bills when it came in'),
                _Rows(
                  rows: [
                    for (final t in billPayments)
                      _Row(
                        icon: CategoryIcon(t.label, size: 24),
                        title: t.note ?? t.label,
                        subtitle: walletNameFor(wallets, t.walletId),
                        amount: t.amount,
                        sign: '-',
                      ),
                  ],
                  empty: 'Paid from this income when it was logged.',
                ),
              ],
              if (cycle.toGoal > 0.005) ...[
                const _SectionTitle('Saved for goals'),
                _Rows(
                  rows: [
                    _Row(
                      icon: Image.asset(AppIcons.moneyBox),
                      title: cycle.goalName ?? 'Goals',
                      subtitle: 'Kept in your wallets, marked for it',
                      amount: cycle.toGoal,
                    ),
                  ],
                ),
              ],
              _SectionTitle(
                'Spent out of it',
                note: widget.entry.payments.isEmpty
                    ? null
                    : '${widget.entry.payments.length} '
                          '${widget.entry.payments.length == 1 ? 'payment' : 'payments'}',
              ),
              _Rows(
                rows: [
                  for (final payment in widget.entry.payments)
                    _Row(
                      icon: CategoryIcon(payment.transaction.label, size: 24),
                      title: payment.transaction.label,
                      subtitle: [
                        formatShortDate(
                          philippineTime(payment.transaction.date),
                        ),
                        if ((payment.transaction.note ?? '').trim().isNotEmpty)
                          payment.transaction.note!.trim(),
                      ].join(' · '),
                      amount: payment.amount,
                      sign: '-',
                      // Only part of it came out of this income.
                      partOf: payment.isPart
                          ? payment.transaction.amount
                          : null,
                    ),
                ],
                empty: 'Nothing spent out of it yet.',
              ),
              const SizedBox(height: 8),
              Text(
                'Each payment is taken from the money that came in first. '
                'When an income runs out, the next one pays the rest, so a '
                'payment can be split between two.',
                style: TextStyle(fontSize: 12, color: colors.textMuted),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// A heading over one part of an income's details.
class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text, {this.note});

  final String text;
  final String? note;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 12, 2, 8),
      child: Row(
        children: [
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.bold,
                color: colors.textPrimary,
              ),
            ),
          ),
          if (note != null)
            Text(
              note!,
              style: TextStyle(fontSize: 12, color: colors.textMuted),
            ),
        ],
      ),
    );
  }
}

/// Rows in one card, with lines between them.
class _Rows extends StatelessWidget {
  const _Rows({required this.rows, this.empty});

  final List<Widget> rows;

  /// Said when there are no rows.
  final String? empty;

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
              child: Text(
                empty ?? '',
                style: TextStyle(color: colors.textBody),
              ),
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

/// One line of an income's details: what it was, and its amount.
class _Row extends StatelessWidget {
  const _Row({
    required this.icon,
    required this.title,
    required this.amount,
    this.subtitle,
    this.sign,
    this.color,
    this.partOf,
  });

  final Widget icon;
  final String title;
  final String? subtitle;
  final double amount;
  final String? sign;
  final Color? color;

  /// The whole payment, when only [amount] of it came out of this income.
  final double? partOf;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final masked = context.select<AppSettingsProvider, bool>(
      (settings) => settings.amountsMasked,
    );
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
                if (subtitle != null && subtitle!.isNotEmpty)
                  Text(
                    subtitle!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12, color: colors.textMuted),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              MoneyText(
                amount,
                sign: sign,
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: color ?? colors.textPrimary,
                ),
              ),
              if (partOf != null)
                Text(
                  'of ${formatPeso(partOf!, masked: masked)}',
                  style: TextStyle(fontSize: 12, color: colors.textMuted),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// A color key, a name and an amount, for the bar above it.
class _Key extends StatelessWidget {
  const _Key({required this.part});

  final ({String label, double amount, Color color}) part;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Row(
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            color: part.color,
            borderRadius: BorderRadius.circular(3),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            part.label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 13, color: colors.textBody),
          ),
        ),
        const SizedBox(width: 6),
        MoneyText(
          part.amount,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: colors.textPrimary,
          ),
        ),
      ],
    );
  }
}

/// Income recorded without a plan, like interest from a bank: what came in
/// and when.
class _UnplannedRow extends StatelessWidget {
  const _UnplannedRow({required this.transaction});

  final AppTransaction transaction;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final note = transaction.note;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      decoration: BoxDecoration(
        color: colors.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colors.border),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: colors.primaryTint,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Image.asset(AppIcons.cashInflow),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  transaction.label,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: colors.textPrimary,
                  ),
                ),
                Text(
                  [
                    'Came in ${formatShortDate(philippineTime(transaction.date))}',
                    if (note != null && note.trim().isNotEmpty) note.trim(),
                  ].join(' · '),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12, color: colors.textMuted),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          MoneyText(
            transaction.amount,
            sign: '+',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: confirmColorOn(context),
            ),
          ),
        ],
      ),
    );
  }
}
