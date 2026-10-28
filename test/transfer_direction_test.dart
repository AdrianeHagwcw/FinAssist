import 'package:flutter_test/flutter_test.dart';

import 'package:testapp/backend/models/transfer_direction.dart';
import 'package:testapp/backend/models/wallet.dart';

void main() {
  group('which way money moved between wallets', () {
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
  });
}
