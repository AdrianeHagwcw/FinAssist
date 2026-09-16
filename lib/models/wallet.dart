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
