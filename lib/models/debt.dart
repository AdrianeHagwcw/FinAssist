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

enum DebtCategory {
  gadget('Gadget or appliance'),
  personalLoan('Personal loan'),
  governmentLoan('Government loan (SSS, Pag-IBIG)'),
  creditCard('Credit card'),
  buyNowPayLater('Buy now, pay later'),
  familyFriend('Family or friend'),
  other('Other');

  const DebtCategory(this.label);

  final String label;

  static DebtCategory fromName(String? name) => DebtCategory.values.firstWhere(
    (c) => c.name == name,
    orElse: () => DebtCategory.other,
  );
}

/// How often an installment is paid. Kept to what installments actually use.
enum PaymentFrequency {
  monthly('Every month', BillRecurrence.monthly),
  weekly('Every week', BillRecurrence.weekly);

  const PaymentFrequency(this.label, this.recurrence);

  final String label;
  final BillRecurrence recurrence;

  static PaymentFrequency fromName(String? name) =>
      PaymentFrequency.values.firstWhere(
        (f) => f.name == name,
        orElse: () => PaymentFrequency.monthly,
      );
}

enum DebtStatus { active, settled }

/// Money owed, in either direction.
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
    this.frequency = PaymentFrequency.monthly,
    this.firstDueDate,
    this.billId,
    this.received = 0,
    this.dueDate,
    this.note,
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
      frequency: PaymentFrequency.fromName(_asString(map['frequency'])),
      firstDueDate: _asDate(map['firstDueDate']),
      billId: _asString(map['billId']),
      received: _asDouble(map['received']),
      dueDate: _asDate(map['dueDate']),
      note: _asString(map['note']),
      status: map['status'] == DebtStatus.settled.name
          ? DebtStatus.settled
          : DebtStatus.active,
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
  final PaymentFrequency frequency;
  final DateTime? firstDueDate;

  /// The bill schedule holding the payments.
  final String? billId;

  // ------------------------------------------ money owed to the user

  /// Paid back so far.
  final double received;

  /// When they said they would pay it back, if at all.
  final DateTime? dueDate;

  final String? note;
  final DebtStatus status;

  /// Everything the user will have paid once every payment is made.
  double get totalPayable => perPayment * paymentCount;

  /// What borrowing costs on top of the amount borrowed. This is shown
  /// instead of an interest rate: most students don't know their rate, but
  /// "₱4,800 more than you borrowed" needs no explaining.
  double get extraCost {
    final extra = totalPayable - principal;
    return extra > 0.005 ? extra : 0;
  }

  DateTime? get lastDueDate => firstDueDate == null
      ? null
      : lastDueDateFor(firstDueDate!, frequency.recurrence, paymentCount);

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

/// How many payments it takes to cover [total] at [perPayment] each, for
/// when the user leaves the count blank.
int paymentsToCover(double total, double perPayment) {
  if (total <= 0 || perPayment <= 0) return 0;
  return (total / perPayment - 1e-9).ceil();
}

/// Where an installment stands, worked out from its bill occurrences.
class DebtProgress {
  const DebtProgress({
    required this.paid,
    required this.paymentsMade,
    required this.total,
    required this.paymentCount,
  });

  /// Worked out from the payments recorded against the installment's bill.
  factory DebtProgress.of(Debt debt, Iterable<BillInstance> instances) {
    var paid = 0.0;
    var made = 0;

    for (final instance in instances) {
      paid += instance.amountPaid;
      if (instance.status == BillStatus.paid) made++;
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
