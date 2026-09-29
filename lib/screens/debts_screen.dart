import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../models/bill.dart';
import '../models/debt.dart';
import '../services/bill_service.dart';
import '../services/debt_service.dart';
import '../theme/app_buttons.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../utils/date_format.dart';
import '../utils/money_format.dart';
import '../widgets/debt_form_sheet.dart';
import '../widgets/empty_state_view.dart';
import '../widgets/money_text.dart';
import 'debt_detail_screen.dart';

/// Debts as its own screen, for the Home shortcut.
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

/// Installments and loans the user pays, and money others owe the user.
class DebtsView extends StatefulWidget {
  const DebtsView({
    this.showing,
    this.debts,
    this.paymentsFor,
    this.onOpen,
    this.bottomPadding = 100,
    super.key,
  });

  /// Switches the list to a direction from outside, like after adding an
  /// installment from the + button.
  final ValueListenable<DebtDirection>? showing;

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

  late DebtDirection _direction = widget.showing?.value ?? DebtDirection.iOwe;

  @override
  void initState() {
    super.initState();
    widget.showing?.addListener(_follow);
  }

  @override
  void dispose() {
    widget.showing?.removeListener(_follow);
    super.dispose();
  }

  void _follow() {
    final direction = widget.showing?.value;
    if (direction != null && mounted) setState(() => _direction = direction);
  }

  /// Opens the form, then shows the list the new entry went to.
  Future<void> _add() async {
    final saved = await showDebtFormSheet(context, direction: _direction);
    if (saved != null && mounted) setState(() => _direction = saved);
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
        final shown = all
            .where((d) => d.direction == DebtDirection.iOwe)
            .toList();

        return ListView(
          padding: EdgeInsets.fromLTRB(20, 16, 20, widget.bottomPadding),
          children: [
            if (shown.isEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 30, bottom: 10),
                child: EmptyStateView(
                  iconAsset: 'assets/icons/icons8-money-box-96.png',
                  title: 'Nothing to pay off',
                  message:
                      'Add an installment or loan, and its payments show up '
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
                      progress: DebtProgress.of(
                        debt,
                        payments.data ?? const [],
                      ),
                    onTap: () => _open(debt),
                  ),
                ),
                const SizedBox(height: 12),
              ],
            const SizedBox(height: 4),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _add,
                style: openButtonStyle(),
                icon: const Icon(Icons.add),
                label: const Text(
                  'Add loan or installment',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ),
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
            debt.category.label,
            style: const TextStyle(fontSize: 12, color: Colors.grey),
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
                  style: const TextStyle(fontSize: 13, color: Colors.grey),
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          // On its own line: next to the amounts it runs off a narrow phone.
          Text(
            done
                ? 'Paid off'
                : '${progress.paymentsLeft} '
                      '${progress.paymentsLeft == 1 ? 'payment' : 'payments'} left'
                      '${last == null ? '' : ' · last one ${formatShortDate(last)}'}',
            style: const TextStyle(fontSize: 12, color: Colors.grey),
          ),
        ],
      ),
    );
  }
}

