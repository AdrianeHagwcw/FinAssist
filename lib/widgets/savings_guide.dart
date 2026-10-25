import 'package:flutter/material.dart';

import '../models/goal.dart';
import '../models/wallet.dart';
import '../theme/app_buttons.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import 'savings_form_parts.dart';

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
    icon: Icons.savings_outlined,
    summary: 'Earn interest while keeping the deposit accessible',
    risk: 'Low risk; terms vary by provider',
    access: 'Access depends on the account terms',
    whatItIs:
        'A savings deposit with an annual interest rate. FinAssist estimates '
        'simple interest from the balance history you record.',
    howItWorks: [
      'Enter the rate shown by your provider and the date interest starts.',
      'The estimate is not a bank calculation or a guaranteed return.',
    ],
    bestFor: ['Savings that earn interest without a fixed maturity date'],
    watchOutFor: [
      'Rates, fees and withdrawal rules can change.',
      'The estimate does not change the recorded balance in FinAssist.',
    ],
    savingsKind: SavingsKind.savingsDeposit,
  ),
  SavingsOption(
    icon: Icons.account_balance_wallet_outlined,
    summary: 'Money available on demand',
    risk: 'Depends on the account provider',
    access: 'Withdrawal terms depend on the account',
    whatItIs:
        'A demand deposit that does not earn interest in this FinAssist '
        'summary.',
    howItWorks: [
      'Record the balance you have already put aside.',
      'FinAssist does not estimate interest or add projected money to it.',
    ],
    bestFor: ['Money held in an accessible account without interest'],
    watchOutFor: [
      'Check withdrawal conditions and fees with the provider.',
      'FinAssist does not connect to or move money in the account.',
    ],
    savingsKind: SavingsKind.demandDeposit,
  ),
  SavingsOption(
    icon: Icons.lock_clock_outlined,
    summary: 'Leave it for a set time, earn more',
    risk: 'Low risk',
    access: 'Locked until the agreed date',
    whatItIs:
        'Money you agree to leave in a bank until a date you choose, '
        'usually earning more than a regular savings account.',
    howItWorks: [
      'Choose how long to leave it, such as a few months or a year.',
      'You get your money and what it earned on the agreed date.',
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

/// The option's picture. A place to keep money uses the same colored icon
/// as its tile in Add Savings, so the two are recognisably the same thing;
/// a purpose keeps its line icon.
Widget optionIcon(SavingsOption option, {double size = 30}) {
  final kind = option.savingsKind;
  return kind == null
      ? Icon(option.icon, color: appPrimaryBlue, size: size)
      : Image.asset(savingsKindIcon(kind), width: size, height: size);
}

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
                  optionIcon(option, size: 32),
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
              const SizedBox(height: 12),
              // Two facts side by side, each with what it is about, so "low
              // risk" and "locked until the date" read as answers. The same
              // cards as under the choice in Add Savings.
              FactPair(
                first: FactCard(
                  iconAsset: 'assets/icons/icons8-shield-96.png',
                  label: 'Risk',
                  value: option.risk,
                ),
                second: FactCard(
                  iconAsset: 'assets/icons/icons8-wallet-96.png',
                  label: 'Taking money out',
                  value: option.access,
                ),
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
                    // Green: saying yes to this option, the same color as
                    // every button that goes ahead.
                    style: confirmButtonStyle(),
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
              // The same full-width button as the one above, in red, so
              // closing is as easy to find and tap as going on.
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  key: const Key('savings-option-close'),
                  onPressed: () => Navigator.pop(context),
                  style: dangerButtonStyle(),
                  child: const Text(
                    'Close',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
