import 'dart:async';

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../models/app_transaction.dart';
import '../models/wallet.dart';
import '../services/wallet_service.dart';
import '../utils/category_options.dart';
import '../theme/app_buttons.dart';
import '../theme/app_colors.dart';
import '../widgets/wallet_picker.dart';
import '../utils/money_format.dart';

class AddExpenseScreen extends StatefulWidget {
  // =========================================================
  // EDIT MODE DATA
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
    // LOAD EXISTING EXPENSE WHEN EDITING
    // ---------------------------------------------------------

    if (_isEditMode) {
      if (widget.initialAmount != null) {
        _amountController.text = formatAmountInput(widget.initialAmount!);
      }

      _selectedCategory = widget.initialCategory;

      _descriptionController.text = widget.initialDescription ?? '';

      _notesController.text = widget.initialNotes ?? '';

      if (widget.initialDate != null) {
        _selectedDate = widget.initialDate!.toDate();
      }
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
            // AMOUNT
            // =================================================
            const Text(
              'Amount',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
            ),

            const SizedBox(height: 8),

            TextField(
              controller: _amountController,

              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),

              decoration: InputDecoration(
                hintText: '0.00',

                prefixText: '₱ ',

                prefixStyle: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: primaryBlue,
                ),

                filled: true,

                fillColor: colors.card,

                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),

                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 15,
                  vertical: 16,
                ),
              ),
            ),

            const SizedBox(height: 20),

            // =================================================
            // CATEGORY
            // =================================================
            const Text(
              'Category',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
            ),

            const SizedBox(height: 8),

            Container(
              decoration: BoxDecoration(
                color: colors.card,
                borderRadius: BorderRadius.circular(12),
              ),

              child: DropdownButtonFormField<String>(
                initialValue: _selectedCategory,

                decoration: InputDecoration(
                  prefixIcon: const Icon(
                    Icons.category_outlined,
                    color: primaryBlue,
                  ),

                  hintText: 'Select category',

                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                ),

                items: _categories.map((category) {
                  return DropdownMenuItem<String>(
                    value: category,
                    child: Text(category),
                  );
                }).toList(),

                onChanged: (value) {
                  setState(() {
                    _selectedCategory = value;
                  });
                },
              ),
            ),

            const SizedBox(height: 20),

            // =================================================
            // DESCRIPTION
            // =================================================
            const Text(
              'Description',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
            ),

            const SizedBox(height: 8),

            TextField(
              controller: _descriptionController,

              decoration: InputDecoration(
                prefixIcon: const Icon(
                  Icons.description_outlined,
                  color: primaryBlue,
                ),

                hintText: 'What did you spend money on?',

                filled: true,

                fillColor: colors.card,

                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
            ),

            const SizedBox(height: 20),

            // =================================================
            // DATE
            // =================================================
            const Text(
              'Date',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
            ),

            const SizedBox(height: 8),

            InkWell(
              onTap: _selectDate,

              borderRadius: BorderRadius.circular(12),

              child: Container(
                width: double.infinity,

                padding: const EdgeInsets.symmetric(
                  horizontal: 15,
                  vertical: 17,
                ),

                decoration: BoxDecoration(
                  color: colors.card,

                  borderRadius: BorderRadius.circular(12),
                ),

                child: Row(
                  children: [
                    const Icon(
                      Icons.calendar_today_outlined,
                      color: primaryBlue,
                    ),

                    const SizedBox(width: 12),

                    Text(
                      '${_selectedDate.day}/'
                      '${_selectedDate.month}/'
                      '${_selectedDate.year}',

                      style: const TextStyle(fontSize: 14),
                    ),

                    const Spacer(),

                    const Icon(Icons.arrow_drop_down, color: Colors.grey),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 20),

            // =================================================
            // WALLET
            // =================================================
            const Text(
              'Paid From',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
            ),

            const SizedBox(height: 8),

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
                label: 'Wallet',
                onChanged: (value) => setState(() => _walletId = value),
              ),

            const SizedBox(height: 20),

            // =================================================
            // NOTES
            // =================================================
            const Text(
              'Notes (Optional)',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
            ),

            const SizedBox(height: 8),

            TextField(
              controller: _notesController,

              maxLines: 4,

              decoration: InputDecoration(
                hintText: 'Add additional notes...',

                filled: true,

                fillColor: colors.card,

                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),

                contentPadding: const EdgeInsets.all(15),
              ),
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
