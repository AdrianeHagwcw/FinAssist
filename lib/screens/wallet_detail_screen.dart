import 'package:flutter/material.dart';

import '../models/app_transaction.dart';
import '../models/goal.dart';
import '../models/wallet.dart';
import '../services/wallet_service.dart';
import '../services/goal_service.dart';
import '../utils/money_format.dart';
import '../theme/app_buttons.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../utils/date_format.dart';
import '../widgets/category_icon.dart';
import '../widgets/empty_state_view.dart';
import '../widgets/interest_sheet.dart';
import '../widgets/item_card.dart';
import '../widgets/money_text.dart';
import '../widgets/transaction_row.dart';
import '../widgets/transfer_sheet.dart';
import '../widgets/wallet_actions.dart';
import 'income_waterfall_screen.dart';

/// One wallet: its balance, the income it receives, and its own transactions.
class WalletDetailScreen extends StatefulWidget {
  const WalletDetailScreen({
    required this.wallet,
    this.wallets,
    this.transactions,
    this.goals,
    super.key,
  });

  /// The wallet as it was when the screen opened. The live copy replaces it
  /// as soon as the wallet stream arrives.
  final Wallet wallet;

  /// Replaces the live wallet list. Used by tests, which can't load Firebase.
  final Stream<List<Wallet>>? wallets;

  /// Replaces this wallet's live transactions. Used by tests.
  final Stream<List<AppTransaction>>? transactions;

  /// Replaces the live goals, for what they hold in this wallet. Used by
  /// tests.
  final Stream<List<Goal>>? goals;

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

  // Tests that hand in their wallets have no goals behind them.
  late final Stream<List<Goal>> _goals =
      widget.goals ??
      (widget.wallets == null
          ? GoalService.watchGoals()
          : Stream.value(const <Goal>[]));

  Future<void> _remove(Wallet wallet) async {
    final removed = await removeWallet(context, wallet);

    if (removed && mounted) Navigator.pop(context);
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
                    case 'income-in':
                      showIncomeWaterfall(context, walletId: wallet.id);
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
              StreamBuilder<List<Goal>>(
                stream: _goals,
                builder: (context, goalsSnapshot) => _WalletHeader(
                  wallet: wallet,
                  goals: goalsSnapshot.data ?? const [],
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
                    return Column(
                      children: [
                        // An account that pays interest now and then gets the
                        // card to add it; other savings keep their summary.
                        if (wallet.paysRegularInterest)
                          InterestCard(wallet: wallet)
                        else if (wallet.purpose == WalletPurpose.savings)
                          _SavingsInterestSummary(
                            wallet: wallet,
                            transactions: transactions,
                          ),
                        Expanded(
                          child: transactions.isEmpty
                              ? const EmptyStateView(
                                  iconAsset:
                                      'assets/icons/icons8-transactions-96.png',
                                  title: 'No transactions yet',
                                  message:
                                      'Money you spend from or add to this '
                                      'wallet shows up here.',
                                )
                              : _TransactionList(
                                  transactions: transactions,
                                  wallet: wallet,
                                  wallets: wallets,
                                ),
                        ),
                      ],
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

class _SavingsInterestSummary extends StatelessWidget {
  const _SavingsInterestSummary({
    required this.wallet,
    required this.transactions,
  });

  final Wallet wallet;
  final List<AppTransaction> transactions;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final kind = wallet.savingsType;
    final isTimeDeposit = kind == SavingsKind.timeDeposit;
    final isSavingsDeposit = kind == SavingsKind.savingsDeposit;
    final isDemandDeposit = kind == SavingsKind.demandDeposit;
    final interest = isTimeDeposit
        ? wallet.estimatedTimeDepositInterest()
        : isSavingsDeposit
        ? wallet.estimatedSavingsDepositInterest(transactions: transactions)
        : null;
    // What reaches the account, once the bank keeps its tax.
    final net = interest == null ? null : afterTax(interest);
    final endValue = isTimeDeposit && net != null
        ? wallet.startingBalance + net
        : null;
    final status = isTimeDeposit
        ? wallet.isMaturedTimeDeposit
              ? 'Its end date has come. Say what you did with the money when '
                    'you are ready.'
              : 'The money stays locked until the end date. Taking it out '
                    'early may cost you.'
        : isSavingsDeposit
        ? 'Counted from what was recorded since you added this account.'
        : isDemandDeposit
        ? 'No interest. You can take money out anytime.'
        : 'This older kind of savings has no interest estimate.';

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colors.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: colors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            kind.label,
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: colors.textPrimary,
            ),
          ),
          if (wallet.annualInterestRatePercent != null)
            Text(
              'Interest: ${percentText(wallet.annualInterestRatePercent!)} '
              'a year',
              style: TextStyle(fontSize: 12, color: colors.textBody),
            ),
          if (wallet.depositStartDate != null)
            Text(
              'Started ${formatShortDate(wallet.depositStartDate!)}',
              style: TextStyle(fontSize: 12, color: colors.textBody),
            ),
          if (isTimeDeposit && wallet.maturityDate != null)
            Text(
              'Ends ${formatShortDate(wallet.maturityDate!)}',
              style: TextStyle(fontSize: 12, color: colors.textBody),
            ),
          const SizedBox(height: 6),
          if (net != null)
            Text(
              'May earn about ${formatPeso(net)} after tax'
              '${endValue == null ? '' : ' · about ${formatPeso(endValue)} at the end'}',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: colors.primaryText,
              ),
            )
          else if (isTimeDeposit || isSavingsDeposit)
            Text(
              'No estimate yet. Check the balance, rate and dates.',
              style: TextStyle(fontSize: 12, color: colors.textBody),
            ),
          const SizedBox(height: 4),
          Text(
            '$status Estimates never change the recorded balance.',
            style: TextStyle(fontSize: 11, color: colors.textBody),
          ),
        ],
      ),
    );
  }
}

class _WalletHeader extends StatelessWidget {
  const _WalletHeader({required this.wallet, required this.goals});

  final Wallet wallet;
  final List<Goal> goals;

  @override
  Widget build(BuildContext context) {
    const incomeLabel = 'Your income is paid into this wallet';

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
          // A spending wallet leads with what can be spent from it; savings
          // money is all set aside, so it leads with what it holds.
          MoneyText(
            wallet.purpose == WalletPurpose.savings || wallet.balance < 0
                ? wallet.balance
                : freeInWallet(wallet, goals),
            style: TextStyle(
              color: wallet.balance < 0 ? Colors.redAccent : Colors.white,
              fontSize: 32,
              fontWeight: FontWeight.bold,
            ),
          ),
          if (wallet.purpose == WalletPurpose.savings ||
              goalMoneyInWallet(goals, wallet.id) > 0.005) ...[
            const SizedBox(height: 10),
            _SavingsWalletBreakdown(wallet: wallet, goals: goals),
          ],
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

class _SavingsWalletBreakdown extends StatelessWidget {
  const _SavingsWalletBreakdown({required this.wallet, required this.goals});

  final Wallet wallet;
  final List<Goal> goals;

  @override
  Widget build(BuildContext context) {
    final assigned = goalMoneyInWallet(goals, wallet.id);
    final available = wallet.isLockedSavings
        ? 0.0
        : freeInWallet(wallet, goals);
    Widget row(String label, double amount) => Padding(
      padding: const EdgeInsets.only(top: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: const TextStyle(color: Colors.white70, fontSize: 12),
          ),
          Text(
            formatPeso(amount),
            style: const TextStyle(color: Colors.white, fontSize: 12),
          ),
        ],
      ),
    );

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 9),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        children: [
          row('Currently holds', wallet.balance),
          row('Set aside for goals', assigned),
          row('Available', available),
          if (wallet.isLockedSavings)
            const Padding(
              padding: EdgeInsets.only(top: 5),
              child: Text(
                'Locked savings — not currently available to use',
                style: TextStyle(color: Colors.white70, fontSize: 11),
              ),
            ),
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
  });

  final List<AppTransaction> transactions;
  final Wallet wallet;
  final List<Wallet> wallets;
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
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: context.appColors.textMuted,
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
  });

  final AppTransaction transaction;
  final Wallet wallet;
  final List<Wallet> wallets;

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
    if (transaction.isDebtMovement) {
      return Image.asset(loanIconAsset(transaction), width: 22, height: 22);
    }

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
                    [
                      transactionDirection(
                        transaction,
                        wallets,
                        forWalletId: wallet.id,
                      ).label,
                      if (note != null && note.isNotEmpty) note,
                    ].join(' · '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      color: context.appColors.textMuted,
                    ),
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
    );
  }
}
