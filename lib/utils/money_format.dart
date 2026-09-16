/// Formats an amount as Philippine Peso, e.g. `₱12,500.00`.
///
/// Negative amounts render as `-₱12,500.00`. Pass [sign] (`'+'` or `'-'`) to
/// force a prefix for income/expense rows; the absolute value is used then.
/// When [masked] is true the digits are replaced with asterisks.
String formatPeso(double amount, {String? sign, bool masked = false}) {
  final prefix = sign ?? (amount < 0 ? '-' : '');

  if (masked) {
    return '$prefix₱*****';
  }

  final parts = amount.abs().toStringAsFixed(2).split('.');
  final integerPart = parts[0].replaceAllMapped(
    RegExp(r'\B(?=(\d{3})+(?!\d))'),
    (match) => ',',
  );

  return '$prefix₱$integerPart.${parts[1]}';
}
