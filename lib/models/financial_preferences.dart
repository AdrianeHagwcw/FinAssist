import '../utils/categories.dart';
import 'allocation.dart';

const incomeFrequencies = {
  'Weekly': 'Weekly',
  'Bi-weekly': 'Every 2 weeks',
  'Semi-monthly': 'Twice a month (15th & month end)',
  'Monthly': 'Monthly',
  'Irregular': 'Irregular (no fixed payday)',
};

/// One planned amount from the profile's `plannedAllocations`, or zero.
double _planned(Map<String, dynamic>? data, String key) {
  final allocations = data?['plannedAllocations'];
  if (allocations is! Map) return 0;
  final amount = allocations[key];
  return amount is num && amount.isFinite && amount > 0 ? amount.toDouble() : 0;
}

/// Account preferences, separate from the device's appearance settings.
class FinancialPreferences {
  const FinancialPreferences({
    this.source = '',
    this.frequency = 'Monthly',
    this.income,
    this.leftover = LeftoverDecision.pending,
    this.customCategories = const [],
    this.hiddenCategories = const [],
    this.plannedBills = 0,
    this.plannedSavings = 0,
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
      plannedBills: _planned(data, 'bills'),
      plannedSavings: _planned(data, 'savings'),
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

  /// What the user plans to set aside from each pay. The amounts are moved
  /// into the bills and savings wallets when income is recorded.
  final double plannedBills;
  final double plannedSavings;

  List<String> get allCategories =>
      {...expenseCategories, ...customCategories}.toList();
  List<String> get availableCategories => allCategories
      .where((c) => c == 'Others' || !hiddenCategories.contains(c))
      .toList();
}
