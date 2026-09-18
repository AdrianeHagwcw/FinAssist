import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'financial_preferences_screen.dart';

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
        PreferenceIntro(
          icon: Icons.help_outline,
          title: 'A little clarity goes a long way',
          message:
              'Quick answers to help you keep your money records in order.',
        ),
        SizedBox(height: 20),
        ExpansionTile(
          title: Text('How do I record money?'),
          children: [
            ListTile(
              title: Text(
                'Tap +, choose income, expense or transfer, then select a wallet. A transfer moves money between wallets without counting it as income or spending.',
              ),
            ),
          ],
        ),
        ExpansionTile(
          title: Text('Why is Safe to Spend lower than my balance?'),
          children: [
            ListTile(
              title: Text(
                'Safe to Spend allows for upcoming bills, savings and goal money. Tap its explanation to see the calculation. Money set aside stays in your wallet.',
              ),
            ),
          ],
        ),
        ExpansionTile(
          title: Text('How do I finish an old pay cycle?'),
          children: [
            ListTile(
              title: Text(
                'Open Pay-cycle history from Transactions or Settings, then Needs review. Choose Review leftover to save, spend or split it. Your default choice is only a suggestion until you confirm.',
              ),
            ),
          ],
        ),
        ExpansionTile(
          title: Text('Can I use FinAssist offline?'),
          children: [
            ListTile(
              title: Text(
                'Previously loaded records remain available offline. New records queue for sync. Connect before signing out or changing devices so your latest changes can sync.',
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
                'Scan Receipt reads the text on a receipt photo, and Voice Entry turns what you say into words. Either way you check the text first, then Use This opens a new expense with it filled in. You add the amount and category and save it yourself; nothing is saved automatically. Receipt photos are not attached to expenses or uploaded anywhere.',
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
