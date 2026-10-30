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
import '../widgets/installment_form_sheet.dart';
import '../widgets/loan_form_sheet.dart';
import '../widgets/money_text.dart';
import 'debt_detail_screen.dart';

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

        return ListView(
          padding: EdgeInsets.fromLTRB(20, 16, 20, widget.bottomPadding),
          children: [
            if (shown.isEmpty)
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
            else
              for (final debt in shown) ...[
                StreamBuilder<List<BillInstance>>(
                  stream: debt.billId == null
                      ? Stream.value(const [])
                      : _payments(debt.billId!),
                  builder: (context, payments) => _InstallmentCard(
                    debt: debt,
                    progress: DebtProgress.of(debt, payments.data ?? const []),
                    onTap: () => _open(debt),
                  ),
                ),
                const SizedBox(height: 12),
              ],
            const SizedBox(height: 4),
            AddButton(
              label: widget.loans ? 'Add Debt' : 'Add Installment',
              onPressed: _add,
            ),
          ],
        );
      },
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
    final done = progress.isPaidOff;
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
              if (done)
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
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: progress.fraction,
              minHeight: 8,
              backgroundColor: colors.track,
              valueColor: AlwaysStoppedAnimation(
                done ? confirmColorOn(context) : appPrimaryBlue,
              ),
            ),
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
            done
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
