import 'package:flutter/material.dart';

import '../models/app_transaction.dart';
import '../models/wallet.dart';
import '../services/ledger_service.dart';
import '../services/wallet_service.dart';
import '../theme/app_buttons.dart';
import '../theme/app_colors.dart';
import '../utils/category_options.dart';
import '../utils/date_format.dart';
import '../utils/income_sources.dart';
import '../utils/money_format.dart';
import 'dialog_kit.dart';
import 'wallet_picker.dart';

/// Opens one transaction to change or delete it. Returns true when something
/// was saved or deleted.
Future<bool> showTransactionEditSheet(
  BuildContext context,
  AppTransaction transaction, {
  Stream<List<Wallet>>? wallets,
}) async {
  final changed = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: context.appColors.card,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (context) =>
        TransactionEditSheet(transaction: transaction, wallets: wallets),
  );

  return changed ?? false;
}

class TransactionEditSheet extends StatefulWidget {
  const TransactionEditSheet({
    required this.transaction,
    this.wallets,
    this.onSave,
    this.onDelete,
    super.key,
  });

  final AppTransaction transaction;

  /// Replaces the live wallet list. Used by tests, which can't load Firebase.
  final Stream<List<Wallet>>? wallets;

  /// Replace saving and deleting. Used by tests.
  final void Function({
    required double amount,
    required String label,
    required String? walletId,
    required String? toWalletId,
    required String? note,
    required DateTime date,
  })?
  onSave;
  final VoidCallback? onDelete;

  @override
  State<TransactionEditSheet> createState() => _TransactionEditSheetState();
}

class _TransactionEditSheetState extends State<TransactionEditSheet> {
  late final AppTransaction _original = widget.transaction;

  late final Stream<List<Wallet>> _wallets =
      widget.wallets ?? WalletService.watchWallets(includeArchived: true);

  late final _amountController = TextEditingController(
    text: formatAmountInput(_original.amount),
  );
  late final _noteController = TextEditingController(
    text: _original.note ?? '',
  );

  late String _label = _original.label;
  late String? _walletId = _original.walletId;
  late String? _toWalletId = _original.toWalletId;
  late DateTime _date = _original.date;

  String? _error;

  late final String? _lockedReason = LedgerService.whyNotEditable(_original);

  bool get _isTransfer => _original.type == TransactionType.transfer;

  @override
  void dispose() {
    _amountController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  List<String> get _labelChoices {
    final base = _original.type == TransactionType.income
        ? incomeSources
        : categoryOptions(context, selected: _label);

    // Keep an older label that is no longer offered, so opening a record
    // doesn't silently rename it.
    return base.contains(_label) ? base : [_label, ...base];
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(now.year - 5),
      lastDate: now,
    );

    if (picked != null) {
      // Keeps the time of day, so the order within that day is preserved.
      setState(
        () => _date = DateTime(
          picked.year,
          picked.month,
          picked.day,
          _date.hour,
          _date.minute,
        ),
      );
    }
  }

  Future<void> _save() async {
    final amount = double.tryParse(
      _amountController.text.trim().replaceAll(',', ''),
    );

    final problem = amount == null || amount <= 0
        ? 'Enter a valid amount.'
        : _walletId == null
        ? 'Choose a wallet.'
        : _isTransfer && (_toWalletId == null || _toWalletId == _walletId)
        ? 'Choose two different wallets.'
        : null;

    if (problem != null) {
      setState(() => _error = problem);
      return;
    }

    final note = _noteController.text.trim();

    if (widget.onSave != null) {
      widget.onSave!(
        amount: amount!,
        label: _label,
        walletId: _walletId,
        toWalletId: _toWalletId,
        note: note.isEmpty ? null : note,
        date: _date,
      );
    } else {
      await LedgerService.update(
        _original,
        amount: amount!,
        label: _isTransfer ? TransactionType.transfer.label : _label,
        walletId: _walletId,
        toWalletId: _toWalletId,
        note: note.isEmpty ? null : note,
        date: _date,
      );
    }

    if (mounted) Navigator.pop(context, true);
  }

  Future<void> _delete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete this transaction?'),
        content: Text(
          _original.isLegacy
              ? 'It will be removed from your history. No balance changes, '
                    'because it is from before you had wallets.'
              : _original.isBillPayment
              ? '${formatPeso(_original.amount)} goes back to the wallet, and '
                    'the bill shows that much owing again.'
              : 'The money it moved will be put back.',
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
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    if (widget.onDelete != null) {
      widget.onDelete!();
    } else {
      await LedgerService.delete(_original);
    }

    if (mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final locked = _lockedReason != null;

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
          child: StreamBuilder<List<Wallet>>(
            stream: _wallets,
            builder: (context, snapshot) {
              final wallets = snapshot.data ?? const <Wallet>[];

              return Column(
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
                    locked
                        ? _original.type.label
                        : 'Edit ${_original.type.label}',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: colors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 16),
                  if (locked) ...[
                    DialogNote(text: _lockedReason),
                    const SizedBox(height: 16),
                    _ReadOnlyRow(
                      label: _original.label,
                      detail: formatShortDate(_original.date),
                      amount: formatPeso(_original.amount),
                    ),
                  ] else ...[
                    AmountField(
                      controller: _amountController,
                      label: 'Amount',
                      autofocus: false,
                    ),
                    const SizedBox(height: 16),
                    if (!_isTransfer) ...[
                      DropdownButtonFormField<String>(
                        initialValue: _label,
                        isExpanded: true,
                        decoration: dialogFieldDecoration(
                          context,
                          _original.type == TransactionType.income
                              ? 'Source'
                              : 'Category',
                        ),
                        items: [
                          for (final choice in _labelChoices)
                            DropdownMenuItem(
                              value: choice,
                              child: Text(choice),
                            ),
                        ],
                        onChanged: (value) =>
                            setState(() => _label = value ?? _label),
                      ),
                      const SizedBox(height: 16),
                    ],
                    if (wallets.isNotEmpty) ...[
                      WalletPicker(
                        wallets: wallets,
                        selectedId: _walletId,
                        label: _isTransfer ? 'From' : 'Wallet',
                        onChanged: (value) => setState(() => _walletId = value),
                      ),
                      if (_isTransfer) ...[
                        const SizedBox(height: 16),
                        WalletPicker(
                          wallets: wallets,
                          selectedId: _toWalletId,
                          label: 'To',
                          excludeId: _walletId,
                          onChanged: (value) =>
                              setState(() => _toWalletId = value),
                        ),
                      ],
                      const SizedBox(height: 16),
                    ],
                    InkWell(
                      onTap: _pickDate,
                      borderRadius: BorderRadius.circular(12),
                      child: InputDecorator(
                        decoration: dialogFieldDecoration(context, 'Date'),
                        child: Row(
                          children: [
                            Expanded(child: Text(formatShortDate(_date))),
                            Image.asset(
                              'assets/icons/icons8-calendar-96.png',
                              width: 22,
                              height: 22,
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _noteController,
                      maxLength: 60,
                      decoration: dialogFieldDecoration(
                        context,
                        'Note (optional)',
                      ),
                    ),
                  ],
                  if (_error != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      _error!,
                      style: TextStyle(
                        color: dangerColorOn(context),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      if (LedgerService.canDeleteHere(_original))
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: _delete,
                            icon: const Icon(Icons.delete_outline, size: 18),
                            label: const Text('Delete'),
                            style: dangerOutlineStyle(context, height: 52),
                          ),
                        ),
                      if (!locked) ...[
                        const SizedBox(width: 12),
                        Expanded(
                          flex: 2,
                          child: ElevatedButton(
                            onPressed: _save,
                            style: confirmButtonStyle(),
                            child: const Text(
                              'Save Changes',
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
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class _ReadOnlyRow extends StatelessWidget {
  const _ReadOnlyRow({
    required this.label,
    required this.detail,
    required this.amount,
  });

  final String label;
  final String detail;
  final String amount;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: colors.textPrimary,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                detail,
                style: const TextStyle(fontSize: 12, color: Colors.grey),
              ),
            ],
          ),
        ),
        Text(
          amount,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: colors.textPrimary,
          ),
        ),
      ],
    );
  }
}
