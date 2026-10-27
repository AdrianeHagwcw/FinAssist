import 'dart:async';

import '../theme/app_colors.dart';
import 'package:flutter/material.dart';

import '../models/goal.dart';
import '../models/wallet.dart';
import '../services/goal_service.dart';
import '../utils/money_format.dart';
import 'dialog_kit.dart';

/// The wallet a new entry should start on: the first spending wallet in
/// the list. Null when there are no wallets yet.
String? defaultWalletId(List<Wallet> wallets) {
  if (wallets.isEmpty) return null;

  // Never the bills or savings wallet: an entry starts on money the user can
  // actually spend, and set-aside money is only moved on purpose.
  final spending = wallets.where((wallet) => !wallet.isSetAside).toList();
  if (spending.isEmpty) return wallets.first.id;

  return spending.first.id;
}

/// Dropdown for choosing which wallet money moves in or out of.
///
/// The caller owns the selection, so the same picker works inside a form, a
/// dialog or a sheet.
class WalletPicker extends StatelessWidget {
  static const _addWalletValue = '__add_wallet__';

  const WalletPicker({
    required this.wallets,
    required this.selectedId,
    required this.onChanged,
    this.label = 'Wallet',
    this.excludeId,
    this.allowed = const {WalletPurpose.spending},
    this.disabledWalletIds = const {},
    this.disabledLabel,
    this.displayBalances,
    this.onAddWallet,
    this.errorText,
    this.helper,
    this.goals,
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

  /// Wallets that should remain visible but cannot be selected.
  final Set<String> disabledWalletIds;

  /// Shown instead of the balance on a wallet that cannot be chosen, such
  /// as "Added", so the reason is plain without trying it.
  final String? disabledLabel;

  /// Optional balances to show instead of the wallet's raw balance, such as
  /// money still free after existing goal claims are deducted.
  final Map<String, double>? displayBalances;
  final VoidCallback? onAddWallet;

  /// What is wrong with the choice, in red under it, for a screen that
  /// checks it itself rather than through a [Form].
  final String? errorText;

  /// A line under the picker, such as what its amounts mean.
  final String? helper;

  /// The goals, so each wallet shows what it has free to spend rather than
  /// what it holds: money set aside for a goal is not spending money. Null
  /// shows what each holds.
  final List<Goal>? goals;

  @override
  Widget build(BuildContext context) {
    final goals = this.goals;
    final shown =
        displayBalances ??
        (goals == null ? null : freeByWallet(wallets, goals));
    final note =
        helper ?? (goals == null ? null : goalMoneyNote(wallets, goals));
    final choices = wallets
        .where(
          (wallet) =>
              wallet.id != excludeId &&
              (allowed.contains(wallet.purpose) || wallet.id == selectedId),
        )
        .toList(growable: false);
    final value =
        choices.any(
          (wallet) =>
              wallet.id == selectedId && !disabledWalletIds.contains(wallet.id),
        )
        ? selectedId
        : null;

    return DropdownButtonFormField<String>(
      initialValue: value,
      isExpanded: true,
      decoration: dialogFieldDecoration(
        context,
        label,
        helper: note,
      ).copyWith(errorText: errorText, helperMaxLines: 2),
      items: [
        for (final wallet in choices)
          DropdownMenuItem(
            value: wallet.id,
            enabled: !disabledWalletIds.contains(wallet.id),
            // A wallet that cannot be chosen is dimmed, so it does not look
            // tappable.
            child: Opacity(
              opacity: disabledWalletIds.contains(wallet.id) ? 0.4 : 1,
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
                    disabledWalletIds.contains(wallet.id) &&
                            disabledLabel != null
                        ? disabledLabel!
                        : formatPeso(shown?[wallet.id] ?? wallet.balance),
                    style: TextStyle(
                      fontSize: 12,
                      color: context.appColors.textMuted,
                    ),
                  ),
                ],
              ),
            ),
          ),
        if (onAddWallet != null)
          const DropdownMenuItem(
            value: _addWalletValue,
            child: Row(
              children: [
                Icon(Icons.add, size: 20),
                SizedBox(width: 10),
                Text('Add wallet'),
              ],
            ),
          ),
      ],
      onChanged: (value) {
        if (value == _addWalletValue) {
          onAddWallet!();
          return;
        }
        onChanged(value);
      },
      validator: (selected) => selected == null ? 'Choose a wallet.' : null,
    );
  }
}

/// Keeps the goals at hand for a screen's wallet pickers and amounts, so
/// each wallet shows what it has free to spend: its balance less what goals
/// hold in it. The same rule on every screen, for every account.
mixin WatchesGoals<T extends StatefulWidget> on State<T> {
  /// Every goal, finished ones too: their money stays set aside until used.
  List<Goal> heldGoals = const [];
  StreamSubscription<List<Goal>>? _goalsSubscription;

  /// Starts listening: to [given] in tests, to none when a test hands in
  /// only its wallets, otherwise to the live goals.
  void watchGoals({Stream<List<Goal>>? given, required bool walletsGiven}) {
    _goalsSubscription =
        (given ??
                (walletsGiven
                    ? Stream.value(const <Goal>[])
                    : GoalService.watchGoals()))
            .listen((goals) {
              if (mounted) setState(() => heldGoals = goals);
            }, onError: (Object _) {});
  }

  @override
  void dispose() {
    _goalsSubscription?.cancel();
    super.dispose();
  }
}
