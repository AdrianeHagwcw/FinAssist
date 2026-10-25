import 'package:cloud_firestore/cloud_firestore.dart';

import 'app_transaction.dart';

const billsPlaceholderWalletId = 'new:bills';
const savingsPlaceholderWalletId = 'new:savings';

/// Kind of money holder. Decides the wallet's icon and default name.
enum WalletType {
  cash('Cash', 'assets/icons/icons8-banknotes-96.png'),
  gcash('GCash', 'assets/icons/icons8-mobile-payment-96.png'),
  maya('Maya', 'assets/icons/icons8-wallet-96.png'),
  bank('Bank', 'assets/icons/bank-96.png'),
  ewallet('E-Wallet', 'assets/icons/icons8-wallet-96.png'),
  other('Other', 'assets/icons/icons8-money-box-96.png');

  const WalletType(this.label, this.iconAsset);

  final String label;

  /// Colored icon file for this wallet type.
  final String iconAsset;

  /// Reads a stored type name, falling back to [other] for unknown values.
  static WalletType fromName(String? name) {
    return WalletType.values.firstWhere(
      (type) => type.name == name,
      orElse: () => WalletType.other,
    );
  }
}

/// How often an account pays its interest. Banks differ, so besides the
/// usual ones the user can set any number of months, or every day, as
/// e-wallet savings such as GSave and Maya Savings pay.
class InterestPayout {
  const InterestPayout._(this.months);

  /// Every [months] months, from 1 to 12.
  const InterestPayout.everyMonths(int months) : this._(months);

  static const daily = InterestPayout._(0);
  static const monthly = InterestPayout._(1);
  static const quarterly = InterestPayout._(3);
  static const semiAnnual = InterestPayout._(6);
  static const yearly = InterestPayout._(12);

  /// The choices offered first; anything else is set under Custom.
  static const presets = [daily, monthly, quarterly, semiAnnual, yearly];

  /// Months between payments; 0 for every day.
  final int months;

  bool get isDaily => months == 0;
  bool get isPreset => presets.contains(this);
  bool get isValid => months >= 0 && months <= 12;

  /// Months between reminders. Interest paid daily is a few centavos at a
  /// time, so it is added once a month, as a bank statement shows it.
  int get remindEvery => isDaily ? 1 : months;

  /// "Every day", "Every month", "Every 6 months".
  String get label => switch (months) {
    0 => 'Every day',
    1 => 'Every month',
    12 => 'Every year',
    _ => 'Every $months months',
  };

  /// A short stable name, for keys and older saved records.
  String get id => switch (months) {
    0 => 'daily',
    1 => 'monthly',
    3 => 'quarterly',
    6 => 'semiAnnual',
    12 => 'yearly',
    _ => 'every$months',
  };

  /// Whether the reminder to add it comes on [day], the 1st of a month:
  /// every month, or every few months counted from January, so every 3
  /// months is January, April, July and October.
  bool remindsOn(DateTime day) =>
      day.day == 1 && (day.year * 12 + day.month - 1) % remindEvery == 0;

  /// Reads a saved record: the number of months, or the name an older
  /// version saved. Anything else starts on monthly, as most banks pay.
  static InterestPayout fromStored({Object? months, Object? name}) {
    if (months is num) {
      final payout = InterestPayout._(months.toInt());
      if (payout.isValid) return payout;
    }
    for (final preset in presets) {
      if (preset.id == name) return preset;
    }
    return monthly;
  }

  @override
  bool operator ==(Object other) =>
      other is InterestPayout && other.months == months;

  @override
  int get hashCode => months.hashCode;
}

/// The share of interest on peso deposits that banks keep as tax before
/// paying it.
const double interestTaxRate = 0.20;

/// What reaches the account of [gross] interest, once the tax is taken.
double afterTax(double gross) => gross * (1 - interestTaxRate);

/// The label every interest income is recorded under, wherever it is added.
const String interestIncomeLabel = 'Interest';

/// What a wallet is for.
///
/// Money kept for bills and for savings sits in its own wallet, so the balance
/// the user sees is only what is theirs to spend. Those two are left out of
/// the total balance and out of Safe to Spend.
enum WalletPurpose {
  spending,
  bills('Bills', 'assets/icons/icons8-receipt-96.png'),
  savings('Savings', 'assets/icons/icons8-money-box-96.png');

  const WalletPurpose([this.defaultName, this.iconAsset]);

  /// The name given to the wallet the app creates for this purpose.
  final String? defaultName;

  /// Icon shown instead of the wallet type's own.
  final String? iconAsset;

  static WalletPurpose fromName(String? name) {
    return WalletPurpose.values.firstWhere(
      (purpose) => purpose.name == name,
      orElse: () => WalletPurpose.spending,
    );
  }
}

/// A wallet the user is adding during onboarding, before it is saved.
/// What a savings record is: where the money is kept, not what it is for.
/// A goal says what it is for, and claims part of a record through its own
/// saved amount.
enum SavingsKind {
  savingsDeposit(
    'Savings Deposit',
    "Earns interest. Taking money out follows your bank's rules.",
  ),
  demandDeposit('Demand Deposit', 'No interest. You can withdraw anytime.'),
  general('General savings', 'Cash, an envelope, money kept by hand'),
  account('Savings account', 'Money you keep in a bank or e-wallet account'),
  timeDeposit(
    'Time Deposit',
    'Earns interest, but stays locked until an end date. Taking it out '
        'early may cost you.',
  ),
  government(
    'Government savings',
    'SSS, Pag-IBIG MP2 or GSIS. You cannot take it out anytime.',
  );

  const SavingsKind(this.label, this.hint);

  final String label;

  /// One line under the choice, so the difference is plain.
  final String hint;

  /// Money that cannot simply be withdrawn today. It is still savings, but
  /// it should never read as cash the user could spend this week.
  bool get isLockedAway =>
      this == SavingsKind.timeDeposit || this == SavingsKind.government;

  bool get isInterestBearing =>
      this == SavingsKind.timeDeposit || this == SavingsKind.savingsDeposit;

  /// Reads a stored name, including the kinds used before these three:
  /// an emergency fund is a goal now, so its money is general savings.
  static SavingsKind fromName(String? name) {
    switch (name) {
      case 'savingsDeposit':
        return SavingsKind.savingsDeposit;
      case 'demandDeposit':
        return SavingsKind.demandDeposit;
      case 'account':
      case 'savingsAccount':
        return SavingsKind.account;
      case 'timeDeposit':
        return SavingsKind.timeDeposit;
      case 'government':
        return SavingsKind.government;
      default:
        return SavingsKind.general;
    }
  }
}

const maximumAnnualInterestRatePercent = 100.0;

bool isValidAnnualInterestRatePercent(double? rate) =>
    rate != null &&
    rate.isFinite &&
    rate >= 0 &&
    rate <= maximumAnnualInterestRatePercent;

bool isEWalletType(WalletType type) =>
    type == WalletType.gcash ||
    type == WalletType.maya ||
    type == WalletType.ewallet;

bool isBankOrEWalletType(WalletType type) =>
    type == WalletType.bank || isEWalletType(type);

/// Estimates simple annual interest for one account. Returns null when the
/// balance or rate is unavailable or outside the supported range.
double? calculateAnnualInterestEstimate({
  required double? balance,
  required double? annualInterestRatePercent,
}) {
  final rate = annualInterestRatePercent;
  if (balance == null ||
      !balance.isFinite ||
      balance < 0 ||
      !isValidAnnualInterestRatePercent(rate)) {
    return null;
  }
  return balance * rate! / 100;
}

class WalletDraft {
  const WalletDraft({
    required this.type,
    required this.name,
    required this.startingBalance,
    this.id,
    this.receivesIncome = false,
    this.balanceRecorded = true,
    this.annualInterestRatePercent,
    this.purpose = WalletPurpose.spending,
    this.savingsKind,
  });

  final WalletType type;
  final String? id;

  /// Custom name such as "BPI Savings"; defaults to the type label.
  final String name;
  final double startingBalance;

  /// Whether the user's main income is paid into this wallet.
  final bool receivesIncome;
  final bool balanceRecorded;
  final double? annualInterestRatePercent;
  final WalletPurpose purpose;
  final String? savingsKind;

  double? get estimatedAnnualInterestIncome {
    if (!isBankOrEWalletType(type)) return null;
    return calculateAnnualInterestEstimate(
      balance: balanceRecorded ? startingBalance : null,
      annualInterestRatePercent: annualInterestRatePercent,
    );
  }

  WalletDraft copyWith({
    bool? receivesIncome,
    bool? balanceRecorded,
    double? annualInterestRatePercent,
    bool clearAnnualInterestRate = false,
    String? name,
    String? id,
  }) {
    return WalletDraft(
      id: id ?? this.id,
      type: type,
      name: name ?? this.name,
      startingBalance: startingBalance,
      receivesIncome: receivesIncome ?? this.receivesIncome,
      balanceRecorded: balanceRecorded ?? this.balanceRecorded,
      annualInterestRatePercent: clearAnnualInterestRate
          ? null
          : annualInterestRatePercent ?? this.annualInterestRatePercent,
      purpose: purpose,
      savingsKind: savingsKind,
    );
  }
}

/// A saved wallet, as stored in `users/{uid}/wallets`.
class Wallet {
  const Wallet({
    required this.id,
    required this.name,
    required this.type,
    required this.balance,
    required this.startingBalance,
    required this.receivesIncome,
    required this.archived,
    required this.sortOrder,
    this.hasRecordedBalance = true,
    this.annualInterestRatePercent,
    this.purpose = WalletPurpose.spending,
    this.savingsKind,
    this.maturityDate,
    this.depositStartDate,
    this.createdAt,
    this.interestPayout = InterestPayout.monthly,
    this.serviceCharge,
  });

  /// Reads a stored wallet document.
  ///
  /// Every field falls back to a safe value, so one malformed record written
  /// by an older build can't break the whole wallet list.
  factory Wallet.fromMap(String id, Map<String, dynamic>? data) {
    final map = data ?? const <String, dynamic>{};
    final type = WalletType.fromName(_asString(map['type']));
    final name = _asString(map['name'])?.trim();

    return Wallet(
      id: id,
      name: name == null || name.isEmpty ? type.label : name,
      type: type,
      balance: _asDouble(map['balance']),
      hasRecordedBalance: map['balanceRecorded'] is bool
          ? map['balanceRecorded'] as bool
          : map['balance'] is num &&
                (map['balance'] as num).toDouble().isFinite,
      startingBalance: _asDouble(map['startingBalance']),
      receivesIncome: map['receivesIncome'] == true,
      archived: map['archived'] == true,
      sortOrder: _asDouble(map['sortOrder']).toInt(),
      annualInterestRatePercent: _asValidInterestRate(
        map['annualInterestRatePercent'],
      ),
      purpose: WalletPurpose.fromName(_asString(map['purpose'])),
      savingsKind: _asString(map['savingsKind']),
      maturityDate: _asDate(map['maturityDate']),
      depositStartDate: _asDate(map['depositStartDate']),
      createdAt: _asDate(map['createdAt']),
      interestPayout: InterestPayout.fromStored(
        months: map['interestPayoutMonths'],
        name: map['interestPayout'],
      ),
      serviceCharge:
          map['serviceCharge'] is num &&
              (map['serviceCharge'] as num).toDouble().isFinite &&
              (map['serviceCharge'] as num) > 0
          ? (map['serviceCharge'] as num).toDouble()
          : null,
    );
  }

  final String id;
  final String name;
  final WalletType type;

  /// Current money in this wallet, kept in step with its transactions.
  final double balance;
  final bool hasRecordedBalance;

  /// What the wallet held when it was first added.
  final double startingBalance;

  /// Whether the user's main income is paid into this wallet.
  final bool receivesIncome;

  /// Archived wallets stay in Firestore so old transactions keep their name,
  /// but they are hidden from the wallet list and the total balance.
  final bool archived;

  /// Position in the wallet list, lowest first.
  final int sortOrder;
  final double? annualInterestRatePercent;

  /// What the wallet holds money for. Bills and savings wallets are money the
  /// user has already committed, so they are shown apart from spending money.
  final WalletPurpose purpose;
  final String? savingsKind;

  /// When an interest-bearing deposit started earning interest.
  final DateTime? depositStartDate;

  /// When the wallet record was created, when available.
  final DateTime? createdAt;

  /// When a time deposit or legacy government savings comes due.
  final DateTime? maturityDate;

  /// How often this account pays its interest.
  final InterestPayout interestPayout;

  /// The service charge last paid from this wallet to send money or pay a
  /// bill. A bank's or e-wallet's fee is the same each time, so it is filled
  /// in when the user adds one again. Null until one is used.
  final double? serviceCharge;

  /// Whether this account pays interest now and then, for the user to add as
  /// income when it comes: a bank or e-wallet with a rate, or a savings
  /// deposit. A time deposit pays at its end date instead, and cash and
  /// demand deposits earn nothing.
  bool get paysRegularInterest {
    final rate = annualInterestRatePercent;
    if (archived || earnsNoInterest || rate == null || rate <= 0) {
      return false;
    }
    return purpose == WalletPurpose.savings
        ? savingsType == SavingsKind.savingsDeposit
        : isBankOrEWallet;
  }

  /// About what one interest payment brings in after tax, at today's
  /// balance; null when this account does not pay interest regularly.
  double? get interestPerPayoutAfterTax {
    if (!paysRegularInterest || balance <= 0) return null;
    final yearly = balance * annualInterestRatePercent! / 100;
    // One payment, or a month of daily ones: what comes between reminders.
    return afterTax(yearly * interestPayout.remindEvery / 12);
  }

  /// True once that day has arrived and the money is still recorded here.
  /// The user still has to say what they did with it; nothing moves on its
  /// own, because FinAssist cannot see a real account.
  bool maturedBy(DateTime now) {
    final due = maturityDate;
    if (due == null || balance <= 0 || archived) return false;
    final day = DateTime(due.year, due.month, due.day);
    final today = DateTime(now.year, now.month, now.day);
    return !day.isAfter(today);
  }

  /// The day this savings can be taken out, while that day is still ahead:
  /// a time deposit before its end date. Null for money that can be taken
  /// out now, or whose date is not recorded.
  DateTime? readyOn(DateTime now) {
    final due = maturityDate;
    if (!isLockedSavings || due == null) return null;
    final day = DateTime(due.year, due.month, due.day);
    return day.isAfter(DateTime(now.year, now.month, now.day)) ? day : null;
  }

  /// True for the bills and savings wallets, whose money is no longer the
  /// user's to spend.
  bool get isSetAside => purpose != WalletPurpose.spending;

  /// Savings the user cannot simply take out: a time deposit before its date,
  /// or money with SSS, GSIS or Pag-IBIG. Counting it with ordinary savings
  /// would promise money that is years away.
  bool get isLockedSavings =>
      purpose == WalletPurpose.savings &&
      SavingsKind.fromName(savingsKind).isLockedAway;

  SavingsKind get savingsType => SavingsKind.fromName(savingsKind);

  /// Cash and demand deposits earn nothing, whatever rate a record carries.
  bool get earnsNoInterest =>
      type == WalletType.cash ||
      (purpose == WalletPurpose.savings &&
          savingsType == SavingsKind.demandDeposit);

  bool get isMaturedTimeDeposit =>
      purpose == WalletPurpose.savings &&
      savingsType == SavingsKind.timeDeposit &&
      maturedBy(DateTime.now());

  double? estimatedTimeDepositInterest() {
    // A deposit filled by transfers from the user's wallets starts at zero
    // and holds its principal as its balance.
    final principal = startingBalance > 0 ? startingBalance : balance;
    final rate = annualInterestRatePercent;
    final start = depositStartDate;
    final maturity = maturityDate;
    if (purpose != WalletPurpose.savings ||
        savingsType != SavingsKind.timeDeposit ||
        !hasRecordedBalance ||
        !balance.isFinite ||
        balance < 0 ||
        principal < 0 ||
        !principal.isFinite ||
        !isValidAnnualInterestRatePercent(rate) ||
        start == null ||
        maturity == null ||
        !_dateOnly(maturity).isAfter(_dateOnly(start))) {
      return null;
    }
    return calculateSimpleInterest(
      principal: principal,
      annualInterestRatePercent: rate!,
      days: calendarDaysBetween(start, maturity),
    );
  }

  double? estimatedMaturityValue() {
    final interest = estimatedTimeDepositInterest();
    return interest == null ? null : startingBalance + interest;
  }

  double? estimatedSavingsDepositInterest({
    required Iterable<AppTransaction> transactions,
    DateTime? asOf,
  }) {
    final start = depositStartDate;
    final rate = annualInterestRatePercent;
    if (purpose != WalletPurpose.savings ||
        savingsType != SavingsKind.savingsDeposit ||
        !hasRecordedBalance ||
        !balance.isFinite ||
        balance < 0 ||
        !isValidAnnualInterestRatePercent(rate) ||
        start == null) {
      return null;
    }

    final now = _dateOnly(asOf ?? DateTime.now());
    final enteredStart = _dateOnly(start);
    if (!enteredStart.isBefore(now)) return 0;
    final created = createdAt == null ? enteredStart : _dateOnly(createdAt!);
    final earningStart = enteredStart.isAfter(created) ? enteredStart : created;
    if (!earningStart.isBefore(now)) return 0;

    final ordered =
        transactions
            .where(
              (transaction) =>
                  transaction.involvesWallet(id) &&
                  !_dateOnly(transaction.date).isBefore(created) &&
                  !_dateOnly(transaction.date).isAfter(now),
            )
            .toList()
          ..sort((a, b) => a.date.compareTo(b.date));

    var runningBalance = startingBalance;
    var previousDate = created;
    var weightedBalanceDays = 0.0;
    for (final transaction in ordered) {
      final transactionDate = _dateOnly(transaction.date);
      if (transactionDate.isBefore(previousDate)) continue;
      if (transactionDate.isAfter(earningStart) && previousDate.isBefore(now)) {
        final intervalStart = previousDate.isAfter(earningStart)
            ? previousDate
            : earningStart;
        final intervalEnd = transactionDate.isBefore(now)
            ? transactionDate
            : now;
        if (intervalEnd.isAfter(intervalStart)) {
          weightedBalanceDays +=
              (runningBalance > 0 ? runningBalance : 0) *
              calendarDaysBetween(intervalStart, intervalEnd);
        }
      }
      runningBalance += transaction.balanceDeltaFor(id);
      if (!runningBalance.isFinite) return null;
      previousDate = transactionDate;
    }

    final intervalStart = previousDate.isAfter(earningStart)
        ? previousDate
        : earningStart;
    if (now.isAfter(intervalStart)) {
      weightedBalanceDays +=
          (runningBalance > 0 ? runningBalance : 0) *
          calendarDaysBetween(intervalStart, now);
    }
    if (!weightedBalanceDays.isFinite) return null;
    return calculateSimpleInterest(
      principal: weightedBalanceDays,
      annualInterestRatePercent: rate!,
      days: 1,
    );
  }

  String get iconAsset => purpose.iconAsset ?? type.iconAsset;

  bool get isEWallet => isEWalletType(type);

  bool get isBankOrEWallet => isBankOrEWalletType(type);

  double? get estimatedAnnualInterestIncome {
    if (!isBankOrEWallet || !hasRecordedBalance) return null;
    return calculateAnnualInterestEstimate(
      balance: balance,
      annualInterestRatePercent: annualInterestRatePercent,
    );
  }

  static String? _asString(Object? value) => value is String ? value : null;

  static double _asDouble(Object? value) =>
      value is num && value.toDouble().isFinite ? value.toDouble() : 0;

  static double? _asValidInterestRate(Object? value) {
    if (value is! num) return null;
    final rate = value.toDouble();
    return isValidAnnualInterestRatePercent(rate) ? rate : null;
  }

  /// Reads a Firestore timestamp, a DateTime, or nothing at all.
  static DateTime? _asDate(Object? value) {
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    return null;
  }
}

DateTime _dateOnly(DateTime date) =>
    DateTime.utc(date.year, date.month, date.day);

int calendarDaysBetween(DateTime start, DateTime end) =>
    _dateOnly(end).difference(_dateOnly(start)).inDays;

double calculateSimpleInterest({
  required double principal,
  required double annualInterestRatePercent,
  required int days,
}) {
  if (!principal.isFinite ||
      principal < 0 ||
      !isValidAnnualInterestRatePercent(annualInterestRatePercent) ||
      days < 0) {
    throw ArgumentError(
      'Simple-interest inputs must be valid and nonnegative.',
    );
  }
  return principal * annualInterestRatePercent / 100 * (days / 365);
}

/// Orders wallets the way they are shown: by [Wallet.sortOrder], then by name
/// so wallets saved without an order still come out in a stable sequence.
void sortWallets(List<Wallet> wallets) {
  wallets.sort((a, b) {
    final byOrder = a.sortOrder.compareTo(b.sortOrder);
    return byOrder != 0
        ? byOrder
        : a.name.toLowerCase().compareTo(b.name.toLowerCase());
  });
}

/// The money the user still has to spend: every wallet that isn't archived,
/// leaving out the bills and savings wallets, whose money is already
/// committed. This is the figure shown as the total balance.
double totalWalletBalance(Iterable<Wallet> wallets) {
  return wallets
      .where((wallet) => !wallet.archived && !wallet.isSetAside)
      .fold<double>(0, (total, wallet) => total + wallet.balance);
}

/// What is held in the bills and savings wallets, shown beside the total
/// balance so the user can still see it is there.
double setAsideWalletBalance(Iterable<Wallet> wallets) {
  return wallets
      .where((wallet) => !wallet.archived && wallet.isSetAside)
      .fold<double>(0, (total, wallet) => total + wallet.balance);
}

/// The balance of the wallet kept for [purpose], or zero when the user has
/// none yet.
double walletBalanceFor(Iterable<Wallet> wallets, WalletPurpose purpose) {
  return wallets
      .where((wallet) => !wallet.archived && wallet.purpose == purpose)
      .fold<double>(0, (total, wallet) => total + wallet.balance);
}

/// Savings the user could reach today, which is what the savings balance on
/// Home means. A time deposit or government savings is left out.
double reachableSavingsBalance(Iterable<Wallet> wallets) {
  return wallets
      .where(
        (wallet) =>
            !wallet.archived &&
            wallet.purpose == WalletPurpose.savings &&
            !wallet.isLockedSavings,
      )
      .fold<double>(0, (total, wallet) => total + wallet.balance);
}

/// Savings held somewhere the user cannot draw on yet, shown on its own so
/// the figure above it stays true.
double lockedSavingsBalance(Iterable<Wallet> wallets) {
  return wallets
      .where((wallet) => !wallet.archived && wallet.isLockedSavings)
      .fold<double>(0, (total, wallet) => total + wallet.balance);
}

/// The [Wallet.sortOrder] a newly added wallet should take.
int nextWalletSortOrder(Iterable<Wallet> wallets) {
  var highest = -1;
  for (final wallet in wallets) {
    if (wallet.sortOrder > highest) highest = wallet.sortOrder;
  }
  return highest + 1;
}

/// The wallet that receives the user's income, or null if none is marked.
Wallet? incomeWallet(Iterable<Wallet> wallets) {
  for (final wallet in wallets) {
    if (wallet.receivesIncome && !wallet.archived) return wallet;
  }
  return null;
}

/// Which wallets need their `receivesIncome` flag changed so that only
/// [selectedId] receives income. Wallets already correct are left out, so the
/// resulting write touches as few documents as possible.
Map<String, bool> incomeWalletUpdates(
  Iterable<Wallet> wallets,
  String selectedId,
) {
  final updates = <String, bool>{};
  for (final wallet in wallets) {
    final shouldReceive = wallet.id == selectedId;
    if (wallet.receivesIncome != shouldReceive) {
      updates[wallet.id] = shouldReceive;
    }
  }
  return updates;
}
