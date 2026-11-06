import 'package:flutter_test/flutter_test.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:testapp/backend/models/allocation.dart';
import 'package:testapp/backend/models/reminder.dart';
import 'package:testapp/backend/models/wallet.dart';
import 'package:testapp/backend/services/allocation_service.dart';
import 'package:testapp/backend/services/wallet_service.dart';

void main() {
  Wallet timeDeposit({
    String id = 'td',
    double balance = 10000,
    double? principal,
    double rate = 3,
    DateTime? start,
    DateTime? matures,
    DateTime? closedAt,
    String? renewedIntoId,
    bool interestRecorded = false,
  }) => Wallet(
    id: id,
    name: 'Time Deposit',
    type: WalletType.other,
    balance: balance,
    startingBalance: principal ?? balance,
    receivesIncome: false,
    archived: false,
    sortOrder: 0,
    purpose: WalletPurpose.savings,
    savingsKind: SavingsKind.timeDeposit.name,
    annualInterestRatePercent: rate,
    depositStartDate: start ?? DateTime(2026, 1, 1),
    maturityDate: matures ?? DateTime(2027, 1, 1),
    principal: principal,
    closedAt: closedAt,
    renewedIntoId: renewedIntoId,
    maturityInterestRecorded: interestRecorded,
  );

  group('time deposit status comes from the stored dates', () {
    final td = timeDeposit(matures: DateTime(2027, 3, 5));

    test('it is locked before the end date', () {
      expect(
        td.timeDepositStatusAt(DateTime(2027, 3, 4, 23, 59)),
        TimeDepositStatus.active,
      );
      expect(td.isActiveTimeDeposit, isTrue);
    });

    test('it matures on the day itself, without a notification', () {
      final onTheDay = timeDeposit(matures: DateTime(2027, 3, 5));
      expect(
        onTheDay.timeDepositStatusAt(DateTime(2027, 3, 5, 0, 1)),
        TimeDepositStatus.matured,
        reason: 'the app resolves this on load, not from a reminder',
      );
      expect(
        onTheDay.timeDepositStatusAt(DateTime(2027, 6, 1)),
        TimeDepositStatus.matured,
        reason: 'an app opened late still sees it as matured',
      );
    });

    test('a claimed or renewed record stays closed', () {
      expect(
        timeDeposit(
          matures: DateTime(2027, 3, 5),
          closedAt: DateTime(2027, 3, 6),
        ).timeDepositStatusAt(DateTime(2027, 3, 7)),
        TimeDepositStatus.closed,
      );
      expect(
        timeDeposit(
          matures: DateTime(2027, 3, 5),
          renewedIntoId: 'new',
        ).timeDepositStatusAt(DateTime(2027, 3, 7)),
        TimeDepositStatus.closed,
      );
    });
  });

  group('older time deposit records still load', () {
    test('a record without principal or new fields reads safely', () {
      final old = Wallet.fromMap('old', {
        'name': 'Old Time Deposit',
        'type': 'other',
        'balance': 12000.0,
        'startingBalance': 10000.0,
        'purpose': 'savings',
        'savingsKind': 'timeDeposit',
        'annualInterestRatePercent': 2,
        'depositStartDate': DateTime(2025, 1, 1),
        'maturityDate': DateTime(2026, 1, 1),
      });

      expect(old.isTimeDeposit, isTrue);
      expect(old.timeDepositPrincipal, 10000);
      expect(old.closedAt, isNull);
      expect(old.renewedIntoId, isNull);
      expect(old.maturityInterestRecorded, isFalse);
      expect(
        old.timeDepositStatusAt(DateTime(2026, 1, 2)),
        TimeDepositStatus.matured,
      );
      // ₱10,000 × 2% for a year = ₱200, less the 20% tax.
      expect(old.timeDepositMaturityInterest, 160);
      expect(old.timeDepositMaturityValue, 10160);
    });

    test('a Firestore timestamp resolves to its Manila calendar date', () {
      final wallet = Wallet.fromMap('ph-date', {
        'name': 'Time Deposit',
        'type': 'other',
        'balance': 10000.0,
        'startingBalance': 10000.0,
        'purpose': 'savings',
        'savingsKind': 'timeDeposit',
        'annualInterestRatePercent': 2,
        'depositStartDate': Timestamp.fromDate(DateTime.utc(2026, 3, 4, 16)),
        'maturityDate': Timestamp.fromDate(DateTime.utc(2027, 3, 4, 16)),
      });

      expect(wallet.depositStartDate, DateTime(2026, 3, 5));
      expect(wallet.maturityDate, DateTime(2027, 3, 5));
      expect(
        wallet.timeDepositStatusAt(DateTime.utc(2027, 3, 4, 16)),
        TimeDepositStatus.matured,
      );
    });
  });

  group('maturity interest is written once, on the maturity date', () {
    test('only a matured, unrecorded deposit is pending', () {
      final active = timeDeposit(id: 'active', matures: DateTime(2027, 3, 7));
      final matured = timeDeposit(id: 'matured', matures: DateTime(2027, 3, 5));
      final already = timeDeposit(
        id: 'already',
        matures: DateTime(2027, 3, 5),
        interestRecorded: true,
      );
      final closed = timeDeposit(
        id: 'closed',
        matures: DateTime(2027, 3, 5),
        closedAt: DateTime(2027, 3, 6),
      );

      final pending = WalletService.pendingTimeDepositInterest([
        active,
        matured,
        already,
        closed,
      ], now: DateTime(2027, 3, 6));

      expect(pending, hasLength(1));
      expect(pending.single.wallet.id, 'matured');
      expect(pending.single.interest, 281.42);
      expect(pending.single.date, DateTime.utc(2027, 3, 4, 16));
      expect(pending.single.entryId, 'td-interest-matured');
    });

    test('the same entry id is planned again, never a second entry', () {
      final td = timeDeposit(id: 'td', matures: DateTime(2027, 3, 5));
      final first = WalletService.pendingTimeDepositInterest([
        td,
      ], now: DateTime(2027, 3, 5));
      final retry = WalletService.pendingTimeDepositInterest([
        td,
      ], now: DateTime(2027, 3, 5));

      expect(first.single.entryId, retry.single.entryId);
      expect(first.single.entryId, 'td-interest-td');
      // Once the flag is stored, the next load plans nothing at all.
      final recorded = timeDeposit(
        id: 'td',
        matures: DateTime(2027, 3, 5),
        interestRecorded: true,
      );
      expect(
        WalletService.pendingTimeDepositInterest([
          recorded,
        ], now: DateTime(2027, 3, 5)),
        isEmpty,
      );
    });
  });

  group('claim and renew only work on a matured, open deposit', () {
    test('offline settlement is accepted as queued, not complete', () {
      const queued = TimeDepositSettlementResult(
        TimeDepositSettlementStatus.queued,
      );
      const handledElsewhere = TimeDepositSettlementResult(
        TimeDepositSettlementStatus.alreadyHandled,
      );

      expect(queued.accepted, isTrue);
      expect(queued.status, TimeDepositSettlementStatus.queued);
      expect(handledElsewhere.accepted, isFalse);
    });

    test('an active deposit is refused before anything is written', () async {
      final active = timeDeposit(matures: DateTime(2027, 3, 5));

      expect(
        (await WalletService.claimTimeDeposit(
          wallet: active,
          capitalTo: const {},
          date: DateTime(2027, 3, 4),
        )).status,
        TimeDepositSettlementStatus.alreadyHandled,
      );
      expect(
        (await WalletService.renewTimeDeposit(
          wallet: active,
          maturityDate: DateTime(2028, 3, 5),
          annualInterestRatePercent: 3,
          date: DateTime(2027, 3, 4),
        )).status,
        TimeDepositSettlementStatus.alreadyHandled,
      );
    });

    test('a claimed deposit cannot be claimed or renewed twice', () async {
      final claimed = timeDeposit(
        matures: DateTime(2027, 3, 5),
        closedAt: DateTime(2027, 3, 6),
      );
      final renewed = timeDeposit(
        matures: DateTime(2027, 3, 5),
        renewedIntoId: 'next',
      );

      for (final wallet in [claimed, renewed]) {
        expect(
          (await WalletService.claimTimeDeposit(
            wallet: wallet,
            capitalTo: const {},
            date: DateTime(2027, 3, 7),
          )).status,
          TimeDepositSettlementStatus.alreadyHandled,
        );
        expect(
          (await WalletService.renewTimeDeposit(
            wallet: wallet,
            maturityDate: DateTime(2028, 3, 5),
            annualInterestRatePercent: 3,
            date: DateTime(2027, 3, 7),
          )).status,
          TimeDepositSettlementStatus.alreadyHandled,
        );
      }
    });

    test('a claim cannot release only part of the original capital', () async {
      final matured = timeDeposit(matures: DateTime(2027, 3, 5));
      await expectLater(
        WalletService.claimTimeDeposit(
          wallet: matured,
          capitalTo: const {'cash': 5000},
          capitalAmount: 5000,
          interestAmount: 0,
          date: DateTime(2027, 3, 6),
          wallets: [matured],
        ),
        throwsArgumentError,
      );
    });
  });

  group('time deposit wallet actions stay locked', () {
    final matured = timeDeposit(matures: DateTime(2027, 3, 5));

    test('balance correction cannot add or remove money', () {
      expect(
        () => WalletService.correctDeclaredBalance(
          wallet: matured,
          recorded: matured.balance + 1,
        ),
        throwsArgumentError,
      );
    });

    test('generic maturity settlement and rollover are refused', () {
      expect(
        () => WalletService.settleMatured(
          wallet: matured,
          received: 1,
          to: const {},
        ),
        throwsArgumentError,
      );
      expect(
        () => WalletService.rollOverMaturity(matured, DateTime(2028, 1, 1)),
        throwsArgumentError,
      );
    });

    test('regular interest entry cannot target a time deposit', () {
      expect(
        () => WalletService.recordInterest(wallet: matured, amount: 1),
        throwsArgumentError,
      );
    });

    test(
      'ordinary transfers cannot move a matured deposit into another TD',
      () {
        final old = timeDeposit(id: 'old', matures: DateTime(2020, 1, 1));
        final next = timeDeposit(id: 'next', matures: DateTime(2028, 1, 1));
        expect(
          () => WalletService.recordTransfers(
            fromWalletId: old.id,
            to: {next.id: 1},
            wallets: [old, next],
          ),
          throwsArgumentError,
        );
      },
    );

    test('income allocation cannot write into a time deposit', () {
      expect(
        () => AllocationService.confirm(
          plan: const AllocationPlan(income: 1),
          incomeByWallet: {matured.id: 1},
          source: 'Salary',
          receivedAt: DateTime(2027, 3, 6),
          wallets: [matured],
        ),
        throwsArgumentError,
      );
    });

    test('expense batches cannot spend from a time deposit', () {
      expect(
        () => WalletService.recordExpenseBatch(
          expenses: [
            ExpenseBatchEntry(
              walletId: matured.id,
              amount: 1,
              label: 'Food',
              note: 'test',
            ),
          ],
          wallets: [matured],
        ),
        throwsArgumentError,
      );
    });

    test('existing terms cannot be changed after the deposit is opened', () {
      expect(
        () => WalletService.updateWallet(
          walletId: matured.id,
          currentWallet: matured,
          updateSavingsMetadata: true,
          savingsKind: SavingsKind.timeDeposit.name,
          annualInterestRatePercent: matured.annualInterestRatePercent,
          depositStartDate: matured.depositStartDate,
          maturityDate: DateTime(2027, 3, 6),
        ),
        throwsArgumentError,
      );
    });
  });

  group('time deposit reminders', () {
    List<PlannedReminder> planned({
      required DateTime now,
      DateTime? matures,
      bool closed = false,
    }) {
      final td = timeDeposit(
        matures: matures ?? DateTime(2027, 3, 5),
        closedAt: closed ? DateTime(2027, 3, 6) : null,
      );
      return planReminders(
        settings: const ReminderSettings(enabled: true, priorities: []),
        bills: const [],
        goals: const [],
        wallets: [td],
        transactions: const [],
        now: now,
      ).where((reminder) => reminder.key.startsWith('savings:td:')).toList();
    }

    test('the four agreed messages are planned on their own days', () {
      final reminders = planned(now: DateTime(2027, 2, 20));
      final bodies = {
        for (final reminder in reminders) reminder.key: reminder.body,
      };

      expect(reminders, hasLength(4));
      expect(bodies.length, reminders.length, reason: 'keys are unique');
      expect(
        bodies['savings:td:matured:7'],
        'Your Time Deposit will mature in 7 days. Get ready to claim your '
        'money!',
      );
      expect(
        bodies['savings:td:matured:3'],
        'Your Time Deposit will mature in 3 days.',
      );
      expect(
        bodies['savings:td:matured:1'],
        'Your Time Deposit matures tomorrow!',
      );
      expect(
        bodies['savings:td:matured'],
        'Your Time Deposit has matured! You can now review and claim your '
        'money.',
      );
      expect(
        reminders.map((r) => r.at).toSet(),
        hasLength(4),
        reason: 'each milestone has its own morning',
      );
    });

    test('planning again gives the same keys, not duplicates', () {
      final first = planned(now: DateTime(2027, 2, 20));
      final again = planned(now: DateTime(2027, 2, 20));
      expect(first.map((r) => r.key).toSet(), again.map((r) => r.key).toSet());
      expect(again, hasLength(4));
    });

    test('a day already gone by is skipped, not sent late', () {
      final reminders = planned(now: DateTime(2027, 3, 1));
      final keys = reminders.map((r) => r.key).toSet();

      expect(keys, isNot(contains('savings:td:matured:7')));
      expect(keys, contains('savings:td:matured:3'));
      expect(keys, contains('savings:td:matured:1'));
      expect(keys, contains('savings:td:matured'));
    });

    test('after the maturity day nothing more is sent', () {
      expect(planned(now: DateTime(2027, 3, 6)), isEmpty);
    });

    test('a claimed or renewed deposit is no longer chased', () {
      expect(planned(now: DateTime(2027, 2, 20), closed: true), isEmpty);
    });
  });
}
