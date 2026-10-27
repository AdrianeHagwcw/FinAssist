import 'dart:async';

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../models/app_transaction.dart';
import '../models/expense_guess.dart';
import '../models/goal.dart';
import '../models/wallet.dart';
import '../services/goal_service.dart';
import '../services/wallet_service.dart';
import '../utils/category_options.dart';
import '../theme/app_buttons.dart';
import '../theme/app_colors.dart';
import '../theme/app_icons.dart';
import '../widgets/category_icon.dart';
import '../widgets/check_after_save.dart';
import '../widgets/dialog_kit.dart';
import '../widgets/wallet_split_picker.dart';
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
  final bool requireCategorySelection;
  final bool requireWalletSelection;

  /// Replaces the live wallet list. Used by tests, which can't load Firebase.
  final Stream<List<Wallet>>? wallets;

  /// Replaces the live goals, read for what they hold in each wallet. Used
  /// by tests.
  final Stream<List<Goal>>? goals;

  const AddExpenseScreen({
    super.key,

    this.wallets,
    this.goals,

    this.documentId,
    this.initialAmount,
    this.initialCategory,
    this.initialDescription,
    this.initialDate,
    this.initialPaymentMethod,
    this.requireCategorySelection = false,
    this.requireWalletSelection = false,
  });

  @override
  State<AddExpenseScreen> createState() => _AddExpenseScreenState();
}

class _AddExpenseScreenState extends State<AddExpenseScreen>
    with CheckAfterSave {
  static const Color primaryBlue = Color(0xFF1976D2);

  // =========================================================
  // CONTROLLERS
  // =========================================================

  final TextEditingController _amountController = TextEditingController();

  final TextEditingController _descriptionController = TextEditingController();

  // =========================================================
  // SELECTED VALUES
  // =========================================================

  String? _selectedCategory;

  /// Whether the category was suggested rather than picked by the user, so a
  /// better suggestion may replace it as the description changes.
  bool _categoryIsSuggestion = false;

  /// What each wallet paid of this expense, by id: never more than it has
  /// free, and together exactly the amount.
  Map<String, double> _paidFrom = const {};
  List<Wallet> _wallets = const [];
  StreamSubscription<List<Wallet>>? _walletsSubscription;

  /// Every goal, for the money each holds in a wallet: that money is not
  /// free to spend.
  List<Goal> _goals = const [];
  StreamSubscription<List<Goal>>? _goalsSubscription;

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
    recheckWhenChanged(_amountController);
    recheckWhenChanged(_descriptionController);

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

          setState(() => _wallets = wallets);
        });
    // Tests that hand in wallets have no goals behind them.
    _goalsSubscription =
        (widget.goals ??
                (widget.wallets == null
                    ? GoalService.watchGoals()
                    : Stream.value(const <Goal>[])))
            .listen((goals) {
              if (mounted) setState(() => _goals = goals);
            }, onError: (Object _) {});
  }

  // =========================================================
  // DISPOSE
  // =========================================================

  @override
  void dispose() {
    _walletsSubscription?.cancel();
    _goalsSubscription?.cancel();
    _amountController.dispose();
    _descriptionController.dispose();

    super.dispose();
  }

  // What is wrong with each field as it stands, or null where it is right.
  // Shown under the field once Save has been tapped, and gone as soon as
  // that field is fixed.

  String? get _amountProblem {
    final text = _amountController.text.trim();
    if (text.isEmpty) return 'Please enter an expense amount.';
    final amount = double.tryParse(text.replaceAll(',', ''));
    return amount == null || !isRecordableAmount(amount)
        ? minimumAmountError
        : null;
  }

  String? get _categoryProblem =>
      _selectedCategory == null ? 'Please select an expense category.' : null;

  String? get _descriptionProblem => _descriptionController.text.trim().isEmpty
      ? 'Please enter a description.'
      : null;

  double get _amount =>
      double.tryParse(_amountController.text.trim().replaceAll(',', '')) ?? 0;

  // Users who have not added a wallet yet can still record the expense; it
  // is kept as history and no balance moves. Otherwise it comes out of the
  // wallets it was paid from, each only up to what it has free.
  String? get _walletProblem {
    if (_wallets.isEmpty) {
      return widget.requireWalletSelection
          ? 'Add a wallet before recording this expense.'
          : null;
    }
    return walletSplitProblem(
      purpose: SplitPurpose.paying,
      amounts: _paidFrom,
      wallets: _wallets,
      goals: _goals,
      target: _amount,
      matchTarget: true,
    );
  }

  // =========================================================
  // SUGGEST CATEGORY
  // =========================================================

  void _suggestCategory() {
    if (widget.requireCategorySelection) return;

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
        _selectedDate = keepTimeOfDay(pickedDate, _selectedDate);
      });
    }
  }

  // =========================================================
  // SAVE / UPDATE EXPENSE
  // =========================================================

  Future<void> _saveExpense() async {
    if (_isEditMode) {
      _showError('Recorded expenses cannot be edited.');
      return;
    }

    // Every problem shows at once, each under its own field.
    markTriedToSave();
    if (_amountProblem != null ||
        _descriptionProblem != null ||
        _categoryProblem != null ||
        _walletProblem != null) {
      return;
    }
    final amount = _amount;

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

    final description = _descriptionController.text.trim();
    final note = description;

    // Writes are not awaited: Firestore saves them locally right away and
    // syncs when online, so saving also works without a connection.

    // =======================================================
    // EDIT EXISTING EXPENSE
    // =======================================================

    if (_paidFrom.isEmpty) {
      // No wallets yet: kept as history, and no balance moves.
      WalletService.recordTransaction(
        type: TransactionType.expense,
        amount: amount,
        label: _selectedCategory!,
        note: note,
        date: _selectedDate,
      );
    } else {
      // One expense from each wallet that paid part of it, saved together.
      WalletService.recordSplit(
        type: TransactionType.expense,
        amounts: _paidFrom,
        label: _selectedCategory!,
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

    Navigator.pop(context, true);
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
          _isEditMode ? 'Expense details' : 'Add Expense',

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
            if (_isEditMode) ...[
              const Text(
                'Recorded expenses are read-only.',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 16),
            ],
            AbsorbPointer(
              absorbing: _isEditMode,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // =================================================
                  // AMOUNT: the number the user came to type, the same
                  // size as every other field
                  // =================================================
                  AmountField(
                    controller: _amountController,
                    label: 'Amount',
                    // Filled in from voice, a receipt or an edit, the form is
                    // checked first, so the keyboard stays closed.
                    autofocus: !_isEditMode && widget.initialAmount == null,
                    errorText: triedToSave ? _amountProblem : null,
                  ),

                  const SizedBox(height: 16),

                  // =================================================
                  // DESCRIPTION: before the category, which is
                  // suggested from it
                  // =================================================
                  TextField(
                    controller: _descriptionController,
                    textCapitalization: TextCapitalization.sentences,
                    decoration:
                        dialogFieldDecoration(
                          context,
                          'Description',
                          hint: 'What did you spend money on?',
                        ).copyWith(
                          errorText: triedToSave ? _descriptionProblem : null,
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

                    decoration:
                        dialogFieldDecoration(
                          context,
                          'Category',
                          helper: _selectedCategory == 'Others'
                              ? 'Use Others when no category fits. In Description, '
                                    'say what you paid for, such as a replacement key.'
                              : null,
                        ).copyWith(
                          helperMaxLines: 3,
                          errorText: triedToSave ? _categoryProblem : null,
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
                          Image.asset(AppIcons.idea, width: 16, height: 16),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              "Suggested for you. Change it if it's wrong.",
                              style: TextStyle(
                                fontSize: 12,
                                color: colors.textBody,
                              ),
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
                  if (_wallets.isEmpty) ...[
                    Text(
                      'You have no wallets yet. This expense will be saved to your '
                      'history, but no wallet balance will change.',
                      style: TextStyle(fontSize: 13, color: colors.textBody),
                    ),
                    if (triedToSave && _walletProblem != null) ...[
                      const SizedBox(height: 6),
                      Text(
                        _walletProblem!,
                        style: TextStyle(
                          fontSize: 12,
                          color: dangerColorOn(context),
                        ),
                      ),
                    ],
                  ] else ...[
                    WalletSplitPicker(
                      key: const ValueKey('expense-paid-from'),
                      wallets: _wallets,
                      // What can be spent, not what goals hold.
                      goals: _goals,
                      purpose: SplitPurpose.paying,
                      target: _amount,
                      matchTarget: true,
                      onChanged: (amounts) =>
                          setState(() => _paidFrom = amounts),
                    ),
                    if (triedToSave && _walletProblem != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        _walletProblem!,
                        key: const Key('expense-paid-from-error'),
                        style: TextStyle(
                          fontSize: 12,
                          color: dangerColorOn(context),
                        ),
                      ),
                    ],
                  ],

                  const SizedBox(height: 16),

                  const SizedBox(height: 12),
                ],
              ),
            ),

            // =================================================
            // SAVE / UPDATE BUTTON
            // =================================================
            SizedBox(
              width: double.infinity,
              height: 55,

              child: ElevatedButton(
                onPressed: _isSaving || _isEditMode ? null : _saveExpense,

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
                        _isEditMode ? 'Expense is read-only' : 'Save Expense',

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
              height: 55,

              child: ElevatedButton(
                onPressed: _isSaving
                    ? null
                    : () {
                        Navigator.pop(context);
                      },

                style: dangerButtonStyle(height: 55),

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
