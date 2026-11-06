import 'package:flutter_test/flutter_test.dart';

import 'package:testapp/backend/models/transfer_direction.dart';
import 'package:testapp/backend/models/wallet.dart';

void main() {
  group('which way money moved between wallets', () {
    Wallet wallet({
      required String id,
      required WalletType type,
      WalletPurpose purpose = WalletPurpose.spending,
      SavingsKind? savingsKind,
    }) => Wallet(
      id: id,
      name: id,
      type: type,
      balance: 0,
      startingBalance: 0,
      receivesIncome: false,
      archived: false,
      sortOrder: 0,
      purpose: purpose,
      savingsKind: savingsKind?.name,
    );

    test('money landing in cash in hand is a withdrawal', () {
      for (final account in [
        WalletType.bank,
        WalletType.gcash,
        WalletType.maya,
        WalletType.ewallet,
        WalletType.other,
      ]) {
        expect(
          TransferDirection.between(from: account, to: WalletType.cash),
          TransferDirection.withdrawal,
          reason: '${account.label} to cash in hand takes money out',
        );
      }
    });

    test('money leaving cash in hand is a deposit', () {
      for (final account in [
        WalletType.bank,
        WalletType.gcash,
        WalletType.maya,
        WalletType.ewallet,
        WalletType.other,
      ]) {
        expect(
          TransferDirection.between(from: WalletType.cash, to: account),
          TransferDirection.deposit,
          reason: 'cash in hand to ${account.label} puts money in',
        );
      }
    });

    test('an account to account move is a transfer', () {
      final accounts = [
        WalletType.bank,
        WalletType.gcash,
        WalletType.maya,
        WalletType.ewallet,
        WalletType.other,
      ];

      for (final from in accounts) {
        for (final to in accounts) {
          expect(
            TransferDirection.between(from: from, to: to),
            TransferDirection.transfer,
            reason: '${from.label} to ${to.label} is between accounts',
          );
        }
      }
    });

    test('cash to cash stays a transfer', () {
      expect(
        TransferDirection.between(from: WalletType.cash, to: WalletType.cash),
        TransferDirection.transfer,
      );
    });

    test('an unknown wallet is not guessed at', () {
      expect(
        TransferDirection.between(from: null, to: WalletType.cash),
        TransferDirection.transfer,
      );
      expect(
        TransferDirection.between(from: WalletType.bank, to: null),
        TransferDirection.transfer,
      );
      expect(
        TransferDirection.between(from: null, to: null),
        TransferDirection.transfer,
      );
    });

    test('shows the three words the CPA gave', () {
      expect(TransferDirection.deposit.label, 'Deposit');
      expect(TransferDirection.withdrawal.label, 'Withdrawal');
      expect(TransferDirection.transfer.label, 'Transfer');

      // The three examples, as they would be written in history.
      expect(
        TransferDirection.between(
          from: WalletType.bank,
          to: WalletType.cash,
        ).label,
        'Withdrawal',
      );
      expect(
        TransferDirection.between(
          from: WalletType.gcash,
          to: WalletType.bank,
        ).label,
        'Transfer',
      );
      expect(
        TransferDirection.between(
          from: WalletType.cash,
          to: WalletType.bank,
        ).label,
        'Deposit',
      );
    });

    test(
      'savings and demand deposits follow the stated transaction labels',
      () {
        for (final kind in [
          SavingsKind.savingsDeposit,
          SavingsKind.demandDeposit,
        ]) {
          final deposit = wallet(
            id: kind.name,
            type: WalletType.other,
            purpose: WalletPurpose.savings,
            savingsKind: kind,
          );
          final cash = wallet(id: 'cash', type: WalletType.cash);
          final ewallet = wallet(id: 'ewallet', type: WalletType.gcash);
          final bank = wallet(id: 'bank', type: WalletType.bank);
          final otherDeposit = wallet(
            id: 'other-${kind.name}',
            type: WalletType.other,
            purpose: WalletPurpose.savings,
            savingsKind: kind == SavingsKind.savingsDeposit
                ? SavingsKind.demandDeposit
                : SavingsKind.savingsDeposit,
          );

          expect(
            TransferDirection.betweenWallets(from: deposit, to: otherDeposit),
            TransferDirection.transfer,
          );
          expect(
            TransferDirection.betweenWallets(from: otherDeposit, to: deposit),
            TransferDirection.transfer,
          );
          expect(
            TransferDirection.betweenWallets(from: cash, to: deposit),
            TransferDirection.deposit,
          );
          expect(
            TransferDirection.betweenWallets(from: ewallet, to: deposit),
            TransferDirection.deposit,
          );
          expect(
            TransferDirection.betweenWallets(from: bank, to: deposit),
            TransferDirection.transfer,
          );
          expect(
            TransferDirection.betweenWallets(from: deposit, to: cash),
            TransferDirection.withdrawal,
          );
          expect(
            TransferDirection.betweenWallets(from: deposit, to: ewallet),
            TransferDirection.withdrawal,
          );
          expect(
            TransferDirection.betweenWallets(from: deposit, to: bank),
            TransferDirection.transfer,
          );
        }
      },
    );
  });

  group('the one transfer rule matrix', () {
    Wallet wallet({
      required String id,
      required WalletType type,
      WalletPurpose purpose = WalletPurpose.spending,
      SavingsKind? savingsKind,
      DateTime? matures,
      DateTime? closedAt,
      double balance = 1000,
    }) => Wallet(
      id: id,
      name: id,
      type: type,
      balance: balance,
      startingBalance: balance,
      receivesIncome: false,
      archived: false,
      sortOrder: 0,
      purpose: purpose,
      savingsKind: savingsKind?.name,
      maturityDate: matures,
      closedAt: closedAt,
    );

    Wallet timeDeposit({
      String id = 'td',
      DateTime? matures,
      DateTime? closedAt,
      double balance = 1000,
    }) => wallet(
      id: id,
      type: WalletType.other,
      purpose: WalletPurpose.savings,
      savingsKind: SavingsKind.timeDeposit,
      matures: matures,
      closedAt: closedAt,
      balance: balance,
    );

    final now = DateTime(2027, 3, 5);
    final tomorrow = DateTime(2027, 3, 6);
    final today = DateTime(2027, 3, 5);

    test('an active time deposit is locked in both directions', () {
      final td = timeDeposit(matures: tomorrow);
      final cash = wallet(id: 'cash', type: WalletType.cash);

      expect(canBeTransferSource(td, now: now), isFalse);
      expect(canBeTransferDestination(td), isFalse);
      expect(
        transferRuleBetween(from: td, to: cash, now: now).allowed,
        isFalse,
      );
      expect(
        transferRuleBetween(from: cash, to: td, now: now).allowed,
        isFalse,
        reason: 'money cannot be added to an open time deposit',
      );
    });

    test('a matured time deposit releases to cash, bank and savings', () {
      final td = timeDeposit(matures: today);
      final nextTimeDeposit = timeDeposit(
        id: 'next-td',
        matures: DateTime(2028, 3, 5),
      );
      final cash = wallet(id: 'cash', type: WalletType.cash);
      final bank = wallet(id: 'bank', type: WalletType.bank);
      final sd = wallet(
        id: 'sd',
        type: WalletType.other,
        purpose: WalletPurpose.savings,
        savingsKind: SavingsKind.savingsDeposit,
      );
      final dd = wallet(
        id: 'dd',
        type: WalletType.other,
        purpose: WalletPurpose.savings,
        savingsKind: SavingsKind.demandDeposit,
      );

      expect(canBeTransferSource(td, now: now), isTrue);
      expect(
        transferRuleBetween(from: td, to: cash, now: now).direction,
        TransferDirection.withdrawal,
      );
      expect(
        transferRuleBetween(from: td, to: bank, now: now).direction,
        TransferDirection.transfer,
      );
      expect(
        transferRuleBetween(from: td, to: sd, now: now).direction,
        TransferDirection.transfer,
      );
      expect(
        transferRuleBetween(from: td, to: dd, now: now).direction,
        TransferDirection.transfer,
      );
      // Even at maturity it cannot take more money in; renewal is its own
      // flow, which creates a new record.
      expect(
        transferRuleBetween(from: cash, to: td, now: now).allowed,
        isFalse,
      );
      expect(
        transferRuleBetween(from: td, to: nextTimeDeposit, now: now).allowed,
        isFalse,
        reason: 'a new term must use the renewal flow',
      );
    });

    test('a claimed or renewed time deposit is history', () {
      final td = timeDeposit(matures: today, closedAt: now);
      final cash = wallet(id: 'cash', type: WalletType.cash);

      expect(canBeTransferSource(td, now: now), isFalse);
      expect(
        transferRuleBetween(from: td, to: cash, now: now).allowed,
        isFalse,
      );
    });

    test('a new time deposit may be funded once, by the right label', () {
      final cash = wallet(id: 'cash', type: WalletType.cash);
      final ewallet = wallet(id: 'gcash', type: WalletType.gcash);
      final bank = wallet(id: 'bank', type: WalletType.bank);
      final sd = wallet(
        id: 'sd',
        type: WalletType.other,
        purpose: WalletPurpose.savings,
        savingsKind: SavingsKind.savingsDeposit,
      );
      final td = timeDeposit(matures: DateTime(2028, 3, 5));

      expect(
        transferRuleBetween(
          from: cash,
          to: td,
          now: now,
          openingDeposit: true,
        ).direction,
        TransferDirection.deposit,
      );
      expect(
        transferRuleBetween(
          from: ewallet,
          to: td,
          now: now,
          openingDeposit: true,
        ).direction,
        TransferDirection.deposit,
      );
      final other = wallet(id: 'other', type: WalletType.other);
      expect(
        transferRuleBetween(
          from: other,
          to: td,
          now: now,
          openingDeposit: true,
        ).allowed,
        isFalse,
        reason: 'only the supported wallet types can fund a new deposit',
      );
      expect(
        transferRuleBetween(
          from: bank,
          to: td,
          now: now,
          openingDeposit: true,
        ).direction,
        TransferDirection.transfer,
      );
      expect(
        transferRuleBetween(
          from: sd,
          to: td,
          now: now,
          openingDeposit: true,
        ).direction,
        TransferDirection.transfer,
      );
      expect(
        transferRuleBetween(
          from: cash,
          to: td,
          now: now,
          openingDeposit: true,
        ).isInternalTransfer,
        isTrue,
      );
    });

    test('savings and demand deposits stay plain transfers between them', () {
      final sd = wallet(
        id: 'sd',
        type: WalletType.other,
        purpose: WalletPurpose.savings,
        savingsKind: SavingsKind.savingsDeposit,
      );
      final sd2 = wallet(
        id: 'sd2',
        type: WalletType.other,
        purpose: WalletPurpose.savings,
        savingsKind: SavingsKind.savingsDeposit,
      );
      final dd = wallet(
        id: 'dd',
        type: WalletType.other,
        purpose: WalletPurpose.savings,
        savingsKind: SavingsKind.demandDeposit,
      );
      final cash = wallet(id: 'cash', type: WalletType.cash);

      for (final (from, to) in [(sd, sd2), (sd, dd), (dd, sd), (dd, dd)]) {
        expect(
          TransferDirection.betweenWallets(from: from, to: to),
          TransferDirection.transfer,
          reason: '${from.id} to ${to.id} reads as Transfer',
        );
      }
      expect(
        TransferDirection.betweenWallets(from: cash, to: sd),
        TransferDirection.deposit,
      );
      expect(
        TransferDirection.betweenWallets(from: sd, to: cash),
        TransferDirection.withdrawal,
      );
      expect(
        transferRuleBetween(from: sd, to: dd, now: now).isInternalTransfer,
        isTrue,
        reason: 'own-wallet moves are never income or spending',
      );
    });
  });
}
