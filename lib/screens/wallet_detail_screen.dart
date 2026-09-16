import 'package:flutter/material.dart';

import '../models/app_transaction.dart';
import '../models/wallet.dart';
import '../services/user_profile_service.dart';
import '../services/wallet_service.dart';
import '../theme/app_buttons.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../utils/date_format.dart';
import '../widgets/category_icon.dart';
import '../widgets/empty_state_view.dart';
import '../widgets/money_text.dart';
import '../widgets/transfer_sheet.dart';
import '../widgets/wallet_actions.dart';

/// One wallet: its balance, the income it receives, and its own transactions.
class WalletDetailScreen extends StatefulWidget {
  const WalletDetailScreen({
    required this.wallet,
    this.wallets,
    this.transactions,
    this.incomeSource,
    super.key,
  });

  /// The wallet as it was when the screen opened. The live copy replaces it
  /// as soon as the wallet stream arrives.
  final Wallet wallet;

  /// Replaces the live wallet list. Used by tests, which can't load Firebase.
  final Stream<List<Wallet>>? wallets;

  /// Replaces this wallet's live transactions. Used by tests.
  final Stream<List<AppTransaction>>? transactions;

  /// Replaces the income source saved during onboarding, e.g. "Allowance".
  final Stream<String?>? incomeSource;

  @override
  State<WalletDetailScreen> createState() => _WalletDetailScreenState();
}

class _WalletDetailScreenState extends State<WalletDetailScreen> {
  // Archived wallets are included so the screen doesn't blank out in the
  // moment between removing this wallet and closing the screen.
  late final Stream<List<Wallet>> _wallets =
      widget.wallets ?? WalletService.watchWallets(includeArchived: true);

  late final Stream<List<AppTransaction>> _transactions =
      widget.transactions ??
      WalletService.watchWalletTransactions(widget.wallet.id);

  late final Stream<String?> _incomeSource =
      widget.incomeSource ??
      UserProfileService.watchProfile().map(
        (profile) => profile.data()?['incomeSource'] as String?,
      );

  Future<void> _remove(Wallet wallet) async {
    final removed = await removeWallet(context, wallet);

    if (removed && mounted) Navigator.pop(context);
  }

  Future<void> _deleteTransaction(AppTransaction transaction) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete this transaction?'),
        content: Text(
          transaction.isLegacy
              ? 'It will be removed from your history. No balance changes, '
                    'because this record came from before you had wallets.'
              : 'The money it moved will be put back into your wallet.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            style: cancelTextStyle(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: dangerTextStyle(context),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    WalletService.deleteTransaction(transaction);
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Wallet>>(
      stream: _wallets,
      builder: (context, walletsSnapshot) {
        final wallets = walletsSnapshot.data ?? [widget.wallet];
        final wallet = wallets.firstWhere(
          (candidate) => candidate.id == widget.wallet.id,
          // Falls back to what was passed in, so the screen still renders if
          // the wallet has just been removed.
          orElse: () => widget.wallet,
        );

        return Scaffold(
          backgroundColor: context.appColors.pageBackground,
          appBar: AppBar(
            title: Text(
              wallet.name,
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            backgroundColor: appPrimaryBlue,
            foregroundColor: Colors.white,
            elevation: 0,
            actions: [
              PopupMenuButton<String>(
                tooltip: 'Wallet options',
                onSelected: (value) {
                  switch (value) {
                    case 'transfer':
                      showTransferSheet(context, fromWalletId: wallet.id);
                    case 'edit':
                      editWallet(context, wallet);
                    case 'income':
                      WalletService.setIncomeWallet(
                        wallet.id,
                        currentWallets: wallets,
                      );
                    case 'remove':
                      _remove(wallet);
                  }
                },
                itemBuilder: (context) => [
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
                      label: 'Set as my income wallet',
                      icon: Icons.account_balance_wallet,
                      color: confirmColorOn(context),
                    ),
                  menuItem(
                    value: 'remove',
                    label: 'Remove wallet',
                    icon: Icons.delete_outline,
                    color: dangerColorOn(context),
                  ),
                ],
              ),
            ],
          ),
          body: Column(
            children: [
              StreamBuilder<String?>(
                stream: _incomeSource,
                builder: (context, incomeSnapshot) => _WalletHeader(
                  wallet: wallet,
                  incomeSource: incomeSnapshot.data,
                ),
              ),
              Expanded(
                child: StreamBuilder<List<AppTransaction>>(
                  stream: _transactions,
                  builder: (context, snapshot) {
                    if (!snapshot.hasData) {
                      return const Center(child: CircularProgressIndicator());
                    }

                    final transactions = snapshot.data!;

                    if (transactions.isEmpty) {
                      return const EmptyStateView(
                        iconAsset: 'assets/icons/icons8-transactions-96.png',
                        title: 'No transactions yet',
                        message:
                            'Money you spend from or add to this wallet shows '
                            'up here.',
                      );
                    }

                    return _TransactionList(
                      transactions: transactions,
                      wallet: wallet,
                      wallets: wallets,
                      onDelete: _deleteTransaction,
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _WalletHeader extends StatelessWidget {
  const _WalletHeader({required this.wallet, required this.incomeSource});

  final Wallet wallet;
  final String? incomeSource;

  @override
  Widget build(BuildContext context) {
    final source = incomeSource?.trim();
    final incomeLabel = source == null || source.isEmpty
        ? 'Your income is paid into this wallet'
        : 'Your $source is paid into this wallet';

    return Container(
      width: double.infinity,
      color: appPrimaryBlue,
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
      child: Column(
        children: [
          Container(
            width: 58,
            height: 58,
            padding: const EdgeInsets.all(13),
            decoration: const BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
            ),
            child: Image.asset(wallet.iconAsset),
          ),
          const SizedBox(height: 12),
          Text(
            wallet.type.label,
            style: const TextStyle(color: Colors.white70, fontSize: 13),
          ),
          const SizedBox(height: 6),
          MoneyText(
            wallet.balance,
            style: TextStyle(
              color: wallet.balance < 0 ? Colors.redAccent : Colors.white,
              fontSize: 32,
              fontWeight: FontWeight.bold,
            ),
          ),
          if (wallet.receivesIncome) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.18),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                incomeLabel,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _TransactionList extends StatelessWidget {
  const _TransactionList({
    required this.transactions,
    required this.wallet,
    required this.wallets,
    required this.onDelete,
  });

  final List<AppTransaction> transactions;
  final Wallet wallet;
  final List<Wallet> wallets;
  final void Function(AppTransaction) onDelete;

  @override
  Widget build(BuildContext context) {
    final children = <Widget>[];
    String? lastLabel;

    for (final transaction in transactions) {
      final label = transactionDateLabel(transaction.date);

      if (label != lastLabel) {
        children.add(
          Padding(
            padding: EdgeInsets.fromLTRB(4, lastLabel == null ? 0 : 18, 4, 8),
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Colors.grey,
              ),
            ),
          ),
        );
        lastLabel = label;
      }

      children.add(
        _TransactionRow(
          transaction: transaction,
          wallet: wallet,
          wallets: wallets,
          onDelete: () => onDelete(transaction),
        ),
      );
      children.add(const SizedBox(height: 8));
    }

    return ListView(
      // Room for the bottom bar and the docked "+" button.
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 100),
      children: children,
    );
  }
}

class _TransactionRow extends StatelessWidget {
  const _TransactionRow({
    required this.transaction,
    required this.wallet,
    required this.wallets,
    required this.onDelete,
  });

  final AppTransaction transaction;
  final Wallet wallet;
  final List<Wallet> wallets;
  final VoidCallback onDelete;

  /// The other wallet's name, for transfers.
  String get _otherWalletName {
    final otherId = transaction.walletId == wallet.id
        ? transaction.toWalletId
        : transaction.walletId;

    for (final candidate in wallets) {
      if (candidate.id == otherId) return candidate.name;
    }

    return 'another wallet';
  }

  String get _title {
    if (transaction.type != TransactionType.transfer) return transaction.label;

    return transaction.walletId == wallet.id
        ? 'To $_otherWalletName'
        : 'From $_otherWalletName';
  }

  Color get _color {
    switch (transaction.type) {
      case TransactionType.expense:
        return Colors.red;
      case TransactionType.income:
        return Colors.green;
      case TransactionType.transfer:
        return appPrimaryBlue;
    }
  }

  Widget get _icon {
    switch (transaction.type) {
      case TransactionType.expense:
        return CategoryIcon(transaction.label, size: 22);
      case TransactionType.income:
        return Image.asset(
          'assets/icons/icons8-money-transfer-96.png',
          width: 22,
          height: 22,
        );
      case TransactionType.transfer:
        return Image.asset(
          'assets/icons/icons8-transactions-96.png',
          width: 22,
          height: 22,
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final delta = transaction.balanceDeltaFor(wallet.id);
    final note = transaction.note;

    return Material(
      color: colors.card,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        // Long press rather than swipe, so a scroll through history can't
        // delete anything by accident.
        onLongPress: onDelete,
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
                  color: colors.primaryTint,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: _icon,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: colors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      note == null || note.isEmpty
                          ? transaction.type.label
                          : note,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              MoneyText(
                transaction.amount,
                sign: delta < 0 ? '-' : '+',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  color: _color,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
