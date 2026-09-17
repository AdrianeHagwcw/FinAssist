import 'app_transaction.dart';

/// What the Transactions list is narrowed to. Every field left null means
/// "any", so the default filter shows everything.
class TransactionFilter {
  const TransactionFilter({
    this.walletId,
    this.type,
    this.category,
    this.from,
    this.to,
  });

  final String? walletId;
  final TransactionType? type;

  /// Matched against a transaction's label, which is the category for an
  /// expense and the source for an income.
  final String? category;

  /// First day included.
  final DateTime? from;

  /// Last day included.
  final DateTime? to;

  bool get isEmpty =>
      walletId == null &&
      type == null &&
      category == null &&
      from == null &&
      to == null;

  /// How many things are being filtered on, for the badge on the filter icon.
  int get activeCount => [
    walletId,
    type,
    category,
    from ?? to,
  ].where((value) => value != null).length;

  bool matches(AppTransaction transaction) {
    if (walletId != null && !transaction.involvesWallet(walletId!)) {
      return false;
    }

    if (type != null && transaction.type != type) return false;

    if (category != null &&
        transaction.label.toLowerCase() != category!.toLowerCase()) {
      return false;
    }

    final day = DateTime(
      transaction.date.year,
      transaction.date.month,
      transaction.date.day,
    );

    if (from != null && day.isBefore(_dateOnly(from!))) return false;
    if (to != null && day.isAfter(_dateOnly(to!))) return false;

    return true;
  }

  TransactionFilter copyWith({
    String? Function()? walletId,
    TransactionType? Function()? type,
    String? Function()? category,
    DateTime? Function()? from,
    DateTime? Function()? to,
  }) {
    return TransactionFilter(
      walletId: walletId == null ? this.walletId : walletId(),
      type: type == null ? this.type : type(),
      category: category == null ? this.category : category(),
      from: from == null ? this.from : from(),
      to: to == null ? this.to : to(),
    );
  }

  static DateTime _dateOnly(DateTime date) =>
      DateTime(date.year, date.month, date.day);
}

/// Money in and money out for a set of transactions. Transfers are left out
/// of both: moving money between your own wallets is neither.
({double moneyIn, double moneyOut}) inAndOut(
  Iterable<AppTransaction> transactions,
) {
  var moneyIn = 0.0;
  var moneyOut = 0.0;

  for (final transaction in transactions) {
    switch (transaction.type) {
      case TransactionType.income:
        moneyIn += transaction.amount;
      case TransactionType.expense:
        moneyOut += transaction.amount;
      case TransactionType.transfer:
        break;
    }
  }

  return (moneyIn: moneyIn, moneyOut: moneyOut);
}

/// Spending per category, largest first.
List<MapEntry<String, double>> spendingByCategory(
  Iterable<AppTransaction> transactions,
) {
  final totals = <String, double>{};

  for (final transaction in transactions) {
    if (transaction.type != TransactionType.expense) continue;
    totals[transaction.label] =
        (totals[transaction.label] ?? 0) + transaction.amount;
  }

  return totals.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
}
