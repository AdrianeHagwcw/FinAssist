import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/app_settings_provider.dart';

import '../models/allocation.dart';
import '../services/budget_service.dart';
import '../theme/app_buttons.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../utils/date_format.dart';
import '../utils/money_format.dart';
import '../widgets/dialog_kit.dart';
import '../widgets/money_text.dart';

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
                      ? 'Still to decide: left from your ${cycle.source} period'
                      : 'Left from your ${cycle.source} period. What should '
                            'happen to it?',
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
    this.onResolve,
    this.initialDecision,
    super.key,
  });

  final AllocationCycle cycle;
  final double leftover;
  final LeftoverDecision? initialDecision;

  /// The day after the period's last day.
  final DateTime periodEnd;

  /// Replaces saving the decision. Used by tests.
  final void Function(LeftoverDecision decision, double saved, double spent)?
  onResolve;

  @override
  State<LeftoverReviewScreen> createState() => _LeftoverReviewScreenState();
}

class _LeftoverReviewScreenState extends State<LeftoverReviewScreen> {
  _Choice? _choice;
  final _saveController = TextEditingController();
  final _spendController = TextEditingController();
  String? _error;
  bool _resolved = false;

  @override
  void initState() {
    super.initState();
    final suggested =
        widget.initialDecision ??
        context.read<AppSettingsProvider?>()?.financial.leftover;
    _choice = switch (suggested) {
      LeftoverDecision.saved => _Choice.save,
      LeftoverDecision.spent => _Choice.spend,
      LeftoverDecision.split => _Choice.split,
      _ => null,
    };
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

  void _resolve(LeftoverDecision decision, double saved, double spent) {
    if (_resolved || widget.cycle.isResolved) return;
    _resolved = true;
    if (widget.onResolve != null) {
      widget.onResolve!(decision, saved, spent);
    } else {
      try {
        BudgetService.resolveLeftover(
          cycle: widget.cycle,
          decision: decision,
          saved: saved,
          spent: spent,
        );
      } catch (_) {
        // Already settled somewhere else, or the amounts no longer add up.
        setState(() {
          _resolved = false;
          _error = 'This leftover was already decided. Reopen it to see how.';
        });
        return;
      }
    }
    Navigator.pop(context, true);
  }

  void _confirm() {
    final leftover = widget.leftover;

    switch (_choice) {
      case null:
        setState(() => _error = 'Choose what to do with it first.');
      case _Choice.save:
        _resolve(LeftoverDecision.saved, leftover, 0);
      case _Choice.spend:
        _resolve(LeftoverDecision.spent, 0, leftover);
      case _Choice.split:
        final saved = double.tryParse(_saveController.text.trim());
        final spent = double.tryParse(_spendController.text.trim());

        if (saved == null ||
            spent == null ||
            !saved.isFinite ||
            !spent.isFinite ||
            saved < 0 ||
            spent < 0) {
          setState(() => _error = 'Enter both amounts.');
          return;
        }
        if ((saved + spent - leftover).abs() > 0.005) {
          setState(
            () => _error =
                'The two amounts must add up to ${formatPeso(leftover)}. '
                'Right now they make ${formatPeso(saved + spent)}.',
          );
          return;
        }
        _resolve(LeftoverDecision.split, saved, spent);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final lastDay = widget.periodEnd.subtract(const Duration(days: 1));

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
                  'Left from your ${widget.cycle.source}',
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
                  'Pay period ${formatShortDate(widget.cycle.receivedAt)} – '
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
            icon: Icons.savings_outlined,
            title: 'Save it',
            subtitle: 'Set it aside. It stops counting as money you can spend.',
            onTap: () => setState(() {
              _choice = _Choice.save;
              _error = null;
            }),
          ),
          _ChoiceTile(
            selected: _choice == _Choice.spend,
            icon: Icons.shopping_bag_outlined,
            title: 'Use it for spending',
            subtitle:
                'Keep it available. It is still recorded, not thrown away.',
            onTap: () => setState(() {
              _choice = _Choice.spend;
              _error = null;
            }),
          ),
          _ChoiceTile(
            selected: _choice == _Choice.split,
            icon: Icons.call_split,
            title: 'Split it',
            subtitle: 'Save part, keep the rest for spending.',
            onTap: () => setState(() {
              _choice = _Choice.split;
              _error = null;
            }),
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
                    decoration: dialogFieldDecoration(
                      context,
                      'Spend',
                    ).copyWith(prefixText: '₱ ', hintText: '0.00'),
                  ),
                ),
              ],
            ),
          ],
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(
              _error!,
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
  final IconData icon;
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
                Icon(icon, color: appPrimaryBlue),
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
                        style: const TextStyle(
                          fontSize: 12,
                          color: Colors.grey,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  selected
                      ? Icons.radio_button_checked
                      : Icons.radio_button_off,
                  color: selected ? appPrimaryBlue : Colors.grey,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
