import 'package:flutter/material.dart';

import '../models/allocation.dart';
import '../models/app_transaction.dart';
import '../models/cycle_history.dart';
import '../services/budget_service.dart';
import '../services/user_profile_service.dart';
import '../services/wallet_service.dart';
import '../theme/app_buttons.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../utils/date_format.dart';
import '../widgets/empty_state_view.dart';
import '../widgets/money_text.dart';
import 'financial_preferences_screen.dart';
import 'leftover_review_screen.dart';

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({
    this.cycles,
    this.transactions,
    this.profile,
    this.today,
    this.onReview,
    super.key,
  });
  final Stream<List<AllocationCycle>>? cycles;
  final Stream<List<AppTransaction>>? transactions;
  final Stream<Map<String, dynamic>?>? profile;
  final DateTime? today;
  final void Function(AllocationCycle, double, DateTime)? onReview;
  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  late final _cycles = widget.cycles ?? BudgetService.watchHistory();
  late final _transactions =
      widget.transactions ?? WalletService.watchTransactions();
  late final _profile =
      widget.profile ?? UserProfileService.watchProfile().map((s) => s.data());
  bool _pendingOnly = false;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text(
        'Pay-cycle history',
        style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
      ),
      centerTitle: true,
      backgroundColor: appPrimaryBlue,
      foregroundColor: Colors.white,
      elevation: 0,
    ),
    body: StreamBuilder<Map<String, dynamic>?>(
      stream: _profile,
      builder: (context, profile) => StreamBuilder<List<AppTransaction>>(
        stream: _transactions,
        builder: (context, transactions) => StreamBuilder<List<AllocationCycle>>(
          stream: _cycles,
          builder: (context, cycles) {
            if (profile.hasError || transactions.hasError || cycles.hasError) {
              return const EmptyStateView(
                iconAsset: 'assets/icons/icons8-calendar-96.png',
                title: 'History is unavailable',
                message:
                    'Your records have not been changed. Reopen this screen to try again.',
              );
            }
            if (!cycles.hasData ||
                !transactions.hasData ||
                profile.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            if (cycles.data!.isEmpty) {
              return const EmptyStateView(
                iconAsset: 'assets/icons/icons8-calendar-96.png',
                title: 'Your story starts with income',
                message:
                    'Use + to add income and plan it. Every pay you log shows up here: what came in, where it went, and what was left at the end.',
              );
            }
            final frequency = profile.data?['incomeFrequency'] as String?;
            final now = widget.today ?? DateTime.now();
            final all = newestCycles(cycles.data!);
            final pending = all
                .where(
                  (c) => cycleStatus(c, frequency, now) == CycleStatus.pending,
                )
                .length;
            final visible = all
                .where(
                  (c) =>
                      !_pendingOnly ||
                      cycleStatus(c, frequency, now) == CycleStatus.pending,
                )
                .toList();
            return ListView.builder(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
              itemCount: visible.length + 1,
              itemBuilder: (context, index) {
                if (index == 0) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      PreferenceIntro(
                        icon: Icons.history,
                        title: 'Every payday, a clearer picture',
                        message: pending == 0
                            ? 'Every pay you log: what came in, where it went, and what was left.'
                            : '$pending ${pending == 1 ? 'cycle is' : 'cycles are'} waiting for a leftover decision.',
                      ),
                      const SizedBox(height: 16),
                      Wrap(
                        spacing: 8,
                        children: [
                          ChoiceChip(
                            label: Text('All cycles (${all.length})'),
                            selected: !_pendingOnly,
                            onSelected: (_) =>
                                setState(() => _pendingOnly = false),
                          ),
                          ChoiceChip(
                            label: Text('Needs review ($pending)'),
                            selected: _pendingOnly,
                            onSelected: (_) =>
                                setState(() => _pendingOnly = true),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Newest first · Amounts are from the plan you made on payday',
                        style: TextStyle(
                          fontSize: 12,
                          color: context.appColors.textBody,
                        ),
                      ),
                      const SizedBox(height: 18),
                      if (visible.isEmpty)
                        const Padding(
                          padding: EdgeInsets.all(24),
                          child: Text('All caught up. No cycles need review.'),
                        ),
                    ],
                  );
                }
                final cycle = visible[index - 1];
                final period = periodOf(cycle, frequency);
                final status = cycleStatus(cycle, frequency, now);
                final left = cycle.isResolved
                    ? cycle.savedAmount + cycle.spentAmount
                    : leftoverOf(cycle, transactions.data!, period);
                final spent = cycle.isResolved
                    ? cycle.remaining - left
                    : spentInCycle(cycle, transactions.data!, period);
                return _CycleCard(
                  cycle: cycle,
                  status: status,
                  spent: spent < 0 ? 0 : spent,
                  periodLabel:
                      '${formatShortDate(period.start)} – ${formatShortDate(period.end.subtract(const Duration(days: 1)))}',
                  leftover: left,
                  onReview: () {
                    if (widget.onReview != null) {
                      widget.onReview!(cycle, left, period.end);
                    } else {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => LeftoverReviewScreen(
                            cycle: cycle,
                            leftover: left,
                            periodEnd: period.end,
                            initialDecision: LeftoverDecision.fromName(
                              profile.data?['defaultLeftover'] as String?,
                            ),
                          ),
                        ),
                      );
                    }
                  },
                );
              },
            );
          },
        ),
      ),
    ),
  );
}

class _CycleCard extends StatelessWidget {
  const _CycleCard({
    required this.cycle,
    required this.status,
    required this.periodLabel,
    required this.leftover,
    required this.spent,
    required this.onReview,
  });
  final AllocationCycle cycle;
  final CycleStatus status;
  final String periodLabel;
  final double leftover;

  /// What was spent out of this pay. Without it the card dropped from what
  /// was left to plan with to what is left now with nothing in between.
  final double spent;
  final VoidCallback onReview;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final (label, icon, color) = switch (status) {
      CycleStatus.active => (
        'In progress',
        Icons.timelapse,
        colors.primaryText,
      ),
      CycleStatus.pending => (
        'Pending',
        Icons.hourglass_top,
        context.isDarkMode ? Colors.amber.shade200 : Colors.brown.shade700,
      ),
      CycleStatus.done => (
        'Done',
        Icons.check_circle_outline,
        confirmColorOn(context),
      ),
      CycleStatus.declined => (
        'Declined',
        Icons.do_not_disturb_on_outlined,
        dangerColorOn(context),
      ),
    };
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: colors.card,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: colors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 12,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      cycle.source,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: .12),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(icon, size: 15, color: color),
                          const SizedBox(width: 5),
                          Text(
                            label,
                            style: TextStyle(
                              color: color,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  periodLabel,
                  style: TextStyle(color: colors.textBody, fontSize: 13),
                ),
                if (cycle.periodStart == null || cycle.periodEnd == null)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      'An older pay · dates worked out from how often you are paid now',
                      style: TextStyle(color: colors.textBody, fontSize: 12),
                    ),
                  ),
                const SizedBox(height: 18),
                _line(
                  context,
                  'Money that came in',
                  cycle.income,
                  strong: true,
                ),
                _line(context, 'Set aside for bills', cycle.toBills),
                _line(
                  context,
                  cycle.goalName == null
                      ? 'Saved for goals'
                      : 'Saved for ${cycle.goalName}',
                  cycle.toGoal,
                ),
                const Divider(height: 24),
                _line(context, 'Left to spend', cycle.remaining),
                _line(context, 'Spent so far', spent),
                _line(
                  context,
                  // Spending past what was left is worth naming, rather than
                  // showing nothing left and hiding by how much.
                  spent > cycle.remaining + 0.005
                      ? 'Over by'
                      : cycle.isResolved
                      ? 'What was left'
                      : 'Still left now',
                  spent > cycle.remaining + 0.005
                      ? spent - cycle.remaining
                      : leftover,
                  strong: true,
                ),
                if (status == CycleStatus.active)
                  const Padding(
                    padding: EdgeInsets.only(top: 8),
                    child: Text(
                      'This pay is still running. On its last day you can decide what to do with whatever is left.',
                      style: TextStyle(fontSize: 12),
                    ),
                  ),
                if (cycle.isResolved) ...[
                  const SizedBox(height: 8),
                  Text(
                    status == CycleStatus.declined
                        ? 'Chose not to save it · kept for spending'
                        : cycle.decision!.label,
                    style: TextStyle(color: colors.textBody, fontSize: 13),
                  ),
                  _line(context, 'Saved', cycle.savedAmount),
                  _line(context, 'Kept for spending', cycle.spentAmount),
                ],
                if (status == CycleStatus.pending) ...[
                  const SizedBox(height: 14),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      style: openOutlineStyle(context).copyWith(
                        foregroundColor: WidgetStatePropertyAll(
                          colors.primaryText,
                        ),
                        side: WidgetStatePropertyAll(
                          BorderSide(
                            color: colors.primaryText.withValues(alpha: .5),
                          ),
                        ),
                      ),
                      onPressed: onReview,
                      icon: const Icon(Icons.arrow_forward, size: 18),
                      label: const Text('Decide what is left'),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _line(
    BuildContext context,
    String label,
    double amount, {
    bool strong = false,
  }) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 5),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Text(
            label,
            style: TextStyle(color: context.appColors.textBody),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: MoneyText(
            amount,
            textAlign: TextAlign.right,
            style: TextStyle(
              color: context.appColors.textPrimary,
              fontWeight: strong ? FontWeight.bold : FontWeight.w500,
              fontSize: strong ? 18 : 14,
            ),
          ),
        ),
      ],
    ),
  );
}
