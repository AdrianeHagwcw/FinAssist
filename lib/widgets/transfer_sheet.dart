import 'package:flutter/material.dart';

import '../models/wallet.dart';
import '../services/wallet_service.dart';
import '../theme/app_colors.dart';
import '../theme/app_buttons.dart';
import '../utils/money_format.dart';
import 'wallet_picker.dart';

/// Moves money between two wallets. Returns true when a transfer was saved.
Future<bool> showTransferSheet(
  BuildContext context, {
  Stream<List<Wallet>>? wallets,
  String? fromWalletId,
}) async {
  final saved = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: context.appColors.card,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (context) =>
        TransferSheet(wallets: wallets, initialFromWalletId: fromWalletId),
  );

  return saved ?? false;
}

class TransferSheet extends StatefulWidget {
  const TransferSheet({this.wallets, this.initialFromWalletId, super.key});

  /// Replaces the live wallet list. Used by tests, which can't load Firebase.
  final Stream<List<Wallet>>? wallets;

  /// The wallet the money starts in. Set when the sheet is opened from a
  /// particular wallet, so the user doesn't have to pick it again.
  final String? initialFromWalletId;

  @override
  State<TransferSheet> createState() => _TransferSheetState();
}

class _TransferSheetState extends State<TransferSheet> {
  late final Stream<List<Wallet>> _wallets =
      widget.wallets ?? WalletService.watchWallets();

  final _formKey = GlobalKey<FormState>();
  final _amountController = TextEditingController();
  final _noteController = TextEditingController();

  late String? _fromId = widget.initialFromWalletId;
  String? _toId;

  @override
  void dispose() {
    _amountController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  double? get _amount =>
      double.tryParse(_amountController.text.trim().replaceAll(',', ''));

  void _save(String? fromId) {
    if (fromId == null || !_formKey.currentState!.validate()) return;

    WalletService.recordTransfer(
      fromWalletId: fromId,
      toWalletId: _toId!,
      amount: _amount!,
      note: _noteController.text,
    );

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

              return Form(
                key: _formKey,
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
                    const Text(
                      'Move money you already have from one wallet to another. '
                      'Your total stays the same.',
                      style: TextStyle(fontSize: 13, color: Colors.grey),
                    ),
                    const SizedBox(height: 20),
                    if (wallets.length < 2)
                      _NeedsTwoWallets(walletCount: wallets.length)
                    else ...[
                      WalletPicker(
                        wallets: wallets,
                        selectedId: from,
                        label: 'From',
                        onChanged: (value) => setState(() {
                          _fromId = value;
                          if (_toId == value) _toId = null;
                        }),
                      ),
                      const SizedBox(height: 16),
                      WalletPicker(
                        wallets: wallets,
                        selectedId: _toId,
                        label: 'To',
                        excludeId: from,
                        onChanged: (value) => setState(() => _toId = value),
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _amountController,
                        autofocus: true,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        decoration: InputDecoration(
                          labelText: 'Amount',
                          prefixText: '₱ ',
                          hintText: '0.00',
                          helperText: source == null
                              ? null
                              : '${source.name} holds '
                                    '${formatPeso(source.balance)}',
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        validator: (value) =>
                            _validateAmount(value, source: source),
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
                          onPressed: () => _save(from),
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

    if (amount == null || amount <= 0) return 'Enter an amount to transfer.';

    if (source != null && amount > source.balance) {
      return '${source.name} only holds ${formatPeso(source.balance)}.';
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
        style: const TextStyle(fontSize: 14, color: Colors.grey, height: 1.4),
      ),
    );
  }
}
