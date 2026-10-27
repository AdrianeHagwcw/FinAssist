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
                'Safe to Spend allows for upcoming bills, savings and goal money. Tap the light bulb on the Available Balance card to see the calculation. Money set aside stays in your wallet.',
              ),
            ),
          ],
        ),
        ExpansionTile(
          title: Text('How do I review money left from earlier income?'),
          children: [
            ListTile(
              title: Text(
                'Open Cash Inflows from Transactions or Settings, then Needs review. Choose Review leftover to save, keep for spending or split it. You can also decide later.',
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
                'Scan Receipt reads the text on a receipt photo, and Voice Entry turns what you say into words. Either way you check the text first, then Use This opens a new expense with the amount, category and description filled in where they could be found. You check and change anything before saving; nothing is saved automatically. Receipt photos are not attached to expenses or uploaded anywhere.',
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
