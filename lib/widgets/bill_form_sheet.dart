import 'package:flutter/material.dart';

import '../utils/amount_input_formatter.dart';
import '../models/bill.dart';
import '../services/bill_service.dart';
import '../theme/app_colors.dart';
import '../theme/app_buttons.dart';
import '../utils/category_options.dart';
import '../utils/date_format.dart';
import '../utils/money_format.dart';
import '../utils/text_limits.dart';
import 'category_icon.dart';
import 'check_after_save.dart';
import 'dialog_kit.dart';

/// Adds or edits a bill schedule. Returns true when it was saved.
///
/// [initialName] and [initialAmount] start a new bill filled in, as from
/// Voice Entry; the user checks them before saving.
Future<bool> showBillFormSheet(
  BuildContext context, {
  Bill? existing,
  String? initialName,
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
    builder: (context) => BillFormSheet(
      existing: existing,
      initialName: initialName,
      initialAmount: initialAmount,
    ),
  );

  return saved ?? false;
}

class BillFormSheet extends StatefulWidget {
  const BillFormSheet({
    this.existing,
    this.initialName,
    this.initialAmount,
    this.onSave,
    super.key,
  });

  /// The bill being edited, or null when adding one.
  final Bill? existing;

  /// What a new bill starts filled in with.
  final String? initialName;
  final double? initialAmount;

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

class _BillFormSheetState extends State<BillFormSheet> with CheckAfterSave {
  final _formKey = GlobalKey<FormState>();

  late final _nameController = TextEditingController(
    text: widget.existing?.name ?? widget.initialName ?? '',
  );
  late final _amountController = TextEditingController(
    text: switch (widget.existing?.amount ?? widget.initialAmount) {
      final amount? => formatAmountInput(amount),
      null => '',
    },
  );

  late String _category = widget.existing?.category ?? 'Bills';
  late DateTime _dueDate = widget.existing?.firstDueDate ?? DateTime.now();
  late BillRecurrence _recurrence =
      widget.existing?.recurrence ?? BillRecurrence.monthly;

  /// Kept from an existing bill. The wallet is chosen when paying: cash on
  /// hand, a bank, or both.
  late final String? _walletId = widget.existing?.walletId;

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
    if (!checkForm(_formKey)) return;

    final amount = double.parse(
      _amountController.text.trim().replaceAll(',', ''),
    );

    final save = widget.onSave ?? _saveToFirestore;
    save(
      name: cleanText(_nameController.text),
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
                  maxLength: maxItemNameLength,
                  inputFormatters: const [SafeTextFormatter()],
                  decoration: dialogFieldDecoration(
                    context,
                    'Bill name',
                    hint: 'e.g. Rent, Internet, Tuition',
                  ),
                  validator: (value) => itemNameProblem(
                    value ?? '',
                    maxLength: maxItemNameLength,
                    empty: 'Give the bill a name.',
                  ),
                ),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _amountController,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  inputFormatters: const [ThousandsSeparatorFormatter()],
                  // The same size as every other field in this form.
                  decoration: dialogFieldDecoration(
                    context,
                    'Amount',
                  ).copyWith(prefixText: '₱ ', hintText: '0.00'),
                  validator: (value) {
                    final amount = double.tryParse(
                      (value ?? '').trim().replaceAll(',', ''),
                    );
                    return !isRecordableAmount(amount)
                        ? minimumAmountError
                        : null;
                  },
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  initialValue: _category,
                  isExpanded: true,
                  decoration: dialogFieldDecoration(
                    context,
                    'Category',
                    helper: _category == 'Others'
                        ? 'Use Others when no category fits. In Bill name, '
                              'say what you pay for, such as a storage unit.'
                        : null,
                  ).copyWith(helperMaxLines: 3),
                  items: [
                    for (final category in categoryOptions(
                      context,
                      selected: _category,
                    ))
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
                DropdownButtonFormField<BillRecurrence>(
                  initialValue: _recurrence,
                  isExpanded: true,
                  decoration: dialogFieldDecoration(
                    context,
                    'Does this repeat?',
                  ),
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
                  style: TextStyle(
                    fontSize: 12,
                    color: context.appColors.textMuted,
                  ),
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
