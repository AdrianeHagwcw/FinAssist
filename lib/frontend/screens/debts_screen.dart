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
import '../widgets/debt_form_sheet.dart';
import '../widgets/empty_state_view.dart';
import '../widgets/loan_form_sheet.dart';
import '../widgets/money_text.dart';
import 'debt_detail_screen.dart';

/// Installments, or with [loans] Debts, as its own screen, for the Home
/// shortcuts.
class DebtsScreen extends StatelessWidget {
  const DebtsScreen({this.loans = false, super.key});

  final bool loans;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.appColors.pageBackground,
      appBar: AppBar(
        title: Text(
          loans ? 'Debts' : 'Installments',
          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
        ),
        centerTitle: true,
        backgroundColor: appPrimaryBlue,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: DebtsView(loans: loans, bottomPadding: 40),
    );
  }
}

/// What the user pays off: things bought on installment, or with [loans]
/// money they borrowed. Two lists with their own forms, since they are
/// worked out differently; both pay through the Bill Planner.
class DebtsView extends StatefulWidget {
  const DebtsView({
    this.loans = false,
    this.debts,
    this.paymentsFor,
    this.onOpen,
    this.bottomPadding = 100,
    super.key,
  });

  /// Borrowed money (Debts) instead of things bought on installment.
  final bool loans;

  /// Replace the live data. Used by tests.
  final Stream<List<Debt>>? debts;
  final Stream<List<BillInstance>> Function(String billId)? paymentsFor;
  final void Function(Debt debt)? onOpen;

  /// Room below the list; more inside the tab bar's shell.
  final double bottomPadding;

  @override
  State<DebtsView> createState() => _DebtsViewState();
}

class _DebtsViewState extends State<DebtsView> {
  late final Stream<List<Debt>> _debts =
      widget.debts ?? DebtService.watchDebts();

  /// Opens the form for this list.
  Future<void> _add() async {
    if (widget.loans) {
      await showLoanFormSheet(context);
    } else {
      await showDebtFormSheet(context);
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
      MaterialPageRoute(builder: (context) => DebtDetailScreen(debt: debt)),
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

        // Only what the user owes. Money they lent out is no longer part of
        // the app; records made before it was dropped stay in the database
        // untouched but are not listed.
        final owed = all.where((d) => d.direction == DebtDirection.iOwe);
        final shown = owed
            .where((d) => d.category.isLoan == widget.loans)
            .toList();
        // Loans saved before the two were split now live under Debts; say
        // so, rather than have them seem to vanish.
        final loansElsewhere =
            !widget.loans && owed.any((d) => d.category.isLoan);

        return ListView(
          padding: EdgeInsets.fromLTRB(20, 16, 20, widget.bottomPadding),
          children: [
            if (loansElsewhere) ...[
              _MovedNote(
                onOpen: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const DebtsScreen(loans: true),
                  ),
                ),
              ),
              const SizedBox(height: 12),
            ],
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

/// Points to Debts from Installments, for loans saved here before.
class _MovedNote extends StatelessWidget {
  const _MovedNote({required this.onOpen});

  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Material(
      color: colors.primaryTint,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onOpen,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  'Money you borrowed is now under Debts.',
                  style: TextStyle(fontSize: 13, color: colors.textBody),
                ),
              ),
              Text(
                'Open Debts',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: colors.primaryText,
                ),
              ),
              Icon(Icons.chevron_right, size: 18, color: colors.primaryText),
            ],
          ),
        ),
      ),
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
