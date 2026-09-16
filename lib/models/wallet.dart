import 'package:flutter/material.dart';

/// Kind of money holder. Decides the wallet's icon and default name.
enum WalletType {
  cash('Cash', Icons.payments_outlined),
  gcash('GCash', Icons.phone_android),
  maya('Maya', Icons.account_balance_wallet_outlined),
  bank('Bank', Icons.account_balance_outlined),
  other('Other', Icons.savings_outlined);

  const WalletType(this.label, this.icon);

  final String label;
  final IconData icon;

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
