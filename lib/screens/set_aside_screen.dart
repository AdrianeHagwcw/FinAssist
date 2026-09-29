import 'package:flutter/material.dart';

import '../models/bill.dart';
import '../models/goal.dart';
import '../models/wallet.dart';
import '../services/allocation_service.dart';
import '../services/goal_service.dart';
import '../services/wallet_service.dart';
import '../theme/app_buttons.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../utils/date_format.dart';
import '../utils/money_format.dart';
import '../widgets/bill_payment_sheet.dart';
import '../widgets/category_icon.dart';
import '../widgets/empty_state_view.dart';
import '../widgets/money_text.dart';
import 'goals_screen.dart';

/// Which half of the screen is being read.
enum SetAsidePart { savings, bills }

/// The money the user has already promised, kept apart from what they can
/// spend: what is saved, and what is waiting for the bills.
///
/// Both hold real money in their own wallet, so each side opens with its own
/// total balance, and underneath it says where that money is going.
class SetAsideScreen extends StatefulWidget {
  const SetAsideScreen({
    this.wallets,
    this.goals,
    this.loadBills,
    this.today,
    this.initialPart = SetAsidePart.savings,
    super.key,
  });

  /// Replaces the live wallets. Used by tests.
  final Stream<List<Wallet>>? wallets;

  /// Replaces the live goals. Used by tests.
  final Stream<List<Goal>>? goals;

  /// Replaces reading the bills still to pay. Used by tests.
  final Future<List<BillInstance>> Function()? loadBills;

  /// Replaces the clock. Used by tests.
  final DateTime? today;

  final SetAsidePart initialPart;

  @override
  State<SetAsideScreen> createState() => _SetAsideScreenState();
}

class _SetAsideScreenState extends State<SetAsideScreen> {
  late final Stream<List<Wallet>> _wallets =
      widget.wallets ?? WalletService.watchWallets();

  late final Stream<List<Goal>> _goals =
      widget.goals ?? GoalService.watchGoals();

  late SetAsidePart _part = widget.initialPart;

  List<BillInstance> _bills = const [];

  DateTime get _now => widget.today ?? DateTime.now();

  @override
  void initState() {
    super.initState();
    _loadBills();
  }

  void _loadBills() {
    final load =
        widget.loadBills ??
        () => AllocationService.loadOutstandingBills(now: _now);

    load()
        .then((bills) {
          if (mounted) setState(() => _bills = bills);
        })
        .catchError((Object _) {
          // Offline and never cached: show the total on its own.
        });
  }

  Future<void> _pay(BillInstance instance) async {
    final paid = await showBillPaymentSheet(context, instance: instance);
    if (paid && mounted) _loadBills();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    return Scaffold(
      backgroundColor: colors.pageBackground,
      appBar: AppBar(
        title: const Text(
          'Set aside',
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
              SizedBox(
                width: double.infinity,
                child: SegmentedButton<SetAsidePart>(
                  segments: const [
                    ButtonSegment(
                      value: SetAsidePart.savings,
                      label: Text('Savings wallet'),
                    ),
                    ButtonSegment(
                      value: SetAsidePart.bills,
                      label: Text('Bills wallet'),
                    ),
                  ],
                  selected: {_part},
                  showSelectedIcon: false,
                  onSelectionChanged: (value) =>
                      setState(() => _part = value.first),
                ),
              ),
              const SizedBox(height: 16),
              if (wallets == null)
                const Center(child: CircularProgressIndicator())
              else if (_part == SetAsidePart.savings)
                ..._savings(wallets)
              else
                ..._billsPart(wallets),
            ],
          );
        },
      ),
    );
  }

  // ------------------------------------------------------------- savings

  List<Widget> _savings(List<Wallet> wallets) {
    final walletTotal = walletBalanceFor(wallets, WalletPurpose.savings);

    return [
      StreamBuilder<List<Goal>>(
        stream: _goals,
        builder: (context, snapshot) {
          final allGoals = snapshot.data ?? const <Goal>[];
          final goals = allGoals
              .where((goal) => goal.status != GoalStatus.used)
              .toList();
          final assignedToGoals = totalSetAsideInPurposeWallets(
            allGoals,
            wallets,
            WalletPurpose.savings,
          );
          // Contributions remain part of the Savings wallet's real balance,
          // but are already held inside their goals. Show only the amount
          // that is still free in the wallet here. A withdrawal reduces the
          // goal's savedByWallet amount, returning it to this total.
          final available = (walletTotal - assignedToGoals)
              .clamp(0.0, double.infinity)
              .toDouble();

          if (goals.isEmpty) {
            return Column(
              children: [
                _TotalCard(
                  title: 'Savings wallet',
                  total: available,
                  iconAsset: 'assets/icons/icons8-money-box-96.png',
                  note: 'Money you have saved and have not put towards a goal.',
                ),
                const SizedBox(height: 20),
                const EmptyStateView(
                  iconAsset: 'assets/icons/icons8-money-box-96.png',
                  title: 'No savings goal yet',
                  message:
                      'Add a goal such as an emergency fund or school money, '
                      'and your savings are counted towards it here.',
                ),
                const SizedBox(height: 16),
                _ManageGoalsButton(
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const GoalsScreen()),
                  ),
                ),
              ],
            );
          }

          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _TotalCard(
                title: 'Savings wallet',
                total: available,
                iconAsset: 'assets/icons/icons8-money-box-96.png',
                note: 'Money you have saved and have not put towards a goal.',
              ),
              const SizedBox(height: 20),
              _SectionTitle('What it is for'),
              const SizedBox(height: 10),
              for (final goal in goals) ...[
                _GoalRow(goal: goal),
                const SizedBox(height: 10),
              ],
              _ManageGoalsButton(
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const GoalsScreen()),
                ),
              ),
              const SizedBox(height: 10),
              _NoteRow(
                label: 'Not promised to a goal yet',
                amount: available,
                hint: 'Yours to put towards any goal.',
              ),
            ],
          );
        },
      ),
    ];
  }

  // --------------------------------------------------------------- bills

  List<Widget> _billsPart(List<Wallet> wallets) {
    final total = walletBalanceFor(wallets, WalletPurpose.bills);
    final owed = _bills.fold<double>(0, (sum, bill) => sum + bill.remaining);
    final short = owed - total;

    return [
      _TotalCard(
        title: 'Bills wallet',
        total: total,
        iconAsset: 'assets/icons/icons8-receipt-96.png',
        note: 'Money waiting for your bills. Paying a bill takes it from here '
            'first.',
      ),
      const SizedBox(height: 20),
      if (_bills.isEmpty)
        const EmptyStateView(
          iconAsset: 'assets/icons/icons8-receipt-96.png',
          title: 'No bills to pay',
          message:
              'Bills you add show up here with what you still owe on them.',
        )
      else ...[
        _SectionTitle('Bills to pay'),
        const SizedBox(height: 10),
        for (final bill in _bills) ...[
          _BillRow(bill: bill, now: _now, onPay: () => _pay(bill)),
          const SizedBox(height: 10),
        ],
        _NoteRow(
          label: short > 0 ? 'Still to set aside' : 'Left after these bills',
          amount: short.abs(),
          hint: short > 0
              ? 'Your bills come to more than this wallet holds.'
              : 'Enough is here for every bill on the list.',
        ),
      ],
    ];
  }
}

/// The balance at the top of either side, named the way the user asked for
/// it: what it is, then the total in it.
class _TotalCard extends StatelessWidget {
  const _TotalCard({
    required this.title,
    required this.total,
    required this.note,
    required this.iconAsset,
  });

  final String title;
  final double total;
  final String note;

  /// The same icon this money carries on Home, so the two read as one thing.
  final String iconAsset;

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
          const SizedBox(height: 8),
          Text(
            note,
            style: const TextStyle(color: Colors.white70, fontSize: 12),
          ),
        ],
      ),
    );
  }
}

/// Opens the goals themselves, where they are added and edited.
class _ManageGoalsButton extends StatelessWidget {
  const _ManageGoalsButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        onPressed: onPressed,
        icon: Image.asset(
          'assets/icons/icons8-goal-96.png',
          width: 18,
          height: 18,
        ),
        label: const Text('Manage goals'),
        style: openOutlineStyle(context),
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

/// One goal the savings are going towards.
class _GoalRow extends StatelessWidget {
  const _GoalRow({required this.goal});

  final Goal goal;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: colors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(goal.kind.icon, size: 20, color: appPrimaryBlue),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  goal.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: colors.textPrimary,
                  ),
                ),
              ),
              MoneyText(
                goal.savedAmount,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  color: colors.textPrimary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: goal.progress.clamp(0, 1),
              minHeight: 6,
              backgroundColor: colors.border,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'of ${formatPeso(goal.targetAmount)} target',
            style: TextStyle(fontSize: 12, color: colors.textBody),
          ),
        ],
      ),
    );
  }
}

/// One bill still to pay, with what is left on it.
class _BillRow extends StatelessWidget {
  const _BillRow({required this.bill, required this.now, required this.onPay});

  final BillInstance bill;
  final DateTime now;
  final VoidCallback onPay;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final overdue = bill.dueDate.isBefore(DateTime(now.year, now.month, now.day));

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.card,
        borderRadius: BorderRadius.circular(14),
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
            child: CategoryIcon(bill.category, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  bill.name,
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
                  overdue
                      ? 'Overdue · ${formatShortDate(bill.dueDate)}'
                      : 'Due ${formatShortDate(bill.dueDate)}',
                  style: TextStyle(
                    fontSize: 12,
                    color: overdue ? Colors.redAccent : colors.textBody,
                  ),
                ),
              ],
            ),
          ),
          MoneyText(
            bill.remaining,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.bold,
              color: colors.textPrimary,
            ),
          ),
          const SizedBox(width: 10),
          TextButton(onPressed: onPay, child: const Text('Pay')),
        ],
      ),
    );
  }
}

/// The line that closes each list: what is spare, or what is still missing.
class _NoteRow extends StatelessWidget {
  const _NoteRow({
    required this.label,
    required this.amount,
    required this.hint,
  });

  final String label;
  final double amount;
  final String hint;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.primaryTint,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(fontSize: 14, color: colors.textPrimary),
                ),
              ),
              MoneyText(
                amount,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: colors.textPrimary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(hint, style: TextStyle(fontSize: 12, color: colors.textBody)),
        ],
      ),
    );
  }
}
