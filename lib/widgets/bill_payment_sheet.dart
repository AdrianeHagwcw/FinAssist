import 'package:flutter/material.dart';

import '../models/bill.dart';
import '../models/wallet.dart';
import '../services/bill_service.dart';
import '../services/wallet_service.dart';
import '../theme/app_colors.dart';
import '../theme/app_buttons.dart';
import '../utils/money_format.dart';
import 'dialog_kit.dart';
import 'wallet_picker.dart';

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
  final void Function({required String walletId, required double amount})?
  onPay;

  @override
  State<BillPaymentSheet> createState() => _BillPaymentSheetState();
}

class _BillPaymentSheetState extends State<BillPaymentSheet> {
  final _formKey = GlobalKey<FormState>();

  late final _amountController = TextEditingController(
    text: widget.payInFull ? widget.instance.remaining.toStringAsFixed(2) : '',
  );

  late final Stream<List<Wallet>> _wallets =
      widget.wallets ?? WalletService.watchWallets();

  String? _walletId;

  @override
  void initState() {
    super.initState();
    _walletId = widget.instance.walletId;
  }

  @override
  void dispose() {
    _amountController.dispose();
    super.dispose();
  }

  void _pay(String? walletId) {
    if (walletId == null || !_formKey.currentState!.validate()) return;

    final amount = double.parse(
      _amountController.text.trim().replaceAll(',', ''),
    );

    final pay =
        widget.onPay ??
        ({required String walletId, required double amount}) =>
            BillService.payInstance(
              instance: widget.instance,
              walletId: walletId,
              amount: amount,
            );

    pay(walletId: walletId, amount: amount);
    Navigator.pop(context, true);
  }

  String? _validateAmount(String? value) {
    final amount = double.tryParse((value ?? '').trim().replaceAll(',', ''));

    if (amount == null || amount <= 0) return 'Enter how much you are paying.';

    if (amount > widget.instance.remaining + 0.005) {
      return 'This bill only needs '
          '${formatPeso(widget.instance.remaining)}.';
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

              final walletId = _walletId ?? defaultWalletId(wallets);

              return Form(
                key: _formKey,
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
                      style: const TextStyle(fontSize: 13, color: Colors.grey),
                    ),
                    const SizedBox(height: 20),
                    if (wallets.isEmpty)
                      const Text(
                        'Add a wallet first, so the payment comes out of '
                        'somewhere.',
                        style: TextStyle(fontSize: 14, color: Colors.grey),
                      )
                    else ...[
                      TextFormField(
                        controller: _amountController,
                        autofocus: true,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        style: const TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                        ),
                        decoration: dialogFieldDecoration(
                          context,
                          'Paying now',
                          helper:
                              'Pay less than this to record a part payment.',
                        ).copyWith(prefixText: '₱ ', hintText: '0.00'),
                        validator: _validateAmount,
                      ),
                      const SizedBox(height: 16),
                      WalletPicker(
                        wallets: wallets,
                        selectedId: walletId,
                        label: 'Paid from',
                        onChanged: (value) => setState(() => _walletId = value),
                      ),
                      const SizedBox(height: 20),
                      SizedBox(
                        width: double.infinity,
                        height: 52,
                        child: ElevatedButton(
                          onPressed: () => _pay(walletId),
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
                      const Text(
                        'This records the payment and takes the money out of '
                        'that wallet. It does not pay anyone for real.',
                        style: TextStyle(fontSize: 12, color: Colors.grey),
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
