import 'package:flutter/material.dart';

import '../models/app_transaction.dart';
import '../models/wallet.dart';
import '../theme/app_buttons.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import 'category_icon.dart';
import 'money_text.dart';

/// The icon for money lent out, or for money borrowed or paid back.
String loanIconAsset(AppTransaction transaction) =>
    transaction.type == TransactionType.expense
    ? 'assets/icons/lend-96.png'
    : 'assets/icons/loan-in-96.png';

/// A wallet's name by id, including archived ones the list was given.
String walletNameFor(List<Wallet> wallets, String? id) {
  for (final wallet in wallets) {
    if (wallet.id == id) return wallet.name;
  }
  return 'a wallet';
}

/// One transaction in a list: what it was, which wallet, and the amount in
/// red, green or blue for money out, in, or moved.
class TransactionRow extends StatelessWidget {
  const TransactionRow({
    required this.transaction,
    required this.wallets,
    required this.onTap,
    super.key,
  });

  final AppTransaction transaction;
  final List<Wallet> wallets;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final t = transaction;

    final (Color color, String sign) = switch (t.type) {
      TransactionType.expense => (dangerColorOn(context), '-'),
      TransactionType.income => (confirmColorOn(context), '+'),
      TransactionType.transfer => (appPrimaryBlue, ''),
    };

    final title = t.type == TransactionType.transfer
        ? '${walletNameFor(wallets, t.walletId)} → '
              '${walletNameFor(wallets, t.toWalletId)}'
        : t.label;

    final details = [
      if (t.type != TransactionType.transfer)
        t.isLegacy ? 'Before wallets' : walletNameFor(wallets, t.walletId),
      if (t.isBillPayment) 'Bill payment',
      if ((t.note ?? '').isNotEmpty) t.note!,
    ].join(' · ');

    return Material(
      color: colors.card,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: colors.border),
          ),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: switch (t.type) {
                  _ when t.isDebtMovement => Image.asset(
                    loanIconAsset(t),
                    width: 22,
                    height: 22,
                  ),
                  TransactionType.expense => CategoryIcon(t.label, size: 22),
                  TransactionType.income => Image.asset(
                    'assets/icons/icons8-money-transfer-96.png',
                    width: 22,
                    height: 22,
                  ),
                  TransactionType.transfer => Icon(
                    Icons.swap_horiz,
                    color: color,
                  ),
                },
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: colors.textPrimary,
                      ),
                    ),
                    if (details.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        details,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 12,
                          color: Colors.grey,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 10),
              MoneyText(
                t.amount,
                sign: sign.isEmpty ? null : sign,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  color: color,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
