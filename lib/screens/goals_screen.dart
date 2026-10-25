import 'package:flutter/material.dart';

import '../models/debt.dart';
import '../models/goal.dart';
import '../services/goal_service.dart';
import '../theme/app_buttons.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../utils/date_format.dart';
import '../utils/money_format.dart';
import '../widgets/back_to_home.dart';
import '../widgets/empty_state_view.dart';
import '../widgets/goal_progress.dart';
import '../widgets/goal_sheets.dart';
import '../widgets/money_text.dart';
import 'goal_detail_screen.dart';

/// The Goals tab: what the user is saving toward, in the order money reaches
/// each goal.
/// Lets other screens open the Goals tab on savings or on a debts list.
class GoalsTabController extends ChangeNotifier {
  bool _showDebts = false;

  bool get showDebts => _showDebts;

  /// The debts list to show. Tells its listeners on every [openDebts], even
  /// to the list already showing.
  final debtsList = _AlwaysNotifier<DebtDirection>(DebtDirection.iOwe);

  void openSavings() {
    _showDebts = false;
    notifyListeners();
  }

  void openDebts(DebtDirection direction) {
    _showDebts = true;
    notifyListeners();
    debtsList.show(direction);
  }

  @override
  void dispose() {
    debtsList.dispose();
    super.dispose();
  }
}

class _AlwaysNotifier<T> extends ValueNotifier<T> {
  _AlwaysNotifier(super.value);

  void show(T next) {
    if (value == next) {
      notifyListeners();
    } else {
      value = next;
    }
  }
}

class GoalsScreen extends StatefulWidget {
  const GoalsScreen({
    this.controller,
    this.goals,
    this.onReorder,
    this.onOpen,
    super.key,
  });

  /// Switches between savings and debts from outside, like Home's shortcuts
  /// or saving an installment from the + button.
  final GoalsTabController? controller;

  /// Replaces the live goals. Used by tests.
  final Stream<List<Goal>>? goals;

  /// Replaces saving a new order. Used by tests.
  final void Function(List<Goal> ordered)? onReorder;

  /// Replaces opening a goal. Used by tests.
  final void Function(Goal goal)? onOpen;

  @override
  State<GoalsScreen> createState() => _GoalsScreenState();
}

class _GoalsScreenState extends State<GoalsScreen> {
  late final Stream<List<Goal>> _goals =
      widget.goals ?? GoalService.watchGoals();

  bool _showFinished = false;

  void _move(List<Goal> active, int index, int direction) {
    final ordered = [...active];
    final goal = ordered.removeAt(index);
    ordered.insert(index + direction, goal);

    (widget.onReorder ?? GoalService.reorder)(ordered);
  }

  void _open(Goal goal) {
    if (widget.onOpen != null) {
      widget.onOpen!(goal);
      return;
    }
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => GoalDetailScreen(goal: goal)),
    );
  }

  Widget _buildSavings(BuildContext context) {
    return StreamBuilder<List<Goal>>(
      stream: _goals,
      builder: (context, snapshot) {
        final goals = snapshot.data;

        if (goals == null) {
          return const Center(child: CircularProgressIndicator());
        }

        final active = goals
            .where((goal) => goal.status == GoalStatus.active)
            .toList();
        final finished = goals
            .where((goal) => goal.status != GoalStatus.active)
            .toList();
        final shown = _showFinished ? finished : active;

        return ListView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 100),
          children: [
            _GoalsFilter(
              showFinished: _showFinished,
              activeCount: active.length,
              finishedCount: finished.length,
              onChanged: (finished) => setState(() => _showFinished = finished),
            ),
            const SizedBox(height: 16),
            if (goals.isEmpty)
              const Padding(
                padding: EdgeInsets.only(top: 40),
                child: EmptyStateView(
                  iconAsset: 'assets/icons/icons8-goal-96.png',
                  title: 'No goals yet',
                  message:
                      'Pick something to save for, like a laptop or an '
                      'emergency fund, and watch it fill up.',
                ),
              )
            else if (shown.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 40),
                child: Text(
                  _showFinished
                      ? 'Goals you finish will show up here.'
                      : 'Every goal is done. Add a new one to keep going.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: context.appColors.textMuted),
                ),
              )
            else ...[
              if (!_showFinished && active.length > 1)
                Padding(
                  padding: EdgeInsets.only(bottom: 10),
                  child: Text(
                    'Money from income reaches the top goal first. Use the '
                    'arrows to change the order.',
                    style: TextStyle(
                      fontSize: 12,
                      color: context.appColors.textMuted,
                    ),
                  ),
                ),
              for (var i = 0; i < shown.length; i++) ...[
                _GoalCard(
                  goal: shown[i],
                  rank: _showFinished ? null : i + 1,
                  onTap: () => _open(shown[i]),
                  onUp: !_showFinished && i > 0
                      ? () => _move(active, i, -1)
                      : null,
                  onDown: !_showFinished && i < shown.length - 1
                      ? () => _move(active, i, 1)
                      : null,
                ),
                const SizedBox(height: 12),
              ],
            ],
            const SizedBox(height: 4),
            // The same green Add button as setup's goals step.
            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton(
                onPressed: () =>
                    showGoalFormSheet(context, nextPriority: active.length),
                style: confirmButtonStyle(),
                child: const Text(
                  'Add Goal',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    return Scaffold(
      backgroundColor: colors.pageBackground,
      appBar: AppBar(
        title: const Text(
          'Goals',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
        ),
        centerTitle: true,
        backgroundColor: appPrimaryBlue,
        foregroundColor: Colors.white,
        elevation: 0,
        // As a tab it goes back to Home; opened on its own it gets the usual
        // back arrow.
        leading: backToHomeButton(context),
      ),
      body: _buildSavings(context),
    );
  }
}

class _GoalCard extends StatelessWidget {
  const _GoalCard({
    required this.goal,
    required this.rank,
    required this.onTap,
    required this.onUp,
    required this.onDown,
  });

  final Goal goal;

  /// Position in the priority order; null for finished goals.
  final int? rank;
  final VoidCallback onTap;
  final VoidCallback? onUp;
  final VoidCallback? onDown;

  /// The plan note names the finish date, so it only shows on its own for a
  /// goal planned by an amount each time.
  bool get _showsFinishDate =>
      goal.targetDate != null &&
      goal.status == GoalStatus.active &&
      goal.planAmount != null;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final done = goal.status != GoalStatus.active;
    final reached = goal.isReached;
    final used = goal.status == GoalStatus.used;

    // Laid out like setup's goal card: the goal icon, the name with what is
    // saved, then the bar with how far along it is.
    return Material(
      color: colors.card,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.fromLTRB(14, 12, 4, 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: colors.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  // A reached goal trades its target for a green check.
                  Image.asset(
                    reached
                        ? goalReachedIcon
                        : 'assets/icons/icons8-goal-96.png',
                    width: 32,
                    height: 32,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          goal.name,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: colors.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 2),
                        if (reached)
                          Text(
                            '${formatPeso(goal.targetAmount)} saved — '
                            'completed!',
                            style: TextStyle(
                              fontSize: 13,
                              color: colors.textBody,
                            ),
                          )
                        else
                          // The saved amount hides with the eye toggle, as
                          // it did before.
                          Row(
                            children: [
                              MoneyText(
                                goal.shownSaved,
                                style: TextStyle(
                                  fontSize: 13,
                                  color: colors.textBody,
                                ),
                              ),
                              Flexible(
                                child: Text(
                                  ' of ${formatPeso(goal.targetAmount)} saved',
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: colors.textBody,
                                  ),
                                ),
                              ),
                            ],
                          ),
                      ],
                    ),
                  ),
                  if (rank != null) ...[
                    IconButton(
                      tooltip: 'Move up',
                      visualDensity: VisualDensity.compact,
                      icon: const Icon(Icons.keyboard_arrow_up),
                      onPressed: onUp,
                    ),
                    IconButton(
                      tooltip: 'Move down',
                      visualDensity: VisualDensity.compact,
                      icon: const Icon(Icons.keyboard_arrow_down),
                      onPressed: onDown,
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 10),
              Padding(
                padding: const EdgeInsets.only(right: 10),
                child: GoalProgressBar(
                  progress: goal.progress,
                  reached: reached,
                ),
              ),
              if (!done)
                if (goalPlanLine(
                      remaining: goal.remaining,
                      targetDate: goal.targetDate,
                      now: DateTime.now(),
                      frequency: goal.frequency,
                      custom: goal.customInterval,
                      planStartedAt: goal.planStartedAt,
                      planAmount: goal.planAmount,
                      behind: behindPlan(goal, now: DateTime.now()),
                    )
                    case final line?) ...[
                  const SizedBox(height: 10),
                  Padding(
                    padding: const EdgeInsets.only(right: 10),
                    child: GoalPlanNote(line),
                  ),
                ],
              // Its place in line, whether it was used, and when it is due.
              // A reached goal says so under its bar already.
              if (rank != null || used || _showsFinishDate) ...[
                const SizedBox(height: 10),
                Padding(
                  padding: const EdgeInsets.only(right: 10),
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      if (rank != null)
                        _Tag(text: '#$rank', color: appPrimaryBlue),
                      if (used)
                        _Tag(
                          text: 'Used',
                          color: confirmColorOn(context),
                          icon: Icons.check,
                        ),
                      if (_showsFinishDate)
                        Text(
                          'Finish by ${formatShortDate(goal.targetDate!)}',
                          style: TextStyle(
                            fontSize: 12,
                            color: colors.textMuted,
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Active or Completed, as two large tiles like the wallet types in New
/// Wallet: the chosen one solid blue, so which list is showing is never in
/// doubt, each with its own icon and how many goals it holds. Each tile is
/// a full 48 points high and read out as a selected or unselected button.
class _GoalsFilter extends StatelessWidget {
  const _GoalsFilter({
    required this.showFinished,
    required this.activeCount,
    required this.finishedCount,
    required this.onChanged,
  });

  final bool showFinished;
  final int activeCount;
  final int finishedCount;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _GoalsFilterTile(
            key: const Key('goals-filter-active'),
            iconAsset: 'assets/icons/icons8-goal-96.png',
            label: 'Active',
            count: activeCount,
            selected: !showFinished,
            onTap: () => onChanged(false),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _GoalsFilterTile(
            key: const Key('goals-filter-completed'),
            iconAsset: goalReachedIcon,
            label: 'Completed',
            count: finishedCount,
            selected: showFinished,
            onTap: () => onChanged(true),
          ),
        ),
      ],
    );
  }
}

class _GoalsFilterTile extends StatelessWidget {
  const _GoalsFilterTile({
    required this.iconAsset,
    required this.label,
    required this.count,
    required this.selected,
    required this.onTap,
    super.key,
  });

  final String iconAsset;
  final String label;
  final int count;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final foreground = selected ? Colors.white : colors.textBody;

    return Semantics(
      button: true,
      selected: selected,
      label: '$label goals, $count',
      excludeSemantics: true,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            constraints: const BoxConstraints(minHeight: 48),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
            decoration: BoxDecoration(
              color: selected ? appPrimaryBlue : colors.card,
              border: Border.all(
                color: selected ? appPrimaryBlue : colors.border,
              ),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Image.asset(iconAsset, width: 18, height: 18),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: selected ? FontWeight.bold : FontWeight.w500,
                      color: foreground,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                // How many, in a badge of its own rather than in brackets.
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: selected
                        ? Colors.white.withValues(alpha: 0.25)
                        : colors.primaryTint,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '$count',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: selected ? Colors.white : colors.primaryText,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Tag extends StatelessWidget {
  const _Tag({required this.text, required this.color, this.icon});

  final String text;
  final Color color;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.13),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 12, color: color),
            const SizedBox(width: 3),
          ],
          Text(
            text,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}
