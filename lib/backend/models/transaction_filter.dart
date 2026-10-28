import 'app_transaction.dart';
import 'transfer_direction.dart';
import 'wallet.dart';

/// What the Transactions list is narrowed to. Every field left null means
/// "any", so the default filter shows everything.
class TransactionFilter {
  const TransactionFilter({
    this.walletId,
    this.type,
    this.direction,
    this.category,
    this.query,
    this.from,
    this.to,
  });

  final String? walletId;
  final TransactionType? type;

  /// A transfer narrowed to one direction, such as a withdrawal from a bank
  /// into cash in hand. Null means any transfer, including one whose wallets
  /// make it a plain transfer.
  final TransferDirection? direction;

  /// Matched against a transaction's label, which is the category for an
  /// expense and the source for an income.
  final String? category;

  /// Matches a transaction's category/source, note, or type label. A
  /// transfer also matches the word its history row shows, such as
  /// "Withdrawal" or "Deposit", when [wallets] is given so its two kinds can
  /// be read.
  final String? query;

  /// First day included.
  final DateTime? from;

  /// Last day included.
  final DateTime? to;

  bool get isEmpty =>
      walletId == null &&
      type == null &&
      direction == null &&
      category == null &&
      (query == null || query!.trim().isEmpty) &&
      from == null &&
      to == null;

  /// How many things are being filtered on, for the badge on the filter icon.
  /// The type and its direction count as one choice, since a direction
  /// already means a transfer.
  int get activeCount =>
      (type != null || direction != null ? 1 : 0) +
      [
        walletId,
        category,
        query == null || query!.trim().isEmpty ? null : query,
        from ?? to,
      ].where((value) => value != null).length;

  /// Whether [transaction] passes every part of this filter.
  ///
  /// [wallets] is only needed for a search by a transfer's direction word.
  /// Without it the search still matches the stored type, "Transfer".
  bool matches(AppTransaction transaction, {List<Wallet> wallets = const []}) {
    if (walletId != null && !transaction.involvesWallet(walletId!)) {
      return false;
    }

    if (type != null && transaction.type != type) return false;

    if (direction != null) {
      if (transaction.type != TransactionType.transfer) return false;
      final actual = TransferDirection.between(
        from: _walletType(wallets, transaction.walletId),
        to: _walletType(wallets, transaction.toWalletId),
      );
      if (actual != direction) return false;
    }

    if (category != null &&
        transaction.label.toLowerCase() != category!.toLowerCase()) {
      return false;
    }

    final search = query?.trim().toLowerCase();
    if (search != null &&
        search.isNotEmpty &&
        ![
          transaction.label,
          transaction.note ?? '',
          transaction.type.label,
          transaction.type.flowLabel,
          if (transaction.type == TransactionType.transfer)
            TransferDirection.between(
              from: _walletType(wallets, transaction.walletId),
              to: _walletType(wallets, transaction.toWalletId),
            ).label,
        ].any((value) => value.toLowerCase().contains(search))) {
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
    TransferDirection? Function()? direction,
    String? Function()? category,
    String? Function()? query,
    DateTime? Function()? from,
    DateTime? Function()? to,
  }) {
    return TransactionFilter(
      walletId: walletId == null ? this.walletId : walletId(),
      type: type == null ? this.type : type(),
      direction: direction == null ? this.direction : direction(),
      category: category == null ? this.category : category(),
      query: query == null ? this.query : query(),
      from: from == null ? this.from : from(),
      to: to == null ? this.to : to(),
    );
  }

  static DateTime _dateOnly(DateTime date) =>
      DateTime(date.year, date.month, date.day);

  static WalletType? _walletType(List<Wallet> wallets, String? id) {
    for (final wallet in wallets) {
      if (wallet.id == id) return wallet.type;
    }
    return null;
  }
}

/// Money in and money out for a set of transactions. Transfers are left out
/// of both: moving money between your own wallets is neither. So is money
/// borrowed, lent or repaid, which isn't earning or spending.
({double moneyIn, double moneyOut}) inAndOut(
  Iterable<AppTransaction> transactions,
) {
  var moneyIn = 0.0;
  var moneyOut = 0.0;

  for (final transaction in transactions) {
    if (transaction.isDebtMovement) continue;

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

/// Money lent out, borrowed, or paid back, which [inAndOut] leaves out.
({double moneyIn, double moneyOut}) loanMovements(
  Iterable<AppTransaction> transactions,
) {
  var moneyIn = 0.0;
  var moneyOut = 0.0;

  for (final transaction in transactions) {
    if (!transaction.isDebtMovement) continue;

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
///
/// Like [inAndOut], money lent out isn't spending: it is expected back.
List<MapEntry<String, double>> spendingByCategory(
  Iterable<AppTransaction> transactions,
) {
  final totals = <String, double>{};

  for (final transaction in transactions) {
    if (transaction.type != TransactionType.expense) continue;
    if (transaction.isDebtMovement) continue;
    // An installment payment counts its interest apart.
    for (final part in transaction.spendingParts) {
      totals[part.key] = (totals[part.key] ?? 0) + part.value;
    }
  }

  return totals.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
}
