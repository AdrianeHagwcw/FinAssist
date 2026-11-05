import 'wallet.dart';

/// Which way money moved between the user's own wallets, in the words a
/// bookkeeper uses.
///
/// The licensed CPA's rule: money arriving in cash in hand is a withdrawal,
/// money leaving cash in hand is a deposit, and a move between two accounts
/// is a transfer. So cash in bank to cash in hand reads as a withdrawal,
/// cash in hand to cash in bank as a deposit, and an e-wallet to a bank as a
/// transfer.
enum TransferDirection {
  deposit('Deposit'),
  withdrawal('Withdrawal'),
  transfer('Transfer');

  const TransferDirection(this.label);

  /// The word shown in transaction history.
  final String label;

  /// The direction of a move from one wallet kind to another.
  ///
  /// Only [WalletType.cash] counts as cash in hand. A bank, an e-wallet and
  /// a savings record (stored as [WalletType.other]) are accounts, so moving
  /// money between them is a transfer. A record whose wallet is unknown, as
  /// with an old entry kept without one, falls back to a transfer rather
  /// than guessing.
  static TransferDirection between({WalletType? from, WalletType? to}) {
    if (from == null || to == null) return TransferDirection.transfer;

    final fromCash = from == WalletType.cash;
    final toCash = to == WalletType.cash;

    // Cash to cash and account to account both stay plain transfers.
    if (fromCash == toCash) return TransferDirection.transfer;

    return toCash ? TransferDirection.withdrawal : TransferDirection.deposit;
  }

  /// The direction of a move when the wallets' savings purposes are known.
  ///
  /// Savings and demand deposits use the bank's Deposit, Withdrawal and
  /// Transfer wording, which differs from ordinary account-to-account moves.
  static TransferDirection betweenWallets({Wallet? from, Wallet? to}) {
    if (from == null || to == null) {
      return between(from: from?.type, to: to?.type);
    }

    final toDeposit =
        to.isSetAside &&
        (to.savingsType == SavingsKind.savingsDeposit ||
            to.savingsType == SavingsKind.demandDeposit);
    if (toDeposit) {
      return from.type == WalletType.cash || isEWalletType(from.type)
          ? TransferDirection.deposit
          : TransferDirection.transfer;
    }

    final fromDeposit =
        from.isSetAside &&
        (from.savingsType == SavingsKind.savingsDeposit ||
            from.savingsType == SavingsKind.demandDeposit);
    if (fromDeposit) {
      return to.type == WalletType.cash || isEWalletType(to.type)
          ? TransferDirection.withdrawal
          : TransferDirection.transfer;
    }

    return between(from: from.type, to: to.type);
  }
}
