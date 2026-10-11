import 'bill.dart';
import 'goal.dart';
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
    this.lastPaydayAt,
    required this.monthlyIncome,
    required this.priorities,
    required this.wallets,
    this.bills = const [],
    this.savingsAccounts = const [],
    this.goals = const [],
  });

  final String name;
  final bool notificationsEnabled;
  final String incomeSource;
  final String incomeFrequency;

  /// The day the user last received their pay. It starts the first pay
  /// period, so the days left are right from the moment setup is finished.
  final DateTime? lastPaydayAt;

  /// Monthly income. For irregular income this is an optional rough estimate,
  /// and null when the user left it blank.
  final double? monthlyIncome;

  /// The profile's legacy `income` value represents one payment, not a month.
  double? get incomePerPayPeriod {
    final amount = monthlyIncome;
    if (amount == null) return null;

    final paymentsPerMonth = switch (incomeFrequency) {
      'Weekly' => 52 / 12,
      'Bi-weekly' => 26 / 12,
      'Semi-monthly' => 2,
      _ => 1,
    };
    return amount / paymentsPerMonth;
  }

  /// Most important first.
  final List<FinancialPriority> priorities;
  final List<WalletDraft> wallets;

  /// Bills the user wants to track from the start of the account.
  final List<OnboardingBill> bills;

  /// Savings wallets created during account setup.
  final List<OnboardingSavingsAccount> savingsAccounts;

  /// Goals to create with the account.
  final List<OnboardingGoal> goals;
}

/// A bill schedule collected during account setup and saved with the profile.
class OnboardingBill {
  const OnboardingBill({
    required this.name,
    required this.amount,
    required this.category,
    required this.firstDueDate,
    required this.recurrence,
  });

  final String name;
  final double amount;
  final String category;
  final DateTime firstDueDate;
  final BillRecurrence recurrence;
}

/// Money the user has already put aside, as they report it. FinAssist records
/// the balance they declare; it never reads a real account.
class OnboardingSavingsAccount {
  const OnboardingSavingsAccount({
    required this.name,
    required this.kind,
    required this.balance,
    this.maturityDate,
    this.note,
  });

  final String name;
  final SavingsKind kind;
  final double balance;

  /// When a time deposit comes due. Null for the other kinds.
  final DateTime? maturityDate;
  final String? note;

  OnboardingSavingsAccount copyWith({
    String? name,
    SavingsKind? kind,
    double? balance,
    DateTime? maturityDate,
    String? note,
  }) {
    return OnboardingSavingsAccount(
      name: name ?? this.name,
      kind: kind ?? this.kind,
      balance: balance ?? this.balance,
      maturityDate: maturityDate ?? this.maturityDate,
      note: note ?? this.note,
    );
  }
}

/// What saved money is for. A goal claims part of a savings record through
/// [allocated]; it never moves the money, so the record's balance is the same
/// before and after.
class OnboardingGoal {
  const OnboardingGoal({
    required this.name,
    required this.kind,
    required this.targetAmount,
    required this.targetDate,
    required this.frequency,
    required this.planAmount,
    required this.note,
    this.fundedBy,
    this.allocated = 0,
  });

  final String name;
  final GoalKind kind;
  final double targetAmount;
  final DateTime? targetDate;
  final ContributionFrequency frequency;
  final double? planAmount;
  final String? note;

  /// The savings record this goal draws on, by its name in the setup list.
  /// Null when the user did not pick one, which is allowed.
  final String? fundedBy;

  /// How much of that record is already counted towards this goal.
  final double allocated;

  /// What is still to be found, never below zero.
  double get remaining {
    final left = targetAmount - allocated;
    return left < 0 ? 0 : left;
  }

  /// How far along the goal is, from 0 to 1.
  double get progress {
    if (targetAmount <= 0) return 0;
    final share = allocated / targetAmount;
    return share > 1 ? 1 : share;
  }

  bool get isReached => remaining <= 0;

  OnboardingGoal copyWith({
    String? name,
    GoalKind? kind,
    double? targetAmount,
    DateTime? targetDate,
    ContributionFrequency? frequency,
    double? planAmount,
    String? note,
    String? fundedBy,
    double? allocated,
    bool clearFunding = false,
  }) {
    return OnboardingGoal(
      name: name ?? this.name,
      kind: kind ?? this.kind,
      targetAmount: targetAmount ?? this.targetAmount,
      targetDate: targetDate ?? this.targetDate,
      frequency: frequency ?? this.frequency,
      planAmount: planAmount ?? this.planAmount,
      note: note ?? this.note,
      fundedBy: clearFunding ? null : (fundedBy ?? this.fundedBy),
      allocated: clearFunding ? 0 : (allocated ?? this.allocated),
    );
  }
}

/// What is left of [record] once every goal drawing on it is counted.
double unallocatedSavings(
  OnboardingSavingsAccount record,
  Iterable<OnboardingGoal> goals, {
  OnboardingGoal? ignoring,
}) {
  var claimed = 0.0;
  for (final goal in goals) {
    if (identical(goal, ignoring)) continue;
    if (goal.fundedBy == record.name) claimed += goal.allocated;
  }
  final left = record.balance - claimed;
  return left < 0 ? 0 : left;
}
