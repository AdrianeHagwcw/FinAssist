import 'package:flutter/material.dart';

const Color _primaryBlue = Color(0xFF1976D2);
const Color _pageBackground = Color(0xFFF6F8FC);

class FinancialGoalsScreen extends StatefulWidget {
  const FinancialGoalsScreen({super.key});

  @override
  State<FinancialGoalsScreen> createState() => _FinancialGoalsScreenState();
}

class _FinancialGoalsScreenState extends State<FinancialGoalsScreen> {
  final List<_FinancialGoal> _goals = [
    _FinancialGoal(name: 'Emergency Fund', target: 50000),
    _FinancialGoal(name: 'New Laptop', target: 35000),
  ];

  Future<void> _addGoal() async {
    final nameController = TextEditingController();
    final targetController = TextEditingController();
    final goal = await showDialog<_FinancialGoal>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Add Financial Goal'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameController,
              autofocus: true,
              decoration: const InputDecoration(labelText: 'Goal name'),
            ),
            TextField(
              controller: targetController,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: const InputDecoration(labelText: 'Target amount'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final name = nameController.text.trim();
              final target = double.tryParse(targetController.text.trim());
              if (name.isNotEmpty && target != null && target > 0) {
                Navigator.pop(
                  context,
                  _FinancialGoal(name: name, target: target),
                );
              }
            },
            child: const Text('Add'),
          ),
        ],
      ),
    );

    nameController.dispose();
    targetController.dispose();
    if (goal != null) setState(() => _goals.add(goal));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _pageBackground,
      appBar: AppBar(
        title: const Text('Financial Goals'),
        backgroundColor: _primaryBlue,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            tooltip: 'Add goal',
            onPressed: _addGoal,
            icon: const Icon(Icons.add),
          ),
        ],
      ),
      body: ListView.builder(
        padding: const EdgeInsets.all(20),
        itemCount: _goals.length,
        itemBuilder: (context, index) {
          final goal = _goals[index];
          return Card(
            margin: const EdgeInsets.only(bottom: 12),
            child: ListTile(
              leading: const Icon(Icons.savings_outlined, color: _primaryBlue),
              title: Text(goal.name),
              subtitle: Text('Target: ₱${goal.target.toStringAsFixed(2)}'),
              trailing: IconButton(
                tooltip: 'Remove goal',
                onPressed: () => setState(() => _goals.removeAt(index)),
                icon: const Icon(Icons.delete_outline, color: Colors.red),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _FinancialGoal {
  const _FinancialGoal({required this.name, required this.target});

  final String name;
  final double target;
}

class ExpenseCategoriesScreen extends StatefulWidget {
  const ExpenseCategoriesScreen({super.key});

  @override
  State<ExpenseCategoriesScreen> createState() =>
      _ExpenseCategoriesScreenState();
}

class _ExpenseCategoriesScreenState extends State<ExpenseCategoriesScreen> {
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

  Future<void> _addCategory() async {
    final controller = TextEditingController();
    final category = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Add Category'),
        content: TextField(
          controller: controller,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(labelText: 'Category name'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final value = controller.text.trim();
              if (value.isNotEmpty) Navigator.pop(context, value);
            },
            child: const Text('Add'),
          ),
        ],
      ),
    );
    controller.dispose();

    if (category != null && !_categories.contains(category)) {
      setState(() => _categories.add(category));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _pageBackground,
      appBar: AppBar(
        title: const Text('Expense Categories'),
        backgroundColor: _primaryBlue,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            tooltip: 'Add category',
            onPressed: _addCategory,
            icon: const Icon(Icons.add),
          ),
        ],
      ),
      body: ListView.separated(
        padding: const EdgeInsets.all(20),
        itemCount: _categories.length,
        separatorBuilder: (context, index) => const SizedBox(height: 8),
        itemBuilder: (context, index) => Card(
          child: ListTile(
            leading: const Icon(Icons.category_outlined, color: _primaryBlue),
            title: Text(_categories[index]),
            trailing: IconButton(
              tooltip: 'Remove category',
              onPressed: () => setState(() => _categories.removeAt(index)),
              icon: const Icon(Icons.delete_outline, color: Colors.red),
            ),
          ),
        ),
      ),
    );
  }
}

class CurrencyScreen extends StatefulWidget {
  const CurrencyScreen({super.key});

  @override
  State<CurrencyScreen> createState() => _CurrencyScreenState();
}

class _CurrencyScreenState extends State<CurrencyScreen> {
  String _currency = 'PHP';
  final Map<String, String> _currencies = {
    'PHP': 'Philippine Peso (₱)',
    'USD': 'US Dollar (\$)',
    'EUR': 'Euro (€)',
    'JPY': 'Japanese Yen (¥)',
  };

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _pageBackground,
      appBar: AppBar(
        title: const Text('Currency'),
        backgroundColor: _primaryBlue,
        foregroundColor: Colors.white,
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: _currencies.entries
            .map(
              (entry) => Card(
                child: ListTile(
                  onTap: () => setState(() => _currency = entry.key),
                  leading: Icon(
                    entry.key == _currency
                        ? Icons.radio_button_checked
                        : Icons.radio_button_unchecked,
                    color: _primaryBlue,
                  ),
                  title: Text(entry.value),
                  subtitle: Text(entry.key),
                  trailing: entry.key == _currency
                      ? const Icon(Icons.check, color: _primaryBlue)
                      : null,
                ),
              ),
            )
            .toList(),
      ),
    );
  }
}
