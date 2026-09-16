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

/// Colored icon file for a category, matching the app's icons8 icon style.
/// Matching is case-insensitive and accepts older spellings.
String categoryIconAsset(String category) {
  switch (category.toLowerCase()) {
    case 'food':
      return 'assets/icons/icons8-cat-food-96.png';
    case 'transportation':
    case 'transport':
      return 'assets/icons/icons8-cat-transportation-96.png';
    case 'shopping':
      return 'assets/icons/icons8-cat-shopping-96.png';
    case 'bills':
    case 'utilities':
      return 'assets/icons/icons8-cat-bills-96.png';
    case 'entertainment':
      return 'assets/icons/icons8-cat-entertainment-96.png';
    case 'healthcare':
    case 'health':
      return 'assets/icons/icons8-cat-healthcare-96.png';
    case 'education':
      return 'assets/icons/icons8-cat-education-96.png';
    default:
      return 'assets/icons/icons8-cat-others-96.png';
  }
}
