import 'package:flutter/material.dart';

import '../../backend/models/goal.dart';
import '../../backend/models/wallet.dart';
import '../../backend/services/wallet_service.dart';
import '../theme/app_colors.dart';
import '../theme/app_buttons.dart';
import '../../backend/utils/money_format.dart';
import 'check_after_save.dart';
import 'service_charge_field.dart';
import 'wallet_picker.dart';
import 'wallet_split_picker.dart';

/// Moves money from one wallet into one or more others. Returns true when a
/// transfer was saved.
Future<bool> showTransferSheet(
  BuildContext context, {
  Stream<List<Wallet>>? wallets,
  String? fromWalletId,
  String? toWalletId,
  double? initialAmount,
}) async {
  final saved = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: context.appColors.card,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (context) => TransferSheet(
      wallets: wallets,
      initialFromWalletId: fromWalletId,
      initialToWalletId: toWalletId,
      initialAmount: initialAmount,
    ),
  );

  return saved ?? false;
}

class TransferSheet extends StatefulWidget {
  const TransferSheet({
    this.wallets,
    this.goals,
    this.onSave,
    this.initialFromWalletId,
    this.initialToWalletId,
    this.initialAmount,
    super.key,
  });

  /// Replaces the live wallet list. Used by tests, which can't load Firebase.
  final Stream<List<Wallet>>? wallets;

  /// Replaces the live goals, for what they hold in each wallet. Used by
  /// tests.
  final Stream<List<Goal>>? goals;

  /// Replaces saving. Used by tests.
  final void Function({
    required String fromWalletId,
    required Map<String, double> to,
    required double serviceCharge,
  })?
  onSave;

  /// The wallet the money starts in. Set when the sheet is opened from a
  /// particular wallet, so the user doesn't have to pick it again.
  final String? initialFromWalletId;

  /// Where the money is headed and how much, when the sheet is opened for
  /// one, such as a savings suggestion.
  final String? initialToWalletId;
  final double? initialAmount;

  @override
  State<TransferSheet> createState() => _TransferSheetState();
}

class _TransferSheetState extends State<TransferSheet>
    with CheckAfterSave, WatchesGoals {
  late final Stream<List<Wallet>> _wallets =
      widget.wallets ?? WalletService.watchWallets();

  final _formKey = GlobalKey<FormState>();
  final _noteController = TextEditingController();

  /// Whether the bank or e-wallet charged for this transfer, and how much.
  bool _charged = false;
  final _chargeController = TextEditingController();

  double get _charge =>
      ServiceChargeField.amountOf(on: _charged, controller: _chargeController);

  late String? _fromId = widget.initialFromWalletId;

  /// How much goes into each wallet, by id.
  late Map<String, double> _to = {
    if (widget.initialToWalletId != null && (widget.initialAmount ?? 0) > 0)
      widget.initialToWalletId!: widget.initialAmount!,
  };

  double get _total =>
      _to.values.fold<double>(0, (sum, amount) => sum + amount);

  @override
  void initState() {
    super.initState();
    _chargeController.addListener(() => setState(() {}));
    watchGoals(given: widget.goals, walletsGiven: widget.wallets != null);
  }

  @override
  void dispose() {
    _noteController.dispose();
    _chargeController.dispose();
    super.dispose();
  }

  /// What stops the transfer, or null. A transfer only moves money that is
  /// there and free: goal money stays put until it is taken out of the goal.
  String? _problem(Wallet? source, List<Wallet> wallets) {
    if (source == null) return 'Choose the wallet it comes from.';
    final into = walletSplitProblem(
      purpose: SplitPurpose.receiving,
      amounts: _to,
      wallets: wallets,
      goals: heldGoals,
    );
    if (into != null) return into;
    if (_total <= 0) return 'Choose where it goes, then enter how much.';
    if (_charged && _charge <= 0) {
      return 'Enter the service charge, or turn it off.';
    }

    // The service charge comes out of the same wallet, so it counts too.
    final charge = _charge;
    final total = _total + charge;
    final withCharge = charge > 0
        ? 'With the ${formatPeso(charge)} service charge, that is '
              '${formatPeso(total)}. '
        : '';
    if (total > source.balance + 0.005) {
      return '$withCharge${source.name} only holds '
          '${formatPeso(source.balance)}.';
    }
    final free = freeInWallet(source, heldGoals);
    if (total > free + 0.005) {
      return '$withCharge${source.name} has ${formatPeso(free)} free to move. '
          'The other ${formatPeso(source.balance - free)} is set aside for '
          'goals.';
    }
    return null;
  }

  void _save(Wallet? source, List<Wallet> wallets) {
    markTriedToSave();
    if (!(_formKey.currentState?.validate() ?? false)) return;
    if (_problem(source, wallets) != null || source == null) return;

    final charge = _charge;
    if (widget.onSave != null) {
      widget.onSave!(fromWalletId: source.id, to: _to, serviceCharge: charge);
    } else {
      WalletService.recordTransfers(
        fromWalletId: source.id,
        to: _to,
        note: _noteController.text,
        serviceCharge: charge,
      );
      // The bank charges the same next time, so it is filled in then.
      if (charge > 0 && source.serviceCharge != charge) {
        WalletService.rememberServiceCharge(source.id, charge);
      }
    }

    Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    return Padding(
      // Keeps the form above the on-screen keyboard.
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
          child: StreamBuilder<List<Wallet>>(
            stream: _wallets,
            builder: (context, snapshot) {
              final wallets = snapshot.data;

              if (wallets == null) {
                return const SizedBox(
                  height: 160,
                  child: Center(child: CircularProgressIndicator()),
                );
              }

              final from = _fromId ?? defaultWalletId(wallets);
              final source = _walletById(wallets, from);
              final free = source == null
                  ? null
                  : freeInWallet(source, heldGoals);
              final error = triedToSave ? _problem(source, wallets) : null;

              return Form(
                key: _formKey,
                autovalidateMode: checkMode,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                      child: Container(
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                          color: colors.border,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Transfer',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: colors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Move money you already have from one wallet to others. '
                      'Your total stays the same.',
                      style: TextStyle(fontSize: 13, color: colors.textMuted),
                    ),
                    const SizedBox(height: 20),
                    if (wallets.length < 2)
                      _NeedsTwoWallets(walletCount: wallets.length)
                    else ...[
                      WalletPicker(
                        wallets: wallets,
                        selectedId: from,
                        label: 'From',
                        // Moving money on purpose is the one place savings
                        // can be picked as the source.
                        allowed: WalletPurpose.values.toSet(),
                        goals: heldGoals,
                        helper: source == null || free == null
                            ? null
                            : free < source.balance - 0.005
                            ? '${source.name} has ${formatPeso(free)} free '
                                  'to move'
                            : '${source.name} holds '
                                  '${formatPeso(source.balance)}',
                        onChanged: (value) => setState(() {
                          _fromId = value;
                          _to = {..._to}..remove(value);
                        }),
                      ),
                      const SizedBox(height: 16),
                      WalletSplitPicker(
                        key: const ValueKey('transfer-to'),
                        wallets: wallets,
                        goals: heldGoals,
                        purpose: SplitPurpose.receiving,
                        question: 'Where is it going?',
                        includeSavings: true,
                        excludeWalletId: from,
                        initialAmounts: _to,
                        totalLabel: 'Moving',
                        onChanged: (amounts) => setState(() => _to = amounts),
                      ),
                      const SizedBox(height: 8),
                      ServiceChargeField(
                        on: _charged,
                        controller: _chargeController,
                        onChanged: (on) => setState(() {
                          _charged = on;
                          // What this wallet charged last time.
                          final last = source?.serviceCharge;
                          if (on &&
                              last != null &&
                              _chargeController.text.trim().isEmpty) {
                            _chargeController.text = formatAmountInput(last);
                          }
                        }),
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _noteController,
                        textCapitalization: TextCapitalization.sentences,
                        maxLength: 60,
                        decoration: InputDecoration(
                          labelText: 'Note (optional)',
                          hintText: 'e.g. cashed in at the store',
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                      ),
                      if (error != null) ...[
                        Text(
                          error,
                          key: const Key('transfer-error'),
                          style: TextStyle(
                            color: dangerColorOn(context),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 10),
                      ],
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        height: 52,
                        child: ElevatedButton(
                          onPressed: () => _save(source, wallets),
                          style: confirmButtonStyle(),
                          child: const Text(
                            'Transfer',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  static Wallet? _walletById(List<Wallet> wallets, String? id) {
    for (final wallet in wallets) {
      if (wallet.id == id) return wallet;
    }
    return null;
  }
}

class _NeedsTwoWallets extends StatelessWidget {
  const _NeedsTwoWallets({required this.walletCount});

  final int walletCount;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Text(
        walletCount == 0
            ? 'Add a wallet first, then you can move money between them.'
            : 'You need a second wallet before you can transfer. Add one from '
                  'the Wallet tab.',
        style: TextStyle(
          fontSize: 14,
          color: context.appColors.textMuted,
          height: 1.4,
        ),
      ),
    );
  }
}
