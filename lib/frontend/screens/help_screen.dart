import 'package:flutter/material.dart';

import '../theme/app_icons.dart';
import '../theme/app_theme.dart';
import '../widgets/info_intro_card.dart';

class HelpScreen extends StatelessWidget {
  const HelpScreen({super.key});
  @override
  Widget build(BuildContext context) => Scaffold(
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
      padding: const EdgeInsets.all(20),
      children: const [
        InfoIntroCard(
          iconAsset: AppIcons.help,
          title: 'A little clarity goes a long way',
          message:
              'Quick answers to help you keep your money records in order.',
        ),
        SizedBox(height: 20),
        ExpansionTile(
          title: Text('How are the amounts calculated?'),
          children: [
            ListTile(
              title: Text(
                'Ask Fin “Anong formula ang ginamit?” or “Safe to Spend formula”. '
                'You can also ask about suggested savings, goals, installments '
                'and reports. The explanation uses your recorded amounts. '
                'Keep them up to date so the results match your situation.',
              ),
            ),
          ],
        ),
        ExpansionTile(
          title: Text('How do I record money?'),
          children: [
            ListTile(
              title: Text(
                'Tap + and choose Expense, Income or Transfer. Then choose where the money is: Cash on Hand, Cash in Bank, or Both. A transfer moves money between your own wallets, so it is not counted as money in or money out.',
              ),
            ),
          ],
        ),
        ExpansionTile(
          title: Text('Why is Safe to Spend lower than my balance?'),
          children: [
            ListTile(
              title: Text(
                'Safe to Spend is what you can spend today and still have enough for bills due this month and your goals. It starts again every midnight, Philippine time. What you spent on earlier days is already out of your balance. Tap the bar or the light bulb on the Available Balance card to see how it is worked out.',
              ),
            ),
          ],
        ),
        ExpansionTile(
          title: Text('How do I review money left from earlier income?'),
          children: [
            ListTile(
              title: Text(
                'Open Cash Inflows from the light bulb at the top of Transactions, or from Settings, then Needs review. Choose Review leftover to save, keep for spending or split it. You can also decide later.',
              ),
            ),
          ],
        ),
        ExpansionTile(
          title: Text('What do Inflow and Outflow mean?'),
          children: [
            ListTile(
              title: Text(
                'Inflow is money that came in, like your salary. Outflow is money that went out, like expenses and payments. Moving money between your own wallets is neither. This Month on Home shows both; tap one to see its list.',
              ),
            ),
          ],
        ),
        ExpansionTile(
          title: Text('What is the difference between Installments and Debts?'),
          children: [
            ListTile(
              title: Text(
                'Installments are things you bought and pay for in parts, like a phone or an appliance. You enter the cash price and the months, and FinAssist works out each payment. Debts are money you borrowed, like from a bank, SSS, Pag-IBIG or family, where the interest is worked out too. Each payment of either one shows in your Bill Planner, where you pay it.',
              ),
            ),
          ],
        ),
        ExpansionTile(
          title: Text('What if I paid one off early?'),
          children: [
            ListTile(
              title: Text(
                'Open the installment or debt and tap Paid it off early. Enter the amount the store or lender asked for and the wallet it came from. The payments left are taken off your Bill Planner. If it was a mistake, tap Undo paying it off.',
              ),
            ),
          ],
        ),
        ExpansionTile(
          title: Text('Can I use FinAssist offline?'),
          children: [
            ListTile(
              title: Text(
                'Previously loaded records remain available offline. New entries wait on your device until you reconnect. Connect before signing out or changing devices so your latest changes are saved to your account.',
              ),
            ),
          ],
        ),
        ExpansionTile(
          title: Text('What happens when I hide a category?'),
          children: [
            ListTile(
              title: Text(
                'It disappears from new expense choices. Your past entries and reports stay unchanged, and you can turn the category on again anytime.',
              ),
            ),
          ],
        ),
        ExpansionTile(
          title: Text('How do Scan Receipt and Voice Entry work?'),
          children: [
            ListTile(
              title: Text(
                'Scan Receipt reads the text on a receipt photo and starts a new expense with the amount, category and description filled in. Receipt photos are not attached to expenses or uploaded anywhere. Voice Entry understands English, Tagalog and Taglish. Say an expense ("Pamasahe 50"), income ("Sweldo 15,000"), a transfer ("Ilipat ang 500 sa GCash"), a bill, goal, installment, debt or wallet to add, or a screen to open ("Buksan ang utang"). It shows what it understood, then opens the form filled in. Either way you check everything before saving; nothing is saved automatically.',
              ),
            ),
          ],
        ),
        ExpansionTile(
          title: Text('How do I save a copy or delete my account?'),
          children: [
            ListTile(
              title: Text(
                'In Settings, Export transactions saves all your records as a file you can open in Excel or Google Sheets. Delete account, just below it, removes your account and all your records for good. Save a copy first if you want one.',
              ),
            ),
          ],
        ),
        ExpansionTile(
          title: Text('How do I report a problem?'),
          children: [
            ListTile(
              title: Text(
                'Share the screen name, what you tried and the error text with the FinAssist team through your existing project contact. Hide balances and personal details in screenshots. No in-app support channel is connected yet.',
              ),
            ),
          ],
        ),
      ],
    ),
  );
}
