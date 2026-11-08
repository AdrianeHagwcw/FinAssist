import 'dart:async';

import 'package:flutter/material.dart';

import '../../backend/models/bill.dart';
import '../../backend/models/debt.dart';
import '../../backend/services/bill_service.dart';
import '../../backend/services/debt_service.dart';
import '../theme/app_buttons.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../../backend/utils/date_format.dart';
import '../../backend/utils/money_format.dart';
import '../widgets/add_button.dart';
import '../widgets/empty_state_view.dart';
import '../widgets/goal_progress.dart';
import '../widgets/installment_form_sheet.dart';
import '../widgets/loan_form_sheet.dart';
import '../widgets/money_text.dart';
import '../widgets/segmented_filter_tile.dart';
import 'debt_detail_screen.dart';

/// Paid in full, whether through its last scheduled payment or early.
///
/// Shared by the card and the Active/Completed filter so what a card shows
/// and where it is listed can never disagree.
bool isDebtCompleted(Debt debt, DebtProgress progress) =>
    progress.isPaidOff ||
    debt.paidOffEarly ||
    debt.status == DebtStatus.settled;

/// Things bought on installment, as its own screen, for the Home shortcuts.
class InstallmentsScreen extends StatelessWidget {
  const InstallmentsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.appColors.pageBackground,
      appBar: AppBar(
        title: const Text(
          'Installments',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
        ),
        centerTitle: true,
        backgroundColor: appPrimaryBlue,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: const InstallmentsView(bottomPadding: 40),
    );
  }
}

/// Money borrowed, as its own screen, for the Home shortcuts.
class DebtsScreen extends StatelessWidget {
  const DebtsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.appColors.pageBackground,
      appBar: AppBar(
        title: const Text(
          'Debts',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
        ),
        centerTitle: true,
        backgroundColor: appPrimaryBlue,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: const DebtsView(bottomPadding: 40),
    );
  }
}

/// What the user pays off in parts: a phone, an appliance, a credit card
/// installment.
class InstallmentsView extends StatelessWidget {
  const InstallmentsView({
    this.debts,
    this.paymentsFor,
    this.onOpen,
    this.bottomPadding = 100,
    super.key,
  });

  /// Replace the live data. Used by tests.
  final Stream<List<Debt>>? debts;
  final Stream<List<BillInstance>> Function(String billId)? paymentsFor;
  final void Function(Debt debt)? onOpen;

  /// Room below the list; more inside the tab bar's shell.
  final double bottomPadding;

  @override
  Widget build(BuildContext context) => _DebtList(
    loans: false,
    debts: debts,
    paymentsFor: paymentsFor,
    onOpen: onOpen,
    bottomPadding: bottomPadding,
  );
}

/// Money the user borrowed, worked out from the interest and paid back the
/// same way. Its own list because the two are entered differently.
class DebtsView extends StatelessWidget {
  const DebtsView({
    this.debts,
    this.paymentsFor,
    this.onOpen,
    this.bottomPadding = 100,
    super.key,
  });

  /// Replace the live data. Used by tests.
  final Stream<List<Debt>>? debts;
  final Stream<List<BillInstance>> Function(String billId)? paymentsFor;
  final void Function(Debt debt)? onOpen;

  /// Room below the list; more inside the tab bar's shell.
  final double bottomPadding;

  @override
  Widget build(BuildContext context) => _DebtList(
    loans: true,
    debts: debts,
    paymentsFor: paymentsFor,
    onOpen: onOpen,
    bottomPadding: bottomPadding,
  );
}

class _DebtList extends StatefulWidget {
  const _DebtList({
    required this.loans,
    this.debts,
    this.paymentsFor,
    this.onOpen,
    this.bottomPadding = 100,
  });

  /// Borrowed money (Debts) instead of things bought on installment.
  final bool loans;

  /// Replace the live data. Used by tests.
  final Stream<List<Debt>>? debts;
  final Stream<List<BillInstance>> Function(String billId)? paymentsFor;
  final void Function(Debt debt)? onOpen;
  final double bottomPadding;

  @override
  State<_DebtList> createState() => _DebtListState();
}

class _DebtListState extends State<_DebtList> {
  late final Stream<List<Debt>> _debts =
      widget.debts ??
      (widget.loans
          ? DebtService.watchLoans()
          : DebtService.watchInstallments());

  /// False shows what is still being paid; true shows what is finished.
  bool _showCompleted = false;

  /// Opens the form for this list.
  Future<void> _add() async {
    if (widget.loans) {
      await showLoanFormSheet(context);
    } else {
      await showInstallmentFormSheet(context);
    }
  }

  Stream<List<BillInstance>> _payments(String billId) =>
      (widget.paymentsFor ?? BillService.watchInstancesForBill)(billId);

  void _open(Debt debt) {
    if (widget.onOpen != null) {
      widget.onOpen!(debt);
      return;
    }
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => widget.loans
            ? LoanDetailScreen(debt: debt)
            : InstallmentDetailScreen(debt: debt),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Debt>>(
      stream: _debts,
      builder: (context, snapshot) {
        final all = snapshot.data;

        if (all == null) {
          return const Center(child: CircularProgressIndicator());
        }

        // Only what the user owes, and only this list's kind: the other is
        // on its own screen. Money they lent out is no longer part of the
        // app; records made before it was dropped stay in the database
        // untouched but are not listed.
        final owed = all.where((d) => d.direction == DebtDirection.iOwe);
        final shown = owed
            .where((d) => d.category.isLoan == widget.loans)
            .toList();

        return _DebtProgressList(
          debts: shown,
          paymentsFor: _payments,
          showCompleted: _showCompleted,
          onChanged: (completed) => setState(() => _showCompleted = completed),
          loans: widget.loans,
          bottomPadding: widget.bottomPadding,
          onOpen: _open,
          onAdd: _add,
        );
      },
    );
  }
}

/// Pairs each debt with how far it has been paid, then shows either the
/// active ones or the completed ones under the same filter Goals uses.
///
/// Progress comes from each debt's bill payments, so an ordinary installment
/// counts as completed when its last payment is made, not only when it is
/// paid off early.
class _DebtProgressList extends StatefulWidget {
  const _DebtProgressList({
    required this.debts,
    required this.paymentsFor,
    required this.showCompleted,
    required this.onChanged,
    required this.loans,
    required this.bottomPadding,
    required this.onOpen,
    required this.onAdd,
  });

  final List<Debt> debts;
  final Stream<List<BillInstance>> Function(String billId) paymentsFor;
  final bool showCompleted;
  final ValueChanged<bool> onChanged;
  final bool loans;
  final double bottomPadding;
  final ValueChanged<Debt> onOpen;
  final VoidCallback onAdd;

  @override
  State<_DebtProgressList> createState() => _DebtProgressListState();
}

class _DebtProgressListState extends State<_DebtProgressList> {
  final _instances = <String, List<BillInstance>>{};
  final _progress = <String, DebtProgress>{};
  final _billIds = <String, String>{};
  final _subscriptions = <String, StreamSubscription<List<BillInstance>>>{};

  @override
  void initState() {
    super.initState();
    _sync();
  }

  @override
  void didUpdateWidget(covariant _DebtProgressList oldWidget) {
    super.didUpdateWidget(oldWidget);
    _sync();
  }

  @override
  void dispose() {
    for (final subscription in _subscriptions.values) {
      subscription.cancel();
    }
    super.dispose();
  }

  /// Subscribes to the payments of any debt that is new here, drops records
  /// that left the list, and recomputes from the latest debt terms.
  void _sync() {
    final ids = {for (final debt in widget.debts) debt.id};
    for (final id in _subscriptions.keys.toList()) {
      if (!ids.contains(id)) {
        _subscriptions.remove(id)?.cancel();
        _billIds.remove(id);
        _instances.remove(id);
        _progress.remove(id);
      }
    }

    for (final debt in widget.debts) {
      final billId = debt.billId;
      if (billId == null) {
        _subscriptions.remove(debt.id)?.cancel();
        _billIds.remove(debt.id);
        _instances[debt.id] = const [];
        continue;
      }

      if (_subscriptions.containsKey(debt.id) && _billIds[debt.id] == billId) {
        continue;
      }

      _subscriptions.remove(debt.id)?.cancel();
      _billIds[debt.id] = billId;
      // Show the plan's own figures at once; the payments fill in when the
      // stream delivers them, as each card did before.
      _instances.putIfAbsent(debt.id, () => const []);
      _subscriptions[debt.id] = widget
          .paymentsFor(billId)
          .listen(
            (instances) {
              if (!mounted) return;
              setState(() {
                _instances[debt.id] = instances;
                _recompute();
              });
            },
            onError: (Object _) {
              if (!mounted) return;
              // A failed read still leaves the plan's own figures usable.
              setState(() {
                _instances[debt.id] = const [];
                _recompute();
              });
            },
          );
    }

    _recompute();
  }

  void _recompute() {
    for (final debt in widget.debts) {
      final instances = _instances[debt.id];
      if (instances == null) continue;
      _progress[debt.id] = DebtProgress.of(debt, instances);
    }
  }

  bool get _ready =>
      widget.debts.every((debt) => _progress.containsKey(debt.id));

  /// Paid in full, whether through its last scheduled payment or early.
  bool _isCompleted(Debt debt, DebtProgress progress) =>
      isDebtCompleted(debt, progress);

  @override
  Widget build(BuildContext context) {
    if (!_ready) {
      return const Center(child: CircularProgressIndicator());
    }

    final active = <Debt>[];
    final completed = <Debt>[];
    for (final debt in widget.debts) {
      final progress = _progress[debt.id]!;
      (_isCompleted(debt, progress) ? completed : active).add(debt);
    }
    final shown = widget.showCompleted ? completed : active;
    final noun = widget.loans ? 'debts' : 'installments';

    return ListView(
      padding: EdgeInsets.fromLTRB(20, 16, 20, widget.bottomPadding),
      children: [
        Row(
          children: [
            Expanded(
              child: SegmentedFilterTile(
                key: Key(
                  widget.loans
                      ? 'debts-filter-active'
                      : 'installments-filter-active',
                ),
                iconAsset: widget.loans
                    ? 'assets/icons/icons8-loan-96.png'
                    : 'assets/icons/installment-96.png',
                label: 'Active',
                count: active.length,
                selected: !widget.showCompleted,
                semanticsLabel: 'Active $noun, ${active.length}',
                onTap: () => widget.onChanged(false),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: SegmentedFilterTile(
                key: Key(
                  widget.loans
                      ? 'debts-filter-completed'
                      : 'installments-filter-completed',
                ),
                iconAsset: goalReachedIcon,
                label: 'Completed',
                count: completed.length,
                selected: widget.showCompleted,
                semanticsLabel: 'Completed $noun, ${completed.length}',
                onTap: () => widget.onChanged(true),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        if (widget.debts.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 30, bottom: 10),
            child: EmptyStateView(
              iconAsset: widget.loans
                  ? 'assets/icons/icons8-loan-96.png'
                  : 'assets/icons/installment-96.png',
              title: widget.loans ? 'No debts yet' : 'No installments yet',
              message: widget.loans
                  ? 'Add money you borrowed. The app works out each '
                        'payment from the interest, and they show up in '
                        'your Bill Planner so you never miss one.'
                  : 'Add an installment and its payments show up '
                        'in your Bill Planner so you never miss one.',
            ),
          )
        else if (shown.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 40),
            child: Text(
              widget.showCompleted
                  ? widget.loans
                        ? 'Debts you finish will show up here.'
                        : 'Installments you finish will show up here.'
                  : widget.loans
                  ? 'Every debt is done. Add a new one to keep going.'
                  : 'Every installment is done. Add a new one to keep going.',
              textAlign: TextAlign.center,
              style: TextStyle(color: context.appColors.textMuted),
            ),
          )
        else
          for (final debt in shown) ...[
            _InstallmentCard(
              debt: debt,
              progress: _progress[debt.id]!,
              onTap: () => widget.onOpen(debt),
            ),
            const SizedBox(height: 12),
          ],
        const SizedBox(height: 4),
        AddButton(
          label: widget.loans ? 'Add Debt' : 'Add Installment',
          onPressed: widget.onAdd,
        ),
      ],
    );
  }
}

class _CardShell extends StatelessWidget {
  const _CardShell({required this.onTap, required this.child});

  final VoidCallback onTap;
  final Widget child;

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
          child: child,
        ),
      ),
    );
  }
}

class _InstallmentCard extends StatelessWidget {
  const _InstallmentCard({
    required this.debt,
    required this.progress,
    required this.onTap,
  });

  final Debt debt;
  final DebtProgress progress;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final completed = isDebtCompleted(debt, progress);
    final last = debt.lastDueDate;

    return _CardShell(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  debt.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: colors.textPrimary,
                  ),
                ),
              ),
              if (completed)
                Icon(Icons.check_circle, color: confirmColorOn(context)),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            debt.kindLabel,
            style: TextStyle(fontSize: 12, color: context.appColors.textMuted),
          ),
          if (debt.paidWithLabel != null)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                'Wallet used: ${debt.paidWithLabel}',
                key: const Key('installment-paid-with-line'),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12,
                  color: context.appColors.textMuted,
                ),
              ),
            ),
          const SizedBox(height: 10),
          // The same bar Goals uses: amber, blue, teal, then green once it
          // is done, easing into each new amount and color.
          GoalProgressBar(
            progress: progress.fraction,
            reached: completed,
            height: 8,
            showPercent: true,
            showLabel: false,
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              MoneyText(
                progress.paid,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: colors.textPrimary,
                ),
              ),
              Flexible(
                child: Text(
                  ' of ${formatPeso(progress.total)} paid',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    color: context.appColors.textMuted,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          // On its own line: next to the amounts it runs off a narrow phone.
          Text(
            completed
                ? debt.paidOffEarly
                      ? 'Paid off early · ${formatShortDate(debt.paidOffAt!)}'
                      : 'Paid off'
                : '${progress.paymentsLeft} '
                      '${progress.paymentsLeft == 1 ? 'payment' : 'payments'} left'
                      '${last == null ? '' : ' · last one ${formatShortDate(last)}'}',
            style: TextStyle(fontSize: 12, color: context.appColors.textMuted),
          ),
        ],
      ),
    );
  }
}
