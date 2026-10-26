import 'package:flutter/material.dart';

import '../models/bill.dart';
import '../models/goal.dart';
import '../models/wallet.dart';
import '../services/bill_service.dart';
import '../services/wallet_service.dart';
import '../theme/app_colors.dart';
import '../theme/app_buttons.dart';
import '../utils/date_format.dart';
import '../utils/money_format.dart';
import 'check_after_save.dart';
import 'wallet_picker.dart';
import 'wallet_split_picker.dart';

/// Records a payment against a bill. Returns true when one was made.
///
/// [payInFull] only decides whether the amount starts filled in with the
/// whole balance ("Mark as Paid") or empty ("Pay part of it"). Either way
/// the user can change it, so there is one form to understand rather than
/// two.
Future<bool> showBillPaymentSheet(
  BuildContext context, {
  required BillInstance instance,
  bool payInFull = true,
  Stream<List<Wallet>>? wallets,
}) async {
  final paid = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: context.appColors.card,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (context) => BillPaymentSheet(
      instance: instance,
      payInFull: payInFull,
      wallets: wallets,
    ),
  );

  return paid ?? false;
}

/// Pays a bill straight from the wallets the money is really in: cash on
/// hand, a bank, or some of each. Any bill can be paid early, and each
/// wallet can add the fee it was charged.
class BillPaymentSheet extends StatefulWidget {
  const BillPaymentSheet({
    required this.instance,
    this.payInFull = true,
    this.wallets,
    this.goals,
    this.onPay,
    super.key,
  });

  final BillInstance instance;
  final bool payInFull;

  /// Replaces the live wallet list. Used by tests, which can't load Firebase.
  final Stream<List<Wallet>>? wallets;

  /// Replaces the live goals, for what each wallet has free. Used by tests.
  final Stream<List<Goal>>? goals;

  /// Records the payment. Tests pass a fake instead of Firestore.
  final void Function(List<BillPaymentPart> parts)? onPay;

  @override
  State<BillPaymentSheet> createState() => _BillPaymentSheetState();
}

class _BillPaymentSheetState extends State<BillPaymentSheet>
    with CheckAfterSave, WatchesGoals {
  late final Stream<List<Wallet>> _wallets =
      widget.wallets ?? WalletService.watchWallets();

  /// What each wallet pays, and the fee each was charged, by wallet id.
  Map<String, double> _amounts = const {};
  Map<String, double> _fees = const {};

  double get _paying =>
      _amounts.values.fold<double>(0, (sum, amount) => sum + amount);
  double get _feesTotal =>
      _fees.values.fold<double>(0, (sum, fee) => sum + fee);

  @override
  void initState() {
    super.initState();
    watchGoals(given: widget.goals, walletsGiven: widget.wallets != null);
  }

  String? _problem(List<Wallet> wallets) => walletSplitProblem(
    purpose: SplitPurpose.paying,
    amounts: _amounts,
    fees: _fees,
    wallets: wallets,
    goals: heldGoals,
    target: widget.instance.remaining,
  );

  void _pay(List<Wallet> wallets) {
    markTriedToSave();
    if (_problem(wallets) != null) return;

    final parts = [
      for (final entry in _amounts.entries)
        BillPaymentPart(
          walletId: entry.key,
          amount: entry.value,
          serviceCharge: _fees[entry.key] ?? 0,
        ),
    ];
    final pay =
        widget.onPay ??
        (List<BillPaymentPart> parts) =>
            BillService.payInstance(instance: widget.instance, parts: parts);
    pay(parts);
    Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final instance = widget.instance;

    return Padding(
      // Keeps the form above the on-screen keyboard.
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
          child: StreamBuilder<List<Wallet>>(
            stream: _wallets,
            builder: (context, snapshot) {
              final wallets = snapshot.data;

              if (wallets == null) {
                return const SizedBox(
                  height: 160,
                  child: Center(child: CircularProgressIndicator()),
                );
              }

              final error = triedToSave ? _problem(wallets) : null;
              final total = _paying + _feesTotal;

              return Column(
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
                    'Pay ${instance.name}',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: colors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${formatPeso(instance.remaining)} still owing · due '
                    '${formatShortDate(instance.dueDate)}',
                    style: TextStyle(fontSize: 13, color: colors.textMuted),
                  ),
                  const SizedBox(height: 20),
                  WalletSplitPicker(
                    key: const ValueKey('bill-pay-from'),
                    wallets: wallets,
                    goals: heldGoals,
                    purpose: SplitPurpose.paying,
                    target: instance.remaining,
                    withFees: true,
                    // "Pay part of it" starts empty, for the amount to type.
                    prefill: widget.payInFull,
                    onChanged: (amounts) => setState(() => _amounts = amounts),
                    onFeesChanged: (fees) => setState(() => _fees = fees),
                  ),
                  if (error != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      error,
                      key: const Key('bill-pay-error'),
                      style: TextStyle(
                        color: dangerColorOn(context),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: ElevatedButton(
                      key: const Key('bill-pay-button'),
                      onPressed: () => _pay(wallets),
                      style: confirmButtonStyle(),
                      child: Text(
                        total > 0 ? 'Pay ${formatPeso(total)}' : 'Pay',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'This records the payment. It does not pay anyone for '
                    'real.',
                    style: TextStyle(fontSize: 12, color: colors.textMuted),
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
