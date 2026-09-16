import 'package:flutter/material.dart';

import '../models/wallet.dart';
import '../services/wallet_service.dart';
import '../theme/app_buttons.dart';
import 'wallet_form_sheet.dart';

/// Wallet actions shared by the wallets list and the wallet detail screen, so
/// both offer the same wording and the same confirmation.

/// Opens the edit sheet and saves the change. Does nothing if the user backs
/// out.
Future<void> editWallet(BuildContext context, Wallet wallet) async {
  final draft = await showWalletFormSheet(context, existing: wallet);

  if (draft == null) return;

  WalletService.updateWallet(
    walletId: wallet.id,
    name: draft.name,
    type: draft.type,
  );
}

/// Asks before hiding a wallet, then archives it. Returns whether it was
/// removed, so a screen showing that wallet can close itself.
Future<bool> removeWallet(BuildContext context, Wallet wallet) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text('Remove ${wallet.name}?'),
      content: const Text(
        'It will be hidden from your wallets and left out of your total. '
        'Its past transactions are kept, so your history stays complete.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          style: cancelTextStyle(context),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, true),
          style: dangerTextStyle(context),
          child: const Text('Remove'),
        ),
      ],
    ),
  );

  if (confirmed != true) return false;

  WalletService.archiveWallet(wallet.id);
  return true;
}
