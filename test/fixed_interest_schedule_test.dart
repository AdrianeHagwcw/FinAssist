import 'package:flutter_test/flutter_test.dart';
import 'package:testapp/backend/models/bill.dart';
import 'package:testapp/backend/models/debt.dart';

void main() {
  group('independent fixed-interest dates', () {
    test('daily, weekly, and fortnightly periods keep their own cadence', () {
      final anchor = DateTime(2026, 12, 28);

      expect(
        interestDueDateAt(anchor, PaymentFrequency.daily, 2),
        DateTime(2026, 12, 29),
      );
      expect(
        interestDueDateAt(anchor, PaymentFrequency.weekly, 2),
        DateTime(2027, 1, 4),
      );
      expect(
        interestDueDateAt(anchor, PaymentFrequency.fortnightly, 2),
        DateTime(2027, 1, 11),
      );
    });

    test('twice-monthly dates preserve the lender schedule through month ends', () {
      final anchor = DateTime(2026, 1, 31);

      expect(
        interestDueDateAt(anchor, PaymentFrequency.semiMonthly, 1),
        DateTime(2026, 1, 31),
      );
      expect(
        interestDueDateAt(anchor, PaymentFrequency.semiMonthly, 2),
        DateTime(2026, 2, 15),
      );
      expect(
        interestDueDateAt(anchor, PaymentFrequency.semiMonthly, 3),
        DateTime(2026, 2, 28),
      );
      expect(
        interestDueDateAt(anchor, PaymentFrequency.semiMonthly, 4),
        DateTime(2026, 3, 15),
      );
    });

    test('monthly, quarterly, semiannual, and annual dates clamp leap days', () {
      final monthEnd = DateTime(2024, 1, 31);
      expect(
        interestDueDateAt(monthEnd, PaymentFrequency.monthly, 2),
        DateTime(2024, 2, 29),
      );
      expect(
        interestDueDateAt(monthEnd, PaymentFrequency.monthly, 3),
        DateTime(2024, 3, 31),
      );
      expect(
        interestDueDateAt(monthEnd, PaymentFrequency.quarterly, 2),
        DateTime(2024, 4, 30),
      );
      expect(
        interestDueDateAt(monthEnd, PaymentFrequency.semiAnnual, 2),
        DateTime(2024, 7, 31),
      );

      final leapDay = DateTime(2024, 2, 29);
      expect(
        interestDueDateAt(leapDay, PaymentFrequency.annually, 2),
        DateTime(2025, 2, 28),
      );
      expect(
        interestDueDateAt(leapDay, PaymentFrequency.annually, 3),
        DateTime(2026, 2, 28),
      );
    });

    test('interest periods are independent of monthly payment dates', () {
      final firstPayment = DateTime(2026, 2, 28);
      final twelfthPayment = lastDueDateFor(
        firstPayment,
        BillRecurrence.monthly,
        12,
      );
      final annualInterestDue = interestDueDateAt(
        DateTime(2026, 1, 31),
        PaymentFrequency.annually,
        2,
      );

      expect(twelfthPayment, DateTime(2027, 1, 28));
      expect(annualInterestDue, DateTime(2027, 1, 31));
      expect(annualInterestDue, isNot(twelfthPayment));
    });

    test('future fixed interest is not included in the debt balance', () {
      final debt = Debt(
        id: 'annual',
        direction: DebtDirection.iOwe,
        name: 'Loan',
        category: DebtCategory.personalLoan,
        principal: 12000,
        perPayment: 1000,
        paymentCount: 12,
        frequency: PaymentFrequency.monthly,
        firstDueDate: DateTime(2026, 2, 28),
        status: DebtStatus.active,
        fixedInterestAmount: 180,
        interestChargedPer: PaymentFrequency.annually,
        interestScheduleAnchor: DateTime(2026, 1, 31),
        nextInterestDueDate: DateTime(2027, 1, 31),
      );

      expect(debt.totalWithAccruedInterest, 12000);
      expect(
        Debt(
          id: debt.id,
          direction: debt.direction,
          name: debt.name,
          category: debt.category,
          principal: debt.principal,
          perPayment: debt.perPayment,
          paymentCount: debt.paymentCount,
          frequency: debt.frequency,
          firstDueDate: debt.firstDueDate,
          status: debt.status,
          fixedInterestAmount: debt.fixedInterestAmount,
          interestChargedPer: debt.interestChargedPer,
          interestScheduleAnchor: debt.interestScheduleAnchor,
          nextInterestDueDate: debt.nextInterestDueDate,
          accruedInterest: 180,
        ).totalWithAccruedInterest,
        12180,
      );
    });

    test('older debts without schedule fields remain readable', () {
      final oldDebt = Debt.fromMap('legacy', {
        'direction': DebtDirection.iOwe.name,
        'name': 'Legacy loan',
        'category': DebtCategory.personalLoan.name,
        'principal': 12000,
        'perPayment': 1000,
        'paymentCount': 12,
        'frequency': PaymentFrequency.monthly.name,
        'firstDueDate': DateTime(2026, 2, 28),
        'status': DebtStatus.active.name,
        'fixedInterestAmount': 180,
        'interestChargedPer': PaymentFrequency.annually.name,
      });

      expect(oldDebt.fixedInterestAmount, 180);
      expect(oldDebt.interestChargedPer, PaymentFrequency.annually);
      expect(oldDebt.interestScheduleAnchor, isNull);
      expect(oldDebt.nextInterestDueDate, isNull);
      expect(oldDebt.interestPeriodsCharged, 0);
      expect(oldDebt.totalWithAccruedInterest, 12000);
    });
  });
}
