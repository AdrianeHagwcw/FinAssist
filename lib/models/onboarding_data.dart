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
    required this.priorities,
    required this.wallets,
    this.bills = const [],
    this.savingsAccounts = const [],
    this.goals = const [],
  });

  final String name;
  final bool notificationsEnabled;

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
    this.annualInterestRatePercent,
    this.depositStartDate,
    this.maturityDate,
    this.note,
    this.interestPayout = InterestPayout.monthly,
  });

  final String name;
  final SavingsKind kind;
  final double balance;

  /// How often a savings deposit pays its interest.
  final InterestPayout interestPayout;
  final double? annualInterestRatePercent;
  final DateTime? depositStartDate;

  /// When a time deposit comes due. Null for the other kinds.
  final DateTime? maturityDate;
  final String? note;

  double? get estimatedSimpleInterest {
    final rate = annualInterestRatePercent;
    final start = depositStartDate;
    if (kind == SavingsKind.demandDeposit) return 0;
    if (!kind.isInterestBearing ||
        rate == null ||
        !isValidAnnualInterestRatePercent(rate) ||
        start == null ||
        !balance.isFinite ||
        balance < 0) {
      return null;
    }
    final end = kind == SavingsKind.timeDeposit ? maturityDate : DateTime.now();
    if (end == null) return null;
    final estimateStart =
        kind == SavingsKind.savingsDeposit &&
            calendarDaysBetween(start, end) > 0
        ? end
        : start;
    final days = calendarDaysBetween(estimateStart, end);
    if (kind == SavingsKind.timeDeposit && days <= 0) return null;
    return calculateSimpleInterest(
      principal: balance,
      annualInterestRatePercent: rate,
      days: days < 0 ? 0 : days,
    );
  }

  OnboardingSavingsAccount copyWith({
    String? name,
    SavingsKind? kind,
    double? balance,
    double? annualInterestRatePercent,
    DateTime? depositStartDate,
    bool clearInterestRate = false,
    bool clearDepositStartDate = false,
    bool clearMaturityDate = false,
    DateTime? maturityDate,
    String? note,
    InterestPayout? interestPayout,
  }) {
    return OnboardingSavingsAccount(
      name: name ?? this.name,
      kind: kind ?? this.kind,
      balance: balance ?? this.balance,
      annualInterestRatePercent: clearInterestRate
          ? null
          : annualInterestRatePercent ?? this.annualInterestRatePercent,
      depositStartDate: clearDepositStartDate
          ? null
          : depositStartDate ?? this.depositStartDate,
      maturityDate: clearMaturityDate
          ? null
          : maturityDate ?? this.maturityDate,
      note: note ?? this.note,
      interestPayout: interestPayout ?? this.interestPayout,
    );
  }
}

/// What saved money is for. A goal can claim part of a wallet's balance
/// through [allocated]; it never moves the money, so the balance is unchanged.
class OnboardingGoal {
  const OnboardingGoal({
    required this.name,
    required this.kind,
    required this.targetAmount,
    required this.targetDate,
    required this.frequency,
    required this.planAmount,
    required this.note,
    this.customInterval,
    this.fundedBy,
    double allocated = 0,
    this.fundingByWalletDraftId = const {},
    this.fundingSource,
  }) : _recordAllocated = allocated;

  final String name;
  final GoalKind kind;
  final double targetAmount;
  final DateTime? targetDate;
  final ContributionFrequency frequency;

  /// The rhythm the user set when [frequency] is Custom.
  final SavingInterval? customInterval;
  final double? planAmount;
  final String? note;

  /// Legacy savings-record name used by older onboarding data.
  /// New goals use [fundingByWalletDraftId] instead.
  final String? fundedBy;

  /// How much of [fundedBy] is already counted towards this goal.
  final double _recordAllocated;

  /// How much of each starting wallet, by draft id, is counted towards this
  /// goal. Cash and bank together give more than one entry.
  final Map<String, double> fundingByWalletDraftId;
  final GoalFundingSource? fundingSource;

  /// Everything already counted towards this goal.
  double get allocated => fundingByWalletDraftId.isEmpty
      ? _recordAllocated
      : fundingByWalletDraftId.values.fold(
          0,
          (total, amount) => total + amount,
        );

  /// The starting wallet holding most of the goal's money.
  String? get fundingWalletDraftId => mainFundingWallet(fundingByWalletDraftId);

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
    SavingInterval? customInterval,
    double? planAmount,
    String? note,
    String? fundedBy,
    double? allocated,
    Map<String, double>? fundingByWalletDraftId,
    GoalFundingSource? fundingSource,
    bool clearFunding = false,
  }) {
    return OnboardingGoal(
      name: name ?? this.name,
      kind: kind ?? this.kind,
      targetAmount: targetAmount ?? this.targetAmount,
      targetDate: targetDate ?? this.targetDate,
      frequency: frequency ?? this.frequency,
      customInterval: customInterval ?? this.customInterval,
      planAmount: planAmount ?? this.planAmount,
      note: note ?? this.note,
      fundedBy: clearFunding ? null : (fundedBy ?? this.fundedBy),
      allocated: clearFunding ? 0 : (allocated ?? _recordAllocated),
      fundingByWalletDraftId: clearFunding
          ? const {}
          : (fundingByWalletDraftId ?? this.fundingByWalletDraftId),
      fundingSource: clearFunding
          ? null
          : (fundingSource ?? this.fundingSource),
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
