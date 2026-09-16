import 'package:flutter/material.dart';

import '../utils/categories.dart';

/// Colored icon for an expense category, used in lists, budgets and reports.
class CategoryIcon extends StatelessWidget {
  const CategoryIcon(this.category, {this.size = 24, super.key});

  final String category;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Image.asset(categoryIconAsset(category), width: size, height: size);
  }
}
