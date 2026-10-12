import 'package:flutter/material.dart';

import '../models/goal.dart';
import '../models/wallet.dart';
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
    required this.icon,
    required this.summary,
    required this.risk,
    required this.access,
    required this.whatItIs,
    required this.howItWorks,
    required this.bestFor,
    required this.watchOutFor,
    this.goalName,
    this.goalKind = GoalKind.regular,
    this.savingsKind,
    this.ownName,
  });

  /// Set only on a card that is not about a savings kind.
  final String? ownName;

  /// The card's title. A card about a place to keep money takes the savings
  /// kind's own label, so the guide can never drift from what sign up and
  /// Add savings show.
  String get name => savingsKind?.label ?? ownName!;
  final IconData icon;
  final String summary;
  final String risk;
  final String access;
  final String whatItIs;
  final List<String> howItWorks;
  final List<String> bestFor;
  final List<String> watchOutFor;

  /// What a goal made from this card is called, and what kind it is. Only
  /// a card about a purpose carries one.
  final String? goalName;
  final GoalKind goalKind;

  /// The savings record this card leads to. A savings account, a time
  /// deposit and government savings are places money is kept, not things to
  /// save for, so they open a record rather than a goal.
  final SavingsKind? savingsKind;

  bool get startsAGoal => goalName != null;
}

const List<SavingsOption> savingsOptions = [
  SavingsOption(
    icon: Icons.payments_outlined,
    summary: 'Money you keep yourself',
    risk: 'Can be lost or spent',
    access: 'Take out anytime',
    whatItIs:
        'Money you hold yourself, such as cash at home, in an envelope or in '
        'a jar. It earns nothing, but it is there the moment you need it.',
    howItWorks: [
      'You set money aside and keep it yourself.',
      'Nothing is added over time, so what you put in is what you get.',
    ],
    bestFor: [
      'Small amounts you may need any day',
      'Saving without a bank account',
    ],
    watchOutFor: [
      'It is the easiest money to spend without noticing.',
      'Cash at home can be lost or taken, and no one replaces it.',
    ],
    savingsKind: SavingsKind.general,
  ),
  SavingsOption(
    ownName: 'Emergency Fund',
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
    goalKind: GoalKind.emergencyFund,
  ),
  SavingsOption(
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
    bestFor: [
      'Money you may need within a few months',
      'Money you want kept safely, not as cash at home',
    ],
    watchOutFor: [
      'Check for minimum balances and fees.',
      'Make sure the bank is covered by PDIC deposit insurance.',
    ],
    savingsKind: SavingsKind.account,
  ),
  SavingsOption(
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
    savingsKind: SavingsKind.timeDeposit,
  ),
  SavingsOption(
    icon: Icons.savings_outlined,
    summary: 'Save through SSS, Pag-IBIG or GSIS',
    risk: 'Very low risk',
    access: 'Only under the agency rules',
    whatItIs:
        'Savings programs run by government agencies, such as Pag-IBIG MP2, '
        'SSS or GSIS. You put money in over time and take it out only when '
        'their rules allow.',
    howItWorks: [
      'Pag-IBIG MP2 runs for five years, then pays what you saved plus its '
          'dividend.',
      'SSS and GSIS savings follow each agency\'s own rules for when you can '
          'claim.',
    ],
    bestFor: [
      'Long-term money you will not touch',
      'Members already paying contributions',
    ],
    watchOutFor: [
      'Earnings are declared afterwards, so the rate is not fixed in '
          'advance.',
      'Taking money out early may not be allowed at all.',
    ],
    savingsKind: SavingsKind.government,
  ),
];

/// The guide entry for a savings kind, so Add savings can explain the
/// choice being made.
SavingsOption savingsOptionFor(SavingsKind kind) =>
    savingsOptions.firstWhere((option) => option.savingsKind == kind);

/// Opens the plain-language explainer for one option. [onAct] adds a button
/// under it; without one the sheet only explains.
Future<void> showSavingsOptionSheet(
  BuildContext context, {
  required SavingsOption option,
  double? monthlyIncome,
  String? actionLabel,
  VoidCallback? onAct,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: context.appColors.card,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => _OptionSheet(
      option: option,
      monthlyIncome: monthlyIncome,
      actionLabel: actionLabel,
      onAct: onAct,
    ),
  );
}

/// "Grow Your Money": a suggested monthly amount to save, and what that
/// saving can be for.
///
/// Where to keep it is explained inside Add savings instead, next to the
/// choice itself, rather than sending the reader there from here.
class SavingsGuide extends StatelessWidget {
  const SavingsGuide({
    required this.monthlyIncome,
    required this.onCreateGoal,
    super.key,
  });

  /// Null when there is no income to base a suggestion on.
  final double? monthlyIncome;

  /// Opens the goal form with this name and kind filled in.
  final void Function(String goalName, GoalKind kind) onCreateGoal;

  /// The savings share of the 50/30/20 rule: half for needs, 30% for wants,
  /// 20% for savings.
  static const savingsShare = 0.20;

  void _open(BuildContext context, SavingsOption option) {
    showSavingsOptionSheet(
      context,
      option: option,
      monthlyIncome: monthlyIncome,
      actionLabel: 'Create Savings Goal',
      onAct: () => onCreateGoal(option.goalName!, option.goalKind),
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
        const SizedBox(height: 18),
        _GroupTitle(
          title: 'What you can save for',
          subtitle: 'The one to start with. For anything else, use Add '
              'New Goal above.',
        ),
        for (final option in savingsOptions.where((o) => o.startsAGoal)) ...[
          _optionCard(context, option),
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

  Widget _optionCard(BuildContext context, SavingsOption option) {
    final colors = context.appColors;

    return _CardShell(
      onTap: () => _open(context, option),
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
                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                ),
              ],
            ),
          ),
          const Icon(Icons.chevron_right, color: Colors.grey),
        ],
      ),
    );
  }
}

/// The heading over each group, saying plainly what the group is.
class _GroupTitle extends StatelessWidget {
  const _GroupTitle({required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
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
          const SizedBox(height: 2),
          Text(
            subtitle,
            style: TextStyle(fontSize: 12, color: colors.textBody),
          ),
        ],
      ),
    );
  }
}

class _CardShell extends StatelessWidget {
  const _CardShell({required this.onTap, required this.child});

  final VoidCallback onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    return Material(
      color: colors.card,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: colors.border),
          ),
          child: child,
        ),
      ),
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
    required this.actionLabel,
    required this.onAct,
  });

  final SavingsOption option;
  final double? monthlyIncome;
  final String? actionLabel;
  final VoidCallback? onAct;

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
              // Not "Best for": naming one best would be a recommendation,
              // and this guide only explains.
              section('Usually used for', option.bestFor),
              section('Watch out for', option.watchOutFor),
              const SizedBox(height: 20),
              if (onAct != null) ...[
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () {
                      Navigator.pop(context);
                      onAct!();
                    },
                    // Blue: it opens the form where the saving happens.
                    style: openButtonStyle(),
                    child: Text(
                      actionLabel ?? 'Continue',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
              ],
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
