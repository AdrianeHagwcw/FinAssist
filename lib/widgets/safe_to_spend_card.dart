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
import '../theme/app_theme.dart';
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
  });

  final SafeToSpend safeToSpend;
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

  /// Buttons shown under the figure. Given a way to open the limit editor so
  /// an outside "Daily Limit" button opens the same sheet as the pencil.
  final Widget Function(BuildContext context, VoidCallback openEditor)?
  footerBuilder;

  /// Shown below the card with the same inputs, such as the leftover notice.
  final Widget Function(BuildContext context, SafeToSpendInputs inputs)?
  belowCard;

  @override
  State<SafeToSpendCard> createState() => _SafeToSpendCardState();
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
  double _goalSavings = 0;
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
        if (mounted) setState(() => _goalSavings = totalSetAside(goals));
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
    final lastIncome = cycles.isEmpty ? null : cycles.first.receivedAt;
    final period = payPeriodFor(frequency, lastIncomeAt: lastIncome, now: now);
    final startOfToday = DateTime(now.year, now.month, now.day);

    return SafeToSpendInputs(
      safeToSpend: SafeToSpend(
        walletBalance: totalWalletBalance(wallets),
        billsDue: billsDueBefore(_bills, period.end),
        savingsReserve: savingsReserveFrom(profile),
        goalSavings: _goalSavings,
        spentToday: discretionarySpending(
          transactions,
          from: startOfToday,
          until: startOfToday.add(const Duration(days: 1)),
        ),
        daysLeft: period.daysLeft(now),
        customDailyLimit: customDailyLimitFrom(profile),
      ),
      period: period,
      frequency: frequency,
      cycles: cycles,
      transactions: transactions,
    );
  }

  Future<void> _openEditor(SafeToSpend safeToSpend) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: context.appColors.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => EditSafeToSpendSheet(safeToSpend: safeToSpend),
    );
  }

  void _explain(SafeToSpendInputs inputs) {
    final s = inputs.safeToSpend;

    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        shape: dialogShape,
        title: const Text('How this is worked out'),
        content: Text(
          'Your wallets hold ${formatPeso(s.walletBalance)}'
          '${s.spentToday > 0 ? ', plus ${formatPeso(s.spentToday)} spent today' : ''}.\n\n'
          'Less ${formatPeso(s.billsDue)} owed on bills due this pay period'
          '${s.savingsReserve > 0 ? ', ${formatPeso(s.savingsReserve)} set aside as savings' : ''}'
          '${s.goalSavings > 0 ? ', ${formatPeso(s.goalSavings)} saved toward goals' : ''}, '
          'that leaves ${formatPeso(s.spendableThisPeriod)} for the '
          '${s.daysLeft} ${s.daysLeft == 1 ? 'day' : 'days'} left: '
          '${formatPeso(s.recommendedDailyLimit)} a day.'
          '${s.usesCustomLimit ? '\n\nYou set your own limit of ${formatPeso(s.dailyLimit)}, which is used instead.' : ''}',
          style: const TextStyle(height: 1.45),
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
                          onEdit: () => _openEditor(inputs.safeToSpend),
                          onExplain: () => _explain(inputs),
                          footer: widget.footerBuilder?.call(
                            context,
                            () => _openEditor(inputs.safeToSpend),
                          ),
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
    required this.onEdit,
    required this.onExplain,
    required this.footer,
  });

  final SafeToSpendInputs inputs;
  final DateTime now;
  final VoidCallback onEdit;
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
      padding: const EdgeInsets.fromLTRB(18, 10, 8, 18),
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
                tooltip: 'Edit daily limit',
                color: appPrimaryBlue,
                icon: const Icon(Icons.edit_outlined, size: 20),
                onPressed: onEdit,
              ),
              PopupMenuButton<String>(
                tooltip: 'More',
                icon: const Icon(Icons.more_vert, size: 20),
                onSelected: (value) {
                  if (value == 'explain') onExplain();
                },
                itemBuilder: (context) => [
                  menuItem(
                    value: 'explain',
                    label: 'How this is worked out',
                    icon: Icons.info_outline,
                    color: appPrimaryBlue,
                  ),
                ],
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
                            'limit${s.usesCustomLimit ? ' (yours)' : ''}',
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

/// Lets the user see the recommended daily limit, set their own, and adjust
/// how much is set aside as savings.
class EditSafeToSpendSheet extends StatefulWidget {
  const EditSafeToSpendSheet({
    required this.safeToSpend,
    this.onSave,
    super.key,
  });

  final SafeToSpend safeToSpend;

  /// Replaces saving. [customLimit] is null when the recommendation is used.
  /// Used by tests.
  final void Function(double? customLimit, double savingsReserve)? onSave;

  @override
  State<EditSafeToSpendSheet> createState() => _EditSafeToSpendSheetState();
}

class _EditSafeToSpendSheetState extends State<EditSafeToSpendSheet> {
  late final SafeToSpend _s = widget.safeToSpend;

  // Empty means the recommendation, which is shown as the hint instead.
  late final _limitController = TextEditingController(
    text: _s.usesCustomLimit ? formatAmountInput(_s.dailyLimit) : '',
  );
  late final _reserveController = TextEditingController(
    text: formatAmountInput(_s.savingsReserve),
  );

  String? _error;

  bool get _useRecommendation => _limitController.text.trim().isEmpty;

  @override
  void dispose() {
    _limitController.dispose();
    _reserveController.dispose();
    super.dispose();
  }

  void _save() {
    final limit = _useRecommendation
        ? _s.recommendedDailyLimit
        : double.tryParse(_limitController.text.trim().replaceAll(',', ''));
    final reserve = double.tryParse(
      _reserveController.text.trim().replaceAll(',', ''),
    );

    if (limit == null || limit < 0) {
      setState(
        () => _error =
            'Enter a daily limit, or leave it empty to use the recommendation.',
      );
      return;
    }
    if (reserve == null || reserve < 0) {
      setState(() => _error = 'Enter how much is set aside, or 0.');
      return;
    }

    final custom = _useRecommendation ? null : limit;

    if (widget.onSave != null) {
      widget.onSave!(custom, reserve);
    } else {
      BudgetService.setDailyLimit(custom);
      if ((reserve - _s.savingsReserve).abs() > 0.005) {
        BudgetService.setSavingsReserve(reserve);
      }
    }

    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        child: SingleChildScrollView(
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
              Text(
                'Daily Limit',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: colors.textPrimary,
                ),
              ),
              const SizedBox(height: 20),
              TextField(
                controller: _limitController,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                ),
                onChanged: (_) => setState(() => _error = null),
                decoration:
                    dialogFieldDecoration(
                      context,
                      'Your daily limit',
                      helper: _useRecommendation
                          ? 'Empty, so the recommendation is used. It updates '
                                'every day.'
                          : 'Your own limit. It stays the same every day. Clear '
                                'it to use the recommendation.',
                    ).copyWith(
                      prefixText: '₱ ',
                      hintText: formatAmountInput(_s.recommendedDailyLimit),
                      // The hint is the recommendation, so keep it in view.
                      floatingLabelBehavior: FloatingLabelBehavior.always,
                    ),
              ),
              const SizedBox(height: 20),
              TextField(
                controller: _reserveController,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: dialogFieldDecoration(
                  context,
                  'Set aside as savings',
                  helper:
                      'Not counted as spendable. Lower it if you have used '
                      'some of your savings.',
                ).copyWith(prefixText: '₱ ', hintText: '0.00'),
              ),
              if (_error != null) ...[
                const SizedBox(height: 10),
                Text(
                  _error!,
                  style: TextStyle(
                    color: dangerColorOn(context),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: TextButton(
                      onPressed: () => Navigator.pop(context),
                      style: cancelTextStyle(context),
                      child: const Text('Cancel'),
                    ),
                  ),
                  Expanded(
                    flex: 2,
                    child: ElevatedButton(
                      onPressed: _save,
                      style: confirmButtonStyle(),
                      child: const Text(
                        'Save',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
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
