import 'package:cloud_firestore/cloud_firestore.dart';

/// What a transaction does to the money in a wallet.
enum TransactionType {
  expense('Expense'),
  income('Income'),
  transfer('Transfer');

  const TransactionType(this.label);

  final String label;

  /// Reads a stored type name, falling back to [expense] for unknown values.
  static TransactionType fromName(String? name) {
    return TransactionType.values.firstWhere(
      (type) => type.name == name,
      orElse: () => TransactionType.expense,
    );
  }
}

/// One entry in `users/{uid}/transactions`: an expense, an income, or a
/// transfer between two wallets.
///
/// [amount] is always positive; the direction comes from [type]. Use
/// [balanceDeltaFor] rather than the raw amount when touching a balance.
class AppTransaction {
  const AppTransaction({
    required this.id,
    required this.type,
    required this.amount,
    required this.label,
    required this.date,
    this.walletId,
    this.toWalletId,
    this.note,
    this.isLegacy = false,
    this.billInstanceId,
    this.debtId,
  });

  /// Reads a stored transaction document.
  ///
  /// [label] also accepts the older `category` and `source` field names so
  /// records copied over from `expenses` and `dailyIncomeTransactions` are
  /// readable without being rewritten.
  factory AppTransaction.fromMap(String id, Map<String, dynamic>? data) {
    final map = data ?? const <String, dynamic>{};
    final type = TransactionType.fromName(_asString(map['type']));
    final label =
        _asString(map['label']) ??
        _asString(map['category']) ??
        _asString(map['source']) ??
        type.label;

    return AppTransaction(
      id: id,
      type: type,
      amount: _asDouble(map['amount']).abs(),
      label: label,
      date: _asDate(map['date']) ?? _asDate(map['createdAt']) ?? DateTime.now(),
      walletId: _asString(map['walletId']),
      toWalletId: _asString(map['toWalletId']),
      note: _asString(map['note']),
      isLegacy: map['legacy'] == true,
      billInstanceId: _asString(map['billInstanceId']),
      debtId: _asString(map['debtId']),
    );
  }

  final String id;
  final TransactionType type;

  /// Always positive. See [balanceDeltaFor] for the signed effect.
  final double amount;

  /// Category for an expense, source for an income, "Transfer" otherwise.
  final String label;
  final DateTime date;

  /// Wallet the money leaves (expense, transfer) or lands in (income).
  ///
  /// Null for records brought over from the old collections, which have no
  /// wallet and so must not change any balance.
  final String? walletId;

  /// Wallet the money lands in. Transfers only.
  final String? toWalletId;
  final String? note;

  /// True for records copied from the pre-wallet collections during the
  /// one-time migration. They are shown in history but never counted into a
  /// wallet balance, so nothing is double counted.
  final bool isLegacy;

  /// Set when this expense is a bill payment, naming the bill occurrence it
  /// paid. Bill payments are planned spending, so they are kept out of what
  /// the user spent "today", and undoing one has to update the bill too.
  final String? billInstanceId;

  bool get isBillPayment => billInstanceId != null;

  /// Set when money moved because of a loan: borrowed money arriving, money
  /// lent out, or a repayment coming back. That money is neither earnings nor
  /// everyday spending, so it is left out of both.
  final String? debtId;

  bool get isDebtMovement => debtId != null;

  /// How this transaction changes the balance of [walletId].
  double get sourceDelta {
    if (walletId == null) return 0;
    return type == TransactionType.income ? amount : -amount;
  }

  /// How this transaction changes the balance of [toWalletId].
  double get destinationDelta {
    if (toWalletId == null || type != TransactionType.transfer) return 0;
    return amount;
  }

  /// How this transaction changes the balance of the wallet [id].
  ///
  /// A transfer touches two wallets, so both sides are added: moving money to
  /// and from the same wallet nets out to zero.
  double balanceDeltaFor(String id) {
    var delta = 0.0;
    if (walletId == id) delta += sourceDelta;
    if (toWalletId == id) delta += destinationDelta;
    return delta;
  }

  /// Whether this transaction belongs in the history of the wallet [id].
  bool involvesWallet(String id) => walletId == id || toWalletId == id;

  static String? _asString(Object? value) {
    if (value is! String) return null;
    return value.isEmpty ? null : value;
  }

  static double _asDouble(Object? value) => value is num ? value.toDouble() : 0;

  static DateTime? _asDate(Object? value) {
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    return null;
  }
}

/// The transactions shown on one wallet's detail screen, newest first.
/// Transfers appear for both the wallet the money left and the one it
/// reached.
List<AppTransaction> transactionsForWallet(
  Iterable<AppTransaction> transactions,
  String walletId,
) {
  final matches = transactions
      .where((transaction) => transaction.involvesWallet(walletId))
      .toList();
  matches.sort((a, b) => b.date.compareTo(a.date));
  return matches;
}
