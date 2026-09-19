import 'package:flutter_test/flutter_test.dart';

import 'package:testapp/models/allocation.dart';
import 'package:testapp/models/bill.dart';
import 'package:testapp/models/debt.dart';
import 'package:testapp/models/safe_to_spend.dart';

void main() {
  final now = DateTime(2026, 9, 5, 10);

  Bill schedule(
    String id,
    double amount,
    DateTime first, {
    BillRecurrence recurrence = BillRecurrence.monthly,
  }) => Bill(
    id: id,
    name: id,
    amount: amount,
    category: 'Bills',
    firstDueDate: first,
    recurrence: recurrence,
  );

  BillInstance occurrence(
    String billId,
    DateTime due, {
    double amount = 1500,
    double paid = 0,
    double carriedOver = 0,
    BillStatus status = BillStatus.unpaid,
    String? carriedInto,
  }) => BillInstance(
    id: billInstanceId(billId, due),
    billId: billId,
    name: billId,
    amount: amount,
    category: 'Bills',
    dueDate: due,
    status: status,
    amountPaid: paid,
    carriedOver: carriedOver,
    carriedInto: carriedInto,
  );

  group('an installment whose last payment differs', () {
    test('totals follow the contract', () {
      const loan = Debt(
        id: 'loan',
        direction: DebtDirection.iOwe,
        name: 'Loan',
        category: DebtCategory.personalLoan,
        principal: 10000,
        status: DebtStatus.active,
        perPayment: 3000,
        paymentCount: 4,
        lastPayment: 1000,
      );
      expect(loan.totalPayable, 10000);
      expect(loan.extraCost, 0);
      expect(loan.hasDifferentLastPayment, isTrue);

      const equal = Debt(
        id: 'phone',
        direction: DebtDirection.iOwe,
        name: 'Phone',
        category: DebtCategory.gadget,
        principal: 10000,
        status: DebtStatus.active,
        perPayment: 1500,
        paymentCount: 8,
      );
      expect(equal.totalPayable, 12000);
      expect(equal.extraCost, 2000);
      expect(equal.hasDifferentLastPayment, isFalse);

      expect(coveringLastPayment(10000, 3000, 4), 1000);
      expect(coveringLastPayment(12000, 1500, 8), 0, reason: 'all the same');
    });

    test('only the last bill asks for the last amount', () {
      final bill = Bill(
        id: 'loan',
        name: 'Loan',
        amount: 3000,
        category: 'Bills',
        firstDueDate: DateTime(2026, 10, 5),
        recurrence: BillRecurrence.monthly,
        endDate: DateTime(2027, 1, 5),
        lastAmount: 1000,
      );
      expect(bill.amountOn(DateTime(2026, 12, 5)), 3000);
      expect(bill.amountOn(DateTime(2027, 1, 5)), 1000);

      final january = newOccurrences(
        bills: [bill],
        year: 2027,
        month: 1,
        existingIds: const {},
        previousMonth: const [],
        now: now,
      );
      expect(january.single.amount, 1000);
    });
  });

  group('carrying an unpaid bill into the next one', () {
    test('moves the unpaid part once, and closes the old bill', () {
      final internet = schedule('internet', 1500, DateTime(2026, 7, 25));
      final august = occurrence(
        'internet',
        DateTime(2026, 8, 25),
        paid: 500,
        status: BillStatus.partial,
      );

      final created = newOccurrences(
        bills: [internet],
        year: 2026,
        month: 9,
        existingIds: const {},
        previousMonth: [august],
        now: now,
      );
      expect(created.single.carried, 1000);
      expect(created.single.from?.id, august.id);
      expect(created.single.id, 'internet_20260925');

      // Once closed, August owes nothing and reads as moved.
      final closed = occurrence(
        'internet',
        DateTime(2026, 8, 25),
        paid: 500,
        status: BillStatus.partial,
        carriedInto: created.single.id,
      );
      expect(closed.isCarriedForward, isTrue);
      expect(closed.isSettled, isTrue);
      expect(closed.remaining, 0);
      expect(closed.movedAmount, 1000);
      expect(closed.urgency(now: now), BillUrgency.moved);
      expect(carryOverFrom(closed, now: now), 0, reason: 'never moved twice');
    });

    test('a weekly bill carries into its first new week only', () {
      final load = schedule(
        'load',
        100,
        DateTime(2026, 8, 3),
        recurrence: BillRecurrence.weekly,
      );
      final lastWeek = occurrence('load', DateTime(2026, 8, 31), amount: 100);

      final created = newOccurrences(
        bills: [load],
        year: 2026,
        month: 9,
        existingIds: const {},
        previousMonth: [lastWeek],
        now: now,
      );
      expect(created.map((o) => o.dueDate.day), [7, 14, 21, 28]);
      expect(created.map((o) => o.carried), [100, 0, 0, 0]);
    });

    test('nothing moves before the bill is overdue, or once it is paid', () {
      final rent = schedule('rent', 3000, DateTime(2026, 7, 10));
      final notYet = newOccurrences(
        bills: [rent],
        year: 2026,
        month: 9,
        existingIds: const {},
        previousMonth: [occurrence('rent', DateTime(2026, 8, 10))],
        now: DateTime(2026, 8, 5),
      );
      expect(notYet.single.carried, 0);

      final paid = newOccurrences(
        bills: [rent],
        year: 2026,
        month: 9,
        existingIds: const {},
        previousMonth: [
          occurrence(
            'rent',
            DateTime(2026, 8, 10),
            paid: 3000,
            status: BillStatus.paid,
          ),
        ],
        now: now,
      );
      expect(paid.single.carried, 0);
    });

    test('bills carried before the fix are closed now', () {
      final august = occurrence('internet', DateTime(2026, 8, 25));
      final september = occurrence(
        'internet',
        DateTime(2026, 9, 25),
        amount: 3000,
        carriedOver: 1500,
      );

      expect(unclosedCarries([september], [august]), [
        (from: august.id, into: september.id),
      ]);
      // Already closed, or paid after all: nothing to do.
      expect(
        unclosedCarries(
          [september],
          [
            occurrence(
              'internet',
              DateTime(2026, 8, 25),
              carriedInto: september.id,
            ),
          ],
        ),
        isEmpty,
      );
      expect(
        unclosedCarries(
          [september],
          [
            occurrence(
              'internet',
              DateTime(2026, 8, 25),
              paid: 1500,
              status: BillStatus.paid,
            ),
          ],
        ),
        isEmpty,
      );
    });

    test('the money is counted once in Safe to Spend and Add Income', () {
      final august = occurrence(
        'internet',
        DateTime(2026, 8, 25),
        carriedInto: 'internet_20260925',
      );
      final september = occurrence(
        'internet',
        DateTime(2026, 9, 25),
        amount: 3000,
        carriedOver: 1500,
      );

      // ₱3,000 in all: September's own ₱1,500 and August's, not ₱4,500.
      expect(billsDueBefore([august, september], DateTime(2026, 10)), 3000);
      expect(outstandingBills([august, september], now: now), [september]);
    });
  });
}
