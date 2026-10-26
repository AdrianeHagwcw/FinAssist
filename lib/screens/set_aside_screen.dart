import 'package:flutter/material.dart';

import '../models/goal.dart';
import '../models/wallet.dart';
import '../models/finance_snapshot.dart';
import '../services/finance_snapshot_service.dart';
import '../widgets/savings_suggestion_card.dart';
import '../widgets/transfer_sheet.dart';
import '../services/goal_service.dart';
import '../services/wallet_service.dart';
import '../theme/app_buttons.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../utils/money_format.dart';
import '../widgets/interest_sheet.dart';
import '../widgets/item_card.dart';
import '../widgets/money_text.dart';
import '../widgets/savings_form_parts.dart';
import '../widgets/set_aside_record_sheet.dart';

/// The user's savings: the accounts they keep money in rather than spend
/// from, what is free in them, and what goals hold there.
///
/// This money is not counted in the Available Balance. Savings deposits and
/// demand deposits can be moved out any time; a time deposit waits for its
/// end date.
class SetAsideScreen extends StatefulWidget {
  const SetAsideScreen({
    this.wallets,
    this.goals,
    this.today,
    this.finances,
    super.key,
  });

  /// Replaces the live wallets. Used by tests.
  final Stream<List<Wallet>>? wallets;

  /// Replaces the live goals. Used by tests.
  final Stream<List<Goal>>? goals;

  /// Replaces the clock. Used by tests.
  final DateTime? today;
  final Stream<FinanceSnapshot>? finances;

  @override
  State<SetAsideScreen> createState() => _SetAsideScreenState();
}

class _SetAsideScreenState extends State<SetAsideScreen> {
  late final Stream<List<Wallet>> _wallets =
      widget.wallets ?? WalletService.watchWallets();

  late final Stream<List<Goal>> _goals =
      widget.goals ?? GoalService.watchGoals();

  late final Stream<FinanceSnapshot> _finances =
      widget.finances ??
      (widget.wallets == null
          ? watchFinanceSnapshot()
          : const Stream<FinanceSnapshot>.empty());

  DateTime get _now => widget.today ?? DateTime.now();

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    return Scaffold(
      backgroundColor: colors.pageBackground,
      appBar: AppBar(
        title: const Text(
          'Savings',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
        ),
        centerTitle: true,
        backgroundColor: appPrimaryBlue,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: StreamBuilder<List<Wallet>>(
        stream: _wallets,
        builder: (context, walletSnapshot) {
          final wallets = walletSnapshot.data;

          return ListView(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 100),
            children: [
              if (wallets == null)
                const Center(child: CircularProgressIndicator())
              else
                ..._savings(wallets),
            ],
          );
        },
      ),
    );
  }

  /// The records behind the total, so a figure typed at sign up can still be
  /// fixed, and money can be moved out of one.
  List<Widget> _records(
    List<Wallet> wallets, {
    List<Goal> goals = const [],
    bool goalsLoaded = true,
  }) {
    final kept = [
      for (final wallet in wallets)
        if (!wallet.archived && wallet.purpose == WalletPurpose.savings) wallet,
    ];
    if (kept.isEmpty) return const [];

    return [
      const _SectionTitle('Your savings records'),
      const SizedBox(height: 10),
      // The same card as setup's savings step.
      for (final wallet in kept)
        ItemCard(
          key: Key('set-aside-record-${wallet.id}'),
          icon: Image.asset(savingsKindIcon(wallet.savingsType)),
          title: wallet.name,
          subtitle: savingsRecordSubtitle(
            name: wallet.name,
            kind: wallet.savingsType,
            balance: wallet.balance,
          ),
          // Goal money sets the lowest a savings balance can be fixed to, so
          // editing waits for the goals.
          onEdit: !goalsLoaded
              ? null
              : () => _editRecord(
                  wallet,
                  minimumBalance: goalMoneyInWallet(goals, wallet.id),
                ),
          details: [
            ...savingsRecordDetails(
              kind: wallet.savingsType,
              balance: wallet.balance,
              rate: wallet.earnsNoInterest
                  ? null
                  : wallet.annualInterestRatePercent,
              start: wallet.depositStartDate,
              end: wallet.maturityDate,
              interestUntilEnd: wallet.estimatedTimeDepositInterest(),
              promised: goalMoneyInWallet(goals, wallet.id),
              today: _now,
              payout: wallet.interestPayout,
            ),
            if (wallet.paysRegularInterest)
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  key: Key('add-interest-${wallet.id}'),
                  onPressed: () async {
                    final added = await showAddInterestSheet(
                      context,
                      wallet: wallet,
                    );
                    if (added && mounted) setState(() {});
                  },
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Add interest that came in'),
                ),
              ),
            // A savings or demand deposit can be drawn on any time: into
            // cash on hand, a bank, or both.
            if (!wallet.isLockedSavings && wallet.balance > 0)
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  key: Key('move-out-${wallet.id}'),
                  onPressed: () =>
                      showTransferSheet(context, fromWalletId: wallet.id),
                  icon: const Icon(Icons.swap_horiz, size: 18),
                  label: const Text('Move money out'),
                ),
              ),
          ],
        ),
      const SizedBox(height: 10),
    ];
  }

  Future<void> _editRecord(Wallet wallet, {double minimumBalance = 0}) async {
    final saved = await showSetAsideRecordSheet(
      context,
      wallet: wallet,
      minimumBalance: minimumBalance,
    );
    if (saved == true && mounted) setState(() {});
  }

  Future<void> _addRecord(
    List<Wallet> wallets, {
    List<Goal> goals = const [],
  }) async {
    final saved = await showSetAsideRecordSheet(
      context,
      wallets: wallets,
      // The goals this screen has read, for what each wallet has free. A
      // copy of its own, as the screen is already listening to the live
      // ones.
      goals: Stream.value(goals),
    );
    if (saved == true && mounted) setState(() {});
  }

  /// Shown even when there are no records at all, so savings left empty at
  /// sign up can still be started here.
  Widget _addRecordButton(List<Wallet> wallets, {List<Goal> goals = const []}) {
    // The same green Add button as the setup steps.
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: ElevatedButton(
        key: const Key('add-savings-record'),
        onPressed: () => _addRecord(wallets, goals: goals),
        style: confirmButtonStyle(),
        child: const Text(
          'Add Savings',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
      ),
    );
  }

  List<Widget> _savings(List<Wallet> wallets) {
    // Matches Home: only savings that can actually be drawn on. A time
    // deposit is named on its own.
    final walletTotal = walletBalanceFor(wallets, WalletPurpose.savings);
    final locked = lockedSavingsBalance(wallets);
    final savingsNote = locked > 0
        ? '${formatPeso(locked)} is locked away and unavailable to spend.'
        : 'Available after money promised to your goals.';

    return [
      StreamBuilder<FinanceSnapshot>(
        stream: _finances,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return const Padding(
              padding: EdgeInsets.only(bottom: 16),
              child: Text(
                'Savings suggestion is unavailable while your records '
                'cannot be loaded. Please try again later.',
              ),
            );
          }
          final records = snapshot.data;
          if (records == null) return const SizedBox.shrink();
          return SavingsSuggestionCard(
            records: records.at(_now),
            onTransfer: (amount) {
              // Saving needs a savings account to go into: with none yet,
              // the user adds one, moving the money in from their wallets.
              final destinations = promisableSavingsRecords(
                wallets,
              ).where((wallet) => !wallet.isLockedSavings).toList();
              if (destinations.isEmpty) {
                _addRecord(wallets);
                return;
              }
              showTransferSheet(
                context,
                toWalletId: destinations.length == 1
                    ? destinations.single.id
                    : null,
                initialAmount: amount,
              );
            },
          );
        },
      ),
      StreamBuilder<List<Goal>>(
        stream: _goals,
        builder: (context, snapshot) {
          final allGoals = snapshot.data ?? const <Goal>[];
          final assignedToGoals = totalSetAsideInPurposeWallets(
            allGoals,
            wallets,
            WalletPurpose.savings,
          );
          // Contributions remain part of the savings' real balance, but are
          // already held inside their goals. Show only the amount that is
          // still free here. Taking money out of a goal returns it to this
          // total.
          final available = (walletTotal - assignedToGoals)
              .clamp(0.0, double.infinity)
              .toDouble();

          // The goals themselves live in Goals; here is only the money:
          // what is free, what goals hold, and the records it sits in.
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _TotalCard(
                title: 'Savings',
                total: available,
                iconAsset: 'assets/icons/icons8-money-box-96.png',
                note: savingsNote,
                onTransfer: () => showTransferSheet(context),
                // Show only money that has been assigned to goals.
                breakdown: assignedToGoals <= 0
                    ? const []
                    : [(label: 'Towards your goals', amount: assignedToGoals)],
              ),
              const SizedBox(height: 24),
              ..._records(
                wallets,
                goals: allGoals,
                goalsLoaded: snapshot.hasData,
              ),
              _addRecordButton(wallets, goals: allGoals),
            ],
          );
        },
      ),
    ];
  }
}

/// The balance at the top, named for what it is, then the total in it.
class _TotalCard extends StatelessWidget {
  const _TotalCard({
    required this.title,
    required this.total,
    required this.note,
    required this.iconAsset,
    this.breakdown = const [],
    this.onTransfer,
  });

  final String title;
  final double total;
  final String note;

  /// How the total is spoken for, read under it. Empty when there is
  /// nothing to split.
  final List<({String label, double amount})> breakdown;

  /// The same icon this money carries on Home, so the two read as one thing.
  final String iconAsset;
  final VoidCallback? onTransfer;

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
          Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(10),
                ),
                padding: const EdgeInsets.all(8),
                child: Image.asset(iconAsset),
              ),
              const SizedBox(width: 12),
              Text(
                title,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          const Text(
            'Total balance',
            style: TextStyle(color: Colors.white70, fontSize: 14),
          ),
          const SizedBox(height: 6),
          MoneyText(
            total,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 32,
              fontWeight: FontWeight.bold,
            ),
          ),
          if (breakdown.isNotEmpty) ...[
            const SizedBox(height: 12),
            const Divider(color: Colors.white24, height: 1),
            for (final row in breakdown)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        row.label,
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 13,
                        ),
                      ),
                    ),
                    MoneyText(
                      row.amount,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
          ],
          const SizedBox(height: 8),
          Text(
            note,
            style: const TextStyle(color: Colors.white70, fontSize: 12),
          ),
          if (onTransfer != null) ...[
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: onTransfer,
                icon: const Icon(Icons.swap_horiz),
                label: const Text('Transfer money'),
                style: openOutlineStyle(context),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.bold,
        color: context.appColors.textPrimary,
      ),
    );
  }
}
