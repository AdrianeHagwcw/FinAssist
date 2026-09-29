import 'package:flutter/material.dart';

import '../models/wallet.dart';
import '../utils/money_format.dart';
import 'dialog_kit.dart';

/// The wallet a new entry should start on: the one that receives income,
/// otherwise the first in the list. Null when there are no wallets yet.
String? defaultWalletId(List<Wallet> wallets) {
  if (wallets.isEmpty) return null;

  // Never the bills or savings wallet: an entry starts on money the user can
  // actually spend, and set-aside money is only moved on purpose.
  final spending = wallets.where((wallet) => !wallet.isSetAside).toList();
  if (spending.isEmpty) return wallets.first.id;

  return incomeWallet(spending)?.id ?? spending.first.id;
}

/// Dropdown for choosing which wallet money moves in or out of.
///
/// The caller owns the selection, so the same picker works inside a form, a
/// dialog or a sheet.
class WalletPicker extends StatelessWidget {
  const WalletPicker({
    required this.wallets,
    required this.selectedId,
    required this.onChanged,
    this.label = 'Wallet',
    this.excludeId,
    this.allowed = const {WalletPurpose.spending},
    super.key,
  });

  final List<Wallet> wallets;
  final String? selectedId;
  final ValueChanged<String?> onChanged;
  final String label;

  /// Wallet to leave out, so a transfer can't pick the same one twice.
  final String? excludeId;

  /// Which kinds of wallet may be chosen. Spending money only by default:
  /// the bills and savings wallets hold money that is already promised, so
  /// they are offered only where spending them is the point, such as paying a
  /// bill, or moving money on purpose with a transfer.
  final Set<WalletPurpose> allowed;

  @override
  Widget build(BuildContext context) {
    final choices = wallets
        .where(
          (wallet) =>
              wallet.id != excludeId &&
              (allowed.contains(wallet.purpose) || wallet.id == selectedId),
        )
        .toList(growable: false);
    final value = choices.any((wallet) => wallet.id == selectedId)
        ? selectedId
        : null;

    return DropdownButtonFormField<String>(
      initialValue: value,
      isExpanded: true,
      decoration: dialogFieldDecoration(context, label),
      items: [
        for (final wallet in choices)
          DropdownMenuItem(
            value: wallet.id,
            child: Row(
              children: [
                Image.asset(wallet.iconAsset, width: 20, height: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    wallet.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  formatPeso(wallet.balance),
                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                ),
              ],
            ),
          ),
      ],
      onChanged: onChanged,
      validator: (selected) => selected == null ? 'Choose a wallet.' : null,
    );
  }
}
