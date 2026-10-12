import 'package:flutter/material.dart';

import '../models/wallet.dart';
import '../theme/app_colors.dart';
import '../utils/money_format.dart';
import 'matured_savings_sheet.dart';

/// Savings records that have reached their maturity date and still hold
/// money. Several are grouped into one card, so Home never stacks up.
List<Wallet> maturedSavings(Iterable<Wallet> wallets, DateTime now) {
  return [
    for (final wallet in wallets)
      if (wallet.purpose == WalletPurpose.savings && wallet.maturedBy(now))
        wallet,
  ];
}

/// Shown under Safe to Spend when a time deposit or government savings has
/// come due. FinAssist cannot see a real account, so it asks rather than
/// moving anything by itself.
class MaturedSavingsNotice extends StatelessWidget {
  const MaturedSavingsNotice({
    required this.wallets,
    this.today,
    this.onAnswered,
    super.key,
  });

  final List<Wallet> wallets;
  final DateTime? today;

  /// Called after the user answers, so Home can refresh.
  final VoidCallback? onAnswered;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final due = maturedSavings(wallets, today ?? DateTime.now());
    if (due.isEmpty) return const SizedBox.shrink();

    final total = due.fold<double>(0, (sum, wallet) => sum + wallet.balance);
    final many = due.length > 1;

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.primaryTint,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Image.asset('assets/icons/icons8-money-box-96.png', width: 22),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  many
                      ? '${due.length} savings ready to take out'
                      : '${due.first.name} is ready to take out',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: colors.textPrimary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            many
                ? '${formatPeso(total)} in all. Tell FinAssist what you did '
                      'with each one.'
                : '${formatPeso(due.first.balance)} recorded. Did you take '
                      'the money out, or did it renew?',
            style: TextStyle(fontSize: 13, height: 1.4, color: colors.textBody),
          ),
          if (many) ...[
            const SizedBox(height: 8),
            for (final wallet in due)
              Padding(
                padding: const EdgeInsets.only(bottom: 2),
                child: Text(
                  '${wallet.name} · ${formatPeso(wallet.balance)}',
                  style: TextStyle(fontSize: 12, color: colors.textBody),
                ),
              ),
          ],
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerLeft,
            child: FilledButton(
              key: const Key('matured-review'),
              onPressed: () => _review(context, due),
              child: Text(many ? 'Review each one' : 'Review'),
            ),
          ),
        ],
      ),
    );
  }

  /// Asks about each matured record in turn, stopping if the user backs out.
  Future<void> _review(BuildContext context, List<Wallet> due) async {
    for (final wallet in due) {
      final answered = await showMaturedSavingsSheet(
        context,
        wallet: wallet,
        wallets: wallets,
      );
      if (answered != true) break;
      if (!context.mounted) return;
    }
    onAnswered?.call();
  }
}
