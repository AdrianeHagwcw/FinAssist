import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../widgets/info_intro_card.dart';

/// One question and its answer.
typedef _Faq = ({String question, String answer});

/// The questions, grouped the way people look for them, so a short heading
/// leads to the right few instead of a list of twelve to read through.
const List<({String title, List<_Faq> faqs})> _sections = [
  (
    title: 'Recording money',
    faqs: [
      (
        question: 'How do I record money?',
        answer:
            'Tap + and choose Expense, Income or Transfer. Then choose where the money is: Cash on Hand, Cash in Bank, Both, or Savings. A transfer moves money between your own wallets, so it is not counted as money in or money out.',
      ),
      (
        question: 'What do Inflow and Outflow mean?',
        answer:
            'Inflow is money that came in, like your salary. Outflow is money that went out, like expenses and payments. Moving money between your own wallets is neither. This Month on Home shows both; tap one to see its list.',
      ),
      (
        question: 'What happens when I hide a category?',
        answer:
            'It disappears from new expense choices. Your past entries and reports stay unchanged, and you can turn the category on again anytime.',
      ),
      (
        question: 'How do Scan Receipt and Voice Entry work?',
        answer:
            'Scan Receipt reads the text on a receipt photo and starts a new expense with the amount, category and description filled in. Receipt photos are not attached to expenses or uploaded anywhere. Voice Entry understands English, Tagalog and Taglish. Say an expense ("Pamasahe 50"), income ("Sweldo 15,000"), a transfer ("Ilipat ang 500 sa GCash"), a bill, goal, installment, debt or wallet to add, or a screen to open ("Buksan ang utang"). It shows what it understood, then opens the form filled in. Either way you check everything before saving; nothing is saved automatically.',
      ),
    ],
  ),
  (
    title: 'Your balance',
    faqs: [
      (
        question: 'Why is Safe to Spend lower than my balance?',
        answer:
            'Safe to Spend is what you can spend today and still have enough for bills due this month and your goals. It starts again every midnight, Philippine time. What you spent on earlier days is already out of your balance. Tap the bar or the light bulb on the Available Balance card to see how it is worked out.',
      ),
      (
        question: 'How are the amounts calculated?',
        answer:
            'Ask Fin “Anong formula ang ginamit?” or “Safe to Spend formula”. '
            'You can also ask about suggested savings, goals, installments '
            'and reports. The explanation uses your recorded amounts. '
            'Keep them up to date so the results match your situation.',
      ),
      (
        question: 'Why is my interest less than the rate says?',
        answer:
            'Banks keep 20% of the interest as tax before paying it, for '
            'savings, time deposits, bank accounts and e-wallets. FinAssist '
            'shows the interest, the tax and what you get, and adds what you '
            'get to your balance. Interest on a loan you pay is not taxed '
            'this way.',
      ),
      (
        question: 'Where do I see what was left each month?',
        answer:
            'Open Cash Inflows from the light bulb at the top of Transactions, or from Settings, then Your money. Each month shows what came in, what went out, and what was left. To put some of it aside, add it to a goal or move it to a savings account.',
      ),
    ],
  ),
  (
    title: 'Installments and debts',
    faqs: [
      (
        question: 'What is the difference between Installments and Debts?',
        answer:
            'Installments are things you bought and pay for in parts, like a phone or an appliance. You enter the cash price and the months, and FinAssist works out each payment. Debts are money you borrowed, like from a bank, SSS, Pag-IBIG or family. Say how the lender charges interest: in each payment (most loans), charged separately, or none. Enter the amount borrowed without interest, and FinAssist works out the interest in each payment. Each payment of either one shows in your Bill Planner, where you pay it.',
      ),
      (
        question: 'What if I paid one off early?',
        answer:
            'Open the debt and tap Paid it off early. Enter the amount the lender asked for and the wallet it came from. The payments left are taken off your Bill Planner. If it was a mistake, tap Undo paying it off. An installment is finished by paying its payments ahead instead.',
      ),
    ],
  ),
  (
    title: 'Account and support',
    faqs: [
      (
        question: 'Can I use FinAssist offline?',
        answer:
            'Previously loaded records remain available offline. New entries wait on your device until you reconnect. Connect before signing out or changing devices so your latest changes are saved to your account.',
      ),
      (
        question: 'How do I save a copy or delete my account?',
        answer:
            'In Settings, Export transactions saves all your records as a file you can open in Excel or Google Sheets. Delete account, just below it, removes your account and all your records for good. Save a copy first if you want one.',
      ),
      (
        question: 'How do I report a problem?',
        answer:
            'Share the screen name, what you tried and the error text with the FinAssist team through your existing project contact. Hide balances and personal details in screenshots. No in-app support channel is connected yet.',
      ),
    ],
  ),
];

class HelpScreen extends StatelessWidget {
  const HelpScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    return Scaffold(
      backgroundColor: colors.pageBackground,
      appBar: AppBar(
        title: const Text(
          'Help & Support',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
        ),
        centerTitle: true,
        backgroundColor: appPrimaryBlue,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
        children: [
          const InfoIntroCard(
            title: 'A little clarity goes a long way',
            message:
                'Quick answers to help you keep your money records in order.',
          ),
          for (final section in _sections) ...[
            const SizedBox(height: 24),
            // The same heading and card as Settings, so Help reads as part
            // of it.
            Text(
              section.title,
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.bold,
                color: colors.textPrimary,
              ),
            ),
            const SizedBox(height: 10),
            Material(
              color: colors.card,
              borderRadius: BorderRadius.circular(16),
              clipBehavior: Clip.antiAlias,
              child: Column(
                children: [
                  for (final (index, faq) in section.faqs.indexed) ...[
                    if (index > 0)
                      Divider(
                        height: 1,
                        indent: 16,
                        endIndent: 16,
                        color: colors.border,
                      ),
                    _Question(faq),
                  ],
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// A question that opens to its answer, in the card's own lines: no extra
/// borders when open, and the answer in softer, easier-to-read text.
class _Question extends StatelessWidget {
  const _Question(this.faq);

  final _Faq faq;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    return ExpansionTile(
      shape: const Border(),
      collapsedShape: const Border(),
      tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
      childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      expandedAlignment: Alignment.topLeft,
      iconColor: colors.primaryText,
      collapsedIconColor: colors.textMuted,
      title: Text(
        faq.question,
        style: TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w600,
          color: colors.textPrimary,
        ),
      ),
      children: [
        Text(
          faq.answer,
          style: TextStyle(fontSize: 14, height: 1.45, color: colors.textBody),
        ),
      ],
    );
  }
}
