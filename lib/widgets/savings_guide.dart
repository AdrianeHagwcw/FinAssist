import 'package:flutter/material.dart';

import '../theme/app_buttons.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../utils/money_format.dart';

/// Monthly income worked out from the onboarding answers, or null when there
/// is none to go on. Irregular income is already a rough monthly estimate.
double? monthlyIncomeFrom(Map<String, dynamic>? profile) {
  final income = profile?['income'];
  if (income is! num || income <= 0) return null;

  final perMonth = switch (profile?['incomeFrequency']) {
    'Weekly' => 52 / 12,
    'Bi-weekly' => 26 / 12,
    'Semi-monthly' => 2,
    _ => 1,
  };

  return income.toDouble() * perMonth;
}

/// One kind of place to keep savings, explained in plain words.
///
/// Kept to generic types on purpose: no bank names, no products, no rates.
/// Those change, and naming them would turn a guide into advice.
class SavingsOption {
  const SavingsOption({
    required this.name,
    required this.icon,
    required this.summary,
    required this.risk,
    required this.access,
    required this.whatItIs,
    required this.howItWorks,
    required this.bestFor,
    required this.watchOutFor,
    required this.goalName,
  });

  final String name;
  final IconData icon;
  final String summary;
  final String risk;
  final String access;
  final String whatItIs;
  final List<String> howItWorks;
  final List<String> bestFor;
  final List<String> watchOutFor;

  /// What a goal made from this card is called.
  final String goalName;
}

const List<SavingsOption> savingsOptions = [
  SavingsOption(
    name: 'Emergency Fund',
    icon: Icons.health_and_safety_outlined,
    summary: 'A cash cushion for surprises',
    risk: 'Very low risk',
    access: 'Take out anytime',
    whatItIs:
        'Money kept aside only for the unexpected, like a medical cost, a '
        'broken phone, or a month with no income.',
    howItWorks: [
      'Set aside a little every time money comes in.',
      'A common target is 3 to 6 months of your essential expenses.',
    ],
    bestFor: ['Anyone starting to save', 'Your very first goal'],
    watchOutFor: [
      "Keep it where you can reach it quickly, not locked away.",
      'Only use it for real emergencies, not wants.',
    ],
    goalName: 'Emergency Fund',
  ),
  SavingsOption(
    name: 'Savings Account',
    icon: Icons.account_balance_outlined,
    summary: 'Flexible savings that earn a little',
    risk: 'Very low risk',
    access: 'Take out anytime',
    whatItIs:
        'A bank or digital bank account that pays some interest on what you '
        'keep in it.',
    howItWorks: [
      'Deposit and withdraw whenever you need.',
      'Interest is usually small, and the rate can change.',
    ],
    bestFor: ['Short-term goals', 'Keeping your emergency fund'],
    watchOutFor: [
      'Check for minimum balances and fees.',
      'Make sure the bank is covered by PDIC deposit insurance.',
    ],
    goalName: 'Savings',
  ),
  SavingsOption(
    name: 'Time Deposit',
    icon: Icons.lock_clock_outlined,
    summary: 'Leave it for a set time, earn more',
    risk: 'Low risk',
    access: 'Locked until the term ends',
    whatItIs:
        'Money you agree to leave in a bank for a fixed period, usually for a '
        'better rate than a regular savings account.',
    howItWorks: [
      'Choose how long to leave it, such as a few months or a year.',
      'You get your money and the interest when the term ends.',
    ],
    bestFor: ['Money you will not need until a set date'],
    watchOutFor: [
      'Taking it out early can mean losing interest or paying a penalty.',
      'There is often a minimum amount to start.',
    ],
    goalName: 'Time Deposit',
  ),
];

/// "Grow Your Money": a suggested monthly amount to save, and plain-language
/// cards about where to keep savings.
class SavingsGuide extends StatelessWidget {
  const SavingsGuide({
    required this.monthlyIncome,
    required this.onCreateGoal,
    super.key,
  });

  /// Null when there is no income to base a suggestion on.
  final double? monthlyIncome;

  /// Opens the goal form with this name filled in.
  final void Function(String goalName) onCreateGoal;

  /// The savings share of the 50/30/20 rule: half for needs, 30% for wants,
  /// 20% for savings.
  static const savingsShare = 0.20;

  void _open(BuildContext context, SavingsOption option) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: context.appColors.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) => _OptionSheet(
        option: option,
        monthlyIncome: monthlyIncome,
        onCreateGoal: () {
          Navigator.pop(sheetContext);
          onCreateGoal(option.goalName);
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Grow Your Money',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: colors.textPrimary,
          ),
        ),
        const SizedBox(height: 12),
        _SuggestionCard(monthlyIncome: monthlyIncome),
        const SizedBox(height: 12),
        for (final option in savingsOptions) ...[
          Material(
            color: colors.card,
            borderRadius: BorderRadius.circular(14),
            child: InkWell(
              onTap: () => _open(context, option),
              borderRadius: BorderRadius.circular(14),
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: colors.border),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        color: colors.primaryTint,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(option.icon, color: appPrimaryBlue),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            option.name,
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                              color: colors.textPrimary,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            option.summary,
                            style: const TextStyle(
                              fontSize: 12,
                              color: Colors.grey,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Icon(Icons.chevron_right, color: Colors.grey),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
        ],
        const SizedBox(height: 4),
        const Text(
          'This is an educational guide, not financial advice. Check each '
          "bank's fees, rates and rules before putting money in.",
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 12, color: Colors.grey, height: 1.4),
        ),
      ],
    );
  }
}

class _SuggestionCard extends StatelessWidget {
  const _SuggestionCard({required this.monthlyIncome});

  final double? monthlyIncome;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final income = monthlyIncome;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.primaryTint,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Suggested to save each month',
            style: TextStyle(fontSize: 12, color: Colors.grey),
          ),
          const SizedBox(height: 4),
          Text(
            income == null
                ? 'Add your usual income to see this'
                : 'About ${formatPeso(income * SavingsGuide.savingsShare)}',
            style: TextStyle(
              fontSize: income == null ? 15 : 20,
              fontWeight: FontWeight.bold,
              color: colors.primaryText,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            income == null
                ? 'It comes from the income you gave when setting up.'
                : '20% of your income, from the 50/30/20 rule: half for '
                      'needs, 30% for wants, 20% for savings. A guideline, not '
                      'a rule.',
            style: TextStyle(fontSize: 12, color: colors.textBody, height: 1.4),
          ),
        ],
      ),
    );
  }
}

class _OptionSheet extends StatelessWidget {
  const _OptionSheet({
    required this.option,
    required this.monthlyIncome,
    required this.onCreateGoal,
  });

  final SavingsOption option;
  final double? monthlyIncome;
  final VoidCallback onCreateGoal;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    Widget section(String title, List<String> points) {
      return Padding(
        padding: const EdgeInsets.only(top: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.bold,
                color: colors.textPrimary,
              ),
            ),
            const SizedBox(height: 6),
            for (final point in points)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(
                  '•  $point',
                  style: TextStyle(color: colors.textBody, height: 1.4),
                ),
              ),
          ],
        ),
      );
    }

    Widget tag(String text) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: colors.primaryTint,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: colors.primaryText,
        ),
      ),
    );

    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.85,
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(option.icon, color: appPrimaryBlue, size: 30),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      option.name,
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: colors.textPrimary,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(option.summary, style: TextStyle(color: colors.textBody)),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [tag(option.risk), tag(option.access)],
              ),
              section('What it is', [option.whatItIs]),
              section('How it works', option.howItWorks),
              section('Best for', option.bestFor),
              section('Watch out for', option.watchOutFor),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: onCreateGoal,
                  // Blue: it opens the goal form, where the saving happens.
                  style: openButtonStyle(),
                  child: const Text(
                    'Create Savings Goal',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Center(
                child: TextButton(
                  onPressed: () => Navigator.pop(context),
                  style: cancelTextStyle(context),
                  child: const Text('Close'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
