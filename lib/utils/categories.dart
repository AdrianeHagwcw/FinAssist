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
  'Pets',
  'Others',
];

/// Chart color for a category. Matching is case-insensitive and accepts older
/// spellings (e.g. `Health`, `Other`) found in existing records.
///
/// Each category keeps its color on every chart, whatever its rank, so Food
/// is the same orange on Home and in Reports. The hues are a colorblind-
/// checked set, stepped separately for light and dark backgrounds. Anything
/// that isn't a known category shares the neutral gray of Others.
Color categoryColor(
  String category, {
  Brightness brightness = Brightness.light,
}) {
  final dark = brightness == Brightness.dark;

  switch (category.toLowerCase()) {
    case 'transportation':
    case 'transport':
      return dark ? const Color(0xFF3987E5) : const Color(0xFF2A78D6);
    case 'food':
      return dark ? const Color(0xFFD95926) : const Color(0xFFEB6834);
    case 'healthcare':
    case 'health':
      return dark ? const Color(0xFF199E70) : const Color(0xFF1BAF7A);
    case 'education':
      return dark ? const Color(0xFFC98500) : const Color(0xFFEDA100);
    case 'shopping':
      return dark ? const Color(0xFFD55181) : const Color(0xFFE87BA4);
    case 'bills':
    case 'utilities':
      return dark ? const Color(0xFFE66767) : const Color(0xFFE34948);
    case 'entertainment':
      return dark ? const Color(0xFF9085E9) : const Color(0xFF4A3AA7);
    case 'pets':
      return const Color(0xFF008300);
    default:
      return dark ? const Color(0xFF8A8986) : const Color(0xFF9A9994);
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
    case 'pets':
      return 'assets/icons/icons8-cat-pets-96.png';
    default:
      return 'assets/icons/icons8-cat-others-96.png';
  }
}
