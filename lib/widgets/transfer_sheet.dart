import 'package:flutter/material.dart';

import '../utils/amount_input_formatter.dart';
import '../models/goal.dart';
import '../models/wallet.dart';
import '../services/wallet_service.dart';
import '../theme/app_colors.dart';
import '../theme/app_buttons.dart';
import '../utils/money_format.dart';
import 'check_after_save.dart';
import 'service_charge_field.dart';
import 'wallet_picker.dart';

/// Moves money between two wallets. Returns true when a transfer was saved.
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
  static const newBillsWalletId = billsPlaceholderWalletId;
  static const newSavingsWalletId = savingsPlaceholderWalletId;

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
    required String toWalletId,
    required double amount,
    required double serviceCharge,
  })?
  onSave;

  /// The wallet the money starts in. Set when the sheet is opened from a
  /// particular wallet, so the user doesn't have to pick it again.
  final String? initialFromWalletId;

  /// The wallet the money is headed for, set when the sheet is opened to top
  /// one up, such as the bills wallet before paying a bill.
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
  late final _amountController = TextEditingController(
    text: widget.initialAmount == null
        ? ''
        : formatAmountInput(widget.initialAmount!),
  );
  final _noteController = TextEditingController();

  /// Whether the bank or e-wallet charged for this transfer, and how much.
  bool _charged = false;
  final _chargeController = TextEditingController();

  double get _charge =>
      ServiceChargeField.amountOf(on: _charged, controller: _chargeController);

  late String? _fromId = widget.initialFromWalletId;
  late String? _toId = widget.initialToWalletId;

  @override
  void initState() {
    super.initState();
    watchGoals(given: widget.goals, walletsGiven: widget.wallets != null);
  }

  @override
  void dispose() {
    _amountController.dispose();
    _noteController.dispose();
    _chargeController.dispose();
    super.dispose();
  }

  double? get _amount =>
      double.tryParse(_amountController.text.trim().replaceAll(',', ''));

  /// Placeholder ids for a bills or savings wallet the user has not made yet.
  /// Choosing one creates it as the money moves in.
  static const _newBills = TransferSheet.newBillsWalletId;
  static const _newSavings = TransferSheet.newSavingsWalletId;

  void _save(String? fromId, List<Wallet> wallets) {
    if (!checkForm(_formKey) || fromId == null) return;

    final purpose = switch (_toId) {
      _newBills => WalletPurpose.bills,
      _newSavings => WalletPurpose.savings,
      _ => null,
    };

    final charge = _charge;
    if (widget.onSave != null) {
      widget.onSave!(
        fromWalletId: fromId,
        toWalletId: _toId!,
        amount: _amount!,
        serviceCharge: charge,
      );
    } else if (purpose == null) {
      WalletService.recordTransfer(
        fromWalletId: fromId,
        toWalletId: _toId!,
        amount: _amount!,
        note: _noteController.text,
        serviceCharge: charge,
      );
    } else {
      WalletService.transferToPurpose(
        fromWalletId: fromId,
        purpose: purpose,
        amount: _amount!,
        wallets: wallets,
        note: _noteController.text,
        serviceCharge: charge,
      );
    }

    // The bank charges the same next time, so it is filled in then.
    final source = _walletById(wallets, fromId);
    if (widget.onSave == null &&
        charge > 0 &&
        source != null &&
        source.serviceCharge != charge) {
      WalletService.rememberServiceCharge(fromId, charge);
    }

    Navigator.pop(context, true);
  }

  /// The wallets the money can go to: the real ones, plus a bills or savings
  /// wallet the user can start here rather than having to make first.
  List<Wallet> _destinations(List<Wallet> wallets) {
    Wallet placeholder(String id, WalletPurpose purpose) => Wallet(
      id: id,
      name: purpose.defaultName ?? 'Set aside',
      type: WalletType.other,
      balance: 0,
      startingBalance: 0,
      receivesIncome: false,
      archived: false,
      sortOrder: 1000,
      purpose: purpose,
    );

    return [
      // Nothing can be added to a time deposit once it is placed; more money
      // goes into a new one, made in Add Savings.
      ...wallets.where((wallet) => !wallet.isLockedSavings),
      if (WalletService.walletFor(wallets, WalletPurpose.bills) == null)
        placeholder(_newBills, WalletPurpose.bills),
      if (WalletService.walletFor(wallets, WalletPurpose.savings) == null)
        placeholder(_newSavings, WalletPurpose.savings),
    ];
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
                      'Move money you already have from one wallet to another. '
                      'Your total stays the same.',
                      style: TextStyle(
                        fontSize: 13,
                        color: context.appColors.textMuted,
                      ),
                    ),
                    const SizedBox(height: 20),
                    if (wallets.isEmpty)
                      _NeedsTwoWallets(walletCount: wallets.length)
                    else ...[
                      WalletPicker(
                        wallets: wallets,
                        selectedId: from,
                        label: 'From',
                        // Moving money on purpose is the one place every
                        // wallet may be picked, in either direction.
                        allowed: WalletPurpose.values.toSet(),
                        goals: heldGoals,
                        onChanged: (value) => setState(() {
                          _fromId = value;
                          if (_toId == value) _toId = null;
                        }),
                      ),
                      const SizedBox(height: 16),
                      WalletPicker(
                        wallets: _destinations(wallets),
                        selectedId: _toId,
                        label: 'To',
                        excludeId: from,
                        allowed: WalletPurpose.values.toSet(),
                        goals: heldGoals,
                        onChanged: (value) => setState(() => _toId = value),
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _amountController,
                        autofocus: true,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        inputFormatters: const [ThousandsSeparatorFormatter()],
                        decoration: InputDecoration(
                          labelText: 'Amount',
                          prefixText: '₱ ',
                          hintText: '0.00',
                          // What can be moved: goal money stays put.
                          helperText: source == null
                              ? null
                              : freeInWallet(source, heldGoals) <
                                    source.balance - 0.005
                              ? '${source.name} has '
                                    '${formatPeso(freeInWallet(source, heldGoals))} '
                                    'free to move'
                              : '${source.name} holds '
                                    '${formatPeso(source.balance)}',
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        validator: (value) =>
                            _validateAmount(value, source: source),
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
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        height: 52,
                        child: ElevatedButton(
                          onPressed: () => _save(from, wallets),
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

  /// A transfer only moves money that is already there, so it is capped at
  /// the source wallet's balance rather than pushing it negative.
  String? _validateAmount(String? value, {required Wallet? source}) {
    final amount = double.tryParse((value ?? '').trim().replaceAll(',', ''));

    if (amount == null || !isRecordableAmount(amount)) {
      return minimumAmountError;
    }

    // The service charge comes out of the same wallet, so it counts too.
    final charge = _charge;
    final total = amount + charge;
    final withCharge = charge > 0
        ? 'With the ${formatPeso(charge)} service charge, that is '
              '${formatPeso(total)}. '
        : '';

    if (source != null && total > source.balance + 0.005) {
      return '$withCharge${source.name} only holds '
          '${formatPeso(source.balance)}.';
    }

    // Money set aside for a goal stays where it is until it is taken out of
    // the goal.
    final free = source == null ? null : freeInWallet(source, heldGoals);
    if (source != null && free != null && total > free + 0.005) {
      return '$withCharge${source.name} has ${formatPeso(free)} free to move. '
          'The other ${formatPeso(source.balance - free)} is set aside for '
          'goals.';
    }

    return null;
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
