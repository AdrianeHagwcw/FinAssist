import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/allocation.dart';
import '../models/app_transaction.dart';
import '../models/bill.dart';
import '../models/goal.dart';
import '../models/safe_to_spend.dart';
import '../models/wallet.dart';
import '../providers/app_settings_provider.dart';
import '../services/allocation_service.dart';
import '../services/bill_service.dart';
import '../services/budget_service.dart';
import '../services/goal_service.dart';
import '../services/user_profile_service.dart';
import '../services/wallet_service.dart';
import '../theme/app_buttons.dart';
import '../theme/app_colors.dart';
import '../utils/money_format.dart';
import 'dialog_kit.dart';
import 'money_text.dart';

/// Everything the Safe-to-Spend figure is worked out from, gathered once so
/// the card and its edit sheet always agree.
class SafeToSpendInputs {
  const SafeToSpendInputs({
    required this.safeToSpend,
    required this.period,
    required this.frequency,
    required this.cycles,
    required this.transactions,
    this.bills = const [],
    this.wallets = const [],
    this.now,
    this.plannedBills,
    this.plannedSavings,
    this.setAside = 0,
  });

  final SafeToSpend safeToSpend;

  /// The wallets the figure was worked out from, so anything shown under
  /// the card can read them without loading them again.
  final List<Wallet> wallets;

  /// Unpaid bills, overdue or coming up, as loaded for the figure.
  final List<BillInstance> bills;

  /// The moment the figure was worked out for.
  final DateTime? now;
  final double? plannedBills;
  final double? plannedSavings;

  /// What is held in the bills and savings wallets right now.
  final double setAside;
  final PayPeriod period;
  final String? frequency;
  final List<AllocationCycle> cycles;
  final List<AppTransaction> transactions;
}

/// Home's hero card: how much can still be spent today without eating into
/// bills or savings.
class SafeToSpendCard extends StatefulWidget {
  const SafeToSpendCard({
    this.wallets,
    this.transactions,
    this.profile,
    this.cycles,
    this.loadBills,
    this.goals,
    this.billSchedules,
    this.today,
    this.footerBuilder,
    this.belowCard,
    super.key,
  });

  /// Replace the live data. Used by tests, which can't load Firebase.
  final Stream<List<Wallet>>? wallets;
  final Stream<List<AppTransaction>>? transactions;
  final Stream<Map<String, dynamic>?>? profile;
  final Stream<List<AllocationCycle>>? cycles;
  final Future<List<BillInstance>> Function()? loadBills;
  final Stream<List<Goal>>? goals;

  /// Replaces watching the bill schedules for changes. Used by tests.
  final Stream<List<Bill>>? billSchedules;
  final DateTime? today;

  /// Buttons shown under the figure.
  final Widget Function(BuildContext context)? footerBuilder;

  /// Shown below the card with the same inputs, such as the leftover notice.
  final Widget Function(BuildContext context, SafeToSpendInputs inputs)?
  belowCard;

  @override
  State<SafeToSpendCard> createState() => _SafeToSpendCardState();
}

/// One line of the working behind Safe to Spend: a label, and the amount
/// being added or taken off.
class _Working extends StatelessWidget {
  const _Working(
    this.label,
    this.amount, {
    this.take = false,
    this.add = false,
    this.strong = false,
  });

  final String label;
  final double amount;

  /// Shown with a minus, because it is money the user cannot spend.
  final bool take;

  /// Shown with a plus: money already spent today is added back before the
  /// day's share is worked out.
  final bool add;
  final bool strong;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final weight = strong ? FontWeight.bold : FontWeight.normal;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                color: strong ? colors.textPrimary : colors.textBody,
                fontWeight: weight,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Text(
            '${take
                ? '− '
                : add
                ? '+ '
                : ''}${formatPeso(amount)}',
            style: TextStyle(
              fontWeight: strong ? FontWeight.bold : FontWeight.w600,
              color: colors.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}

class _SafeToSpendCardState extends State<SafeToSpendCard> {
  late final Stream<List<Wallet>> _wallets =
      widget.wallets ?? WalletService.watchWallets();
  late final Stream<List<AppTransaction>> _transactions =
      widget.transactions ?? WalletService.watchTransactions();
  late final Stream<Map<String, dynamic>?> _profile =
      widget.profile ??
      UserProfileService.watchProfile().map((snapshot) => snapshot.data());
  late final Stream<List<AllocationCycle>> _cycles =
      widget.cycles ?? BudgetService.watchRecentCycles();

  /// Money set aside for goals. Held here rather than in another nested
  /// builder, since only its total matters.
  List<Goal> _goalsData = const [];
  StreamSubscription<List<Goal>>? _goalSubscription;

  /// Bumped whenever a bill is added, edited or deleted, so the bills due are
  /// read again. Paying a bill already shows up as a new transaction, but
  /// adding one doesn't, and Safe to Spend would otherwise miss it until the
  /// next transaction.
  int _billsVersion = 0;
  StreamSubscription<List<Bill>>? _billSubscription;

  @override
  void initState() {
    super.initState();
    _goalSubscription = (widget.goals ?? GoalService.watchGoals()).listen(
      (goals) {
        if (mounted) setState(() => _goalsData = goals);
      },
      // Unreachable goals are left out rather than blocking the card.
      onError: (Object _) {},
    );
    _billSubscription = (widget.billSchedules ?? BillService.watchBills())
        .listen((_) {
          if (mounted) setState(() => _billsVersion++);
        }, onError: (Object _) {});
  }

  @override
  void dispose() {
    _goalSubscription?.cancel();
    _billSubscription?.cancel();
    super.dispose();
  }

  List<BillInstance> _bills = const [];

  /// Bills are re-read when the transactions or the bill schedules change.
  int _billsLoadedFor = -1;

  DateTime get _now => widget.today ?? DateTime.now();

  void _refreshBills(List<AppTransaction> transactions) {
    final signature = Object.hash(
      transactions.length,
      transactions.isEmpty ? null : transactions.first.id,
      _billsVersion,
    );
    if (signature == _billsLoadedFor) return;
    _billsLoadedFor = signature;

    final load =
        widget.loadBills ??
        () => AllocationService.loadOutstandingBills(now: _now);

    load()
        .then((bills) {
          if (mounted) setState(() => _bills = bills);
        })
        .catchError((Object _) {
          // Offline and never cached: carry on as if no bills are due.
        });
  }

  SafeToSpendInputs _inputs({
    required List<Wallet> wallets,
    required List<AppTransaction> transactions,
    required Map<String, dynamic>? profile,
    required List<AllocationCycle> cycles,
  }) {
    final now = _now;
    final frequency = profile?['incomeFrequency'] as String?;
    // Only pay starts a new period; a gift just adds to this one.
    final lastIncome = periodAnchor(cycles, profile);
    final period = payPeriodFor(frequency, lastIncomeAt: lastIncome, now: now);
    final startOfToday = DateTime(now.year, now.month, now.day);

    return SafeToSpendInputs(
      safeToSpend: SafeToSpend(
        walletBalance: totalWalletBalance(wallets),
        billsDue: billsDueBefore(_bills, period.end),
        billsWalletBalance: walletBalanceFor(wallets, WalletPurpose.bills),
        goalSavings: totalSetAsideInSpendingWallets(_goalsData, wallets),
        spentToday: discretionarySpending(
          transactions,
          from: startOfToday,
          until: startOfToday.add(const Duration(days: 1)),
        ),
        daysLeft: period.daysLeft(now),
      ),
      wallets: wallets,
      period: period,
      frequency: frequency,
      cycles: cycles,
      transactions: transactions,
      bills: _bills,
      now: now,
      plannedBills: plannedAllocationFrom(profile, 'bills'),
      plannedSavings: plannedAllocationFrom(profile, 'savings'),
      setAside: setAsideWalletBalance(wallets),
    );
  }

  void _explain(SafeToSpendInputs inputs) {
    final s = inputs.safeToSpend;

    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        shape: dialogShape,
        title: const Text('How this is worked out'),
        // Laid out like a receipt rather than written as a paragraph: the
        // reader follows one line at a time and arrives at the figure on the
        // card, instead of parsing a sentence full of amounts.
        content: SingleChildScrollView(
          child: Builder(
            builder: (context) {
              final days =
                  '${s.daysLeft} '
                  '${s.daysLeft == 1 ? 'day' : 'days'}';
              // With nothing taken off, a total line would repeat the line
              // above it and read like a mistake.
              final takesSomeOff =
                  s.billsDue > 0 || s.goalSavings > 0 || s.spentToday > 0;

              return Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _Working('Money in your wallets', s.walletBalance),
                  if (s.spentToday > 0)
                    _Working('What you spent today', s.spentToday, add: true),
                  if (s.billsDue > 0)
                    _Working(
                      'Bills not yet covered',
                      (s.billsDue - s.billsWalletBalance).clamp(
                        0.0,
                        double.infinity,
                      ),
                      take: true,
                    ),
                  if (s.goalSavings > 0)
                    _Working('Saved for your goals', s.goalSavings, take: true),
                  if (takesSomeOff) ...[
                    const Divider(height: 22),
                    // Named for the stretch it covers, so it is not read as
                    // what can be spent today.
                    _Working(
                      'Left until your next pay',
                      s.spendableThisPeriod,
                      strong: true,
                    ),
                  ] else if (s.walletBalance > 0) ...[
                    const SizedBox(height: 10),
                    const Text(
                      'You have no bills due and nothing saved for goals out '
                      'of this money, so all of it is yours to spend.',
                      style: TextStyle(height: 1.45),
                    ),
                  ],
                  const SizedBox(height: 10),
                  // A brand new account has nothing to share out yet, so it
                  // is told what to do rather than shown ₱0 a day.
                  Text(
                    s.walletBalance <= 0
                        ? 'Once you add income or a wallet balance, this '
                              'shows how much of it you can spend each day '
                              'until your next pay.'
                        : 'That is ${formatPeso(s.recommendedDailyLimit)} a '
                              'day for the $days until your next pay.',
                    style: const TextStyle(height: 1.45),
                  ),
                ],
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Got it'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Wallet>>(
      stream: _wallets,
      builder: (context, walletSnapshot) {
        return StreamBuilder<List<AppTransaction>>(
          stream: _transactions,
          builder: (context, transactionSnapshot) {
            return StreamBuilder<Map<String, dynamic>?>(
              stream: _profile,
              builder: (context, profileSnapshot) {
                return StreamBuilder<List<AllocationCycle>>(
                  stream: _cycles,
                  builder: (context, cycleSnapshot) {
                    final transactions =
                        transactionSnapshot.data ?? const <AppTransaction>[];

                    if (transactionSnapshot.hasData) {
                      _refreshBills(transactions);
                    }

                    if (!walletSnapshot.hasData) {
                      return const SizedBox(
                        height: 150,
                        child: Center(child: CircularProgressIndicator()),
                      );
                    }

                    final inputs = _inputs(
                      wallets: walletSnapshot.data!,
                      transactions: transactions,
                      profile: profileSnapshot.data,
                      cycles: cycleSnapshot.data ?? const [],
                    );

                    return Column(
                      children: [
                        _HeroCard(
                          inputs: inputs,
                          now: _now,
                          onExplain: () => _explain(inputs),
                          footer: widget.footerBuilder?.call(context),
                        ),
                        if (widget.belowCard != null)
                          widget.belowCard!(context, inputs),
                      ],
                    );
                  },
                );
              },
            );
          },
        );
      },
    );
  }
}

class _HeroCard extends StatelessWidget {
  const _HeroCard({
    required this.inputs,
    required this.now,
    required this.onExplain,
    required this.footer,
  });

  final SafeToSpendInputs inputs;
  final DateTime now;
  final VoidCallback onExplain;
  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final s = inputs.safeToSpend;
    final masked = context.select<AppSettingsProvider, bool>(
      (settings) => settings.amountsMasked,
    );

    final barColor = s.isOverLimit
        ? dangerColorOn(context)
        : s.usedFraction >= 0.75
        ? Colors.amber.shade700
        : confirmColorOn(context);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(18, 10, 12, 18),
      decoration: BoxDecoration(
        color: colors.card,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Safe to Spend Today',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: colors.textPrimary,
                  ),
                ),
              ),
              IconButton(
                tooltip: masked ? 'Show amounts' : 'Hide amounts',
                icon: Icon(
                  masked
                      ? Icons.visibility_off_outlined
                      : Icons.visibility_outlined,
                  size: 20,
                ),
                onPressed: () =>
                    context.read<AppSettingsProvider>().toggleAmountsMasked(),
              ),
              IconButton(
                key: const Key('safe-to-spend-info'),
                tooltip: 'How this is worked out',
                icon: const Icon(Icons.info_outline, size: 20),
                onPressed: onExplain,
              ),
            ],
          ),
          const SizedBox(height: 4),
          Padding(
            padding: const EdgeInsets.only(right: 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                MoneyText(
                  s.leftToday.abs(),
                  sign: s.isOverLimit ? '-' : null,
                  style: TextStyle(
                    fontSize: 32,
                    fontWeight: FontWeight.bold,
                    color: s.isOverLimit
                        ? dangerColorOn(context)
                        : colors.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  s.isOverLimit
                      ? 'over your ${formatPeso(s.dailyLimit, masked: masked)} '
                            'daily limit'
                      : 'of ${formatPeso(s.dailyLimit, masked: masked)} daily '
                            'limit',
                  style: const TextStyle(fontSize: 13, color: Colors.grey),
                ),
                const SizedBox(height: 14),
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: LinearProgressIndicator(
                    value: s.usedFraction,
                    minHeight: 8,
                    backgroundColor: colors.track,
                    valueColor: AlwaysStoppedAnimation(barColor),
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Today spent: '
                        '${formatPeso(s.spentToday, masked: masked)}',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: colors.textBody,
                        ),
                      ),
                    ),
                    Text(
                      '${s.daysLeft} ${s.daysLeft == 1 ? 'day' : 'days'} left '
                      'this period',
                      style: const TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                  ],
                ),
                if (footer != null) ...[const SizedBox(height: 16), footer!],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
