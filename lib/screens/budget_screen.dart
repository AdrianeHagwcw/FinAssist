import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../services/user_profile_service.dart';
import '../utils/money_format.dart';
import '../theme/app_buttons.dart';
import '../theme/app_colors.dart';
import '../widgets/category_icon.dart';
import '../widgets/category_budget_dialog.dart';
import '../widgets/empty_state_view.dart';

const Color _budgetPrimaryBlue = Color(0xFF1976D2);

class BudgetScreen extends StatefulWidget {
  const BudgetScreen({super.key});

  @override
  State<BudgetScreen> createState() => _BudgetScreenState();
}

class _BudgetScreenState extends State<BudgetScreen> {
  final User? _user = FirebaseAuth.instance.currentUser;

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

  String _formatMoney(double amount) => formatPeso(amount);

  Future<void> _showBudgetDialog({
    DocumentSnapshot<Map<String, dynamic>>? existing,
  }) async {
    final data = existing?.data();

    await showCategoryBudgetDialog(
      context,
      category: data?['category']?.toString(),
      amount: (data?['amount'] as num?)?.toDouble(),
      period: data?['period']?.toString(),
    );
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
                child: CategoryIcon(category, size: 24),
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
                itemBuilder: (context) => [
                  menuItem(
                    value: 'edit',
                    label: 'Edit',
                    icon: Icons.edit,
                    color: _budgetPrimaryBlue,
                  ),
                  menuItem(
                    value: 'delete',
                    label: 'Delete',
                    icon: Icons.delete_outline,
                    color: dangerColorOn(context),
                  ),
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
                backgroundColor: context.appColors.track,
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
      backgroundColor: context.appColors.pageBackground,
      appBar: AppBar(
        title: const Text(
          'Category Budgets',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
        ),
        centerTitle: true,
        backgroundColor: _budgetPrimaryBlue,
        foregroundColor: Colors.white,
        elevation: 0,
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
                return const EmptyStateView(
                  iconAsset: 'assets/icons/icons8-pie-chart-96.png',
                  title: 'No category budgets yet',
                  message:
                      'Set a limit for a category like Food or Transportation, '
                      'and this screen will show how much of it you have left.',
                );
              }

              return ListView.builder(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 96),
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
