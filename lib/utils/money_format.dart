/// Formats an amount as Philippine Peso, e.g. `₱12,500` or `₱12,500.50`.
///
/// Centavos only show when there are some, so whole amounts read cleanly.
/// Negative amounts render as `-₱12,500`. Pass [sign] (`'+'` or `'-'`) to
/// force a prefix for income/expense rows; the absolute value is used then.
/// When [masked] is true the digits are replaced with asterisks.
String formatPeso(double amount, {String? sign, bool masked = false}) {
  final cents = (amount.abs() * 100).round();
  final prefix = sign ?? (amount < 0 && cents > 0 ? '-' : '');

  if (masked) {
    return '$prefix₱*****';
  }

  final integerPart = (cents ~/ 100).toString().replaceAllMapped(
    RegExp(r'\B(?=(\d{3})+(?!\d))'),
    (match) => ',',
  );
  final centavos = cents % 100;

  return centavos == 0
      ? '$prefix₱$integerPart'
      : '$prefix₱$integerPart.${centavos.toString().padLeft(2, '0')}';
}

/// An amount as it should start out in a text field: `20000` or `150.50`,
/// with no peso sign or commas so it can be edited and read back.
String formatAmountInput(double amount) {
  final cents = (amount * 100).round();
  return cents % 100 == 0
      ? (cents ~/ 100).toString()
      : (cents / 100).toStringAsFixed(2);
}

/// A short amount for chart axes: `₱950`, `₱1.5k`, `₱20k`, `₱1.25M`.
String formatPesoCompact(double amount) {
  final sign = amount < 0 ? '-' : '';
  final value = amount.abs();

  String trim(double number, int decimals) {
    var text = number.toStringAsFixed(decimals);
    if (text.contains('.')) {
      text = text
          .replaceFirst(RegExp(r'0+$'), '')
          .replaceFirst(RegExp(r'\.$'), '');
    }
    return text;
  }

  // Thresholds sit where rounding would otherwise print ₱1000k.
  if (value >= 999950) return '$sign₱${trim(value / 1000000, 2)}M';
  if (value >= 999.5) return '$sign₱${trim(value / 1000, 1)}k';
  return '$sign₱${trim(value, 0)}';
}
