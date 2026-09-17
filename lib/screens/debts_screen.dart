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
  State<DebtsView> createState() => _DebtsViewState();
}

class _DebtsViewState extends State<DebtsView> {
  late final Stream<List<Debt>> _debts =
      widget.debts ?? DebtService.watchDebts();

  DebtDirection _direction = DebtDirection.iOwe;

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

        final iOwe = _direction == DebtDirection.iOwe;
        final shown = all.where((d) => d.direction == _direction).toList();
        final owedBack = all
            .where(
              (d) =>
                  d.direction == DebtDirection.owedToMe &&
                  d.status == DebtStatus.active,
            )
            .fold<double>(0, (total, d) => total + d.stillOwedToMe);

        return ListView(
          padding: EdgeInsets.fromLTRB(20, 16, 20, widget.bottomPadding),
          children: [
            SizedBox(
              width: double.infinity,
              child: SegmentedButton<DebtDirection>(
                segments: const [
                  ButtonSegment(
                    value: DebtDirection.iOwe,
                    label: Text('I owe'),
                  ),
                  ButtonSegment(
                    value: DebtDirection.owedToMe,
                    label: Text('Owed to me'),
                  ),
                ],
                selected: {_direction},
                showSelectedIcon: false,
                onSelectionChanged: (value) =>
                    setState(() => _direction = value.first),
              ),
            ),
            const SizedBox(height: 16),
            if (!iOwe && owedBack > 0) ...[
              _OwedBackBanner(amount: owedBack),
              const SizedBox(height: 16),
            ],
            if (shown.isEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 30, bottom: 10),
                child: EmptyStateView(
                  iconAsset: 'assets/icons/icons8-money-box-96.png',
                  title: iOwe ? 'Nothing to pay off' : 'No one owes you',
                  message: iOwe
                      ? 'Add an installment or loan, and its payments show up '
                            'in your Bill Planner so you never miss one.'
                      : 'Lent someone money? Keep track of it here until they '
                            'pay you back.',
                ),
              )
            else
              for (final debt in shown) ...[
                if (iOwe)
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
                  )
                else
                  _OwedToMeCard(debt: debt, onTap: () => _open(debt)),
                const SizedBox(height: 12),
              ],
            const SizedBox(height: 4),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () =>
                    showDebtFormSheet(context, direction: _direction),
                style: openButtonStyle(),
                icon: const Icon(Icons.add),
                label: Text(
                  iOwe ? 'Add Installment' : 'Add Money Owed to Me',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _OwedBackBanner extends StatelessWidget {
  const _OwedBackBanner({required this.amount});

  final double amount;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.appColors.primaryTint,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              'Still to come back to you',
              style: TextStyle(color: context.appColors.textBody),
            ),
          ),
          MoneyText(
            amount,
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.bold,
              color: context.appColors.textPrimary,
            ),
          ),
        ],
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

class _OwedToMeCard extends StatelessWidget {
  const _OwedToMeCard({required this.debt, required this.onTap});

  final Debt debt;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final settled = debt.status == DebtStatus.settled;
    final fraction = debt.principal <= 0
        ? 0.0
        : (debt.received / debt.principal).clamp(0.0, 1.0).toDouble();

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
              if (settled)
                Icon(Icons.check_circle, color: confirmColorOn(context)),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: fraction,
              minHeight: 8,
              backgroundColor: colors.track,
              valueColor: AlwaysStoppedAnimation(confirmColorOn(context)),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              MoneyText(
                debt.received > 0 ? debt.received : 0,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: colors.textPrimary,
                ),
              ),
              Flexible(
                child: Text(
                  ' of ${formatPeso(debt.principal)} back',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 13, color: Colors.grey),
                ),
              ),
              const SizedBox(width: 8),
              if (settled)
                const Text(
                  'Settled',
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                )
              else if (debt.dueDate != null)
                Text(
                  'by ${formatShortDate(debt.dueDate!)}',
                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
