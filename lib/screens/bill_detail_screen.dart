import 'package:flutter/material.dart';

import '../models/app_transaction.dart';
import '../models/bill.dart';
import '../models/wallet.dart';
import '../services/bill_service.dart';
import '../services/wallet_service.dart';
import '../theme/app_buttons.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../utils/date_format.dart';
import '../widgets/bill_form_sheet.dart';
import '../widgets/bill_payment_sheet.dart';
import '../widgets/bill_status_badge.dart';
import '../widgets/category_icon.dart';
import '../widgets/money_text.dart';

/// One bill on one due date: what is owed, what has been paid, and the
/// actions that settle it.
class BillDetailScreen extends StatefulWidget {
  const BillDetailScreen({
    required this.instance,
    this.liveInstance,
    this.history,
    this.bills,
    this.wallets,
    this.loadPayments,
    this.today,
    super.key,
  });

  /// The occurrence as it was when the screen opened.
  final BillInstance instance;

  /// Replaces the live copy of this occurrence. Used by tests.
  final Stream<BillInstance?>? liveInstance;

  /// Replaces the other cycles of the same bill. Used by tests.
  final Stream<List<BillInstance>>? history;

  /// Replaces the live bill schedules. Used by tests.
  final Stream<List<Bill>>? bills;

  /// Replaces the live wallet list, used to name the wallet each payment came
  /// from. Used by tests.
  final Stream<List<Wallet>>? wallets;

  /// Replaces the payments made against this bill. Used by tests.
  final Future<List<AppTransaction>> Function(BillInstance)? loadPayments;

  /// Injectable so tests don't depend on the clock.
  final DateTime? today;

  @override
  State<BillDetailScreen> createState() => _BillDetailScreenState();
}

class _BillDetailScreenState extends State<BillDetailScreen> {
  late final Stream<BillInstance?> _instance =
      widget.liveInstance ?? BillService.watchInstance(widget.instance.id);

  late final Stream<List<BillInstance>> _history =
      widget.history ??
      BillService.watchInstancesForBill(widget.instance.billId);

  late final Stream<List<Bill>> _bills =
      widget.bills ?? BillService.watchBills();

  late final Stream<List<Wallet>> _wallets =
      widget.wallets ?? WalletService.watchWallets(includeArchived: true);

  /// Bumped after a payment changes, to reload the breakdown.
  int _paymentsKey = 0;

  Future<List<AppTransaction>> _payments(BillInstance instance) {
    return (widget.loadPayments ?? BillService.loadPayments)(instance);
  }

  Future<void> _pay(BillInstance instance, {required bool inFull}) async {
    final paid = await showBillPaymentSheet(
      context,
      instance: instance,
      payInFull: inFull,
    );

    if (paid && mounted) setState(() => _paymentsKey++);
  }

  Future<void> _undoOnePayment(
    BillInstance instance,
    AppTransaction payment,
    String walletName,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Undo this payment?'),
        content: Text(
          '${_money(payment.amount)} goes back to $walletName, and the bill '
          'shows that much still owing.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            style: cancelTextStyle(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: dangerTextStyle(context),
            child: const Text('Undo'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    BillService.undoPayment(instance, payment);
    if (mounted) setState(() => _paymentsKey++);
  }

  Future<void> _undoPayments(BillInstance instance) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Undo this payment?'),
        content: Text(
          'The bill goes back to unpaid and '
          '${_money(instance.amountPaid)} returns to your wallet.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            style: cancelTextStyle(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: dangerTextStyle(context),
            child: const Text('Undo'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    await BillService.undoPayments(instance);
    if (mounted) setState(() => _paymentsKey++);
  }

  Future<void> _editOccurrence(BillInstance instance) async {
    final amountController = TextEditingController(
      text: instance.amount.toStringAsFixed(2),
    );

    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(18)),
        ),
        title: const Text('Just this one'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Change what this month costs without touching the schedule.',
              style: TextStyle(fontSize: 13, color: Colors.grey),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: amountController,
              autofocus: true,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: const InputDecoration(
                labelText: 'Amount',
                prefixText: '₱ ',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            style: cancelTextStyle(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: confirmTextStyle(context),
            child: const Text('Save'),
          ),
        ],
      ),
    );

    final amount = double.tryParse(
      amountController.text.trim().replaceAll(',', ''),
    );
    amountController.dispose();

    if (saved != true || amount == null || amount <= 0) return;

    BillService.updateInstance(instanceId: instance.id, amount: amount);
  }

  Future<void> _deleteBill(Bill bill) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Delete ${bill.name}?'),
        content: const Text(
          'It stops falling due, and any unpaid dates are removed. Dates you '
          'already paid are kept, because they explain money that really left '
          'your wallet.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            style: cancelTextStyle(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: dangerTextStyle(context),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    await BillService.deleteBill(bill.id);

    if (mounted) Navigator.pop(context);
  }

  String _money(double amount) => '₱${amount.toStringAsFixed(2)}';

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<BillInstance?>(
      stream: _instance,
      builder: (context, snapshot) {
        // Falls back to what was passed in, so the screen still renders while
        // the live copy loads or just after the bill is deleted.
        final instance = snapshot.data ?? widget.instance;

        return StreamBuilder<List<Bill>>(
          stream: _bills,
          builder: (context, billsSnapshot) {
            final bill = _billFor(billsSnapshot.data, instance.billId);

            return Scaffold(
              backgroundColor: context.appColors.pageBackground,
              appBar: AppBar(
                title: Text(
                  instance.name,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                backgroundColor: appPrimaryBlue,
                foregroundColor: Colors.white,
                elevation: 0,
                actions: [
                  PopupMenuButton<String>(
                    tooltip: 'Bill options',
                    onSelected: (value) {
                      switch (value) {
                        case 'occurrence':
                          _editOccurrence(instance);
                        case 'schedule':
                          if (bill != null) {
                            showBillFormSheet(context, existing: bill);
                          }
                        case 'delete':
                          if (bill != null) _deleteBill(bill);
                      }
                    },
                    itemBuilder: (context) => [
                      menuItem(
                        value: 'occurrence',
                        label: 'Change just this one',
                        icon: Icons.edit_calendar,
                        color: appPrimaryBlue,
                      ),
                      if (bill != null) ...[
                        menuItem(
                          value: 'schedule',
                          label: 'Edit the schedule',
                          icon: Icons.edit,
                          color: appPrimaryBlue,
                        ),
                        menuItem(
                          value: 'delete',
                          label: 'Delete this bill',
                          icon: Icons.delete_outline,
                          color: dangerColorOn(context),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
              body: ListView(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 40),
                children: [
                  _BillHeader(
                    instance: instance,
                    recurrence: bill?.recurrence,
                    today: widget.today,
                  ),
                  const SizedBox(height: 20),
                  _BillActions(
                    instance: instance,
                    onPayFull: () => _pay(instance, inFull: true),
                    onPayPartial: () => _pay(instance, inFull: false),
                    onUndo: () => _undoPayments(instance),
                    onSkip: () => BillService.skipInstance(instance.id),
                    onUnskip: () => BillService.unskipInstance(instance.id),
                  ),
                  if (instance.paymentIds.isNotEmpty) ...[
                    const SizedBox(height: 24),
                    Text(
                      'Payments',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: context.appColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 10),
                    StreamBuilder<List<Wallet>>(
                      stream: _wallets,
                      builder: (context, walletSnapshot) =>
                          FutureBuilder<List<AppTransaction>>(
                            key: ValueKey(_paymentsKey),
                            future: _payments(instance),
                            builder: (context, paymentsSnapshot) =>
                                _PaymentBreakdown(
                                  payments: paymentsSnapshot.data ?? const [],
                                  wallets:
                                      walletSnapshot.data ?? const <Wallet>[],
                                  onUndo: (payment, walletName) =>
                                      _undoOnePayment(
                                        instance,
                                        payment,
                                        walletName,
                                      ),
                                ),
                          ),
                    ),
                  ],
                  const SizedBox(height: 24),
                  Text(
                    'Past cycles',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: context.appColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 10),
                  StreamBuilder<List<BillInstance>>(
                    stream: _history,
                    builder: (context, historySnapshot) => _BillHistory(
                      instances: historySnapshot.data ?? const [],
                      currentId: instance.id,
                      today: widget.today,
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  static Bill? _billFor(List<Bill>? bills, String billId) {
    if (bills == null) return null;

    for (final bill in bills) {
      if (bill.id == billId) return bill;
    }

    return null;
  }
}

class _BillHeader extends StatelessWidget {
  const _BillHeader({
    required this.instance,
    required this.recurrence,
    required this.today,
  });

  final BillInstance instance;
  final BillRecurrence? recurrence;
  final DateTime? today;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final progress = instance.amount > 0
        ? (instance.amountPaid / instance.amount).clamp(0.0, 1.0).toDouble()
        : 0.0;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: colors.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 46,
                height: 46,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: colors.primaryTint,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: CategoryIcon(instance.category, size: 24),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      instance.category,
                      style: const TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Due ${formatShortDate(instance.dueDate)}',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: colors.textPrimary,
                      ),
                    ),
                  ],
                ),
              ),
              BillStatusBadge(instance: instance, now: today),
            ],
          ),
          const SizedBox(height: 18),
          MoneyText(
            instance.amount,
            style: TextStyle(
              fontSize: 30,
              fontWeight: FontWeight.bold,
              color: colors.textPrimary,
            ),
          ),
          if (recurrence != null) ...[
            const SizedBox(height: 4),
            Text(
              recurrence!.explanation,
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],
          if (instance.carriedOver > 0) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: colors.primaryTint,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                'Includes ${_peso(instance.carriedOver)} left unpaid from the '
                'cycle before.',
                style: TextStyle(fontSize: 12, color: colors.textBody),
              ),
            ),
          ],
          if (instance.amountPaid > 0) ...[
            const SizedBox(height: 16),
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                value: progress,
                minHeight: 8,
                backgroundColor: colors.track,
                valueColor: const AlwaysStoppedAnimation(Colors.green),
              ),
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Paid ${_peso(instance.amountPaid)}',
                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                ),
                Text(
                  instance.remaining > 0
                      ? '${_peso(instance.remaining)} to go'
                      : 'Fully paid',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: instance.remaining > 0
                        ? colors.textPrimary
                        : Colors.green,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  static String _peso(double amount) => '₱${amount.toStringAsFixed(2)}';
}

class _BillActions extends StatelessWidget {
  const _BillActions({
    required this.instance,
    required this.onPayFull,
    required this.onPayPartial,
    required this.onUndo,
    required this.onSkip,
    required this.onUnskip,
  });

  final BillInstance instance;
  final VoidCallback onPayFull;
  final VoidCallback onPayPartial;
  final VoidCallback onUndo;
  final VoidCallback onSkip;
  final VoidCallback onUnskip;

  @override
  Widget build(BuildContext context) {
    if (instance.status == BillStatus.skipped) {
      return OutlinedButton.icon(
        onPressed: onUnskip,
        icon: const Icon(Icons.undo),
        label: const Text('Put this bill back'),
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(double.infinity, 48),
        ),
      );
    }

    return Column(
      children: [
        if (instance.remaining > 0) ...[
          SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton.icon(
              onPressed: onPayFull,
              icon: const Icon(Icons.check),
              label: const Text(
                'Mark as Paid',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              style: confirmButtonStyle(),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: onPayPartial,
                  style: openOutlineStyle(context),
                  child: const Text('Pay part of it'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton(
                  onPressed: onSkip,
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(0, 46),
                    foregroundColor: Colors.grey,
                  ),
                  child: const Text('Skip this one'),
                ),
              ),
            ],
          ),
        ],
        if (instance.amountPaid > 0) ...[
          if (instance.remaining > 0) const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: onUndo,
            icon: const Icon(Icons.undo, size: 18),
            label: const Text('Undo payment'),
            style: dangerOutlineStyle(context).copyWith(
              minimumSize: const WidgetStatePropertyAll(
                Size(double.infinity, 46),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _BillHistory extends StatelessWidget {
  const _BillHistory({
    required this.instances,
    required this.currentId,
    required this.today,
  });

  final List<BillInstance> instances;
  final String currentId;
  final DateTime? today;

  @override
  Widget build(BuildContext context) {
    final others = instances
        .where((instance) => instance.id != currentId)
        .toList();

    if (others.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 12),
        child: Text(
          'This is the only cycle so far.',
          style: TextStyle(color: Colors.grey, fontSize: 13),
        ),
      );
    }

    final colors = context.appColors;

    return Column(
      children: [
        for (final instance in others) ...[
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: colors.card,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: colors.border),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        formatShortDate(instance.dueDate),
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: colors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 5),
                      BillStatusBadge(instance: instance, now: today),
                    ],
                  ),
                ),
                MoneyText(
                  instance.amount,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: colors.textPrimary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
        ],
      ],
    );
  }
}

/// Each payment made against a bill: how much, from which wallet, and when.
///
/// A bill can be settled from more than one wallet — part in cash today, the
/// rest by GCash tomorrow — so this lists them separately rather than showing
/// one lump sum that hides where the money came from.
class _PaymentBreakdown extends StatelessWidget {
  const _PaymentBreakdown({
    required this.payments,
    required this.wallets,
    required this.onUndo,
  });

  final List<AppTransaction> payments;
  final List<Wallet> wallets;
  final void Function(AppTransaction payment, String walletName) onUndo;

  String _walletName(String? walletId) {
    for (final wallet in wallets) {
      if (wallet.id == walletId) return wallet.name;
    }
    return 'a wallet';
  }

  @override
  Widget build(BuildContext context) {
    if (payments.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 12),
        child: Text(
          'Loading payments...',
          style: TextStyle(color: Colors.grey, fontSize: 13),
        ),
      );
    }

    final colors = context.appColors;

    return Column(
      children: [
        for (final payment in payments) ...[
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: colors.card,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: colors.border),
            ),
            child: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: Colors.green.withValues(alpha: 0.13),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.check, size: 18, color: Colors.green),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'From ${_walletName(payment.walletId)}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: colors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        formatShortDate(payment.date),
                        style: const TextStyle(
                          fontSize: 11,
                          color: Colors.grey,
                        ),
                      ),
                    ],
                  ),
                ),
                MoneyText(
                  payment.amount,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: colors.textPrimary,
                  ),
                ),
                IconButton(
                  tooltip: 'Undo this payment',
                  color: dangerColorOn(context),
                  icon: const Icon(Icons.close, size: 18),
                  onPressed: () =>
                      onUndo(payment, _walletName(payment.walletId)),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
        ],
      ],
    );
  }
}
