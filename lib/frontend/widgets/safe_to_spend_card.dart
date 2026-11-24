import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../../backend/models/app_transaction.dart';
import '../../backend/models/bill.dart';
import '../../backend/models/debt.dart';
import '../../backend/models/goal.dart';
import 'app_icon_button.dart';
import '../../backend/models/safe_to_spend.dart';
import '../../backend/models/wallet.dart';
import '../providers/app_settings_provider.dart';
import '../../backend/services/allocation_service.dart';
import '../../backend/services/bill_service.dart';
import '../../backend/services/debt_service.dart';
import '../../backend/services/goal_service.dart';
import '../../backend/services/wallet_service.dart';
import '../theme/app_buttons.dart';
import '../theme/app_colors.dart';
import '../../backend/utils/money_format.dart';
import '../../backend/utils/ph_time.dart';
import 'dialog_kit.dart';
import 'money_text.dart';

/// Everything the Safe-to-Spend figure is worked out from, gathered once so
/// the card and anything under it always agree.
class SafeToSpendInputs {
  const SafeToSpendInputs({
    required this.safeToSpend,
    this.bills = const [],
    this.wallets = const [],
    this.now,
  });

  final SafeToSpend safeToSpend;

  /// The wallets the figure was worked out from, so anything shown under
  /// the card can read them without loading them again.
  final List<Wallet> wallets;

  /// Unpaid bills, overdue or coming up, as loaded for the figure.
  final List<BillInstance> bills;

  /// The moment the figure was worked out for.
  final DateTime? now;
}

/// Home's hero card: how much can still be spent today without eating into
/// bills or savings.
class SafeToSpendCard extends StatefulWidget {
  const SafeToSpendCard({
    this.wallets,
    this.transactions,
    this.loadBills,
    this.loadDebts,
    this.goals,
    this.billSchedules,
    this.today,
    this.showFigure = true,
    this.belowCard,
    super.key,
  });

  /// Replace the live data. Used by tests, which can't load Firebase.
  final Stream<List<Wallet>>? wallets;
  final Stream<List<AppTransaction>>? transactions;
  final Future<List<BillInstance>> Function()? loadBills;

  /// Replaces reading the plans behind the bills, used to tell an
  /// installment payment from a debt payment. Used by tests.
  final Future<List<Debt>> Function()? loadDebts;
  final Stream<List<Goal>>? goals;

  /// Replaces watching the bill schedules for changes. Used by tests.
  final Stream<List<Bill>>? billSchedules;
  final DateTime? today;

  /// False on Home, which shows the total balance instead: only what
  /// [belowCard] builds is shown, from the same inputs (bills due soon,
  /// matured savings).
  final bool showFigure;

  /// Shown below the card with the same inputs, such as bills due soon.
  final Widget Function(BuildContext context, SafeToSpendInputs inputs)?
  belowCard;

  @override
  State<SafeToSpendCard> createState() => _SafeToSpendCardState();
}

/// One line of the working behind Safe to Spend: a label, and the amount,
/// with a minus in front of money taken off.
class _Working extends StatelessWidget {
  const _Working(
    this.label,
    this.amount, {
    this.take = false,
    this.strong = false,
    this.color,
  });

  final String label;
  final double amount;

  /// Shown with a minus, because it is money the user cannot spend.
  final bool take;
  final bool strong;

  /// The amount's own color, such as red for spending past today's amount.
  final Color? color;

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
            '${take ? '− ' : ''}${formatPeso(amount)}',
            style: TextStyle(
              fontWeight: strong ? FontWeight.bold : FontWeight.w600,
              color: color ?? colors.textPrimary,
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

  /// Which plans are installments and which are borrowed money, by plan id.
  /// Null until they are read, or when they couldn't be, and the bills are
  /// then shown as one total.
  Map<String, bool>? _planIsLoan;

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

  /// Whether the last read of the bills failed, and whether any read has ever
  /// worked. Told quietly on the card, so the figure is never passed off as
  /// whole when bills are missing from it.
  bool _billsReadFailed = false;
  bool _billsLoadedOnce = false;

  /// Bills are re-read when the transactions or the bill schedules change.
  int _billsLoadedFor = -1;

  /// Philippine time, whatever the phone's time zone.
  DateTime get _now => widget.today ?? philippineNow();

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

    // The plans behind the bills say which payments are installments and
    // which are debts. If they can't be read the bills still count; they are
    // just shown as one total instead of three.
    Future<Map<String, bool>?> planKinds() async {
      try {
        final debts = await (widget.loadDebts ?? DebtService.loadDebts)();
        return {for (final debt in debts) debt.id: debt.category.isLoan};
      } catch (_) {
        return null;
      }
    }

    load()
        .then((bills) async {
          final kinds = await planKinds();
          if (!mounted) return;
          setState(() {
            _bills = bills;
            _planIsLoan = kinds;
            _billsReadFailed = false;
            _billsLoadedOnce = true;
          });
        })
        .catchError((Object _) {
          if (!mounted) return;
          setState(() => _billsReadFailed = true);
        });
  }

  SafeToSpendInputs _inputs({
    required List<Wallet> wallets,
    required List<AppTransaction> transactions,
  }) {
    final now = _now;

    return SafeToSpendInputs(
      // The same working Add Expense uses for its heads-up.
      safeToSpend: safeToSpendFrom(
        wallets: wallets,
        transactions: transactions,
        bills: _bills,
        goals: _goalsData,
        now: now,
        planIsLoan: _planIsLoan,
        billsUnknown: _billsReadFailed && !_billsLoadedOnce,
        billsOutOfDate: _billsReadFailed && _billsLoadedOnce,
      ),
      wallets: wallets,
      bills: _bills,
      now: now,
    );
  }

  void _explain(SafeToSpendInputs inputs) =>
      showSafeToSpendWorking(context, inputs.safeToSpend);

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Wallet>>(
      stream: _wallets,
      builder: (context, walletSnapshot) {
        return StreamBuilder<List<AppTransaction>>(
          stream: _transactions,
          builder: (context, transactionSnapshot) {
            final transactions =
                transactionSnapshot.data ?? const <AppTransaction>[];

            if (transactionSnapshot.hasData) {
              _refreshBills(transactions);
            }

            if (!walletSnapshot.hasData) {
              return widget.showFigure
                  ? const SizedBox(
                      height: 150,
                      child: Center(child: CircularProgressIndicator()),
                    )
                  : const SizedBox.shrink();
            }

            final inputs = _inputs(
              wallets: walletSnapshot.data!,
              transactions: transactions,
            );

            return Column(
              children: [
                if (widget.showFigure)
                  _HeroCard(
                    inputs: inputs,
                    now: _now,
                    onExplain: () => _explain(inputs),
                  ),
                if (widget.belowCard != null)
                  widget.belowCard!(context, inputs),
              ],
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
  });

  final SafeToSpendInputs inputs;
  final DateTime now;
  final VoidCallback onExplain;

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
              // The same colored icons as Home's balance card.
              AppIconButton(
                iconAsset: masked ? amountsHiddenIcon : amountsShownIcon,
                tooltip: masked ? 'Show amounts' : 'Hide amounts',
                onPressed: () =>
                    context.read<AppSettingsProvider>().toggleAmountsMasked(),
              ),
              AppIconButton(
                key: const Key('safe-to-spend-info'),
                iconAsset: infoIcon,
                tooltip: 'How this is worked out',
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
                  style: TextStyle(
                    fontSize: 13,
                    color: context.appColors.textMuted,
                  ),
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
                    // Wraps rather than pushes past the card with large text.
                    Flexible(
                      child: Text(
                        '${s.daysLeft} ${s.daysLeft == 1 ? 'day' : 'days'} '
                        'left this month',
                        textAlign: TextAlign.end,
                        style: TextStyle(
                          fontSize: 12,
                          color: context.appColors.textMuted,
                        ),
                      ),
                    ),
                  ],
                ),
                // One quiet line when bills are missing from the figure,
                // rather than a banner or a warning of its own.
                if (s.billsUnknown || s.billsOutOfDate) ...[
                  const SizedBox(height: 6),
                  Text(
                    s.billsUnknown
                        ? "Bills aren't counted yet."
                        : 'Bills may be out of date.',
                    style: TextStyle(
                      fontSize: 12,
                      color: context.appColors.textMuted,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// How Safe to Spend is worked out, line by line, ending on [s]'s figure.
void showSafeToSpendWorking(BuildContext context, SafeToSpend s) {
  showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      shape: dialogShape,
      title: const Text('How this is worked out'),
      content: SingleChildScrollView(child: SafeToSpendWorking(s)),
      actions: [gotItButton(context)],
    ),
  );
}

/// The blue, full-width button that closes an explanation.
Widget gotItButton(BuildContext context) => SizedBox(
  width: double.infinity,
  child: ElevatedButton(
    onPressed: () => Navigator.pop(context),
    style: openButtonStyle(height: 48),
    child: const Text('Got it', style: TextStyle(fontWeight: FontWeight.bold)),
  ),
);

/// The working behind Safe to Spend, laid out like a receipt rather than
/// written as a paragraph: the reader follows one line at a time and
/// arrives at today's figure, instead of parsing a sentence full of amounts.
class SafeToSpendWorking extends StatelessWidget {
  const SafeToSpendWorking(this.s, {this.balanceShown = false, super.key});

  final SafeToSpend s;

  /// The Available Balance is shown just above, as in Home's popup, so the
  /// sum doesn't start by repeating it.
  final bool balanceShown;

  @override
  Widget build(BuildContext context) {
    // A brand new account has nothing to share out yet, so it is told
    // what to do rather than shown ₱0 a day.
    if (s.walletBalance <= 0) {
      return const Text(
        'Add income or a wallet balance to see how much you can spend each '
        'day.',
        style: TextStyle(height: 1.45),
      );
    }

    final muted = TextStyle(
      fontSize: 12,
      height: 1.4,
      color: context.appColors.textMuted,
    );
    final days = '${s.daysLeft} ${s.daysLeft == 1 ? 'day' : 'days'}';
    // Measured from the start of today, so today's spending is taken off
    // the day's share once rather than from the balance as well.
    final start = s.walletBalance + s.spentToday - s.goalSavings;
    final over = s.isOverLimit;
    // Today's spending makes the start differ from the balance shown above.
    final showStart = !balanceShown || s.spentToday > 0;
    final billsTaken = s.billsDue > 0;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (showStart)
          _Working(
            s.spentToday > 0
                ? 'Available Balance at the start of today'
                : 'Available Balance',
            start,
          ),
        if (s.hasBillBreakdown) ...[
          if (s.billsOnlyDue > 0)
            _Working('Bills due this month', s.billsOnlyDue, take: true),
          if (s.installmentsDue! > 0)
            _Working(
              'Installments due this month',
              s.installmentsDue!,
              take: true,
            ),
          if (s.debtsDue! > 0)
            _Working('Debts due this month', s.debtsDue!, take: true),
        ] else if (s.billsDue > 0)
          _Working('Bills due this month', s.billsDue, take: true),
        if (showStart || billsTaken) const Divider(height: 22),
        // With nothing taken off, what is left is the balance itself.
        if (billsTaken) _Working('Left after bills', s.spendableThisPeriod),
        _Working(
          'Safe to spend each day ($days left)',
          s.recommendedDailyLimit,
          strong: s.spentToday <= 0,
        ),
        if (s.spentToday > 0) ...[
          _Working('Spent today', s.spentToday, take: true),
          const Divider(height: 22),
          _Working(
            over ? "Over today's safe amount" : 'Left to spend today',
            over ? -s.leftToday : s.leftToday,
            strong: true,
            color: over ? dangerColorOn(context) : null,
          ),
        ],
        if (start < s.billsDue - 0.005) ...[
          const SizedBox(height: 8),
          Text(
            "This month's bills are more than your Available Balance.",
            style: TextStyle(
              fontSize: 13,
              height: 1.4,
              color: dangerColorOn(context),
            ),
          ),
        ],
        const SizedBox(height: 10),
        Text(
          'Counts bills due this month, overdue ones included.',
          style: muted,
        ),
        if (s.billsUnknown || s.billsOutOfDate) ...[
          const SizedBox(height: 6),
          Text(
            s.billsUnknown
                ? "Bills aren't counted yet."
                : 'Bills may be out of date.',
            style: muted,
          ),
        ],
      ],
    );
  }
}
