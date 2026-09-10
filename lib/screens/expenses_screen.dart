import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'add_expense_screen.dart';

class ExpensesScreen extends StatefulWidget {
  const ExpensesScreen({super.key});

  @override
  State<ExpensesScreen> createState() => _ExpensesScreenState();
}

class _ExpensesScreenState extends State<ExpensesScreen> {
  static const Color primaryBlue = Color(0xFF1976D2);

  String selectedCategory = 'All';

  final List<String> categories = [
    'All',
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
  // GET CURRENT USER'S EXPENSES
  // =========================================================

  Stream<QuerySnapshot<Map<String, dynamic>>> _expensesStream() {
    final user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      return const Stream.empty();
    }

    return FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .collection('expenses')
        .orderBy('date', descending: true)
        .snapshots();
  }

  // =========================================================
  // CATEGORY ICON
  // =========================================================

  IconData _getCategoryIcon(String category) {
    switch (category) {
      case 'Food':
        return Icons.restaurant;

      case 'Transportation':
        return Icons.directions_car;

      case 'Shopping':
        return Icons.shopping_bag;

      case 'Bills':
        return Icons.receipt_long;

      case 'Entertainment':
        return Icons.movie;

      case 'Healthcare':
        return Icons.health_and_safety;

      case 'Education':
        return Icons.school;

      default:
        return Icons.category;
    }
  }

  // =========================================================
  // FORMAT DATE
  // =========================================================

  String _formatDate(dynamic date) {
    if (date is Timestamp) {
      final DateTime expenseDate = date.toDate();

      return '${expenseDate.day}/${expenseDate.month}/${expenseDate.year}';
    }

    return 'No date';
  }

  // =========================================================
  // DELETE EXPENSE
  // =========================================================

  Future<void> _deleteExpense(String documentId) async {
    final user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      _showError('You are not logged in.');
      return;
    }

    try {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .collection('expenses')
          .doc(documentId)
          .delete();

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Expense deleted successfully.'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      if (!mounted) return;

      _showError('Failed to delete expense.');
    }
  }

  // =========================================================
  // DELETE CONFIRMATION
  // =========================================================

  void _confirmDelete(String documentId, String title) {
    showDialog(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Delete Expense'),
          content: Text('Are you sure you want to delete "$title"?'),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(dialogContext);
              },
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () {
                Navigator.pop(dialogContext);
                _deleteExpense(documentId);
              },
              child: const Text('Delete', style: TextStyle(color: Colors.red)),
            ),
          ],
        );
      },
    );
  }

  // =========================================================
  // EDIT EXPENSE
  // =========================================================

  Future<void> _editExpense(Map<String, dynamic> expense) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => AddExpenseScreen(
          documentId: expense['id'] as String,
          initialAmount: expense['amount'] as double,
          initialCategory: expense['category'] as String,
          initialDescription: expense['title'] as String,
          initialDate: expense['date'] as Timestamp?,
          initialPaymentMethod: expense['paymentMethod'] as String,
          initialNotes: expense['notes'] as String,
        ),
      ),
    );

    // Firestore StreamBuilder automatically updates.
  }

  // =========================================================
  // ERROR MESSAGE
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
    final user = FirebaseAuth.instance.currentUser;

    // =======================================================
    // USER NOT LOGGED IN
    // =======================================================

    if (user == null) {
      return Scaffold(
        backgroundColor: const Color(0xFFF6F8FC),

        appBar: AppBar(
          backgroundColor: primaryBlue,
          foregroundColor: Colors.white,
          elevation: 0,
          centerTitle: true,

          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () {
              Navigator.pop(context);
            },
          ),

          title: const Text(
            'Expenses',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
        ),

        body: const Center(
          child: Text(
            'Please log in to view your expenses.',
            style: TextStyle(fontSize: 16, color: Colors.grey),
          ),
        ),
      );
    }

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

        // BACK TO HOME
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            Navigator.pop(context);
          },
        ),

        title: const Text(
          'Expenses',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
        ),
      ),

      // =====================================================
      // FIRESTORE DATA
      // =====================================================
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: _expensesStream(),

        builder: (context, snapshot) {
          // -------------------------------------------------
          // LOADING
          // -------------------------------------------------

          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(
              child: CircularProgressIndicator(color: primaryBlue),
            );
          }

          // -------------------------------------------------
          // ERROR
          // -------------------------------------------------

          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(30),

                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,

                  children: [
                    const Icon(
                      Icons.error_outline,
                      size: 60,
                      color: Colors.red,
                    ),

                    const SizedBox(height: 15),

                    const Text(
                      'Unable to load expenses',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),

                    const SizedBox(height: 8),

                    Text(
                      '${snapshot.error}',
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 12, color: Colors.grey),
                    ),

                    const SizedBox(height: 20),

                    ElevatedButton(
                      onPressed: () {
                        setState(() {});
                      },

                      style: ElevatedButton.styleFrom(
                        backgroundColor: primaryBlue,
                        foregroundColor: Colors.white,
                      ),

                      child: const Text('Try Again'),
                    ),
                  ],
                ),
              ),
            );
          }

          // -------------------------------------------------
          // GET DOCUMENTS
          // -------------------------------------------------

          final documents = snapshot.data?.docs ?? [];

          final allExpenses = documents.map((doc) {
            final data = doc.data();

            return {
              'id': doc.id,
              'title': data['description'] ?? 'Expense',
              'category': data['category'] ?? 'Others',
              'amount': (data['amount'] ?? 0).toDouble(),
              'date': data['date'],
              'paymentMethod': data['paymentMethod'] ?? '',
              'notes': data['notes'] ?? '',
            };
          }).toList();

          // -------------------------------------------------
          // FILTER
          // -------------------------------------------------

          final filteredExpenses = selectedCategory == 'All'
              ? allExpenses
              : allExpenses
                    .where((expense) => expense['category'] == selectedCategory)
                    .toList();

          // -------------------------------------------------
          // TOTAL
          // -------------------------------------------------

          final double totalExpenses = filteredExpenses.fold<double>(
            0,
            (sums, expense) => sums + (expense['amount'] as double),
          );

          return Column(
            children: [
              // =================================================
              // SUMMARY CARD
              // =================================================
              Container(
                width: double.infinity,
                margin: const EdgeInsets.all(20),
                padding: const EdgeInsets.all(20),

                decoration: BoxDecoration(
                  color: primaryBlue,
                  borderRadius: BorderRadius.circular(18),

                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.08),
                      blurRadius: 8,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),

                child: Row(
                  children: [
                    Container(
                      width: 50,
                      height: 50,

                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(12),
                      ),

                      child: const Icon(
                        Icons.account_balance_wallet_outlined,
                        color: Colors.white,
                        size: 28,
                      ),
                    ),

                    const SizedBox(width: 15),

                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,

                        children: [
                          const Text(
                            'Total Expenses',
                            style: TextStyle(
                              color: Colors.white70,
                              fontSize: 13,
                            ),
                          ),

                          const SizedBox(height: 4),

                          Text(
                            '₱${totalExpenses.toStringAsFixed(2)}',

                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 25,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),

                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,

                      children: [
                        const Text(
                          'Transactions',
                          style: TextStyle(color: Colors.white70, fontSize: 12),
                        ),

                        const SizedBox(height: 4),

                        Text(
                          '${filteredExpenses.length}',

                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              // =================================================
              // CATEGORY FILTER
              // =================================================
              SizedBox(
                height: 45,

                child: ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 20),

                  scrollDirection: Axis.horizontal,

                  itemCount: categories.length,

                  itemBuilder: (context, index) {
                    final category = categories[index];

                    final isSelected = selectedCategory == category;

                    return Padding(
                      padding: const EdgeInsets.only(right: 8),

                      child: ChoiceChip(
                        label: Text(category),

                        selected: isSelected,

                        selectedColor: primaryBlue,

                        backgroundColor: Colors.white,

                        labelStyle: TextStyle(
                          color: isSelected ? Colors.white : Colors.black87,

                          fontWeight: isSelected
                              ? FontWeight.bold
                              : FontWeight.normal,
                        ),

                        side: BorderSide(
                          color: isSelected
                              ? primaryBlue
                              : const Color(0xFFE0E0E0),
                        ),

                        onSelected: (selected) {
                          setState(() {
                            selectedCategory = category;
                          });
                        },
                      ),
                    );
                  },
                ),
              ),

              const SizedBox(height: 15),

              // =================================================
              // EXPENSE LIST
              // =================================================
              Expanded(
                child: filteredExpenses.isEmpty
                    ? const Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,

                          children: [
                            Icon(
                              Icons.receipt_long_outlined,
                              size: 60,
                              color: Colors.grey,
                            ),

                            SizedBox(height: 15),

                            Text(
                              'No expenses found',
                              style: TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.bold,
                                color: Colors.grey,
                              ),
                            ),

                            SizedBox(height: 5),

                            Text(
                              'Tap "Add Expense" to create one.',
                              style: TextStyle(
                                color: Colors.grey,
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.only(bottom: 100),

                        itemCount: filteredExpenses.length,

                        itemBuilder: (context, index) {
                          final expense = filteredExpenses[index];

                          return _expenseCard(
                            documentId: expense['id'] as String,

                            title: expense['title'] as String,

                            category: expense['category'] as String,

                            amount: expense['amount'] as double,

                            date: _formatDate(expense['date']),

                            paymentMethod: expense['paymentMethod'] as String,

                            notes: expense['notes'] as String,

                            rawDate: expense['date'] as Timestamp?,
                          );
                        },
                      ),
              ),
            ],
          );
        },
      ),

      // =====================================================
      // ADD EXPENSE BUTTON
      // =====================================================
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          await Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => const AddExpenseScreen()),
          );
        },

        backgroundColor: primaryBlue,
        foregroundColor: Colors.white,

        icon: const Icon(Icons.add),

        label: const Text(
          'Add Expense',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
      ),
    );
  }

  // =========================================================
  // EXPENSE CARD
  // =========================================================

  Widget _expenseCard({
    required String documentId,
    required String title,
    required String category,
    required double amount,
    required String date,
    required String paymentMethod,
    required String notes,
    required Timestamp? rawDate,
  }) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 5),

      padding: const EdgeInsets.all(15),

      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
      ),

      child: Row(
        children: [
          // =================================================
          // ICON
          // =================================================
          Container(
            width: 48,
            height: 48,

            decoration: BoxDecoration(
              color: const Color(0xFFEAF3FB),
              borderRadius: BorderRadius.circular(12),
            ),

            child: Icon(
              _getCategoryIcon(category),
              color: primaryBlue,
              size: 24,
            ),
          ),

          const SizedBox(width: 13),

          // =================================================
          // INFORMATION
          // =================================================
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,

              children: [
                Text(
                  title,

                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                  ),
                ),

                const SizedBox(height: 4),

                Text(
                  category,

                  style: const TextStyle(
                    color: primaryBlue,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),

                const SizedBox(height: 3),

                Text(
                  date,

                  style: const TextStyle(color: Colors.grey, fontSize: 11),
                ),
              ],
            ),
          ),

          // =================================================
          // AMOUNT + MENU
          // =================================================
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,

            children: [
              Text(
                '-₱${amount.toStringAsFixed(2)}',

                style: const TextStyle(
                  color: Colors.red,
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                ),
              ),

              const SizedBox(height: 5),

              PopupMenuButton<String>(
                padding: EdgeInsets.zero,
                iconSize: 20,

                onSelected: (value) {
                  if (value == 'edit') {
                    _editExpense({
                      'id': documentId,
                      'title': title,
                      'category': category,
                      'amount': amount,
                      'date': rawDate,
                      'paymentMethod': paymentMethod,
                      'notes': notes,
                    });
                  } else if (value == 'delete') {
                    _confirmDelete(documentId, title);
                  }
                },

                itemBuilder: (context) => [
                  const PopupMenuItem(
                    value: 'edit',

                    child: Row(
                      children: [
                        Icon(Icons.edit_outlined, size: 20),

                        SizedBox(width: 10),

                        Text('Edit'),
                      ],
                    ),
                  ),

                  const PopupMenuItem(
                    value: 'delete',

                    child: Row(
                      children: [
                        Icon(Icons.delete_outline, size: 20, color: Colors.red),

                        SizedBox(width: 10),

                        Text('Delete'),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }
}
