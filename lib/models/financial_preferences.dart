import '../utils/categories.dart';
import 'allocation.dart';

const incomeFrequencies = {
  'Weekly': 'Weekly',
  'Bi-weekly': 'Every 2 weeks',
  'Semi-monthly': 'Twice a month (15th & month end)',
  'Monthly': 'Monthly',
  'Irregular': 'Irregular (no fixed payday)',
};

/// Account preferences, separate from the device's appearance settings.
class FinancialPreferences {
  const FinancialPreferences({
    this.source = '',
    this.frequency = 'Monthly',
    this.income,
    this.leftover = LeftoverDecision.pending,
    this.customCategories = const [],
    this.hiddenCategories = const [],
  });

  factory FinancialPreferences.fromMap(Map<String, dynamic>? data) {
    final amount = data?['income'];
    List<String> strings(String key) => (data?[key] is List)
        ? (data![key] as List).whereType<String>().toSet().toList()
        : const [];
    return FinancialPreferences(
      source: data?['incomeSource'] is String ? data!['incomeSource'] : '',
      frequency: incomeFrequencies.containsKey(data?['incomeFrequency'])
          ? data!['incomeFrequency']
          : 'Monthly',
      income: amount is num && amount.isFinite && amount > 0
          ? amount.toDouble()
          : null,
      leftover:
          LeftoverDecision.fromName(data?['defaultLeftover'] as String?) ??
          LeftoverDecision.pending,
      customCategories: strings('customCategories'),
      hiddenCategories: strings('hiddenCategories'),
    );
  }

  final String source;
  final String frequency;
  final double? income;
  final LeftoverDecision leftover;

  /// Categories added before the list was fixed. They still show and can be
  /// hidden, but no new ones are added: every category needs its own icon,
  /// and automatic categorisation later can only suggest from a set list.
  final List<String> customCategories;
  final List<String> hiddenCategories;

  List<String> get allCategories =>
      {...expenseCategories, ...customCategories}.toList();
  List<String> get availableCategories => allCategories
      .where((c) => c == 'Others' || !hiddenCategories.contains(c))
      .toList();
}
