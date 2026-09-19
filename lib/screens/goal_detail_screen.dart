import 'package:flutter/material.dart';

import '../models/goal.dart';
import '../models/wallet.dart';
import '../services/goal_service.dart';
import '../services/wallet_service.dart';
import '../theme/app_buttons.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../utils/date_format.dart';
import '../utils/money_format.dart';
import '../widgets/goal_sheets.dart';
import '../widgets/money_text.dart';

/// One goal: how far along it is, when it will be reached at this pace, and
/// every amount set aside for it.
class GoalDetailScreen extends StatefulWidget {
  const GoalDetailScreen({
    required this.goal,
    this.liveGoal,
    this.contributions,
    this.wallets,
    this.today,
    super.key,
  });

  /// The goal as it was when the screen opened.
  final Goal goal;

  /// Replace the live data. Used by tests.
  final Stream<Goal?>? liveGoal;
  final Stream<List<GoalContribution>>? contributions;
  final Stream<List<Wallet>>? wallets;
  final DateTime? today;

  @override
  State<GoalDetailScreen> createState() => _GoalDetailScreenState();
}

class _GoalDetailScreenState extends State<GoalDetailScreen> {
  late final Stream<Goal?> _goal =
      widget.liveGoal ?? GoalService.watchGoal(widget.goal.id);
  late final Stream<List<GoalContribution>> _contributions =
      widget.contributions ?? GoalService.watchContributions(widget.goal.id);
  late final Stream<List<Wallet>> _wallets =
      widget.wallets ?? WalletService.watchWallets(includeArchived: true);

  Future<void> _delete(Goal goal) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Delete ${goal.name}?'),
        content: Text(
          goal.setAside > 0
              ? 'Its history is removed and the ${formatPeso(goal.setAside)} '
                    'set aside becomes spendable again. No wallet balance '
                    'changes, because that money never left your wallets.'
              : 'Its history is removed.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            style: cancelTextStyle(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: dangerTextStyle(context),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    await GoalService.deleteGoal(goal);
    if (mounted) Navigator.pop(context);
  }

  Future<void> _markUsed(Goal goal) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Mark this money as used?'),
        content: Text(
          'Record the ${formatPeso(goal.shownSaved)} as spent on '
          '${goal.name}. It stops being set aside, and the goal stays in '
          'Completed as something you achieved.\n\nRemember to log what you '
          'bought as an expense, so your wallet balance goes down.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            style: cancelTextStyle(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: confirmTextStyle(context),
            child: const Text('Mark as used'),
          ),
        ],
      ),
    );

    if (confirmed == true) GoalService.markUsed(goal);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    return StreamBuilder<Goal?>(
      stream: _goal,
      builder: (context, goalSnapshot) {
        final goal = goalSnapshot.data ?? widget.goal;

        return Scaffold(
          backgroundColor: colors.pageBackground,
          appBar: AppBar(
            title: Text(
              goal.name,
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            backgroundColor: appPrimaryBlue,
            foregroundColor: Colors.white,
            elevation: 0,
            actions: [
              PopupMenuButton<String>(
                tooltip: 'Goal options',
                onSelected: (value) {
                  if (value == 'edit') {
                    showGoalFormSheet(context, existing: goal);
                  }
                  if (value == 'delete') _delete(goal);
                },
                itemBuilder: (context) => [
                  menuItem(
                    value: 'edit',
                    label: 'Edit goal',
                    icon: Icons.edit,
                    color: appPrimaryBlue,
                  ),
                  menuItem(
                    value: 'delete',
                    label: 'Delete goal',
                    icon: Icons.delete_outline,
                    color: dangerColorOn(context),
                  ),
                ],
              ),
            ],
          ),
          body: StreamBuilder<List<GoalContribution>>(
            stream: _contributions,
            builder: (context, snapshot) {
              final contributions = snapshot.data ?? const <GoalContribution>[];

              return ListView(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 40),
                children: [
                  _ProgressHeader(
                    goal: goal,
                    contributions: contributions,
                    now: widget.today ?? DateTime.now(),
                  ),
                  const SizedBox(height: 16),
                  if (goal.status == GoalStatus.completed)
                    _CompletedCard(
                      goal: goal,
                      onNewGoal: () => showGoalFormSheet(context),
                      onUsed: () => _markUsed(goal),
                    )
                  else if (goal.status == GoalStatus.active)
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: () => showContributionSheet(context, goal),
                        style: confirmButtonStyle(),
                        icon: const Icon(Icons.savings_outlined),
                        label: const Text(
                          'Contribute Now',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                  if (goal.status != GoalStatus.used &&
                      goal.shownSaved > 0) ...[
                    const SizedBox(height: 10),
                    OutlinedButton.icon(
                      onPressed: () =>
                          showContributionSheet(context, goal, takeOut: true),
                      style: dangerOutlineStyle(context),
                      icon: const Icon(Icons.remove, size: 18),
                      label: const Text('Take money out'),
                    ),
                  ],
                  const SizedBox(height: 24),
                  Text(
                    'History',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: colors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 10),
                  StreamBuilder<List<Wallet>>(
                    stream: _wallets,
                    builder: (context, walletSnapshot) => _History(
                      contributions: contributions,
                      wallets: walletSnapshot.data ?? const [],
                    ),
                  ),
                ],
              );
            },
          ),
        );
      },
    );
  }
}

class _ProgressHeader extends StatelessWidget {
  const _ProgressHeader({
    required this.goal,
    required this.contributions,
    required this.now,
  });

  final Goal goal;
  final List<GoalContribution> contributions;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final projected = projectedCompletion(goal, contributions, now: now);
    final done = goal.status != GoalStatus.active;
    final ringColor = done ? confirmColorOn(context) : appPrimaryBlue;

    String paceText;
    if (done) {
      paceText = goal.status == GoalStatus.used
          ? 'Reached and used.'
          : 'Target reached.';
    } else if (projected == null) {
      paceText = 'Save a couple of times and a finish date will show here.';
    } else if (goal.targetDate != null && projected.isAfter(goal.targetDate!)) {
      paceText =
          'At this pace you finish around ${formatShortDate(projected)}, '
          'after your target date.';
    } else {
      paceText =
          'At this pace you finish around ${formatShortDate(projected)}.';
    }

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: colors.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colors.border),
      ),
      child: Column(
        children: [
          SizedBox(
            width: 140,
            height: 140,
            child: Stack(
              fit: StackFit.expand,
              children: [
                CircularProgressIndicator(
                  value: goal.progress,
                  strokeWidth: 12,
                  backgroundColor: colors.track,
                  valueColor: AlwaysStoppedAnimation(ringColor),
                ),
                Center(
                  child: Text(
                    '${(goal.progress * 100).round()}%',
                    style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                      color: colors.textPrimary,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              MoneyText(
                goal.shownSaved,
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: colors.textPrimary,
                ),
              ),
              Text(
                ' of ${formatPeso(goal.targetAmount)}',
                style: const TextStyle(fontSize: 16, color: Colors.grey),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            [
              if (!done && goal.remaining > 0)
                '${formatPeso(goal.remaining)} to go',
              if (goal.targetDate != null)
                'Target ${formatShortDate(goal.targetDate!)}',
              'Priority #${goal.priority + 1}',
            ].join(' · '),
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 13, color: Colors.grey),
          ),
          const SizedBox(height: 12),
          Text(
            paceText,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, color: colors.textBody),
          ),
          if (!done) _PlanLine(goal: goal, now: now),
        ],
      ),
    );
  }
}

class _CompletedCard extends StatelessWidget {
  const _CompletedCard({
    required this.goal,
    required this.onNewGoal,
    required this.onUsed,
  });

  final Goal goal;
  final VoidCallback onNewGoal;
  final VoidCallback onUsed;

  @override
  Widget build(BuildContext context) {
    final green = confirmColorOn(context);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: green.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.check_circle, color: green),
              const SizedBox(width: 8),
              Text(
                'You reached this goal!',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: green,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'The ${formatPeso(goal.shownSaved)} is still set aside. When you '
            'spend it on ${goal.name}, mark it as used.',
            style: TextStyle(fontSize: 13, color: context.appColors.textBody),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: onNewGoal,
                  style: openOutlineStyle(context),
                  child: const Text('Start a new goal'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: ElevatedButton(
                  onPressed: onUsed,
                  style: confirmButtonStyle(height: 46),
                  child: const Text('Mark as used'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _History extends StatelessWidget {
  const _History({required this.contributions, required this.wallets});

  final List<GoalContribution> contributions;
  final List<Wallet> wallets;

  String _walletName(String? id) {
    for (final wallet in wallets) {
      if (wallet.id == id) return wallet.name;
    }
    return 'a wallet';
  }

  @override
  Widget build(BuildContext context) {
    if (contributions.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 12),
        child: Text(
          'Nothing set aside yet.',
          style: TextStyle(color: Colors.grey),
        ),
      );
    }

    final colors = context.appColors;

    return Column(
      children: [
        for (final entry in contributions) ...[
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: colors.card,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: colors.border),
            ),
            child: Row(
              children: [
                Icon(
                  entry.isWithdrawal ? Icons.remove_circle : Icons.check_circle,
                  color: entry.isWithdrawal
                      ? dangerColorOn(context)
                      : confirmColorOn(context),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        entry.isWithdrawal
                            ? 'Taken out, ${_walletName(entry.walletId)}'
                            : 'Set aside in ${_walletName(entry.walletId)}',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: colors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        formatShortDate(entry.date),
                        style: const TextStyle(
                          fontSize: 12,
                          color: Colors.grey,
                        ),
                      ),
                    ],
                  ),
                ),
                MoneyText(
                  entry.amount.abs(),
                  sign: entry.isWithdrawal ? '-' : '+',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: entry.isWithdrawal
                        ? dangerColorOn(context)
                        : confirmColorOn(context),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
        ],
      ],
    );
  }
}

/// The goal's saving plan and whether the user is keeping up with it.
class _PlanLine extends StatelessWidget {
  const _PlanLine({required this.goal, required this.now});

  final Goal goal;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final plan = goal.planAmount;
    final needed = neededPerContribution(
      remaining: goal.remaining,
      targetDate: goal.targetDate,
      frequency: goal.frequency,
      now: now,
      planStartedAt: goal.planStartedAt,
    );

    final String text;
    final Color color;

    if (plan != null) {
      final behind = behindPlan(goal, now: now) ?? 0;
      if (behind > 0.005) {
        text =
            'Plan: ${formatPeso(plan)} ${goal.frequency.per} · behind by '
            '${formatPeso(behind)}';
        color = dangerColorOn(context);
      } else {
        text = 'Plan: ${formatPeso(plan)} ${goal.frequency.per} · on track';
        color = confirmColorOn(context);
      }
    } else if (needed != null) {
      text =
          'Save ${formatPeso(needed)} ${goal.frequency.per} to finish by '
          '${formatShortDate(goal.targetDate!)}';
      color = context.appColors.textBody;
    } else {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          text,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: color,
          ),
        ),
      ),
    );
  }
}
