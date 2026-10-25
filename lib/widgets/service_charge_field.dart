import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../utils/amount_input_formatter.dart';
import '../utils/money_format.dart';
import 'dialog_kit.dart';

/// An optional service charge on a transfer or a bill payment, the same on
/// both: off until the user says there was one, then its amount. A bank's
/// or e-wallet's fee is the same each time, so the screen fills in what the
/// wallet charged last.
///
/// It is saved as a Service Charge expense of its own, so it shows with the
/// rest of the spending rather than inside the money moved.
class ServiceChargeField extends StatelessWidget {
  const ServiceChargeField({
    required this.on,
    required this.controller,
    required this.onChanged,
    super.key,
  });

  final bool on;
  final TextEditingController controller;
  final ValueChanged<bool> onChanged;

  /// The charge as typed, or zero while it is off, blank or not an amount.
  static double amountOf({
    required bool on,
    required TextEditingController controller,
  }) {
    if (!on) return 0;
    final amount = double.tryParse(controller.text.trim().replaceAll(',', ''));
    return amount != null && isRecordableAmount(amount) ? amount : 0;
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SwitchListTile(
          key: const Key('service-charge-switch'),
          value: on,
          contentPadding: EdgeInsets.zero,
          title: const Text('Add a service charge'),
          subtitle: Text(
            'If the bank or e-wallet charged a fee. Optional.',
            style: TextStyle(fontSize: 12, color: colors.textMuted),
          ),
          onChanged: onChanged,
        ),
        if (on) ...[
          const SizedBox(height: 4),
          TextFormField(
            key: const Key('service-charge-amount'),
            controller: controller,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: const [ThousandsSeparatorFormatter()],
            decoration:
                dialogFieldDecoration(
                  context,
                  'Service charge',
                  helper:
                      'Saved as a Service Charge expense, and filled in for '
                      'this wallet next time.',
                ).copyWith(
                  prefixText: '₱ ',
                  hintText: 'e.g. 15',
                  helperMaxLines: 2,
                ),
            validator: (value) =>
                isRecordableAmount(
                  double.tryParse((value ?? '').trim().replaceAll(',', '')),
                )
                ? null
                : minimumAmountError,
          ),
        ],
      ],
    );
  }
}
