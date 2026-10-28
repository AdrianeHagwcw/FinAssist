import 'package:flutter/material.dart';
import '../utils/amount_input_formatter.dart';

import '../../backend/models/allocation.dart';
import '../../backend/models/goal.dart';
import '../../backend/models/wallet.dart';
import '../../backend/services/budget_service.dart';
import '../../backend/services/goal_service.dart';
import '../../backend/services/wallet_service.dart';
import '../theme/app_buttons.dart';
import '../theme/app_colors.dart';
import '../theme/app_icons.dart';
import '../theme/app_theme.dart';
import '../../backend/utils/date_format.dart';
import '../../backend/utils/money_format.dart';
import '../widgets/check_after_save.dart';
import '../widgets/dialog_kit.dart';
import '../widgets/money_text.dart';
import '../widgets/wallet_split_picker.dart';

/// A pending leftover on Home: "⏳ ₱850 left from your Allowance period".
class LeftoverNotice extends StatelessWidget {
  const LeftoverNotice({
    required this.cycle,
    required this.leftover,
    required this.onReview,
    super.key,
  });

  final AllocationCycle cycle;
  final double leftover;
  final VoidCallback onReview;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final pending = cycle.decision == LeftoverDecision.pending;

    return Container(
      margin: const EdgeInsets.only(top: 14),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.primaryTint,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          const DecisionBadge(decision: LeftoverDecision.pending),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                MoneyText(
                  leftover,
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.bold,
                    color: colors.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  pending
                      ? 'Still to decide: left from ${_monthName(cycle)}'
                      : 'Left from ${_monthName(cycle)}. What should happen '
                            'to it?',
                  style: TextStyle(fontSize: 12, color: colors.textBody),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          ElevatedButton(
            onPressed: onReview,
            style: openButtonStyle(height: 40),
            child: const Text('Decide'),
          ),
        ],
      ),
    );
  }
}

/// The ✅ / ⏳ badge for a leftover decision, matching the plan's badge system.
class DecisionBadge extends StatelessWidget {
  const DecisionBadge({required this.decision, super.key});

  final LeftoverDecision decision;

  @override
  Widget build(BuildContext context) {
    final pending = decision == LeftoverDecision.pending;
    final declined = decision == LeftoverDecision.spent;
    final color = pending
        ? Colors.amber.shade700
        : declined
        ? dangerColorOn(context)
        : confirmColorOn(context);

    return Tooltip(
      message: pending ? 'Pending' : decision.label,
      child: Container(
        width: 38,
        height: 38,
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.15),
          shape: BoxShape.circle,
        ),
        child: Icon(
          pending
              ? Icons.hourglass_top
              : declined
              ? Icons.close
              : Icons.check,
          size: 20,
          color: color,
        ),
      ),
    );
  }
}

enum _Choice { save, spend, split }

/// Decides what happens to money left over at the end of a pay period.
class LeftoverReviewScreen extends StatefulWidget {
  const LeftoverReviewScreen({
    required this.cycle,
    required this.leftover,
    required this.periodEnd,
    this.others = const [],
    this.onResolve,
    this.onSaving,
    this.wallets,
    this.goals,
    super.key,
  });

  final AllocationCycle cycle;
  final double leftover;

  /// The month's other incomes still undecided, closed by the same decision.
  final List<AllocationCycle> others;

  /// The day after the period's last day.
  final DateTime periodEnd;

  /// Replaces saving the decision. Used by tests.
  final void Function(LeftoverDecision decision, double saved, double spent)?
  onResolve;

  /// Told where saved money goes, alongside [onResolve]. Used by tests.
  final void Function(LeftoverSaving saving)? onSaving;

  /// Replace the live wallets and goals. Used by tests.
  final Stream<List<Wallet>>? wallets;
  final Stream<List<Goal>>? goals;

  @override
  State<LeftoverReviewScreen> createState() => _LeftoverReviewScreenState();
}

class _LeftoverReviewScreenState extends State<LeftoverReviewScreen>
    with CheckAfterSave {
  _Choice? _choice;
  final _saveController = TextEditingController();
  final _spendController = TextEditingController();

  /// Set when the leftover was already decided somewhere else. Nothing typed
  /// here can fix that, so it stays.
  String? _alreadyDecided;
  bool _resolved = false;

  // A test that replaces saving has no Firebase behind it.
  bool get _live => widget.onResolve == null;

  late final Stream<List<Wallet>> _walletStream =
      widget.wallets ??
      (_live ? WalletService.watchWallets() : Stream.value(const []));
  late final Stream<List<Goal>> _goalStream =
      widget.goals ??
      (_live ? GoalService.watchGoals() : Stream.value(const []));

  List<Wallet> _wallets = const [];
  List<Goal> _goals = const [];

  /// Where saved money goes, as `goal:` or `savings:` and an id, and how much
  /// of it is in each wallet now.
  String? _saveTo;
  Map<String, double> _from = const {};

  @override
  void initState() {
    super.initState();
    recheckWhenChanged(_saveController);
    recheckWhenChanged(_spendController);
    _walletStream.listen((wallets) {
      if (mounted) setState(() => _wallets = wallets);
    }, onError: (Object _) {});
    _goalStream.listen((goals) {
      if (mounted) setState(() => _goals = goals);
    }, onError: (Object _) {});
    // Start the split down the middle, so the two boxes already add up.
    final half = (widget.leftover * 50).round() / 100;
    _saveController.text = formatAmountInput(half);
    _spendController.text = formatAmountInput(widget.leftover - half);
  }

  @override
  void dispose() {
    _saveController.dispose();
    _spendController.dispose();
    super.dispose();
  }

  /// Goals still being saved for, and savings accounts that can take more.
  List<Goal> get _openGoals => [
    for (final goal in _goals)
      if (goal.status == GoalStatus.active) goal,
  ];
  List<Wallet> get _savingsAccounts => [
    for (final wallet in _wallets)
      if (!wallet.archived &&
          wallet.purpose == WalletPurpose.savings &&
          !wallet.isLockedSavings)
        wallet,
  ];

  /// The choice made, or the first one there is.
  String? get _destination {
    final options = [
      for (final goal in _openGoals) 'goal:${goal.id}',
      for (final wallet in _savingsAccounts) 'savings:${wallet.id}',
    ];
    if (options.contains(_saveTo)) return _saveTo;
    return options.firstOrNull;
  }

  Goal? get _goalChosen {
    final destination = _destination;
    if (destination == null || !destination.startsWith('goal:')) return null;
    return _openGoals.where((goal) => 'goal:${goal.id}' == destination).first;
  }

  String? get _savingsChosen {
    final destination = _destination;
    if (destination == null || !destination.startsWith('savings:')) {
      return null;
    }
    return destination.substring('savings:'.length);
  }

  /// What is being saved, for the choice made.
  double get _savedAmount => switch (_choice) {
    _Choice.save => widget.leftover,
    _Choice.split => _parse(_saveController) ?? 0,
    _ => 0,
  };

  void _resolve(LeftoverDecision decision, double saved, double spent) {
    if (_resolved || widget.cycle.isResolved) return;
    _resolved = true;
    final saving = saved > 0
        ? LeftoverSaving(
            goal: _goalChosen,
            savingsWalletId: _savingsChosen,
            from: _from,
          )
        : null;
    if (widget.onResolve != null) {
      widget.onResolve!(decision, saved, spent);
      if (saving != null) widget.onSaving?.call(saving);
    } else {
      try {
        BudgetService.resolveLeftover(
          cycle: widget.cycle,
          decision: decision,
          saved: saved,
          spent: spent,
          saving: saving,
          others: widget.others,
        );
      } catch (_) {
        // Already settled somewhere else, or the amounts no longer add up.
        setState(() {
          _resolved = false;
          _alreadyDecided =
              'This leftover was already decided. Reopen it to see how.';
        });
        return;
      }
    }
    Navigator.pop(context, true);
  }

  static double? _parse(TextEditingController controller) =>
      double.tryParse(controller.text.trim().replaceAll(',', ''));

  /// What stops the choice being confirmed as it stands, or null. Shown
  /// once Confirm has been tapped, and gone as soon as it is fixed.
  String? get _problem {
    if (_choice == null) return 'Choose what to do with it first.';
    if (_choice == _Choice.spend) return null;

    if (_choice == _Choice.split) {
      final saved = _parse(_saveController);
      final spent = _parse(_spendController);
      if (saved == null ||
          spent == null ||
          !saved.isFinite ||
          !spent.isFinite ||
          saved < 0 ||
          spent < 0) {
        return 'Enter both amounts.';
      }
      if ((saved + spent - widget.leftover).abs() > 0.005) {
        return 'The two amounts must add up to '
            '${formatPeso(widget.leftover)}. Right now they make '
            '${formatPeso(saved + spent)}.';
      }
    }
    return _savingProblem;
  }

  /// Saved money needs somewhere to go, and must be in the wallets it is
  /// said to be in.
  String? get _savingProblem {
    final saved = _savedAmount;
    if (saved <= 0) return null;
    if (_destination == null) {
      return 'To save it, first add a goal in Goals or a savings account in '
          'Savings.';
    }
    final goal = _goalChosen;
    if (goal != null && saved > goal.remaining + 0.005) {
      return '${goal.name} only needs ${formatPeso(goal.remaining)} more.';
    }
    return walletSplitProblem(
      purpose: SplitPurpose.giving,
      amounts: _from,
      wallets: _wallets,
      goals: _goals,
      target: saved,
      matchTarget: true,
    );
  }

  void _confirm() {
    markTriedToSave();
    if (_problem != null) return;
    final leftover = widget.leftover;

    switch (_choice!) {
      case _Choice.save:
        _resolve(LeftoverDecision.saved, leftover, 0);
      case _Choice.spend:
        _resolve(LeftoverDecision.spent, 0, leftover);
      case _Choice.split:
        _resolve(
          LeftoverDecision.split,
          _parse(_saveController)!,
          _parse(_spendController)!,
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final lastDay = widget.periodEnd.subtract(const Duration(days: 1));
    final error = _alreadyDecided ?? (triedToSave ? _problem : null);

    return Scaffold(
      backgroundColor: colors.pageBackground,
      appBar: AppBar(
        title: const Text(
          'Leftover Money',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
        ),
        centerTitle: true,
        backgroundColor: appPrimaryBlue,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: appPrimaryBlue,
              borderRadius: BorderRadius.circular(18),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Left from ${_monthName(widget.cycle)}',
                  style: const TextStyle(color: Colors.white70, fontSize: 13),
                ),
                const SizedBox(height: 10),
                MoneyText(
                  widget.leftover,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 34,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'What came in less what went out, '
                  '${formatShortDate(periodOf(widget.cycle).start)} – '
                  '${formatShortDate(lastDay)}',
                  style: const TextStyle(color: Colors.white70, fontSize: 12),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          Text(
            'What should happen to it?',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: colors.textPrimary,
            ),
          ),
          const SizedBox(height: 12),
          _ChoiceTile(
            selected: _choice == _Choice.save,
            icon: AppIcons.moneyBox,
            title: 'Save it',
            subtitle: 'Set it aside. It stops counting as money you can spend.',
            onTap: () => setState(() => _choice = _Choice.save),
          ),
          _ChoiceTile(
            selected: _choice == _Choice.spend,
            icon: AppIcons.shopping,
            title: 'Use it for spending',
            subtitle:
                'Keep it available. It is still recorded, not thrown away.',
            onTap: () => setState(() => _choice = _Choice.spend),
          ),
          _ChoiceTile(
            selected: _choice == _Choice.split,
            icon: AppIcons.split,
            title: 'Split it',
            subtitle: 'Save part, keep the rest for spending.',
            onTap: () => setState(() => _choice = _Choice.split),
          ),
          if (_choice == _Choice.split) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _saveController,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    inputFormatters: const [ThousandsSeparatorFormatter()],
                    decoration: dialogFieldDecoration(
                      context,
                      'Save',
                    ).copyWith(prefixText: '₱ ', hintText: '0.00'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _spendController,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    inputFormatters: const [ThousandsSeparatorFormatter()],
                    decoration: dialogFieldDecoration(
                      context,
                      'Spend',
                    ).copyWith(prefixText: '₱ ', hintText: '0.00'),
                  ),
                ),
              ],
            ),
          ],
          if (_savedAmount > 0) ..._savingFields(),
          if (error != null) ...[
            const SizedBox(height: 12),
            Text(
              error,
              style: TextStyle(
                color: dangerColorOn(context),
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _confirm,
              style: confirmButtonStyle(),
              child: const Text(
                'Confirm',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ),
          ),
          const SizedBox(height: 8),
          TextButton(
            // "Later" is its own answer: the decision is marked pending and
            // the reminder stays on Home until it is made.
            onPressed: () => _resolve(LeftoverDecision.pending, 0, 0),
            style: cancelTextStyle(context),
            child: const Text('Decide later'),
          ),
        ],
      ),
    );
  }

  /// Where the saved money goes, and which wallets it is in now.
  List<Widget> _savingFields() {
    final goals = _openGoals;
    final accounts = _savingsAccounts;
    if (goals.isEmpty && accounts.isEmpty) return const [];

    return [
      const SizedBox(height: 16),
      DropdownButtonFormField<String>(
        key: const Key('leftover-save-to'),
        initialValue: _destination,
        isExpanded: true,
        decoration: dialogFieldDecoration(context, 'Save it to'),
        items: [
          for (final goal in goals)
            DropdownMenuItem(
              value: 'goal:${goal.id}',
              child: Text(
                'Goal: ${goal.name}',
                overflow: TextOverflow.ellipsis,
              ),
            ),
          for (final wallet in accounts)
            DropdownMenuItem(
              value: 'savings:${wallet.id}',
              child: Text(
                'Savings: ${wallet.name}',
                overflow: TextOverflow.ellipsis,
              ),
            ),
        ],
        onChanged: (value) => setState(() => _saveTo = value),
      ),
      const SizedBox(height: 16),
      WalletSplitPicker(
        key: const ValueKey('leftover-from'),
        wallets: _wallets,
        goals: _goals,
        purpose: SplitPurpose.giving,
        question: 'Which wallets is it in now?',
        target: _savedAmount,
        matchTarget: true,
        initialAmounts: _from,
        totalLabel: 'Saving',
        onChanged: (amounts) => setState(() => _from = amounts),
      ),
    ];
  }
}

class _ChoiceTile extends StatelessWidget {
  const _ChoiceTile({
    required this.selected,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final bool selected;

  /// The app's colored icon for the choice.
  final String icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: colors.card,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: selected ? appPrimaryBlue : colors.border,
                width: selected ? 1.8 : 1,
              ),
            ),
            child: Row(
              children: [
                Image.asset(icon, width: 28, height: 28),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: colors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: TextStyle(
                          fontSize: 12,
                          color: context.appColors.textMuted,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  selected
                      ? Icons.radio_button_checked
                      : Icons.radio_button_unchecked,
                  color: selected
                      ? appPrimaryBlue
                      : context.appColors.textMuted,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The month an income belongs to, as "Oct 2026": what is left is decided
/// for the whole month.
String _monthName(AllocationCycle cycle) {
  final month = periodOf(cycle).start;
  return '${formatMonthName(month)} ${month.year}';
}
