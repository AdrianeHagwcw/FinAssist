import 'dart:async';

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../models/app_transaction.dart';
import '../models/expense_guess.dart';
import '../models/wallet.dart';
import '../services/wallet_service.dart';
import '../utils/category_options.dart';
import '../theme/app_buttons.dart';
import '../theme/app_colors.dart';
import '../widgets/category_icon.dart';
import '../widgets/dialog_kit.dart';
import '../widgets/wallet_picker.dart';
import '../utils/date_format.dart';
import '../utils/money_format.dart';

class AddExpenseScreen extends StatefulWidget {
  // =========================================================
  // STARTING VALUES: an expense being edited (with its
  // documentId), or a new one from voice entry or a receipt
  // =========================================================

  final String? documentId;
  final double? initialAmount;
  final String? initialCategory;
  final String? initialDescription;
  final Timestamp? initialDate;
  final String? initialPaymentMethod;
  final String? initialNotes;

  /// Replaces the live wallet list. Used by tests, which can't load Firebase.
  final Stream<List<Wallet>>? wallets;

  const AddExpenseScreen({
    super.key,

    this.wallets,

    this.documentId,
    this.initialAmount,
    this.initialCategory,
    this.initialDescription,
    this.initialDate,
    this.initialPaymentMethod,
    this.initialNotes,
  });

  @override
  State<AddExpenseScreen> createState() => _AddExpenseScreenState();
}

class _AddExpenseScreenState extends State<AddExpenseScreen> {
  static const Color primaryBlue = Color(0xFF1976D2);

  // =========================================================
  // CONTROLLERS
  // =========================================================

  final TextEditingController _amountController = TextEditingController();

  final TextEditingController _descriptionController = TextEditingController();

  final TextEditingController _notesController = TextEditingController();

  // =========================================================
  // SELECTED VALUES
  // =========================================================

  String? _selectedCategory;

  /// Whether the category was suggested rather than picked by the user, so a
  /// better suggestion may replace it as the description changes.
  bool _categoryIsSuggestion = false;

  /// Which wallet this expense is paid from. Null only while the wallets are
  /// still loading, or for a user who has none yet.
  String? _walletId;
  List<Wallet> _wallets = const [];
  StreamSubscription<List<Wallet>>? _walletsSubscription;

  DateTime _selectedDate = DateTime.now();

  bool _isSaving = false;

  // =========================================================
  // CHECK IF EDIT MODE
  // =========================================================

  bool get _isEditMode => widget.documentId != null;

  // =========================================================
  // CATEGORIES
  // =========================================================

  List<String> get _categories =>
      categoryOptions(context, selected: _selectedCategory);

  // =========================================================
  // INIT
  // =========================================================

  @override
  void initState() {
    super.initState();

    // ---------------------------------------------------------
    // STARTING VALUES
    // ---------------------------------------------------------

    // An expense being edited, or a new one started from voice entry or a
    // receipt scan, which the user checks before saving.
    if (widget.initialAmount != null) {
      _amountController.text = formatAmountInput(widget.initialAmount!);
    }

    _selectedCategory = widget.initialCategory;
    _categoryIsSuggestion = !_isEditMode && widget.initialCategory != null;

    if (widget.initialDate != null) {
      _selectedDate = widget.initialDate!.toDate();
    }

    _descriptionController.text = widget.initialDescription ?? '';
    _notesController.text = widget.initialNotes ?? '';

    // A new expense gets its category suggested from the description, until
    // the user picks one.
    if (!_isEditMode) {
      _descriptionController.addListener(_suggestCategory);
    }

    // The wallet list is held here rather than read from a builder, because
    // saving needs to know which wallet was picked.
    _walletsSubscription = (widget.wallets ?? WalletService.watchWallets())
        .listen((wallets) {
          if (!mounted) return;

          setState(() {
            _wallets = wallets;
            _walletId ??= defaultWalletId(wallets);
          });
        });
  }

  // =========================================================
  // DISPOSE
  // =========================================================

  @override
  void dispose() {
    _walletsSubscription?.cancel();
    _amountController.dispose();
    _descriptionController.dispose();
    _notesController.dispose();

    super.dispose();
  }

  /// The wallet this expense is paid from, or null when there is none.
  Wallet? get _selectedWallet {
    for (final wallet in _wallets) {
      if (wallet.id == _walletId) return wallet;
    }
    return null;
  }

  // =========================================================
  // SUGGEST CATEGORY
  // =========================================================

  void _suggestCategory() {
    // A category the user picked is theirs; only a suggestion is replaced.
    if (_selectedCategory != null && !_categoryIsSuggestion) return;

    final suggestion = suggestCategory(
      _descriptionController.text,
      from: availableCategoriesOf(context),
    );
    if (suggestion == _selectedCategory) return;

    setState(() {
      _selectedCategory = suggestion;
      _categoryIsSuggestion = suggestion != null;
    });
  }

  // =========================================================
  // SELECT DATE
  // =========================================================

  Future<void> _selectDate() async {
    final DateTime? pickedDate = await showDatePicker(
      context: context,

      initialDate: _selectedDate,

      firstDate: DateTime(2020),

      lastDate: DateTime.now(),
    );

    if (pickedDate != null) {
      setState(() {
        _selectedDate = pickedDate;
      });
    }
  }

  // =========================================================
  // SAVE / UPDATE EXPENSE
  // =========================================================

  Future<void> _saveExpense() async {
    // ---------------------------------------------------------
    // AMOUNT
    // ---------------------------------------------------------

    if (_amountController.text.trim().isEmpty) {
      _showError('Please enter an expense amount.');
      return;
    }

    final double? amount = double.tryParse(
      _amountController.text.trim().replaceAll(',', ''),
    );

    if (amount == null || !amount.isFinite || amount <= 0) {
      _showError('Please enter a valid expense amount.');
      return;
    }

    // ---------------------------------------------------------
    // CATEGORY
    // ---------------------------------------------------------

    if (_selectedCategory == null) {
      _showError('Please select an expense category.');
      return;
    }

    // ---------------------------------------------------------
    // DESCRIPTION
    // ---------------------------------------------------------

    if (_descriptionController.text.trim().isEmpty) {
      _showError('Please enter a description.');
      return;
    }

    // ---------------------------------------------------------
    // WALLET
    // ---------------------------------------------------------

    // Users who have not added a wallet yet can still record the expense; it
    // is kept as history and no balance moves.
    if (_wallets.isNotEmpty && _walletId == null) {
      _showError('Please choose which wallet this was paid from.');
      return;
    }

    // More than the wallet holds is allowed, since money may have come in
    // that isn't logged yet, but it is checked first so a typo such as
    // 65000 for 6500 doesn't go through unnoticed.
    final paidFrom = _selectedWallet;
    if (!_isEditMode && paidFrom != null && amount > paidFrom.balance + 0.005) {
      final saveAnyway = await _confirmOverBalance(paidFrom, amount);
      if (!mounted) return;
      if (!saveAnyway) return;
    }

    // ---------------------------------------------------------
    // USER
    // ---------------------------------------------------------

    final User? user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      _showError('You are not logged in. Please log in again.');
      return;
    }

    // ---------------------------------------------------------
    // PREVENT DOUBLE SAVE
    // ---------------------------------------------------------

    if (_isSaving) {
      return;
    }

    setState(() {
      _isSaving = true;
    });

    // =======================================================
    // COMMON DATA
    // =======================================================

    final wallet = _selectedWallet;
    final description = _descriptionController.text.trim();
    final note = [
      description,
      _notesController.text.trim(),
    ].where((part) => part.isNotEmpty).join('\n\n');

    // Writes are not awaited: Firestore saves them locally right away and
    // syncs when online, so saving also works without a connection.

    // =======================================================
    // EDIT EXISTING EXPENSE
    // =======================================================

    if (_isEditMode) {
      // Rewrites the matching wallet entry, putting back what the old version
      // took out before applying the new amount.
      WalletService.replaceTransaction(
        id: widget.documentId!,
        type: TransactionType.expense,
        amount: amount,
        label: _selectedCategory!,
        walletId: wallet?.id,
        note: note,
        date: _selectedDate,
      );
    }
    // =======================================================
    // ADD NEW EXPENSE
    // =======================================================
    else {
      // The wallet ledger is the only source for new records. Older records
      // remain available through the one-time legacy import.
      WalletService.recordTransaction(
        type: TransactionType.expense,
        amount: amount,
        label: _selectedCategory!,
        walletId: wallet?.id,
        note: note,
        date: _selectedDate,
      );
    }

    // =======================================================
    // SUCCESS
    // =======================================================

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          _isEditMode
              ? 'Expense updated successfully!'
              : 'Expense added successfully!',
        ),
        backgroundColor: Colors.green,
      ),
    );

    Navigator.pop(context);
  }

  /// Asks before saving an expense larger than what [wallet] holds.
  Future<bool> _confirmOverBalance(Wallet wallet, double amount) async {
    final save = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text("More than what's in ${wallet.name}"),
        content: Text(
          'This expense is ${formatPeso(amount)}, but ${wallet.name} has '
          '${formatPeso(wallet.balance)}, so it would show '
          '${formatPeso(wallet.balance - amount)}. If money came in that '
          "isn't logged yet, add it as income too.",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            style: cancelTextStyle(context),
            child: const Text('Fix Amount'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: confirmTextStyle(context),
            child: const Text('Save Anyway'),
          ),
        ],
      ),
    );
    return save == true;
  }

  // =========================================================
  // ERROR
  // =========================================================

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.red),
    );
  }

  // =========================================================
  // BUILD
  // =========================================================

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    return Scaffold(
      backgroundColor: colors.pageBackground,

      // =====================================================
      // APP BAR
      // =====================================================
      appBar: AppBar(
        backgroundColor: primaryBlue,
        foregroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,

        title: Text(
          _isEditMode ? 'Edit Expense' : 'Add Expense',

          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
        ),
      ),

      // =====================================================
      // BODY
      // =====================================================
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),

        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,

          children: [
            // =================================================
            // AMOUNT: the number the user came to type, as large
            // as on Add Income
            // =================================================
            AmountField(
              controller: _amountController,
              label: 'Amount',
              // Filled in from voice, a receipt or an edit, the form is
              // checked first, so the keyboard stays closed.
              autofocus: !_isEditMode && widget.initialAmount == null,
            ),

            const SizedBox(height: 16),

            // =================================================
            // DESCRIPTION: before the category, which is
            // suggested from it
            // =================================================
            TextField(
              controller: _descriptionController,
              textCapitalization: TextCapitalization.sentences,
              decoration: dialogFieldDecoration(
                context,
                'Description',
                hint: 'What did you spend money on?',
              ),
            ),

            const SizedBox(height: 16),

            // =================================================
            // CATEGORY: shown with its own icon
            // =================================================
            DropdownButtonFormField<String>(
              // Rebuilt when a suggestion changes the category.
              key: ValueKey(_selectedCategory),
              initialValue: _selectedCategory,
              isExpanded: true,

              decoration: dialogFieldDecoration(context, 'Category').copyWith(
                prefixIcon: Padding(
                  padding: const EdgeInsets.all(12),
                  child: _selectedCategory == null
                      ? Image.asset(
                          'assets/icons/icons8-pie-chart-96.png',
                          width: 24,
                          height: 24,
                        )
                      : CategoryIcon(_selectedCategory!),
                ),
              ),

              // The chosen one's icon is already at the start of the field.
              selectedItemBuilder: (context) => [
                for (final category in _categories) Text(category),
              ],

              items: [
                for (final category in _categories)
                  DropdownMenuItem<String>(
                    value: category,
                    child: Row(
                      children: [
                        CategoryIcon(category, size: 22),
                        const SizedBox(width: 12),
                        Text(category),
                      ],
                    ),
                  ),
              ],

              onChanged: (value) {
                setState(() {
                  _selectedCategory = value;
                  _categoryIsSuggestion = false;
                });
              },
            ),

            if (_categoryIsSuggestion && _selectedCategory != null)
              Padding(
                padding: const EdgeInsets.only(top: 6, left: 4),
                child: Row(
                  children: [
                    Icon(
                      Icons.lightbulb_outline,
                      size: 14,
                      color: colors.textBody,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        "Suggested for you. Change it if it's wrong.",
                        style: TextStyle(fontSize: 12, color: colors.textBody),
                      ),
                    ),
                  ],
                ),
              ),

            const SizedBox(height: 16),

            // =================================================
            // DATE: written the way Add Income writes it
            // =================================================
            InkWell(
              onTap: _selectDate,
              borderRadius: BorderRadius.circular(12),
              child: InputDecorator(
                decoration: dialogFieldDecoration(context, 'Date'),
                child: Row(
                  children: [
                    Expanded(child: Text(formatShortDate(_selectedDate))),
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

            // =================================================
            // WALLET
            // =================================================
            if (_wallets.isEmpty)
              Text(
                'You have no wallets yet. This expense will be saved to your '
                'history, but no wallet balance will change.',
                style: TextStyle(fontSize: 13, color: colors.textBody),
              )
            else
              WalletPicker(
                wallets: _wallets,
                selectedId: _walletId,
                label: 'Paid from',
                onChanged: (value) => setState(() => _walletId = value),
              ),

            const SizedBox(height: 16),

            // =================================================
            // NOTES
            // =================================================
            TextField(
              controller: _notesController,
              maxLines: 4,
              textCapitalization: TextCapitalization.sentences,
              decoration: dialogFieldDecoration(
                context,
                'Notes (optional)',
                hint: 'Add additional notes...',
              ).copyWith(alignLabelWithHint: true),
            ),

            const SizedBox(height: 30),

            // =================================================
            // SAVE / UPDATE BUTTON
            // =================================================
            SizedBox(
              width: double.infinity,
              height: 55,

              child: ElevatedButton(
                onPressed: _isSaving ? null : _saveExpense,

                style: confirmButtonStyle(height: 55),

                child: _isSaving
                    ? const SizedBox(
                        width: 24,
                        height: 24,

                        child: CircularProgressIndicator(
                          strokeWidth: 2.5,
                          color: Colors.white,
                        ),
                      )
                    : Text(
                        _isEditMode ? 'Update Expense' : 'Save Expense',

                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
              ),
            ),

            const SizedBox(height: 15),

            // =================================================
            // CANCEL
            // =================================================
            SizedBox(
              width: double.infinity,
              height: 50,

              child: OutlinedButton(
                onPressed: _isSaving
                    ? null
                    : () {
                        Navigator.pop(context);
                      },

                style: dangerOutlineStyle(context, height: 50).copyWith(
                  shape: WidgetStatePropertyAll(
                    RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                ),

                child: const Text(
                  'Cancel',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                ),
              ),
            ),

            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }
}
