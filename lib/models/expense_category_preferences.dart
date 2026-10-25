import '../utils/categories.dart';

/// The account's choices for which expense categories appear on new entries.
class ExpenseCategoryPreferences {
  const ExpenseCategoryPreferences({
    this.customCategories = const [],
    this.hiddenCategories = const [],
  });

  factory ExpenseCategoryPreferences.fromMap(Map<String, dynamic>? data) {
    List<String> strings(String key) => data?[key] is List
        ? (data![key] as List).whereType<String>().toSet().toList()
        : const [];

    return ExpenseCategoryPreferences(
      customCategories: strings('customCategories'),
      hiddenCategories: strings('hiddenCategories'),
    );
  }

  /// Legacy categories remain available to users who already recorded them.
  final List<String> customCategories;
  final List<String> hiddenCategories;

  List<String> get allCategories =>
      {...expenseCategories, ...customCategories}.toList();

  List<String> get availableCategories => allCategories
      .where((category) =>
          category == 'Others' || !hiddenCategories.contains(category))
      .toList();
}
