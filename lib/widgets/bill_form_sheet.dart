import 'package:flutter/material.dart';

import '../models/bill.dart';
import '../models/wallet.dart';
import '../services/bill_service.dart';
import '../services/wallet_service.dart';
import '../theme/app_colors.dart';
import '../theme/app_buttons.dart';
import '../utils/categories.dart';
import '../utils/date_format.dart';
import 'category_icon.dart';
import 'dialog_kit.dart';
import 'wallet_picker.dart';

/// Adds or edits a bill schedule. Returns true when it was saved.
Future<bool> showBillFormSheet(
  BuildContext context, {
  Bill? existing,
  Stream<List<Wallet>>? wallets,
}) async {
  final saved = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: context.appColors.card,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (context) => BillFormSheet(existing: existing, wallets: wallets),
  );

  return saved ?? false;
}

class BillFormSheet extends StatefulWidget {
  const BillFormSheet({this.existing, this.wallets, this.onSave, super.key});

  /// The bill being edited, or null when adding one.
  final Bill? existing;

  /// Replaces the live wallet list. Used by tests, which can't load Firebase.
  final Stream<List<Wallet>>? wallets;

  /// Saves the bill. Tests pass a fake instead of Firestore.
  final void Function({
    required String name,
    required double amount,
    required String category,
    required DateTime firstDueDate,
    required BillRecurrence recurrence,
    String? walletId,
  })?
  onSave;

  @override
  State<BillFormSheet> createState() => _BillFormSheetState();
}

class _BillFormSheetState extends State<BillFormSheet> {
  final _formKey = GlobalKey<FormState>();

  late final _nameController = TextEditingController(
    text: widget.existing?.name ?? '',
  );
  late final _amountController = TextEditingController(
    text: widget.existing == null
        ? ''
        : widget.existing!.amount.toStringAsFixed(2),
  );

  late final Stream<List<Wallet>> _wallets =
      widget.wallets ?? WalletService.watchWallets();

  late String _category = widget.existing?.category ?? 'Bills';
  late DateTime _dueDate = widget.existing?.firstDueDate ?? DateTime.now();
  late BillRecurrence _recurrence =
      widget.existing?.recurrence ?? BillRecurrence.monthly;
  late String? _walletId = widget.existing?.walletId;

  bool get _isEditing => widget.existing != null;

  @override
  void dispose() {
    _nameController.dispose();
    _amountController.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _dueDate,
      // Bills can be backdated a little, for one already missed.
      firstDate: DateTime(DateTime.now().year - 1),
      lastDate: DateTime(DateTime.now().year + 5),
    );

    if (picked != null) setState(() => _dueDate = picked);
  }

  void _save() {
    if (!_formKey.currentState!.validate()) return;

    final amount = double.parse(
      _amountController.text.trim().replaceAll(',', ''),
    );

    final save = widget.onSave ?? _saveToFirestore;
    save(
      name: _nameController.text,
      amount: amount,
      category: _category,
      firstDueDate: _dueDate,
      recurrence: _recurrence,
      walletId: _walletId,
    );

    Navigator.pop(context, true);
  }

  void _saveToFirestore({
    required String name,
    required double amount,
    required String category,
    required DateTime firstDueDate,
    required BillRecurrence recurrence,
    String? walletId,
  }) {
    if (_isEditing) {
      BillService.updateBill(
        billId: widget.existing!.id,
        name: name,
        amount: amount,
        category: category,
        firstDueDate: firstDueDate,
        recurrence: recurrence,
        walletId: walletId,
      );
    } else {
      BillService.addBill(
        name: name,
        amount: amount,
        category: category,
        firstDueDate: firstDueDate,
        recurrence: recurrence,
        walletId: walletId,
      );
    }
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
          child: Form(
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
                  _isEditing ? 'Edit Bill' : 'New Bill',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: colors.textPrimary,
                  ),
                ),
                const SizedBox(height: 18),
                TextFormField(
                  controller: _nameController,
                  textCapitalization: TextCapitalization.words,
                  maxLength: 40,
                  decoration: dialogFieldDecoration(
                    context,
                    'Bill name',
                    hint: 'e.g. Rent, Internet, Tuition',
                  ),
                  validator: (value) => (value ?? '').trim().isEmpty
                      ? 'Give the bill a name.'
                      : null,
                ),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _amountController,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                  ),
                  decoration: dialogFieldDecoration(
                    context,
                    'Amount',
                  ).copyWith(prefixText: '₱ ', hintText: '0.00'),
                  validator: (value) {
                    final amount = double.tryParse(
                      (value ?? '').trim().replaceAll(',', ''),
                    );
                    return amount == null || amount <= 0
                        ? 'Enter how much this bill is.'
                        : null;
                  },
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  initialValue: _category,
                  isExpanded: true,
                  decoration: dialogFieldDecoration(context, 'Category'),
                  items: [
                    for (final category in expenseCategories)
                      DropdownMenuItem(
                        value: category,
                        child: Row(
                          children: [
                            CategoryIcon(category, size: 20),
                            const SizedBox(width: 10),
                            Text(category),
                          ],
                        ),
                      ),
                  ],
                  onChanged: (value) =>
                      setState(() => _category = value ?? _category),
                ),
                const SizedBox(height: 16),
                InkWell(
                  onTap: _pickDate,
                  borderRadius: BorderRadius.circular(12),
                  child: InputDecorator(
                    decoration: dialogFieldDecoration(
                      context,
                      _isEditing ? 'Due date' : 'First due date',
                    ),
                    child: Row(
                      children: [
                        Expanded(child: Text(formatShortDate(_dueDate))),
                        const Icon(Icons.calendar_today, size: 18),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<BillRecurrence>(
                  initialValue: _recurrence,
                  isExpanded: true,
                  decoration: dialogFieldDecoration(context, 'Repeats'),
                  items: [
                    for (final recurrence in BillRecurrence.values)
                      DropdownMenuItem(
                        value: recurrence,
                        child: Text(recurrence.label),
                      ),
                  ],
                  onChanged: (value) =>
                      setState(() => _recurrence = value ?? _recurrence),
                ),
                const SizedBox(height: 8),
                Text(
                  _recurrence.explanation,
                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                ),
                const SizedBox(height: 16),
                StreamBuilder<List<Wallet>>(
                  stream: _wallets,
                  builder: (context, snapshot) {
                    final wallets = snapshot.data ?? const <Wallet>[];

                    if (wallets.isEmpty) return const SizedBox.shrink();

                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        WalletPicker(
                          wallets: wallets,
                          selectedId: _walletId,
                          label: 'Usually paid from (optional)',
                          onChanged: (value) =>
                              setState(() => _walletId = value),
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'Only a suggestion. You still choose the wallet when '
                          'you actually pay it.',
                          style: TextStyle(fontSize: 12, color: Colors.grey),
                        ),
                      ],
                    );
                  },
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton(
                    onPressed: _save,
                    style: confirmButtonStyle(),
                    child: Text(
                      _isEditing ? 'Save Changes' : 'Add Bill',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
