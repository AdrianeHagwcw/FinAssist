import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

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

  const AddExpenseScreen({
    super.key,

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
  String? _selectedPaymentMethod;

  DateTime _selectedDate = DateTime.now();

  bool _isSaving = false;

  // =========================================================
  // CHECK IF EDIT MODE
  // =========================================================

  bool get _isEditMode => widget.documentId != null;

  // =========================================================
  // CATEGORIES
  // =========================================================

  final List<String> _categories = [
    'Food',
    'Transportation',
    'Shopping',
    'Bills',
    'Entertainment',
    'Healthcare',
    'Education',
    'Others',
  ];

  // =========================================================
  // PAYMENT METHODS
  // =========================================================

  final List<String> _paymentMethods = [
    'Cash',
    'GCash',
    'Bank Transfer',
    'Debit Card',
    'Credit Card',
    'Other',
  ];

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
        _amountController.text = widget.initialAmount!.toStringAsFixed(2);
      }

      _selectedCategory = widget.initialCategory;

      _descriptionController.text = widget.initialDescription ?? '';

      _selectedPaymentMethod = widget.initialPaymentMethod;

      _notesController.text = widget.initialNotes ?? '';

      if (widget.initialDate != null) {
        _selectedDate = widget.initialDate!.toDate();
      }
    }
  }

  // =========================================================
  // DISPOSE
  // =========================================================

  @override
  void dispose() {
    _amountController.dispose();
    _descriptionController.dispose();
    _notesController.dispose();

    super.dispose();
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

    if (amount == null || amount <= 0) {
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
    // PAYMENT METHOD
    // ---------------------------------------------------------

    if (_selectedPaymentMethod == null) {
      _showError('Please select a payment method.');
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

    try {
      // =======================================================
      // COMMON DATA
      // =======================================================

      final Map<String, dynamic> expenseData = {
        'amount': amount,
        'category': _selectedCategory,
        'description': _descriptionController.text.trim(),
        'date': Timestamp.fromDate(_selectedDate),
        'paymentMethod': _selectedPaymentMethod,
        'notes': _notesController.text.trim(),
      };

      // =======================================================
      // EDIT EXISTING EXPENSE
      // =======================================================

      if (_isEditMode) {
        await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .collection('expenses')
            .doc(widget.documentId)
            .update(expenseData);
      }
      // =======================================================
      // ADD NEW EXPENSE
      // =======================================================
      else {
        expenseData['userId'] = user.uid;
        expenseData['email'] = user.email;
        expenseData['createdAt'] = FieldValue.serverTimestamp();

        await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .collection('expenses')
            .add(expenseData);
      }

      // =======================================================
      // SUCCESS
      // =======================================================

      if (!mounted) return;

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
    // FIREBASE ERROR
    // =========================================================
    on FirebaseException catch (e) {
      if (!mounted) return;

      String message = 'Unable to save expense.';

      if (e.code == 'permission-denied') {
        message = 'Permission denied. Please check your Firestore rules.';
      } else if (e.code == 'network-request-failed') {
        message = 'Network error. Please check your internet connection.';
      } else if (e.code == 'not-found') {
        message = 'The expense no longer exists.';
      }

      _showError(message);

      setState(() {
        _isSaving = false;
      });
    }
    // =========================================================
    // OTHER ERROR
    // =========================================================
    catch (e) {
      if (!mounted) return;

      _showError('Something went wrong while saving the expense.');

      setState(() {
        _isSaving = false;
      });
    }
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
    return Scaffold(
      backgroundColor: const Color(0xFFF6F8FC),

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

                fillColor: Colors.white,

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
                color: Colors.white,
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

                fillColor: Colors.white,

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
                  color: Colors.white,

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
            // PAYMENT METHOD
            // =================================================
            const Text(
              'Payment Method',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
            ),

            const SizedBox(height: 8),

            Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
              ),

              child: DropdownButtonFormField<String>(
                initialValue: _selectedPaymentMethod,

                decoration: InputDecoration(
                  prefixIcon: const Icon(
                    Icons.payment_outlined,
                    color: primaryBlue,
                  ),

                  hintText: 'Select payment method',

                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                ),

                items: _paymentMethods.map((method) {
                  return DropdownMenuItem<String>(
                    value: method,
                    child: Text(method),
                  );
                }).toList(),

                onChanged: (value) {
                  setState(() {
                    _selectedPaymentMethod = value;
                  });
                },
              ),
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

                fillColor: Colors.white,

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

                style: ElevatedButton.styleFrom(
                  backgroundColor: primaryBlue,

                  foregroundColor: Colors.white,

                  disabledBackgroundColor: primaryBlue.withValues(alpha: 0.6),

                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),

                  elevation: 0,
                ),

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

                style: OutlinedButton.styleFrom(
                  foregroundColor: primaryBlue,

                  side: const BorderSide(color: primaryBlue),

                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
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
