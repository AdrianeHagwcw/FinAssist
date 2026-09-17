import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/app_settings_provider.dart';
import 'categories.dart';

List<String> categoryOptions(
  BuildContext context, {
  String? selected,
  bool includeHidden = false,
}) {
  final prefs = context.watch<AppSettingsProvider?>()?.financial;
  final categories = includeHidden
      ? prefs?.allCategories
      : prefs?.availableCategories;
  return {
    ?selected,
    ...?categories,
    if (categories == null) ...expenseCategories,
  }.toList();
}
