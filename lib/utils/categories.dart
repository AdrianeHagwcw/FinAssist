import 'package:flutter/material.dart';

/// Expense categories offered when recording an expense.
const List<String> expenseCategories = [
  'Food',
  'Transportation',
  'Shopping',
  'Bills',
  'Entertainment',
  'Healthcare',
  'Education',
  'Others',
];

/// Color for a category. Matching is case-insensitive and accepts older
/// spellings (e.g. `Health`, `Other`) found in existing records.
Color categoryColor(String category) {
  switch (category.toLowerCase()) {
    case 'food':
      return Colors.orange;
    case 'transportation':
    case 'transport':
      return Colors.blue;
    case 'shopping':
      return Colors.purple;
    case 'bills':
    case 'utilities':
      return Colors.red;
    case 'entertainment':
      return Colors.pink;
    case 'healthcare':
    case 'health':
      return Colors.green;
    case 'education':
      return Colors.indigo;
    case 'others':
    case 'other':
      return Colors.grey;
    default:
      return Colors.teal;
  }
}

IconData categoryIcon(String category) {
  switch (category.toLowerCase()) {
    case 'food':
      return Icons.restaurant;
    case 'transportation':
    case 'transport':
      return Icons.directions_car;
    case 'shopping':
      return Icons.shopping_bag;
    case 'bills':
    case 'utilities':
      return Icons.receipt_long;
    case 'entertainment':
      return Icons.movie;
    case 'healthcare':
    case 'health':
      return Icons.health_and_safety;
    case 'education':
      return Icons.school;
    default:
      return Icons.category;
  }
}
