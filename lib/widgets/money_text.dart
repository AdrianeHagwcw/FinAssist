import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/app_settings_provider.dart';
import '../utils/money_format.dart';

/// Displays a peso amount and respects the app-wide privacy mask.
class MoneyText extends StatelessWidget {
  const MoneyText(
    this.amount, {
    this.sign,
    this.style,
    this.textAlign,
    this.maxLines,
    this.overflow,
    super.key,
  });

  final double amount;
  final String? sign;
  final TextStyle? style;
  final TextAlign? textAlign;
  final int? maxLines;
  final TextOverflow? overflow;

  @override
  Widget build(BuildContext context) {
    final masked = context.select<AppSettingsProvider, bool>(
      (settings) => settings.amountsMasked,
    );

    return Text(
      formatPeso(amount, sign: sign, masked: masked),
      style: style,
      textAlign: textAlign,
      maxLines: maxLines,
      overflow: overflow,
    );
  }
}
