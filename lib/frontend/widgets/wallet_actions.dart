import 'package:material_ui/material_ui.dart';

import '../../backend/models/wallet.dart';
import '../../backend/services/wallet_service.dart';
import '../../backend/utils/unique_name.dart';
import '../../backend/utils/text_limits.dart';
import 'wallet_form_sheet.dart';
import 'dialog_kit.dart';

/// Wallet actions shared by the wallets list and the wallet detail screen, so
/// both offer the same wording and the same confirmation.

/// Opens the edit sheet and saves the change. Does nothing if the user backs
/// out.
Future<void> editWallet(BuildContext context, Wallet wallet) async {
  final draft = await showWalletFormSheet(context, existing: wallet);

  if (draft == null) return;

  // A new name already used by another wallet gets the next number.
  var name = draft.name;
  if (name != wallet.name) {
    final others = await WalletService.loadWallets();
    name = uniqueName(name, [
      for (final other in others)
        if (other.id != wallet.id && !other.archived) other.name,
    ], maxLength: maxSavedWalletNameLength);
  }

  WalletService.updateWallet(
    walletId: wallet.id,
    name: name,
    type: draft.type,
    updateAnnualInterestRate: true,
    annualInterestRatePercent: draft.annualInterestRatePercent,
  );
}

/// Asks before hiding a wallet, then archives it. Returns whether it was
/// removed, so a screen showing that wallet can close itself.
Future<bool> removeWallet(BuildContext context, Wallet wallet) async {
  final confirmed = await confirmDestructive(
    context,
    title: 'Remove ${wallet.name}?',
    message:
        'It will be hidden from your wallets and left out of your total. '
        'Its past transactions are kept, so your history stays complete.',
    action: 'Remove',
  );

  if (!confirmed) return false;

  WalletService.archiveWallet(wallet.id);
  return true;
}
