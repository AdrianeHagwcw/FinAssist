import 'package:flutter/material.dart';

import '../models/wallet.dart';
import '../services/user_profile_service.dart';
import '../services/wallet_service.dart';
import '../theme/app_buttons.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../widgets/empty_state_view.dart';
import '../widgets/legacy_import_card.dart';
import '../widgets/money_text.dart';
import '../widgets/transfer_sheet.dart';
import '../widgets/wallet_actions.dart';
import '../widgets/wallet_form_sheet.dart';
import 'income_waterfall_screen.dart';
import 'wallet_detail_screen.dart';

/// The Wallet tab: the combined balance, then one card per wallet.
class WalletsScreen extends StatefulWidget {
  const WalletsScreen({this.wallets, this.incomeSource, super.key});

  /// Replaces the live wallet list. Used by tests, which can't load Firebase.
  final Stream<List<Wallet>>? wallets;

  /// Replaces the income source saved during onboarding, e.g. "Allowance".
  final Stream<String?>? incomeSource;

  @override
  State<WalletsScreen> createState() => _WalletsScreenState();
}

class _WalletsScreenState extends State<WalletsScreen> {
  // Held in state so a rebuild doesn't start a second listener.
  late final Stream<List<Wallet>> _wallets =
      widget.wallets ?? WalletService.watchWallets();

  late final Stream<String?> _incomeSource =
      widget.incomeSource ??
      UserProfileService.watchProfile().map(
        (profile) => profile.data()?['incomeSource'] as String?,
      );

  Future<void> _addWallet(List<Wallet> currentWallets) async {
    final draft = await showWalletFormSheet(context);

    if (draft == null) return;

    await WalletService.addWallet(
      type: draft.type,
      name: draft.name,
      startingBalance: draft.startingBalance,
      // The very first wallet receives income until the user picks another.
      receivesIncome: currentWallets.isEmpty,
      currentWallets: currentWallets,
    );
  }

  void _openWallet(Wallet wallet) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => WalletDetailScreen(wallet: wallet),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    return Scaffold(
      backgroundColor: colors.pageBackground,
      appBar: AppBar(
        title: const Text(
          'Wallets',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
        ),
        centerTitle: true,
        backgroundColor: appPrimaryBlue,
        foregroundColor: Colors.white,
        elevation: 0,
        automaticallyImplyLeading: false,
      ),
      body: StreamBuilder<List<Wallet>>(
        stream: _wallets,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return _WalletsError(error: snapshot.error!);
          }

          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final wallets = snapshot.data!;

          if (wallets.isEmpty) {
            return Column(
              children: [
                Expanded(
                  child: EmptyStateView(
                    iconAsset: 'assets/icons/icons8-wallet-96.png',
                    title: 'No wallets yet',
                    message:
                        'Add your Cash, GCash, Maya or bank wallet to start '
                        'tracking where your money actually sits.',
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                  child: _AddWalletButton(onPressed: () => _addWallet(wallets)),
                ),
              ],
            );
          }

          return StreamBuilder<String?>(
            stream: _incomeSource,
            builder: (context, incomeSnapshot) {
              return ListView(
                // Room for the bottom bar and the docked "+" button.
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 100),
                children: [
                  const LegacyImportCard(),
                  _TotalBalanceCard(
                    total: totalWalletBalance(wallets),
                    walletCount: wallets.length,
                  ),
                  const SizedBox(height: 20),
                  Text(
                    'My Wallets',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: colors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 12),
                  for (final wallet in wallets) ...[
                    _WalletCard(
                      wallet: wallet,
                      incomeSource: incomeSnapshot.data,
                      onTap: () => _openWallet(wallet),
                      onTransfer: () =>
                          showTransferSheet(context, fromWalletId: wallet.id),
                      onAddIncome: () =>
                          showIncomeWaterfall(context, walletId: wallet.id),
                      onEdit: () => editWallet(context, wallet),
                      onSetIncomeWallet: () => WalletService.setIncomeWallet(
                        wallet.id,
                        currentWallets: wallets,
                      ),
                      onRemove: () => removeWallet(context, wallet),
                    ),
                    const SizedBox(height: 12),
                  ],
                  const SizedBox(height: 4),
                  _AddWalletButton(onPressed: () => _addWallet(wallets)),
                ],
              );
            },
          );
        },
      ),
    );
  }
}

class _TotalBalanceCard extends StatelessWidget {
  const _TotalBalanceCard({required this.total, required this.walletCount});

  final double total;
  final int walletCount;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: appPrimaryBlue,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Total Balance',
            style: TextStyle(color: Colors.white70, fontSize: 14),
          ),
          const SizedBox(height: 14),
          MoneyText(
            total,
            style: TextStyle(
              color: total < 0 ? Colors.redAccent : Colors.white,
              fontSize: 32,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            'Across $walletCount wallet${walletCount == 1 ? '' : 's'}',
            style: const TextStyle(color: Colors.white70, fontSize: 12),
          ),
        ],
      ),
    );
  }
}

class _WalletCard extends StatelessWidget {
  const _WalletCard({
    required this.wallet,
    required this.incomeSource,
    required this.onTap,
    required this.onTransfer,
    required this.onAddIncome,
    required this.onEdit,
    required this.onSetIncomeWallet,
    required this.onRemove,
  });

  final Wallet wallet;

  /// What the user called their income during onboarding, e.g. "Allowance".
  final String? incomeSource;
  final VoidCallback onTap;
  final VoidCallback onTransfer;
  final VoidCallback onAddIncome;
  final VoidCallback onEdit;
  final VoidCallback onSetIncomeWallet;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final source = incomeSource?.trim();
    final incomeLabel = source == null || source.isEmpty
        ? 'Receives my income'
        : 'Receives my $source';

    return Material(
      color: colors.card,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: colors.border),
          ),
          child: Row(
            children: [
              Container(
                width: 46,
                height: 46,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: colors.primaryTint,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Image.asset(wallet.iconAsset),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      wallet.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: colors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      wallet.type.label,
                      style: const TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                    if (wallet.receivesIncome) ...[
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: colors.primaryTint,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          incomeLabel,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: colors.primaryText,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  MoneyText(
                    wallet.balance,
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.bold,
                      color: wallet.balance < 0
                          ? Colors.red
                          : colors.textPrimary,
                    ),
                  ),
                  PopupMenuButton<String>(
                    tooltip: 'Wallet options',
                    icon: const Icon(Icons.more_horiz, size: 20),
                    padding: EdgeInsets.zero,
                    onSelected: (value) {
                      switch (value) {
                        case 'income-in':
                          onAddIncome();
                        case 'transfer':
                          onTransfer();
                        case 'edit':
                          onEdit();
                        case 'income':
                          onSetIncomeWallet();
                        case 'archive':
                          onRemove();
                      }
                    },
                    itemBuilder: (context) => [
                      menuItem(
                        value: 'income-in',
                        label: 'Add income',
                        icon: Icons.add_card,
                        color: appPrimaryBlue,
                      ),
                      menuItem(
                        value: 'transfer',
                        label: 'Transfer money',
                        icon: Icons.swap_horiz,
                        color: appPrimaryBlue,
                      ),
                      menuItem(
                        value: 'edit',
                        label: 'Edit wallet',
                        icon: Icons.edit,
                        color: appPrimaryBlue,
                      ),
                      if (!wallet.receivesIncome)
                        menuItem(
                          value: 'income',
                          label: incomeLabel.replaceFirst('Receives', 'Set as'),
                          icon: Icons.account_balance_wallet,
                          color: confirmColorOn(context),
                        ),
                      menuItem(
                        value: 'archive',
                        label: 'Remove wallet',
                        icon: Icons.delete_outline,
                        color: dangerColorOn(context),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AddWalletButton extends StatelessWidget {
  const _AddWalletButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: ElevatedButton.icon(
        onPressed: onPressed,
        icon: const Icon(Icons.add),
        label: const Text(
          'Add Wallet',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
        style: ElevatedButton.styleFrom(
          backgroundColor: appPrimaryBlue,
          foregroundColor: Colors.white,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      ),
    );
  }
}

class _WalletsError extends StatelessWidget {
  const _WalletsError({required this.error});

  final Object error;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off, size: 42, color: Colors.grey),
            const SizedBox(height: 14),
            Text(
              'We could not load your wallets',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.bold,
                color: context.appColors.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Check your connection and try again.\n$error',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 13, color: Colors.grey),
            ),
          ],
        ),
      ),
    );
  }
}
