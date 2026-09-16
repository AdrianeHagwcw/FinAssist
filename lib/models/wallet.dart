/// Kind of money holder. Decides the wallet's icon and default name.
enum WalletType {
  cash('Cash', 'assets/icons/icons8-banknotes-96.png'),
  gcash('GCash', 'assets/icons/icons8-mobile-payment-96.png'),
  maya('Maya', 'assets/icons/icons8-wallet-96.png'),
  bank('Bank', 'assets/icons/icons8-bank-96.png'),
  other('Other', 'assets/icons/icons8-money-box-96.png');

  const WalletType(this.label, this.iconAsset);

  final String label;

  /// Colored icon file for this wallet type.
  final String iconAsset;

  /// Reads a stored type name, falling back to [other] for unknown values.
  static WalletType fromName(String? name) {
    return WalletType.values.firstWhere(
      (type) => type.name == name,
      orElse: () => WalletType.other,
    );
  }
}

/// A wallet the user is adding during onboarding, before it is saved.
class WalletDraft {
  const WalletDraft({
    required this.type,
    required this.name,
    required this.startingBalance,
    this.receivesIncome = false,
  });

  final WalletType type;

  /// Custom name such as "BPI Savings"; defaults to the type label.
  final String name;
  final double startingBalance;

  /// Whether the user's main income is paid into this wallet.
  final bool receivesIncome;

  WalletDraft copyWith({bool? receivesIncome}) {
    return WalletDraft(
      type: type,
      name: name,
      startingBalance: startingBalance,
      receivesIncome: receivesIncome ?? this.receivesIncome,
    );
  }
}

/// A saved wallet, as stored in `users/{uid}/wallets`.
class Wallet {
  const Wallet({
    required this.id,
    required this.name,
    required this.type,
    required this.balance,
    required this.startingBalance,
    required this.receivesIncome,
    required this.archived,
    required this.sortOrder,
  });

  /// Reads a stored wallet document.
  ///
  /// Every field falls back to a safe value, so one malformed record written
  /// by an older build can't break the whole wallet list.
  factory Wallet.fromMap(String id, Map<String, dynamic>? data) {
    final map = data ?? const <String, dynamic>{};
    final type = WalletType.fromName(_asString(map['type']));
    final name = _asString(map['name'])?.trim();

    return Wallet(
      id: id,
      name: name == null || name.isEmpty ? type.label : name,
      type: type,
      balance: _asDouble(map['balance']),
      startingBalance: _asDouble(map['startingBalance']),
      receivesIncome: map['receivesIncome'] == true,
      archived: map['archived'] == true,
      sortOrder: _asDouble(map['sortOrder']).toInt(),
    );
  }

  final String id;
  final String name;
  final WalletType type;

  /// Current money in this wallet, kept in step with its transactions.
  final double balance;

  /// What the wallet held when it was first added.
  final double startingBalance;

  /// Whether the user's main income is paid into this wallet.
  final bool receivesIncome;

  /// Archived wallets stay in Firestore so old transactions keep their name,
  /// but they are hidden from the wallet list and the total balance.
  final bool archived;

  /// Position in the wallet list, lowest first.
  final int sortOrder;

  String get iconAsset => type.iconAsset;

  static String? _asString(Object? value) => value is String ? value : null;

  static double _asDouble(Object? value) => value is num ? value.toDouble() : 0;
}

/// Orders wallets the way they are shown: by [Wallet.sortOrder], then by name
/// so wallets saved without an order still come out in a stable sequence.
void sortWallets(List<Wallet> wallets) {
  wallets.sort((a, b) {
    final byOrder = a.sortOrder.compareTo(b.sortOrder);
    return byOrder != 0
        ? byOrder
        : a.name.toLowerCase().compareTo(b.name.toLowerCase());
  });
}

/// Combined balance of every wallet that isn't archived.
double totalWalletBalance(Iterable<Wallet> wallets) {
  return wallets
      .where((wallet) => !wallet.archived)
      .fold<double>(0, (sum, wallet) => sum + wallet.balance);
}

/// The [Wallet.sortOrder] a newly added wallet should take.
int nextWalletSortOrder(Iterable<Wallet> wallets) {
  var highest = -1;
  for (final wallet in wallets) {
    if (wallet.sortOrder > highest) highest = wallet.sortOrder;
  }
  return highest + 1;
}

/// The wallet that receives the user's income, or null if none is marked.
Wallet? incomeWallet(Iterable<Wallet> wallets) {
  for (final wallet in wallets) {
    if (wallet.receivesIncome && !wallet.archived) return wallet;
  }
  return null;
}

/// Which wallets need their `receivesIncome` flag changed so that only
/// [selectedId] receives income. Wallets already correct are left out, so the
/// resulting write touches as few documents as possible.
Map<String, bool> incomeWalletUpdates(
  Iterable<Wallet> wallets,
  String selectedId,
) {
  final updates = <String, bool>{};
  for (final wallet in wallets) {
    final shouldReceive = wallet.id == selectedId;
    if (wallet.receivesIncome != shouldReceive) {
      updates[wallet.id] = shouldReceive;
    }
  }
  return updates;
}
