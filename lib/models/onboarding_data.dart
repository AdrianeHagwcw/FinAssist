import 'wallet.dart';

/// What the user can rank as most important during onboarding.
enum FinancialPriority {
  payBills('Pay bills on time'),
  saveForGoal('Save toward a goal'),
  generalSavings('Build general savings'),
  trackSpending('Just track my spending');

  const FinancialPriority(this.label);

  final String label;
}

/// Everything collected by the onboarding wizard, saved in one go.
class OnboardingData {
  const OnboardingData({
    required this.name,
    required this.notificationsEnabled,
    required this.incomeSource,
    required this.incomeFrequency,
    required this.income,
    required this.dailyBudget,
    required this.priorities,
    required this.wallets,
    this.plannedBills = 0,
    this.plannedSavings = 0,
    this.plannedOthers = 0,
  });

  final String name;
  final bool notificationsEnabled;
  final String incomeSource;
  final String incomeFrequency;

  /// Usual income per pay period. For irregular income this is an optional
  /// rough monthly estimate, and null when the user left it blank.
  final double? income;

  /// Optional daily spending limit; null when the user skipped it.
  final double? dailyBudget;

  /// Most important first.
  final List<FinancialPriority> priorities;
  final List<WalletDraft> wallets;

  /// Per-pay amounts the user plans to direct toward each category.
  final double plannedBills;
  final double plannedSavings;
  final double plannedOthers;
}
