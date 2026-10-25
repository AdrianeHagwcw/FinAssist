import 'package:flutter/material.dart';

import '../utils/amount_input_formatter.dart';
import '../models/bill.dart';
import '../models/wallet.dart';
import 'transfer_sheet.dart';
import '../services/bill_service.dart';
import '../services/wallet_service.dart';
import '../theme/app_colors.dart';
import '../theme/app_buttons.dart';
import '../utils/money_format.dart';
import 'check_after_save.dart';
import 'dialog_kit.dart';
import 'money_text.dart';
import 'service_charge_field.dart';

/// Records a payment against a bill. Returns true when one was made.
///
/// [payInFull] only decides what the amount box starts at: the whole balance
/// for "Mark as Paid", empty for "Pay part of it". Either way the user can
/// change it, so there is one form to understand rather than two.
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

class BillPaymentSheet extends StatefulWidget {
  const BillPaymentSheet({
    required this.instance,
    this.payInFull = true,
    this.wallets,
    this.onPay,
    super.key,
  });

  final BillInstance instance;
  final bool payInFull;

  /// Replaces the live wallet list. Used by tests, which can't load Firebase.
  final Stream<List<Wallet>>? wallets;

  /// Records the payment. Tests pass a fake instead of Firestore.
  final void Function({
    required String walletId,
    required double amount,
    required double serviceCharge,
  })?
  onPay;

  @override
  State<BillPaymentSheet> createState() => _BillPaymentSheetState();
}

/// Shown in place of the form when there is no bills wallet yet.
class _NothingSetAside extends StatelessWidget {
  const _NothingSetAside({required this.onMove, required this.message});

  final VoidCallback onMove;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          message,
          style: TextStyle(fontSize: 14, color: context.appColors.textMuted),
        ),
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: onMove,
            icon: const Icon(Icons.swap_horiz, size: 18),
            label: const Text('Move money to Bills'),
            style: openOutlineStyle(context),
          ),
        ),
      ],
    );
  }
}

/// What the bills wallet holds, so the user can see what a payment has to
/// fit inside before typing an amount.
class _HeldForBills extends StatelessWidget {
  const _HeldForBills({required this.amount});

  final double amount;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colors.primaryTint,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Image.asset(
            'assets/icons/icons8-receipt-96.png',
            width: 22,
            height: 22,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Set aside for bills',
              style: TextStyle(fontSize: 13, color: colors.textBody),
            ),
          ),
          MoneyText(
            amount,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.bold,
              color: colors.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}

class _BillPaymentSheetState extends State<BillPaymentSheet>
    with CheckAfterSave {
  final _formKey = GlobalKey<FormState>();

  late final _amountController = TextEditingController(
    text: widget.payInFull ? formatAmountInput(widget.instance.remaining) : '',
  );

  late final Stream<List<Wallet>> _wallets =
      widget.wallets ?? WalletService.watchWallets();

  /// Whether the bank, e-wallet or biller charged for paying, and how much.
  bool _charged = false;
  final _chargeController = TextEditingController();

  double get _charge =>
      ServiceChargeField.amountOf(on: _charged, controller: _chargeController);

  @override
  void dispose() {
    _amountController.dispose();
    _chargeController.dispose();
    super.dispose();
  }

  /// Opens the transfer sheet so the user can put money into their bills
  /// wallet without losing the payment they were in the middle of.
  Future<void> _moveToBills(List<Wallet> wallets) async {
    final bills = WalletService.walletFor(wallets, WalletPurpose.bills);
    await showTransferSheet(context, toWalletId: bills?.id);
  }

  void _pay(Wallet? billsWallet) {
    final walletId = billsWallet?.id;
    if (walletId == null || !checkForm(_formKey)) return;

    final amount = double.parse(
      _amountController.text.trim().replaceAll(',', ''),
    );
    final charge = _charge;

    final pay =
        widget.onPay ??
        ({
          required String walletId,
          required double amount,
          required double serviceCharge,
        }) => BillService.payInstance(
          instance: widget.instance,
          walletId: walletId,
          amount: amount,
          serviceCharge: serviceCharge,
        );

    pay(walletId: walletId, amount: amount, serviceCharge: charge);

    // The same charge is filled in next time.
    if (widget.onPay == null &&
        charge > 0 &&
        billsWallet!.serviceCharge != charge) {
      WalletService.rememberServiceCharge(walletId, charge);
    }
    Navigator.pop(context, true);
  }

  /// [held] is what the bills wallet has now, so the message goes as soon
  /// as the amount is lowered or money is moved across.
  String? _validateAmount(String? value, {required double held}) {
    final amount = double.tryParse((value ?? '').trim().replaceAll(',', ''));

    if (amount == null || !isRecordableAmount(amount)) {
      return minimumAmountError;
    }

    if (amount > widget.instance.remaining + 0.005) {
      return 'This bill only needs '
          '${formatPeso(widget.instance.remaining)}.';
    }

    // The service charge comes out of the Bills wallet too.
    final total = amount + _charge;
    if (total > held + 0.005) {
      return 'Your Bills wallet is ${formatPeso(total - held)} short'
          '${_charge > 0 ? ' with the service charge' : ''}. Move money '
          'across, or pay part of it.';
    }

    return null;
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

              // Bills are paid out of the money set aside for them, and
              // nowhere else, so spending money is never quietly used up by a
              // bill the user thought was already covered.
              final billsWallet = WalletService.walletFor(
                wallets,
                WalletPurpose.bills,
              );
              final held = billsWallet?.balance ?? 0;

              return Form(
                key: _formKey,
                autovalidateMode: checkMode,
                child: Column(
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
                      '${formatPeso(instance.remaining)} still owing',
                      style: TextStyle(
                        fontSize: 13,
                        color: context.appColors.textMuted,
                      ),
                    ),
                    const SizedBox(height: 20),
                    if (billsWallet == null)
                      _NothingSetAside(
                        onMove: () => _moveToBills(wallets),
                        message:
                            'You have not set money aside for bills yet. Move '
                            'some into a Bills wallet first, then pay from '
                            'there.',
                      )
                    else ...[
                      _HeldForBills(amount: held),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _amountController,
                        autofocus: true,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        inputFormatters: const [ThousandsSeparatorFormatter()],
                        decoration: dialogFieldDecoration(
                          context,
                          'Paying now',
                          helper:
                              'Pay less than this to record a part payment.',
                        ).copyWith(prefixText: '₱ ', hintText: '0.00'),
                        validator: (value) =>
                            _validateAmount(value, held: held),
                      ),
                      const SizedBox(height: 8),
                      ServiceChargeField(
                        on: _charged,
                        controller: _chargeController,
                        onChanged: (on) => setState(() {
                          _charged = on;
                          // What the Bills wallet was charged last time.
                          final last = billsWallet.serviceCharge;
                          if (on &&
                              last != null &&
                              _chargeController.text.trim().isEmpty) {
                            _chargeController.text = formatAmountInput(last);
                          }
                        }),
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        height: 52,
                        child: ElevatedButton(
                          onPressed: () => _pay(billsWallet),
                          style: confirmButtonStyle(),
                          child: const Text(
                            'Record Payment',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        'This records the payment and takes the money out of '
                        'your Bills wallet. It does not pay anyone for real.',
                        style: TextStyle(
                          fontSize: 12,
                          color: context.appColors.textMuted,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Center(
                        child: TextButton(
                          onPressed: () => _moveToBills(wallets),
                          child: const Text('Move money to Bills'),
                        ),
                      ),
                    ],
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}
