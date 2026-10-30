import 'package:flutter/material.dart';

import '../utils/amount_input_formatter.dart';
import '../../backend/utils/money_format.dart';
import 'dialog_kit.dart';

/// An optional service charge on a transfer: what the bank or e-wallet
/// charged, left empty when there was none.
///
/// It is saved as a Service Charge expense of its own, so it shows with the
/// rest of the spending rather than inside the money moved.
class ServiceChargeField extends StatelessWidget {
  const ServiceChargeField({
    required this.controller,
    this.lastFee,
    super.key,
  });

  final TextEditingController controller;

  /// What this wallet charged on its last transfer, if it did.
  final double? lastFee;

  /// The charge as typed, or zero while it is blank or not an amount.
  static double amountOf(TextEditingController controller) {
    final amount = double.tryParse(controller.text.trim().replaceAll(',', ''));
    return amount != null && isRecordableAmount(amount) ? amount : 0;
  }

  @override
  Widget build(BuildContext context) {
    final hasLastFee = lastFee != null && lastFee! > 0;

    return TextFormField(
      key: const Key('service-charge-amount'),
      controller: controller,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: const [ThousandsSeparatorFormatter()],
      decoration: dialogFieldDecoration(
        context,
        'Service charge',
        helper: hasLastFee
            ? 'Last time this wallet charged ${formatPeso(lastFee!)}.'
            : 'If the bank or e-wallet charged a fee for this transfer.',
      ).copyWith(
        // The peso sign waits for the first digit, so the hint can't be
        // taken for an amount already filled in.
        prefixText: controller.text.isEmpty ? null : '₱ ',
        hintText: 'Optional',
        helperMaxLines: 2,
      ),
      validator: (value) {
        final text = (value ?? '').trim().replaceAll(',', '');
        if (text.isEmpty) return null;
        return isRecordableAmount(double.tryParse(text))
            ? null
            : minimumAmountError;
      },
    );
  }
}
