import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../services/user_profile_service.dart';

const Color _budgetPrimaryBlue = Color(0xFF1976D2);
const Color _budgetPageBackground = Color(0xFFF6F8FC);

class BudgetScreen extends StatefulWidget {
  const BudgetScreen({super.key});

  @override
  State<BudgetScreen> createState() => _BudgetScreenState();
}

class _BudgetScreenState extends State<BudgetScreen> {
  static const _categories = [
    'Food',
    'Transportation',
    'Shopping',
    'Bills',
    'Entertainment',
    'Healthcare',
    'Education',
    'Others',
  ];

  final User? _user = FirebaseAuth.instance.currentUser;

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

  Stream<QuerySnapshot<Map<String, dynamic>>> get _budgetStream {
    if (_user == null) return const Stream.empty();

    return FirebaseFirestore.instance
        .collection('users')
        .doc(_user.uid)
        .collection('categoryBudgets')
        .snapshots();
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> get _expenseStream {
    if (_user == null) return const Stream.empty();

    return FirebaseFirestore.instance
        .collection('users')
        .doc(_user.uid)
        .collection('expenses')
        .snapshots();
  }

  DateTime _periodStart(DateTime now, String period) {
    final date = DateTime(now.year, now.month, now.day);
    switch (period) {
      case 'weekly':
        return date.subtract(Duration(days: date.weekday - DateTime.monday));
      case 'monthly':
        return DateTime(now.year, now.month);
      default:
        return date;
    }
  }

  DateTime _periodEnd(DateTime start, String period) {
    switch (period) {
      case 'weekly':
        return start.add(const Duration(days: 7));
      case 'monthly':
        return DateTime(start.year, start.month + 1);
      default:
        return start.add(const Duration(days: 1));
    }
  }

  double _spentForBudget(
    Map<String, dynamic> budget,
    List<QueryDocumentSnapshot<Map<String, dynamic>>> expenses,
  ) {
    final category = budget['category']?.toString().toLowerCase();
    final period = budget['period']?.toString() ?? 'daily';
    final start = _periodStart(DateTime.now(), period);

    return expenses.fold<double>(0, (total, expense) {
      final data = expense.data();
      final expenseCategory = data['category']?.toString().toLowerCase();
      final date = (data['date'] as Timestamp?)?.toDate();
      if (category == null || expenseCategory != category || date == null) {
        return total;
      }
      if (date.isBefore(start) || !date.isBefore(_periodEnd(start, period))) {
        return total;
      }
      return total + ((data['amount'] as num?)?.toDouble() ?? 0);
    });
  }

  String _periodLabel(String period) {
    switch (period) {
      case 'weekly':
        return 'Weekly';
      case 'monthly':
        return 'Monthly';
      default:
        return 'Daily';
    }
  }

  String _formatMoney(double amount) => '₱${amount.toStringAsFixed(2)}';

  Future<void> _showBudgetDialog({
    DocumentSnapshot<Map<String, dynamic>>? existing,
  }) async {
    final data = existing?.data();
    final amountController = TextEditingController(
      text: data?['amount'] is num
          ? (data!['amount'] as num).toStringAsFixed(2)
          : '',
    );
    var category = data?['category']?.toString() ?? _categories.first;
    var period = data?['period']?.toString() ?? 'daily';
    var isSaving = false;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(
            existing == null ? 'Add Category Budget' : 'Edit Category Budget',
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String>(
                initialValue: category,
                decoration: const InputDecoration(labelText: 'Category'),
                items: _categories
                    .map(
                      (value) =>
                          DropdownMenuItem(value: value, child: Text(value)),
                    )
                    .toList(),
                onChanged: isSaving
                    ? null
                    : (value) => setDialogState(() => category = value!),
              ),
              TextField(
                controller: amountController,
                enabled: !isSaving,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(
                  labelText: 'Budget amount',
                  prefixText: '₱',
                ),
              ),
              DropdownButtonFormField<String>(
                initialValue: period,
                decoration: const InputDecoration(labelText: 'Budget period'),
                items: const [
                  DropdownMenuItem(value: 'daily', child: Text('Daily')),
                  DropdownMenuItem(value: 'weekly', child: Text('Weekly')),
                  DropdownMenuItem(value: 'monthly', child: Text('Monthly')),
                ],
                onChanged: isSaving
                    ? null
                    : (value) => setDialogState(() => period = value!),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: isSaving ? null : () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: isSaving
                  ? null
                  : () async {
                      final amount = double.tryParse(
                        amountController.text.trim().replaceAll(',', ''),
                      );
                      if (amount == null || amount <= 0) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Enter a valid positive amount.'),
                          ),
                        );
                        return;
                      }

                      setDialogState(() => isSaving = true);
                      try {
                        await UserProfileService.saveCategoryBudget(
                          category: category,
                          amount: amount,
                          period: period,
                        );
                        if (mounted && dialogContext.mounted) {
                          Navigator.pop(dialogContext);
                        }
                      } catch (_) {
                        if (!context.mounted) return;
                        setDialogState(() => isSaving = false);
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text(
                              'Category budget could not be saved.',
                            ),
                          ),
                        );
                      }
                    },
              child: isSaving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Save'),
            ),
          ],
        ),
      ),
    );
    amountController.dispose();
  }

  Future<void> _deleteBudget(String category) async {
    try {
      await UserProfileService.deleteCategoryBudget(category);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Category budget could not be deleted.')),
      );
    }
  }

  Widget _budgetCard(
    DocumentSnapshot<Map<String, dynamic>> document,
    List<QueryDocumentSnapshot<Map<String, dynamic>>> expenses,
  ) {
    final budget = document.data() ?? <String, dynamic>{};
    final category = budget['category']?.toString() ?? 'Category';
    final amount = (budget['amount'] as num?)?.toDouble() ?? 0;
    final period = budget['period']?.toString() ?? 'daily';
    final spent = _spentForBudget(budget, expenses);
    final progress = amount > 0
        ? (spent / amount).clamp(0.0, 1.0).toDouble()
        : 0.0;
    final remaining = amount - spent;
    final color = progress >= 1
        ? Colors.red
        : progress >= 0.75
        ? Colors.amber.shade700
        : _budgetPrimaryBlue;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 8, 14),
        child: Column(
          children: [
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: CircleAvatar(
                backgroundColor: _budgetPrimaryBlue.withValues(alpha: 0.1),
                child: Icon(
                  _getCategoryIcon(category),
                  color: _budgetPrimaryBlue,
                ),
              ),
              title: Text(
                category,
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              subtitle: Text(
                '${_periodLabel(period)} limit: ${_formatMoney(amount)}',
              ),
              trailing: PopupMenuButton<String>(
                onSelected: (value) {
                  if (value == 'edit') _showBudgetDialog(existing: document);
                  if (value == 'delete') _deleteBudget(category);
                },
                itemBuilder: (context) => const [
                  PopupMenuItem(value: 'edit', child: Text('Edit')),
                  PopupMenuItem(value: 'delete', child: Text('Delete')),
                ],
              ),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '${_formatMoney(spent)} spent',
                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                ),
                Text(
                  remaining >= 0
                      ? '${_formatMoney(remaining)} left'
                      : '${_formatMoney(remaining.abs())} over',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: color,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                value: progress,
                minHeight: 8,
                backgroundColor: const Color(0xFFE4EAF3),
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_user == null) {
      return const Scaffold(
        body: Center(child: Text('No user is currently signed in.')),
      );
    }

    return Scaffold(
      backgroundColor: _budgetPageBackground,
      appBar: AppBar(
        title: const Text('Category Budgets'),
        backgroundColor: _budgetPrimaryBlue,
        foregroundColor: Colors.white,
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: _budgetStream,
        builder: (context, budgetSnapshot) {
          if (budgetSnapshot.hasError) {
            return const Center(
              child: Text('Could not load category budgets.'),
            );
          }
          if (budgetSnapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: _expenseStream,
            builder: (context, expenseSnapshot) {
              if (expenseSnapshot.hasError) {
                return const Center(
                  child: Text('Could not load spending data.'),
                );
              }
              final budgets = budgetSnapshot.data?.docs ?? [];
              final expenses = expenseSnapshot.data?.docs ?? [];

              if (budgets.isEmpty) {
                return const Center(
                  child: Padding(
                    padding: EdgeInsets.all(32),
                    child: Text(
                      'No category budgets yet. Add one to track spending by category.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.grey),
                    ),
                  ),
                );
              }

              return ListView.builder(
                padding: const EdgeInsets.all(20),
                itemCount: budgets.length,
                itemBuilder: (context, index) =>
                    _budgetCard(budgets[index], expenses),
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showBudgetDialog(),
        backgroundColor: _budgetPrimaryBlue,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add),
        label: const Text('Add Budget'),
      ),
    );
  }
}
