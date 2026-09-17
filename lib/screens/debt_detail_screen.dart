import 'package:flutter/material.dart';

import '../models/app_transaction.dart';
import '../models/bill.dart';
import '../models/debt.dart';
import '../models/wallet.dart';
import '../services/bill_service.dart';
import '../services/debt_service.dart';
import '../services/wallet_service.dart';
import '../theme/app_buttons.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../utils/date_format.dart';
import '../utils/money_format.dart';
import '../widgets/bill_status_badge.dart';
import '../widgets/dialog_kit.dart';
import '../widgets/money_text.dart';
import '../widgets/wallet_picker.dart';
import 'bill_calendar_screen.dart';

/// One installment or one amount owed to the user.
class DebtDetailScreen extends StatefulWidget {
  const DebtDetailScreen({
    required this.debt,
    this.liveDebt,
    this.payments,
    this.transactions,
    this.wallets,
    super.key,
  });

  final Debt debt;

  /// Replace the live data. Used by tests.
  final Stream<Debt?>? liveDebt;
  final Stream<List<BillInstance>>? payments;
  final Stream<List<AppTransaction>>? transactions;
  final Stream<List<Wallet>>? wallets;

  @override
  State<DebtDetailScreen> createState() => _DebtDetailScreenState();
}

class _DebtDetailScreenState extends State<DebtDetailScreen> {
  late final Stream<Debt?> _debt =
      widget.liveDebt ?? DebtService.watchDebt(widget.debt.id);

  late final Stream<List<BillInstance>> _payments =
      widget.payments ??
      (widget.debt.billId == null
          ? Stream.value(const [])
          : BillService.watchInstancesForBill(widget.debt.billId!));

  late final Stream<List<AppTransaction>> _transactions =
      widget.transactions ?? WalletService.watchTransactions();

  late final Stream<List<Wallet>> _wallets =
      widget.wallets ?? WalletService.watchWallets(includeArchived: true);

  Future<bool> _confirm({
    required String title,
    required String message,
    required String action,
  }) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            style: cancelTextStyle(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: dangerTextStyle(context),
            child: Text(action),
          ),
        ],
      ),
    );
    return confirmed == true;
  }

  Future<void> _delete(Debt debt) async {
    final iOwe = debt.direction == DebtDirection.iOwe;
    final ok = await _confirm(
      title: 'Delete ${debt.name}?',
      message: iOwe
          ? 'Its unpaid payments are removed from your Bill Planner. Payments '
                'you already made stay, because that money really left your '
                'wallet.'
          : 'It stops being tracked. Any money already moved between your '
                'wallets stays recorded.',
      action: 'Delete',
    );
    if (!ok) return;

    await DebtService.deleteDebt(debt);
    if (mounted) Navigator.pop(context);
  }

  Future<void> _recordRepayment(Debt debt) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: context.appColors.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => RepaymentSheet(debt: debt, wallets: _wallets),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    return StreamBuilder<Debt?>(
      stream: _debt,
      builder: (context, snapshot) {
        final debt = snapshot.data ?? widget.debt;
        final iOwe = debt.direction == DebtDirection.iOwe;

        return Scaffold(
          backgroundColor: colors.pageBackground,
          appBar: AppBar(
            title: Text(
              debt.name,
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            backgroundColor: appPrimaryBlue,
            foregroundColor: Colors.white,
            elevation: 0,
            actions: [
              PopupMenuButton<String>(
                tooltip: 'Options',
                onSelected: (value) async {
                  if (value == 'delete') _delete(debt);
                  if (value == 'forgive') {
                    final ok = await _confirm(
                      title: 'Stop expecting the rest?',
                      message:
                          'The ${formatPeso(debt.stillOwedToMe)} still owed is '
                          'written off and this is marked settled. No wallet '
                          'changes.',
                      action: 'Write it off',
                    );
                    if (ok) DebtService.forgive(debt);
                  }
                },
                itemBuilder: (context) => [
                  if (!iOwe && debt.status == DebtStatus.active)
                    menuItem(
                      value: 'forgive',
                      label: 'Write off the rest',
                      icon: Icons.volunteer_activism_outlined,
                      color: dangerColorOn(context),
                    ),
                  menuItem(
                    value: 'delete',
                    label: 'Delete',
                    icon: Icons.delete_outline,
                    color: dangerColorOn(context),
                  ),
                ],
              ),
            ],
          ),
          body: iOwe
              ? _InstallmentBody(debt: debt, payments: _payments)
              : _OwedToMeBody(
                  debt: debt,
                  transactions: _transactions,
                  wallets: _wallets,
                  onRecord: () => _recordRepayment(debt),
                  onUndo: (repayment) async {
                    final ok = await _confirm(
                      title: 'Undo this repayment?',
                      message:
                          '${formatPeso(repayment.amount)} comes back out of '
                          'the wallet and is owed again.',
                      action: 'Undo',
                    );
                    if (ok) DebtService.undoRepayment(debt, repayment);
                  },
                ),
        );
      },
    );
  }
}

class _InstallmentBody extends StatelessWidget {
  const _InstallmentBody({required this.debt, required this.payments});

  final Debt debt;
  final Stream<List<BillInstance>> payments;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    return StreamBuilder<List<BillInstance>>(
      stream: payments,
      builder: (context, snapshot) {
        final instances = [...?snapshot.data]
          ..sort((a, b) => a.dueDate.compareTo(b.dueDate));
        final progress = DebtProgress.of(debt, instances);
        final last = debt.lastDueDate;

        return ListView(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 40),
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: colors.card,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: colors.border),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    progress.isPaidOff ? 'Paid off' : 'Still to pay',
                    style: const TextStyle(fontSize: 13, color: Colors.grey),
                  ),
                  const SizedBox(height: 6),
                  MoneyText(
                    progress.remaining,
                    style: TextStyle(
                      fontSize: 30,
                      fontWeight: FontWeight.bold,
                      color: colors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 14),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: LinearProgressIndicator(
                      value: progress.fraction,
                      minHeight: 10,
                      backgroundColor: colors.track,
                      valueColor: AlwaysStoppedAnimation(
                        progress.isPaidOff
                            ? confirmColorOn(context)
                            : appPrimaryBlue,
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    '${formatPeso(progress.paid)} of '
                    '${formatPeso(progress.total)} paid · '
                    '${progress.paymentsLeft} of ${debt.paymentCount} '
                    'payments left',
                    style: TextStyle(fontSize: 13, color: colors.textBody),
                  ),
                  const Divider(height: 28),
                  _Line('Borrowed', formatPeso(debt.principal)),
                  _Line(
                    debt.frequency == PaymentFrequency.weekly
                        ? 'Each week'
                        : 'Each month',
                    formatPeso(debt.perPayment),
                  ),
                  if (debt.extraCost > 0)
                    _Line('More than you borrowed', formatPeso(debt.extraCost)),
                  if (last != null)
                    _Line('Last payment', formatShortDate(last)),
                  if (debt.note != null) _Line('Notes', debt.note!),
                ],
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const BillCalendarScreen(),
                  ),
                ),
                style: openButtonStyle(),
                icon: const Icon(Icons.calendar_month),
                label: const Text(
                  'Pay in Bill Planner',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Each payment is a bill, so you pay it, part-pay it, and choose '
              'the wallet there.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
            const SizedBox(height: 22),
            Text(
              'Payments so far',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: colors.textPrimary,
              ),
            ),
            const SizedBox(height: 10),
            if (instances.isEmpty)
              const Text(
                'Payments appear here once their month is opened in the Bill '
                'Planner.',
                style: TextStyle(color: Colors.grey),
              )
            else
              for (final instance in instances)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          formatShortDate(instance.dueDate),
                          style: TextStyle(color: colors.textPrimary),
                        ),
                      ),
                      BillStatusBadge(instance: instance),
                      const SizedBox(width: 10),
                      MoneyText(
                        instance.amount,
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          color: colors.textPrimary,
                        ),
                      ),
                    ],
                  ),
                ),
          ],
        );
      },
    );
  }
}

class _OwedToMeBody extends StatelessWidget {
  const _OwedToMeBody({
    required this.debt,
    required this.transactions,
    required this.wallets,
    required this.onRecord,
    required this.onUndo,
  });

  final Debt debt;
  final Stream<List<AppTransaction>> transactions;
  final Stream<List<Wallet>> wallets;
  final VoidCallback onRecord;
  final void Function(AppTransaction repayment) onUndo;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final settled = debt.status == DebtStatus.settled;
    final fraction = debt.principal <= 0
        ? 0.0
        : (debt.received / debt.principal).clamp(0.0, 1.0).toDouble();

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 40),
      children: [
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: colors.card,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: colors.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                settled ? 'Settled' : 'Still owed to you',
                style: const TextStyle(fontSize: 13, color: Colors.grey),
              ),
              const SizedBox(height: 6),
              MoneyText(
                debt.stillOwedToMe,
                style: TextStyle(
                  fontSize: 30,
                  fontWeight: FontWeight.bold,
                  color: colors.textPrimary,
                ),
              ),
              const SizedBox(height: 14),
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: LinearProgressIndicator(
                  value: fraction,
                  minHeight: 10,
                  backgroundColor: colors.track,
                  valueColor: AlwaysStoppedAnimation(confirmColorOn(context)),
                ),
              ),
              const SizedBox(height: 10),
              Text(
                '${formatPeso(debt.received > 0 ? debt.received : 0)} of '
                '${formatPeso(debt.principal)} paid back',
                style: TextStyle(fontSize: 13, color: colors.textBody),
              ),
              if (debt.dueDate != null || debt.note != null)
                const Divider(height: 28),
              if (debt.dueDate != null)
                _Line('Promised by', formatShortDate(debt.dueDate!)),
              if (debt.note != null) _Line('Notes', debt.note!),
            ],
          ),
        ),
        if (!settled) ...[
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: onRecord,
              style: confirmButtonStyle(),
              icon: const Icon(Icons.check),
              label: const Text(
                'Record a Repayment',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ),
          ),
        ],
        const SizedBox(height: 22),
        Text(
          'Repayments',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: colors.textPrimary,
          ),
        ),
        const SizedBox(height: 10),
        StreamBuilder<List<Wallet>>(
          stream: wallets,
          builder: (context, walletSnapshot) {
            final walletList = walletSnapshot.data ?? const <Wallet>[];

            return StreamBuilder<List<AppTransaction>>(
              stream: transactions,
              builder: (context, snapshot) {
                final repayments = (snapshot.data ?? const <AppTransaction>[])
                    .where(
                      (t) =>
                          t.debtId == debt.id &&
                          t.type == TransactionType.income,
                    )
                    .toList();

                if (repayments.isEmpty) {
                  return const Text(
                    'Nothing paid back yet.',
                    style: TextStyle(color: Colors.grey),
                  );
                }

                return Column(
                  children: [
                    for (final repayment in repayments)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Row(
                          children: [
                            Icon(
                              Icons.check_circle,
                              color: confirmColorOn(context),
                              size: 20,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                '${formatShortDate(repayment.date)} · into '
                                '${_walletName(walletList, repayment.walletId)}',
                                style: TextStyle(color: colors.textPrimary),
                              ),
                            ),
                            MoneyText(
                              repayment.amount,
                              sign: '+',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: confirmColorOn(context),
                              ),
                            ),
                            IconButton(
                              tooltip: 'Undo this repayment',
                              color: dangerColorOn(context),
                              icon: const Icon(Icons.close, size: 18),
                              onPressed: () => onUndo(repayment),
                            ),
                          ],
                        ),
                      ),
                  ],
                );
              },
            );
          },
        ),
      ],
    );
  }

  static String _walletName(List<Wallet> wallets, String? id) {
    for (final wallet in wallets) {
      if (wallet.id == id) return wallet.name;
    }
    return 'a wallet';
  }
}

class _Line extends StatelessWidget {
  const _Line(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Text(
              label,
              style: const TextStyle(fontSize: 13, color: Colors.grey),
            ),
          ),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: context.appColors.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Records money paid back to the user.
class RepaymentSheet extends StatefulWidget {
  const RepaymentSheet({
    required this.debt,
    required this.wallets,
    this.onSave,
    super.key,
  });

  final Debt debt;
  final Stream<List<Wallet>> wallets;

  /// Replaces saving. Used by tests.
  final void Function(double amount, String walletId)? onSave;

  @override
  State<RepaymentSheet> createState() => _RepaymentSheetState();
}

class _RepaymentSheetState extends State<RepaymentSheet> {
  late final _amountController = TextEditingController(
    text: widget.debt.stillOwedToMe.toStringAsFixed(2),
  );
  String? _walletId;
  String? _error;

  @override
  void dispose() {
    _amountController.dispose();
    super.dispose();
  }

  void _save(List<Wallet> wallets) {
    final amount = double.tryParse(
      _amountController.text.trim().replaceAll(',', ''),
    );
    final walletId = _walletId ?? defaultWalletId(wallets);
    final owed = widget.debt.stillOwedToMe;

    final problem = amount == null || amount <= 0
        ? 'Enter how much was paid back.'
        : amount > owed + 0.005
        ? 'Only ${formatPeso(owed)} is still owed.'
        : walletId == null
        ? 'Add a wallet first.'
        : null;

    if (problem != null) {
      setState(() => _error = problem);
      return;
    }

    if (widget.onSave != null) {
      widget.onSave!(amount!, walletId!);
    } else {
      DebtService.recordRepayment(
        widget.debt,
        amount: amount!,
        walletId: walletId!,
      );
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
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
          child: StreamBuilder<List<Wallet>>(
            stream: widget.wallets,
            builder: (context, snapshot) {
              final wallets = snapshot.data ?? const <Wallet>[];

              return Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${widget.debt.name} paid you back',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: colors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 16),
                  AmountField(controller: _amountController, label: 'Amount'),
                  const SizedBox(height: 16),
                  if (wallets.isNotEmpty)
                    WalletPicker(
                      wallets: wallets,
                      selectedId: _walletId ?? defaultWalletId(wallets),
                      label: 'Into which wallet?',
                      onChanged: (value) => setState(() => _walletId = value),
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
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () => _save(wallets),
                      style: confirmButtonStyle(),
                      child: const Text(
                        'Record Repayment',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}
