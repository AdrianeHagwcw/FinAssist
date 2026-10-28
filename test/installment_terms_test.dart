import 'package:flutter_test/flutter_test.dart';

import 'package:testapp/backend/models/bill.dart';
import 'package:testapp/backend/models/debt.dart';

/// An installment is entered as a cash price and a number of months, and
/// FinAssist works out the payments. The store already quoted the price, so
/// nothing is added on top: there is no interest to track.
void main() {
  Debt plan({
    double price = 10000,
    double down = 0,
    int months = 3,
    DateTime? firstDue,
    int paidBefore = 0,
  }) {
    final total = price - down;
    final split = installmentPayments(total: total, count: months);
    return Debt(
      id: 'd',
      direction: DebtDirection.iOwe,
      name: 'Phone',
      category: DebtCategory.gadget,
      principal: total,
      perPayment: split.perPayment,
      lastPayment: (split.lastPayment - split.perPayment).abs() > 0.005
          ? split.lastPayment
          : 0,
      paymentCount: months,
      firstDueDate: firstDue ?? DateTime(2026, 4, 10),
      billId: 'b',
      status: DebtStatus.active,
      paidBefore: paidBefore,
    );
  }

  group('working out the payments', () {
    test('₱10,000 over 3 months adds up exactly', () {
      final split = installmentPayments(total: 10000, count: 3);
      expect(split.perPayment, 3333.33);
      expect(split.lastPayment, 3333.34);
      expect(split.perPayment * 2 + split.lastPayment, closeTo(10000, 0.001));
    });

    test('a down payment comes off before the split', () {
      // ₱30,000 price less ₱5,000 down: ₱25,000 over 12 months.
      final split = installmentPayments(total: 25000, count: 12);
      expect(split.perPayment, 2083.33);
      expect(split.lastPayment, 2083.37);
      expect(split.perPayment * 11 + split.lastPayment, closeTo(25000, 0.001));
    });

    test('nothing to split asks for nothing', () {
      expect(installmentPayments(total: 0, count: 12).perPayment, 0);
      expect(installmentPayments(total: 10000, count: 0).perPayment, 0);
    });

    test('the plan shows the computed last payment only when it differs', () {
      final three = plan();
      expect(three.hasDifferentLastPayment, isTrue);
      expect(three.finalPayment, 3333.34);
      expect(three.totalPayable, closeTo(10000, 0.001));
      expect(three.amountOf(3), 3333.34);

      final even = plan(price: 12000, months: 12);
      expect(even.perPayment, 1000);
      expect(even.hasDifferentLastPayment, isFalse);
      expect(even.finalPayment, 1000);
    });
  });

  group('when the payments fall due', () {
    test('the first is the same day next month, kept to the month end', () {
      // 31 January has no 31 February.
      expect(nextMonthSameDay(DateTime(2026, 1, 31)), DateTime(2026, 2, 28));
      expect(nextMonthSameDay(DateTime(2024, 1, 31)), DateTime(2024, 2, 29));
      expect(nextMonthSameDay(DateTime(2026, 12, 31)), DateTime(2027, 1, 31));
      expect(nextMonthSameDay(DateTime(2026, 3, 10)), DateTime(2026, 4, 10));
    });

    test('payments already made put the next one next month', () {
      // Three payments made, so the first of the plan was three months ago
      // and the fourth falls next month.
      final today = DateTime(2026, 3, 10);
      final first = addMonthsClamped(nextMonthSameDay(today), -3);
      final started = plan(firstDue: first, months: 6, paidBefore: 3);
      expect(started.dueDateOf(4), DateTime(2026, 4, 10));
      expect(started.lastDueDate, DateTime(2026, 6, 10));
    });

    test('the schedule starts next month and ends on the last payment', () {
      final started = plan(firstDue: DateTime(2026, 4, 10));
      final bill = Bill(
        id: 'b',
        name: 'Phone',
        amount: started.perPayment,
        category: 'Bills',
        firstDueDate: started.firstDueDate!,
        recurrence: BillRecurrence.monthly,
        endDate: started.lastDueDate,
        interestShare: started.interestShare,
      );

      expect(bill.occurrencesIn(2026, 3), isEmpty);
      expect(bill.occurrencesIn(2026, 4), [DateTime(2026, 4, 10)]);
      expect(bill.occurrencesIn(2026, 6), [DateTime(2026, 6, 10)]);
      // Nothing after the last payment.
      expect(bill.occurrencesIn(2026, 7), isEmpty);
      expect(bill.interestShare, 0);
    });
  });

  group('interest', () {
    test('an installment carries none, whatever the price splits into', () {
      final started = plan();
      expect(started.extraCost, closeTo(0, 0.001));
      expect(started.interestShare, 0);
      expect(started.interestOf(1), 0);
    });

    test('a loan keeps its own share', () {
      const loan = Debt(
        id: 'l',
        direction: DebtDirection.iOwe,
        name: 'BPI loan',
        category: DebtCategory.personalLoan,
        principal: 5600,
        perPayment: 560,
        paymentCount: 12,
        status: DebtStatus.active,
      );
      expect(loan.extraCost, closeTo(1120, 0.001));
      expect(loan.interestShare, closeTo(1 / 6, 1e-9));
      expect(loan.interestOf(1), closeTo(93.33, 0.01));
    });
  });

  group('the card or account used', () {
    test('is read back from what was stored', () {
      final stored = Debt.fromMap('d', {
        'name': 'iPhone 15',
        'principal': 48000,
        'perPayment': 4000,
        'paymentCount': 12,
        'paidWithWalletId': 'bank',
        'paidWithLabel': 'BPI Savings',
      });

      expect(stored.paidWithWalletId, 'bank');
      expect(stored.paidWithLabel, 'BPI Savings');

      final byCard = Debt.fromMap('e', {
        'name': 'Aircon',
        'paidWithWalletId': 'card',
        'paidWithLabel': 'BPI credit card',
      });
      expect(byCard.paidWithWalletId, 'card');
      expect(byCard.paidWithLabel, 'BPI credit card');
    });

    test('is absent when none was recorded', () {
      final stored = Debt.fromMap('d', {'name': 'Phone'});
      expect(stored.paidWithWalletId, isNull);
      expect(stored.paidWithLabel, isNull);
    });
  });
}
