import 'package:flutter/material.dart';

import '../models/goal.dart';
import '../services/goal_service.dart';
import '../services/user_profile_service.dart';
import '../theme/app_buttons.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../utils/date_format.dart';
import '../utils/money_format.dart';
import '../widgets/empty_state_view.dart';
import '../widgets/goal_sheets.dart';
import '../widgets/money_text.dart';
import '../widgets/savings_guide.dart';
import 'debts_screen.dart';
import 'goal_detail_screen.dart';

/// The Goals tab: what the user is saving toward, in the order money reaches
/// each goal.
class GoalsScreen extends StatefulWidget {
  const GoalsScreen({
    this.goals,
    this.profile,
    this.onReorder,
    this.onOpen,
    super.key,
  });

  /// Replaces the live goals. Used by tests.
  final Stream<List<Goal>>? goals;

  /// Replaces the live profile, read for the savings suggestion. Used by
  /// tests.
  final Stream<Map<String, dynamic>?>? profile;

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

  late final Stream<Map<String, dynamic>?> _profile =
      widget.profile ??
      UserProfileService.watchProfile().map((snapshot) => snapshot.data());

  bool _showFinished = false;

  /// Savings goals, or debts. Both live in this one tab so the bottom bar
  /// stays at the plan's four tabs.
  bool _showDebts = false;

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
            SegmentedButton<bool>(
              segments: [
                ButtonSegment(
                  value: false,
                  label: Text('Active (${active.length})'),
                ),
                ButtonSegment(
                  value: true,
                  label: Text('Completed (${finished.length})'),
                ),
              ],
              selected: {_showFinished},
              showSelectedIcon: false,
              onSelectionChanged: (value) =>
                  setState(() => _showFinished = value.first),
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
                  style: const TextStyle(color: Colors.grey),
                ),
              )
            else ...[
              if (!_showFinished && active.length > 1)
                const Padding(
                  padding: EdgeInsets.only(bottom: 10),
                  child: Text(
                    'Money from income reaches the top goal first. Use the '
                    'arrows to change the order.',
                    style: TextStyle(fontSize: 12, color: Colors.grey),
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
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () =>
                    showGoalFormSheet(context, nextPriority: active.length),
                style: openButtonStyle(),
                icon: const Icon(Icons.add),
                label: const Text(
                  'Add New Goal',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ),
            ),
            const SizedBox(height: 28),
            StreamBuilder<Map<String, dynamic>?>(
              stream: _profile,
              builder: (context, profile) => SavingsGuide(
                monthlyIncome: monthlyIncomeFrom(profile.data),
                onCreateGoal: (name) => showGoalFormSheet(
                  context,
                  nextPriority: active.length,
                  initialName: name,
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
        automaticallyImplyLeading: false,
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
            child: SizedBox(
              width: double.infinity,
              child: SegmentedButton<bool>(
                segments: const [
                  ButtonSegment(
                    value: false,
                    icon: Icon(Icons.savings_outlined),
                    label: Text('Savings'),
                  ),
                  ButtonSegment(
                    value: true,
                    icon: Icon(Icons.receipt_long_outlined),
                    label: Text('Debts'),
                  ),
                ],
                selected: {_showDebts},
                showSelectedIcon: false,
                onSelectionChanged: (value) =>
                    setState(() => _showDebts = value.first),
              ),
            ),
          ),
          Expanded(
            child: _showDebts ? const DebtsView() : _buildSavings(context),
          ),
        ],
      ),
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

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final done = goal.status != GoalStatus.active;

    return Material(
      color: colors.card,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.fromLTRB(16, 14, 8, 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: colors.border),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        if (rank != null) ...[
                          _Tag(text: '#$rank', color: appPrimaryBlue),
                          const SizedBox(width: 8),
                        ],
                        if (done) ...[
                          _Tag(
                            text: goal.status == GoalStatus.used
                                ? 'Used'
                                : 'Reached',
                            color: confirmColorOn(context),
                            icon: Icons.check,
                          ),
                          const SizedBox(width: 8),
                        ],
                        Expanded(
                          child: Text(
                            goal.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: colors.textPrimary,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: LinearProgressIndicator(
                        value: goal.progress,
                        minHeight: 8,
                        backgroundColor: colors.track,
                        valueColor: AlwaysStoppedAnimation(
                          done ? confirmColorOn(context) : appPrimaryBlue,
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        MoneyText(
                          goal.shownSaved,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: colors.textPrimary,
                          ),
                        ),
                        Text(
                          ' of ${formatPeso(goal.targetAmount)}',
                          style: const TextStyle(
                            fontSize: 13,
                            color: Colors.grey,
                          ),
                        ),
                        const Spacer(),
                        if (goal.targetDate != null && !done)
                          Text(
                            'by ${formatShortDate(goal.targetDate!)}',
                            style: const TextStyle(
                              fontSize: 12,
                              color: Colors.grey,
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              if (rank != null)
                Column(
                  children: [
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
                ),
            ],
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
