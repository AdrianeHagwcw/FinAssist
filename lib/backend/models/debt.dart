import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';

import 'bill.dart';

/// Which way the money is owed.
enum DebtDirection {
  /// The user borrowed or bought on installment, and pays it back.
  iOwe,

  /// Someone owes the user.
  owedToMe;

  static DebtDirection fromName(String? name) => DebtDirection.values
      .firstWhere((d) => d.name == name, orElse: () => DebtDirection.iOwe);
}

/// What is being paid off. Things bought on installment are listed under
/// Installments; borrowed money ([isLoan]) under Debts. Both are paid the
/// same way, through the Bill Planner.
enum DebtCategory {
  gadget('Gadget or appliance'),
  personalLoan('Bank or lending company'),
  governmentLoan('SSS, Pag-IBIG or GSIS'),
  creditCard('Credit card installment'),
  cardCashLoan('Cash from a credit card'),
  buyNowPayLater('Buy now, pay later'),
  familyFriend('Family or friend'),
  otherLoan('Other'),
  other('Other');

  const DebtCategory(this.label);

  final String label;

  /// Borrowed money, as opposed to something bought on installment.
  bool get isLoan => switch (this) {
    personalLoan || governmentLoan || cardCashLoan || familyFriend => true,
    otherLoan => true,
    _ => false,
  };

  /// A bank, lending company, card issuer or government fund, which must
  /// tell the borrower the interest before the loan is signed (Truth in
  /// Lending Act, RA 3765). Their rate is asked for, not optional.
  bool get mustDiscloseRate =>
      this == personalLoan || this == governmentLoan || this == cardCashLoan;

  /// The kinds of thing bought on installment, for the Installments form.
  static List<DebtCategory> get installmentKinds =>
      values.where((kind) => !kind.isLoan).toList();

  /// The kinds of loan, for the Debts form.
  static List<DebtCategory> get loanKinds =>
      values.where((kind) => kind.isLoan).toList();

  static DebtCategory fromName(String? name) => DebtCategory.values.firstWhere(
    (c) => c.name == name,
    orElse: () => DebtCategory.other,
  );
}

/// The kind of installment its name suggests, or null when the name says
/// nothing: "Phone" is a gadget, "SSS loan" a government loan, "Tita Baby"
/// family. Saves a choice the user would otherwise make by hand.
DebtCategory? guessDebtCategory(String name) {
  final text = name.toLowerCase();
  bool has(List<String> words) => words.any(
    (word) => RegExp('\\b${RegExp.escape(word)}\\b').hasMatch(text),
  );

  // Checked in this order, so "SSS loan" is the government's, not any loan,
  // and "Cash2Go" is cash taken from a card, not a card installment.
  if (has(['sss', 'pag-ibig', 'pagibig', 'hdmf', 'gsis', 'philhealth'])) {
    return DebtCategory.governmentLoan;
  }
  if (has(['cash2go', 'cash 2 go', 'cash advance', 'card cash'])) {
    return DebtCategory.cardCashLoan;
  }
  if (has(['credit card', 'card'])) return DebtCategory.creditCard;
  if (has([
    'paylater',
    'spaylater',
    'lazpaylater',
    'ggives',
    'gcredit',
    'atome',
    'billease',
    'home credit',
    'maya credit',
  ])) {
    return DebtCategory.buyNowPayLater;
  }
  if (has([
    'phone',
    'cellphone',
    'cp',
    'iphone',
    'samsung',
    'oppo',
    'vivo',
    'xiaomi',
    'realme',
    'laptop',
    'computer',
    'tablet',
    'ipad',
    'tv',
    'television',
    'ref',
    'refrigerator',
    'aircon',
    'washing machine',
    'electric fan',
    'camera',
    'console',
    'gadget',
    'appliance',
  ])) {
    return DebtCategory.gadget;
  }
  if (has([
    'tita',
    'tito',
    'mama',
    'papa',
    'nanay',
    'tatay',
    'kuya',
    'ate',
    'lola',
    'lolo',
    'pinsan',
    'friend',
    'kaibigan',
    'family',
  ])) {
    return DebtCategory.familyFriend;
  }
  if (has([
    'loan',
    'utang',
    'gloan',
    'lending',
    'tala',
    'cashalo',
    'digido',
    'juanhand',
  ])) {
    return DebtCategory.personalLoan;
  }
  return null;
}

/// How often an installment is paid. Kept to what installments actually use.
enum PaymentFrequency {
  monthly('Every month', BillRecurrence.monthly),
  semiMonthly('Twice a month', BillRecurrence.semiMonthly),
  fortnightly('Every 2 weeks', BillRecurrence.fortnightly),
  weekly('Every week', BillRecurrence.weekly);

  const PaymentFrequency(this.label, this.recurrence);

  final String label;
  final BillRecurrence recurrence;

  /// How many payments fall in a year, to turn a rate per payment into a
  /// rate a year.
  int get perYear => switch (this) {
    PaymentFrequency.monthly => 12,
    PaymentFrequency.semiMonthly => 24,
    PaymentFrequency.fortnightly => 26,
    PaymentFrequency.weekly => 52,
  };

  /// Under one payment's amount: "Each month", or "Twice a month".
  String get eachLabel => switch (this) {
    PaymentFrequency.monthly => 'Each month',
    PaymentFrequency.weekly => 'Each week',
    _ => label,
  };

  static PaymentFrequency fromName(String? name) =>
      PaymentFrequency.values.firstWhere(
        (f) => f.name == name,
        orElse: () => PaymentFrequency.monthly,
      );
}

/// What a rate the lender quoted is counted per.
enum RatePeriod {
  month('a month'),
  year('a year'),

  /// One rate for the whole loan, such as 20% on ₱5,600.
  wholeLoan('for the whole loan');

  const RatePeriod(this.label);

  /// As it reads in a sentence: "1% a month".
  final String label;

  /// As a choice on its own, under "Charged".
  String get choiceLabel => switch (this) {
    RatePeriod.month => 'Every month',
    RatePeriod.year => 'Every year',
    RatePeriod.wholeLoan => 'Once (whole loan)',
  };

  static RatePeriod fromName(String? name) => RatePeriod.values.firstWhere(
    (period) => period.name == name,
    orElse: () => RatePeriod.month,
  );
}

/// How a lender works out interest.
enum InterestBasis {
  /// On the whole amount borrowed, for the whole time, even as it is paid
  /// down: how most cash loans and card installments are quoted (an
  /// "add-on" rate).
  wholeAmount(
    'Same every payment',
    'Like Cash2Go and most cash loans',
    'the same every payment',
  ),

  /// Only on what is still owed, so each payment carries less interest than
  /// the one before (a "diminishing balance"): most home and car loans.
  remainingBalance(
    'Less as you pay',
    'Like SSS, Pag-IBIG, home and car loans',
    'less as you pay',
  );

  const InterestBasis(this.label, this.example, this.inSentence);

  /// Described by what the user sees on their payments, not the lender's
  /// words for it ("add-on", "diminishing balance").
  final String label;
  final String example;

  /// As it reads after the rate: "1% a month, the same every payment".
  final String inSentence;

  static InterestBasis fromName(String? name) =>
      InterestBasis.values.firstWhere(
        (b) => b.name == name,
        orElse: () => InterestBasis.wholeAmount,
      );
}

enum DebtStatus { active, settled }

/// Money owed, in either direction.
///
/// One record holds both things bought on installment and money borrowed:
/// [DebtCategory.isLoan] says which. They are listed apart in the app
/// (Installments and Debts), but they share this class and the `debts`
/// collection, so nothing needs migrating between the two.
///
/// For money the user owes, the payments live in the Bill Planner as a bill
/// schedule with a last due date, so they are paid, part-paid and reminded
/// about like any other bill, and Safe to Spend already sets them aside. This
/// record holds the terms and links to that schedule.
class Debt {
  const Debt({
    required this.id,
    required this.direction,
    required this.name,
    required this.category,
    required this.principal,
    required this.status,
    this.perPayment = 0,
    this.paymentCount = 0,
    this.lastPayment = 0,
    this.frequency = PaymentFrequency.monthly,
    this.firstDueDate,
    this.billId,
    this.received = 0,
    this.dueDate,
    this.note,
    this.paidBefore = 0,
    this.quotedRate,
    this.quotedRatePer = RatePeriod.month,
    this.rateBasis = InterestBasis.wholeAmount,
    this.fees = 0,
    this.otherKind,
    this.paidWithWalletId,
    this.paidWithLabel,
    this.paidOffAt,
    this.paidOffAmount = 0,
  });

  factory Debt.fromMap(String id, Map<String, dynamic>? data) {
    final map = data ?? const <String, dynamic>{};
    final name = map['name'] is String ? (map['name'] as String).trim() : '';

    return Debt(
      id: id,
      direction: DebtDirection.fromName(_asString(map['direction'])),
      name: name.isEmpty ? 'Debt' : name,
      category: DebtCategory.fromName(_asString(map['category'])),
      principal: _asDouble(map['principal']).abs(),
      perPayment: _asDouble(map['perPayment']).abs(),
      paymentCount: _asDouble(map['paymentCount']).toInt(),
      lastPayment: _asDouble(map['lastPayment']).abs(),
      frequency: PaymentFrequency.fromName(_asString(map['frequency'])),
      firstDueDate: _asDate(map['firstDueDate']),
      billId: _asString(map['billId']),
      received: _asDouble(map['received']),
      dueDate: _asDate(map['dueDate']),
      note: _asString(map['note']),
      status: map['status'] == DebtStatus.settled.name
          ? DebtStatus.settled
          : DebtStatus.active,
      paidBefore: _asDouble(map['paidBefore']).toInt().clamp(0, 1 << 20),
      quotedRate: map['quotedRate'] is num
          ? (map['quotedRate'] as num).toDouble().abs()
          : null,
      quotedRatePer: RatePeriod.fromName(_asString(map['quotedRatePer'])),
      rateBasis: InterestBasis.fromName(_asString(map['rateBasis'])),
      fees: _asDouble(map['fees']).abs(),
      otherKind: _asString(map['otherKind']),
      paidWithWalletId: _asString(map['paidWithWalletId']),
      paidWithLabel: _asString(map['paidWithLabel']),
      paidOffAt: _asDate(map['paidOffAt']),
      paidOffAmount: _asDouble(map['paidOffAmount']).abs(),
    );
  }

  final String id;
  final DebtDirection direction;

  /// What it's for, or who owes it.
  final String name;
  final DebtCategory category;

  /// The amount borrowed or lent.
  final double principal;

  // ------------------------------------------------ money the user owes

  final double perPayment;
  final int paymentCount;

  /// The contract's last payment when it differs from the others, such as
  /// ₱1,000 closing three payments of ₱3,000. Zero means the same as them.
  final double lastPayment;
  final PaymentFrequency frequency;
  final DateTime? firstDueDate;

  /// The bill schedule holding the payments.
  final String? billId;

  /// Payments made before the user tracked it here. They count as paid,
  /// though no wallet moved for them in the app.
  final int paidBefore;

  /// The rate the lender or store said they charge, if the user knows it.
  /// Banks and lenders must disclose the full cost before a loan is signed
  /// (Truth in Lending Act, RA 3765), so it is asked for, never required.
  final double? quotedRate;
  final RatePeriod quotedRatePer;

  /// How the quoted rate is charged.
  final InterestBasis rateBasis;

  /// Processing or service fees taken out of the loan, so less than
  /// [principal] reached the user. A cost of borrowing like interest.
  final double fees;

  /// What the user actually got: the amount borrowed less [fees].
  double get amountReceived {
    final received = principal - fees;
    return received > 0 ? received : 0;
  }

  /// What the user called the kind when they chose Other.
  final String? otherKind;

  /// The wallet the purchase was charged to, for an installment: a card or
  /// account the user already has. Display only; it never moves money.
  final String? paidWithWalletId;

  /// The card or account in the user's own words, when it is not one of
  /// their wallets, such as a credit card they did not add.
  final String? paidWithLabel;

  /// When it was paid off before its schedule ended, and what that last
  /// payment was. Null while it runs its course.
  final DateTime? paidOffAt;
  final double paidOffAmount;

  bool get paidOffEarly => paidOffAt != null;

  /// What is still owed of the money the user got, after [paidSoFar]: each
  /// payment pays back a fixed share of it, the rest being interest.
  double loanLeft(double paidSoFar) {
    final left = amountReceived - paidSoFar * (1 - interestShare);
    return left > 0.005 ? _centavos(left) : 0;
  }

  /// How a payment of [amount] that finishes it early splits: what is still
  /// owed of the money borrowed, and the rest, which is interest or a fee
  /// for paying early. Less than what is owed is a discount: no interest.
  ({double toLoan, double interest}) payoffSplit(
    double amount,
    double paidSoFar,
  ) {
    final left = loanLeft(paidSoFar);
    final toLoan = amount < left ? amount : left;
    return (toLoan: _centavos(toLoan), interest: _centavos(amount - toLoan));
  }

  /// The kind as shown: the user's own word for Other or Other loan.
  String get kindLabel {
    final own = otherKind?.trim();
    final ownWord =
        category == DebtCategory.other || category == DebtCategory.otherLoan;
    return ownWord && own != null && own.isNotEmpty ? own : category.label;
  }

  // ------------------------------------------ money owed to the user

  /// Paid back so far.
  final double received;

  /// When they said they would pay it back, if at all.
  final DateTime? dueDate;

  final String? note;
  final DebtStatus status;

  /// What the last payment is: its own amount, or the usual one.
  double get finalPayment => lastPayment > 0 ? lastPayment : perPayment;

  /// Whether the contract's last payment differs from the others.
  bool get hasDifferentLastPayment =>
      paymentCount > 1 && (finalPayment - perPayment).abs() > 0.005;

  /// Everything the user will have paid once every payment is made: the
  /// usual payments, then the last one.
  double get totalPayable =>
      paymentCount < 1 ? 0 : perPayment * (paymentCount - 1) + finalPayment;

  /// What borrowing costs on top of what the user got: interest, and any
  /// [fees] taken out. This is shown instead of an interest rate: most
  /// students don't know their rate, but "₱4,800 more than you borrowed"
  /// needs no explaining.
  double get extraCost {
    final extra = totalPayable - amountReceived;
    return extra > 0.005 ? extra : 0;
  }

  DateTime? get lastDueDate => firstDueDate == null
      ? null
      : lastDueDateFor(firstDueDate!, frequency.recurrence, paymentCount);

  /// When payment [number] (from 1) falls due.
  DateTime? dueDateOf(int number) => firstDueDate == null
      ? null
      : lastDueDateFor(firstDueDate!, frequency.recurrence, number);

  /// What payment [number] (from 1) asks for.
  double amountOf(int number) =>
      number == paymentCount && hasDifferentLastPayment
      ? finalPayment
      : perPayment;

  /// The part of every peso paid that is interest: [extraCost] out of
  /// [totalPayable]. Every payment carries the same share, so the interest
  /// recorded adds up to [extraCost] once all of them are made.
  ///
  /// Installments carry none in the app: the price the store quoted is the
  /// whole of what is paid, so this is zero for them. Loans keep their split,
  /// which early payoff and Reports still use.
  double get interestShare =>
      category.isLoan && totalPayable > 0 ? extraCost / totalPayable : 0;

  /// The interest inside payment [number] (from 1).
  double interestOf(int number) =>
      interestPartOf(amountOf(number), interestShare);

  /// The extra cost as a share of what was borrowed: ₱1,120 on ₱5,600 is 20%.
  /// The quick way to see what borrowing costs.
  double get extraCostPercent =>
      principal <= 0 ? 0 : extraCost / principal * 100;

  /// How long the payments run, in months.
  double get termMonths => paymentCount * 12 / frequency.perYear;

  /// What the payments really cost a year, as a rate, worked out from the
  /// amounts alone, so nobody needs to know their rate to see it.
  ///
  /// A quoted "add-on" rate is charged on the whole amount for the whole
  /// time, even as it is paid down, so it understates the cost: 20% extra
  /// over 12 monthly payments is about 35% a year. This is the rate at which
  /// the payments are worth exactly what was borrowed, the first one a
  /// period after borrowing (an internal rate of return), times the
  /// payments in a year. Null when nothing is paid on top.
  ///
  /// It is worked out from what the user actually got, so fees taken out
  /// count too, as the Truth in Lending Act counts them.
  double? get yearlyCostPercent {
    final received = amountReceived;
    if (extraCost <= 0 || received <= 0 || paymentCount < 1) return null;

    // What the payments are worth today at [rate] a period.
    double worth(double rate) {
      var total = 0.0;
      var discount = 1.0;
      for (var number = 1; number <= paymentCount; number++) {
        discount /= 1 + rate;
        total += amountOf(number) * discount;
      }
      return total;
    }

    // Worth falls as the rate rises, so the rate is found by halving the
    // range it lies in.
    var low = 0.0;
    var high = 1.0;
    while (worth(high) > received && high < 1000) {
      high *= 2;
    }
    for (var step = 0; step < 100; step++) {
      final middle = (low + high) / 2;
      if (worth(middle) > received) {
        low = middle;
      } else {
        high = middle;
      }
    }
    return (low + high) / 2 * frequency.perYear * 100;
  }

  /// [yearlyCostPercent] a month, the way lenders usually quote.
  double? get monthlyCostPercent {
    final yearly = yearlyCostPercent;
    return yearly == null ? null : yearly / 12;
  }

  /// Whether the payments cost more than the rate the lender quoted, read
  /// the most generous way: as an add-on rate on the whole amount for the
  /// whole time. Then the difference can only be fees or charges the
  /// quoted rate left out. A peso a payment is allowed for rounding.
  /// Fees the user told us about are not counted as a surprise.
  bool get costsMoreThanQuoted {
    final quoted = quotedRate;
    if (quoted == null || paymentCount < 1) return false;
    final allowed = switch (quotedRatePer) {
      RatePeriod.month => principal * quoted / 100 * termMonths,
      RatePeriod.year => principal * quoted / 12 / 100 * termMonths,
      RatePeriod.wholeLoan => principal * quoted / 100,
    };
    return extraCost - fees > allowed + paymentCount * 1.0 + 0.005;
  }

  /// Still to come back, for money owed to the user.
  double get stillOwedToMe {
    final left = principal - received;
    return left > 0 ? left : 0;
  }

  static String? _asString(Object? value) =>
      value is String && value.isNotEmpty ? value : null;

  static double _asDouble(Object? value) => value is num ? value.toDouble() : 0;

  static DateTime? _asDate(Object? value) =>
      value is Timestamp ? value.toDate() : null;
}

/// A loan's payments worked out from the rate the lender quoted, the way
/// lenders work them out. Each payment is rounded to the centavo and the
/// last one takes up what rounding left over, as on a loan statement.
class LoanPayments {
  const LoanPayments({
    required this.perPayment,
    required this.lastPayment,
    required this.interest,
  });

  final double perPayment;

  /// The last payment when rounding makes it differ; zero when it doesn't.
  final double lastPayment;

  /// All the interest, on top of the amount borrowed.
  final double interest;
}

double _centavos(double amount) => (amount * 100).round() / 100;

/// The payments on [principal] at [rate] percent [per] month, year or for
/// the whole loan, charged on [basis], in [count] payments [frequency].
/// Null when there is nothing to work out yet.
///
/// On the whole amount (add-on): ₱5,000 at 1% a month for 3 months is
/// ₱150 of interest, so ₱5,150 in 3 payments of ₱1,716.67, the last
/// ₱1,716.66. On what's left to pay, each payment is the same and carries
/// interest only on what is still owed.
LoanPayments? loanPayments({
  required double principal,
  required double rate,
  required RatePeriod per,
  required InterestBasis basis,
  required int count,
  required PaymentFrequency frequency,
}) {
  if (principal <= 0 || count < 1 || rate < 0) return null;
  final months = count * 12 / frequency.perYear;

  if (basis == InterestBasis.wholeAmount || per == RatePeriod.wholeLoan) {
    final interest = switch (per) {
      RatePeriod.month => principal * rate / 100 * months,
      RatePeriod.year => principal * rate / 12 / 100 * months,
      RatePeriod.wholeLoan => principal * rate / 100,
    };
    final total = _centavos(principal + interest);
    final each = _centavos(total / count);
    final last = _centavos(total - each * (count - 1));
    return LoanPayments(
      perPayment: each,
      lastPayment: (last - each).abs() > 0.005 ? last : 0,
      interest: total - principal,
    );
  }

  // On what's left to pay: the rate for one payment's stretch of time.
  final yearly = per == RatePeriod.month ? rate * 12 : rate;
  final periodic = yearly / 100 / frequency.perYear;
  final exact = periodic == 0
      ? principal / count
      : principal * periodic / (1 - math.pow(1 + periodic, -count));
  final each = _centavos(exact);
  var owed = principal;
  for (var number = 1; number < count; number++) {
    owed = owed * (1 + periodic) - each;
  }
  final last = _centavos(owed * (1 + periodic));
  return LoanPayments(
    perPayment: each,
    lastPayment: (last - each).abs() > 0.005 ? last : 0,
    interest: each * (count - 1) + last - principal,
  );
}

/// How many payments it takes to cover [total] at [perPayment] each, for
/// when the user leaves the count blank.
int paymentsToCover(double total, double perPayment) {
  if (total <= 0 || perPayment <= 0) return 0;
  return (total / perPayment - 1e-9).ceil();
}

/// The last of [count] payments that cover exactly [total] at [perPayment]
/// each, when it comes out smaller: ₱10,000 at ₱3,000 ends with ₱1,000.
/// Zero when every payment is the same.
double coveringLastPayment(double total, double perPayment, int count) {
  if (count < 2 || perPayment <= 0) return 0;
  final rest = ((total - perPayment * (count - 1)) * 100).round() / 100;
  return rest > 0 && rest < perPayment - 0.005 ? rest : 0;
}

/// [total] split into [count] payments for an installment: each rounded to
/// the centavo, and the last one taking whatever rounding leaves, so the
/// payments add up to [total] exactly.
///
/// ₱10,000 over 3 months is 3 × ₱3,333.33 and a last one of ₱3,333.34.
({double perPayment, double lastPayment}) installmentPayments({
  required double total,
  required int count,
}) {
  if (total <= 0 || count < 1) return (perPayment: 0, lastPayment: 0);
  final each = _centavos(total / count);
  return (perPayment: each, lastPayment: _centavos(total - each * (count - 1)));
}

/// [day] moved [months] months, keeping its day where the month is long
/// enough and taking the month's last day where it is not: 31 January one
/// month on is 28 or 29 February.
DateTime addMonthsClamped(DateTime day, int months) {
  final target = DateTime(day.year, day.month + months, 1);
  final lastDay = DateTime(target.year, target.month + 1, 0).day;
  return DateTime(target.year, target.month, math.min(day.day, lastDay));
}

/// The first payment of a plan started on [day]: the same day next month.
DateTime nextMonthSameDay(DateTime day) => addMonthsClamped(day, 1);

/// Where an installment stands, worked out from its bill occurrences.
class DebtProgress {
  const DebtProgress({
    required this.paid,
    required this.paymentsMade,
    required this.total,
    required this.paymentCount,
  });

  /// Worked out from the payments recorded against the installment's bill,
  /// after those made before it was tracked.
  factory DebtProgress.of(Debt debt, Iterable<BillInstance> instances) {
    final before = debt.paidBefore.clamp(0, debt.paymentCount);
    var paid = 0.0;
    var made = before;
    for (var number = 1; number <= before; number++) {
      paid += debt.amountOf(number);
    }

    for (final instance in instances) {
      paid += instance.amountPaid;
      if (instance.status == BillStatus.paid) made++;
    }

    // Paid off early: what was paid is the whole of it, with nothing left.
    if (debt.paidOffEarly) {
      return DebtProgress(
        paid: paid,
        paymentsMade: debt.paymentCount,
        total: paid,
        paymentCount: debt.paymentCount,
      );
    }

    return DebtProgress(
      paid: paid,
      paymentsMade: made,
      total: debt.totalPayable,
      paymentCount: debt.paymentCount,
    );
  }

  final double paid;
  final int paymentsMade;
  final double total;
  final int paymentCount;

  double get remaining {
    final left = total - paid;
    return left > 0.005 ? left : 0;
  }

  int get paymentsLeft {
    final left = paymentCount - paymentsMade;
    return left > 0 ? left : 0;
  }

  bool get isPaidOff => total > 0 && remaining == 0;

  double get fraction =>
      total <= 0 ? 0 : (paid / total).clamp(0.0, 1.0).toDouble();
}

/// [value] as a percent, to one decimal while it is small: "2.9%", "35%".
String roundedPercent(double value) {
  final rounded = value >= 10
      ? value.roundToDouble()
      : (value * 10).round() / 10;
  return rounded == rounded.truncateToDouble()
      ? '${rounded.toInt()}%'
      : '$rounded%';
}

/// What an installment's payments really cost, as a rate in a sentence.
/// Only for one with an extra cost, so [Debt.yearlyCostPercent] is set.
String costRateText(Debt debt) =>
    'That works out to about ${roundedPercent(debt.monthlyCostPercent!)} a '
    'month, or ${roundedPercent(debt.yearlyCostPercent!)} a year.';
