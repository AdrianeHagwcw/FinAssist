import 'package:flutter/material.dart';

import '../../backend/models/goal.dart';
import '../../backend/models/wallet.dart';
import '../../backend/services/wallet_service.dart';
import '../theme/app_buttons.dart';
import '../theme/app_colors.dart';
import '../../backend/utils/money_format.dart';
import 'add_button.dart';

/// Shown after a wallet is added from the Wallets screen: the wallets added
/// so far, then the Cash Summary they make with the rest, as setup shows it.
/// The user can add another straight away, without going back to the Add
/// Wallet button. Returns true to add another.
///
/// The figures come from the saved wallets themselves, so a name the app
/// numbered ("Cash 2") and every balance read exactly as they were saved.
Future<bool> showWalletsAddedSheet(
  BuildContext context, {
  required Set<String> addedIds,
  required List<Goal> goals,
  Stream<List<Wallet>>? wallets,
}) async {
  final another = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: context.appColors.card,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (context) => WalletsAddedSheet(
      addedIds: addedIds,
      goals: goals,
      wallets: wallets ?? WalletService.watchWallets(),
    ),
  );
  return another == true;
}

class WalletsAddedSheet extends StatelessWidget {
  const WalletsAddedSheet({
    required this.addedIds,
    required this.goals,
    required this.wallets,
    super.key,
  });

  final Set<String> addedIds;
  final List<Goal> goals;
  final Stream<List<Wallet>> wallets;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    return SafeArea(
      child: StreamBuilder<List<Wallet>>(
        stream: wallets,
        builder: (context, snapshot) {
          final all = snapshot.data ?? const <Wallet>[];
          final spending = all
              .where((wallet) => !wallet.archived && !wallet.isSetAside)
              .toList();
          final added = [
            for (final wallet in all)
              if (addedIds.contains(wallet.id)) wallet,
          ];

          // What can be spent, each wallet less what its goals hold: the
          // same figures as Home.
          double free(Iterable<Wallet> group) => group.fold<double>(
            0,
            (total, wallet) => total + freeInWallet(wallet, goals),
          );
          final cashOnHand = free(
            spending.where((wallet) => wallet.type == WalletType.cash),
          );
          final inBank = free(
            spending.where((wallet) => wallet.type != WalletType.cash),
          );
          final interest = spending
              .map((wallet) => wallet.estimatedAnnualInterestIncome)
              .whereType<double>()
              .fold<double>(0, (total, gross) => total + afterTax(gross));

          return SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: colors.border,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Icon(Icons.check_circle, color: confirmColorOn(context)),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        addedIds.length == 1
                            ? 'Wallet added'
                            : '${addedIds.length} wallets added',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: colors.textPrimary,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  'Add another, or tap Done if that is all.',
                  style: TextStyle(fontSize: 13, color: colors.textMuted),
                ),
                const SizedBox(height: 16),
                for (final wallet in added)
                  _AddedRow(wallet: wallet, key: Key('added-${wallet.id}')),
                const SizedBox(height: 8),
                Text(
                  'Cash Summary',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: colors.textPrimary,
                  ),
                ),
                const SizedBox(height: 10),
                _SummaryRow(
                  iconAssets: [WalletType.cash.iconAsset],
                  label: 'Cash on Hand',
                  amount: cashOnHand,
                ),
                _SummaryRow(
                  iconAssets: [WalletType.bank.iconAsset],
                  label: 'Cash in Bank',
                  amount: inBank,
                ),
                _SummaryRow(
                  // Cash on hand plus cash in bank, so both their icons.
                  iconAssets: [
                    WalletType.cash.iconAsset,
                    WalletType.bank.iconAsset,
                  ],
                  label: 'Total Available Money',
                  amount: cashOnHand + inBank,
                  emphasized: true,
                  key: const Key('added-total'),
                ),
                if (interest > 0.005)
                  _SummaryRow(
                    iconAssets: const [
                      'assets/icons/icons8-combo-chart-100.png',
                    ],
                    label: 'Interest in a Year (after tax)',
                    amount: interest,
                  ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.pop(context, false),
                        style: openOutlineStyle(context, height: 52),
                        child: const Text(
                          'Done',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 2,
                      child: AddButton(
                        label: 'Add Another',
                        onPressed: () => Navigator.pop(context, true),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// One wallet just added: its icon, name and balance.
class _AddedRow extends StatelessWidget {
  const _AddedRow({required this.wallet, super.key});

  final Wallet wallet;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: colors.pageBackground,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: colors.border),
      ),
      child: Row(
        children: [
          Image.asset(wallet.iconAsset, width: 26, height: 26),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              wallet.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: colors.textPrimary,
              ),
            ),
          ),
          Text(
            formatPeso(wallet.balance),
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: colors.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}

/// A Cash Summary line, as setup draws it.
class _SummaryRow extends StatelessWidget {
  const _SummaryRow({
    required this.iconAssets,
    required this.label,
    required this.amount,
    this.emphasized = false,
    super.key,
  });

  final List<String> iconAssets;
  final String label;
  final double amount;
  final bool emphasized;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: emphasized ? colors.primaryTint : colors.pageBackground,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: emphasized ? colors.primaryText : colors.border,
        ),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 34,
            height: 28,
            child: iconAssets.length == 1
                ? Align(
                    alignment: Alignment.centerLeft,
                    child: Image.asset(iconAssets.first, width: 28, height: 28),
                  )
                : Stack(
                    children: [
                      Positioned(
                        left: 0,
                        top: 0,
                        child: Image.asset(
                          iconAssets[0],
                          width: 22,
                          height: 22,
                        ),
                      ),
                      Positioned(
                        right: 0,
                        bottom: 0,
                        child: Image.asset(
                          iconAssets[1],
                          width: 22,
                          height: 22,
                        ),
                      ),
                    ],
                  ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontWeight: emphasized ? FontWeight.bold : FontWeight.w600,
                color: colors.textPrimary,
              ),
            ),
          ),
          Text(
            formatPeso(amount),
            style: TextStyle(
              fontSize: emphasized ? 16 : 14,
              fontWeight: FontWeight.bold,
              color: colors.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}
