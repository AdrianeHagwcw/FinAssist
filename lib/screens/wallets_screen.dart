import 'package:flutter/material.dart';

import '../models/goal.dart';
import '../models/wallet.dart';
import '../services/wallet_service.dart';
import '../theme/app_buttons.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../widgets/add_button.dart';
import '../widgets/back_to_home.dart';
import '../widgets/empty_state_view.dart';
import '../widgets/legacy_import_card.dart';
import '../widgets/money_text.dart';
import '../widgets/transfer_sheet.dart';
import '../widgets/wallet_actions.dart';
import '../widgets/wallet_form_sheet.dart';
import '../widgets/wallets_added_sheet.dart';
import '../widgets/wallet_picker.dart';
import 'income_waterfall_screen.dart';
import 'wallet_detail_screen.dart';

/// The Wallet tab: the combined balance, then one card per wallet.
class WalletsScreen extends StatefulWidget {
  const WalletsScreen({this.wallets, this.goals, super.key});

  /// Replaces the live wallet list. Used by tests, which can't load Firebase.
  final Stream<List<Wallet>>? wallets;

  /// Replaces the live goals, for what they hold in each wallet. Used by
  /// tests.
  final Stream<List<Goal>>? goals;

  @override
  State<WalletsScreen> createState() => _WalletsScreenState();
}

class _WalletsScreenState extends State<WalletsScreen> with WatchesGoals {
  // Held in state so a rebuild doesn't start a second listener.
  late final Stream<List<Wallet>> _wallets =
      widget.wallets ?? WalletService.watchWallets();

  @override
  void initState() {
    super.initState();
    watchGoals(given: widget.goals, walletsGiven: widget.wallets != null);
  }

  /// Adds wallets one after another, as setup does: after each, what was
  /// added and the Cash Summary they make, with Add Another right there, so
  /// several wallets never mean going back to the Add Wallet button.
  Future<void> _addWallet(List<Wallet> currentWallets) async {
    final addedIds = <String>{};
    while (true) {
      if (!mounted) return;
      final draft = await showWalletFormSheet(context);
      if (draft == null) return;

      final id = await WalletService.addWallet(
        type: draft.type,
        name: draft.name,
        startingBalance: draft.startingBalance,
        balanceRecorded: draft.balanceRecorded,
        annualInterestRatePercent: draft.annualInterestRatePercent,
        // The very first wallet receives income until the user picks another.
        receivesIncome: currentWallets.isEmpty && addedIds.isEmpty,
        // After the first, the list is read again, so a second "Cash" is
        // numbered "Cash 2" and each goes at the end.
        currentWallets: addedIds.isEmpty ? currentWallets : null,
      );
      addedIds.add(id);
      if (!mounted) return;

      final another = await showWalletsAddedSheet(
        context,
        addedIds: addedIds,
        goals: heldGoals,
      );
      if (!another) return;
    }
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
        leading: backToHomeButton(context),
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

          // Bills and savings money has its own tab, so only spending
          // wallets are listed here; their total is named underneath.
          final spending = wallets.where((w) => !w.isSetAside).toList();

          return ListView(
            // Room for the bottom bar and the docked "+" button.
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 100),
            children: [
              const LegacyImportCard(),
              _TotalBalanceCard(
                total: spending.fold<double>(
                  0,
                  (sum, wallet) => sum + freeInWallet(wallet, heldGoals),
                ),
                inWallets: totalWalletBalance(wallets),
                walletCount: spending.length,
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
              for (final wallet in spending) ...[
                _WalletCard(
                  wallet: wallet,
                  forGoals: goalMoneyInWallet(heldGoals, wallet.id),
                  onTap: () => _openWallet(wallet),
                  onTransfer: () =>
                      showTransferSheet(context, fromWalletId: wallet.id),
                  onAddIncome: () =>
                      showIncomeWaterfall(context, walletId: wallet.id),
                  onEdit: () => editWallet(context, wallet),
                  onRemove: () => removeWallet(context, wallet),
                ),
                const SizedBox(height: 12),
              ],
              const SizedBox(height: 4),
              _AddWalletButton(onPressed: () => _addWallet(wallets)),
            ],
          );
        },
      ),
    );
  }
}

/// The top of the Wallets tab, read like a statement so it adds up: what is
/// in these wallets, less what goals hold in them, is the available
/// balance. Only these wallets, so every figure on it belongs to the sum.
class _TotalBalanceCard extends StatelessWidget {
  const _TotalBalanceCard({
    required this.total,
    required this.inWallets,
    required this.walletCount,
  });

  /// What can be spent: the spending wallets less what goals hold in them.
  final double total;

  /// What the spending wallets hold in all, goal money included.
  final double inWallets;
  final int walletCount;

  double get _forGoals => inWallets - total;

  @override
  Widget build(BuildContext context) {
    Widget line(
      String label,
      double amount, {
      String sign = '',
      bool result = false,
    }) => Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                color: result ? Colors.white : Colors.white70,
                fontSize: result ? 13 : 12,
                fontWeight: result ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ),
          MoneyText(
            amount,
            sign: sign.isEmpty ? null : sign,
            style: TextStyle(
              color: Colors.white,
              fontSize: result ? 13 : 12,
              fontWeight: result ? FontWeight.bold : FontWeight.w600,
            ),
          ),
        ],
      ),
    );

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
            'Available Balance',
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
          // How the figure above is reached, only when goals hold some:
          // in these wallets, less what goals hold, is what is available.
          if (_forGoals > 0.005) ...[
            const SizedBox(height: 8),
            line('In these wallets', inWallets),
            line('Set aside for goals', _forGoals, sign: '-'),
            const SizedBox(height: 6),
            const Divider(height: 1, color: Colors.white24),
            line('Available balance', total, result: true),
          ],
        ],
      ),
    );
  }
}

class _WalletCard extends StatelessWidget {
  const _WalletCard({
    required this.wallet,
    this.forGoals = 0,
    required this.onTap,
    required this.onTransfer,
    required this.onAddIncome,
    required this.onEdit,
    required this.onRemove,
  });

  final Wallet wallet;

  /// What goals hold in this wallet; the rest is what can be spent.
  final double forGoals;

  final VoidCallback onTap;
  final VoidCallback onTransfer;
  final VoidCallback onAddIncome;
  final VoidCallback onEdit;
  final VoidCallback onRemove;

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
                      style: TextStyle(
                        fontSize: 12,
                        color: context.appColors.textMuted,
                      ),
                    ),
                    if (forGoals > 0.005)
                      Row(
                        children: [
                          MoneyText(
                            forGoals,
                            style: TextStyle(
                              fontSize: 12,
                              color: context.appColors.textMuted,
                            ),
                          ),
                          Text(
                            ' set aside for goals',
                            style: TextStyle(
                              fontSize: 12,
                              color: context.appColors.textMuted,
                            ),
                          ),
                        ],
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  // What can be spent from it.
                  MoneyText(
                    wallet.balance < 0 || forGoals <= 0
                        ? wallet.balance
                        : (wallet.balance - forGoals)
                              .clamp(0.0, double.infinity)
                              .toDouble(),
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
                        case 'archive':
                          onRemove();
                      }
                    },
                    itemBuilder: (context) => [
                      menuItem(
                        value: 'income-in',
                        label: 'Add income',
                        icon: Icons.add_card,
                        color: confirmColorOn(context),
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
                        icon: Icons.edit_outlined,
                        color: appPrimaryBlue,
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
    return AddButton(label: 'Add Wallet', onPressed: onPressed);
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
            Icon(
              Icons.cloud_off_outlined,
              size: 42,
              color: context.appColors.textMuted,
            ),
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
              style: TextStyle(
                fontSize: 13,
                color: context.appColors.textMuted,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
