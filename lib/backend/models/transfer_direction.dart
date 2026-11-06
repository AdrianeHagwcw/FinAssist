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
  /// A time deposit follows the same wording when it is opened, and reads as
  /// a withdrawal or transfer when its matured money is released.
  static TransferDirection betweenWallets({
    Wallet? from,
    Wallet? to,
    bool openingDeposit = false,
  }) {
    if (from == null || to == null) {
      return between(from: from?.type, to: to?.type);
    }

    if (to.isTimeDeposit && openingDeposit) {
      return from.type == WalletType.cash || isEWalletType(from.type)
          ? TransferDirection.deposit
          : TransferDirection.transfer;
    }

    if (from.isTimeDeposit) {
      return to.type == WalletType.cash || isEWalletType(to.type)
          ? TransferDirection.withdrawal
          : TransferDirection.transfer;
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

/// Whether one move between the user's own wallets may happen, and what it
/// is called.
///
/// This is the single rule matrix for every screen, Quick Action and the
/// maturity claim/renew flow. A screen may hide a wallet for clarity, but the
/// service layer asks this before writing anything.
class WalletTransferRule {
  const WalletTransferRule._({
    required this.allowed,
    required this.direction,
    this.reason,
  });

  const WalletTransferRule.allowed(TransferDirection direction)
    : this._(allowed: true, direction: direction);

  const WalletTransferRule.blocked(String reason)
    : this._(
        allowed: false,
        direction: TransferDirection.transfer,
        reason: reason,
      );

  final bool allowed;
  final TransferDirection direction;

  /// Why the move is not allowed, for a message under the form.
  final String? reason;

  /// Every move between the user's own wallets is internal: none of it is
  /// income or spending. The label ([direction]) is shown to the user; this
  /// flag is what reports use.
  bool get isInternalTransfer => true;

  String get label => direction.label;
}

/// Wallets allowed to fund a time deposit as it is first opened.
bool canFundTimeDeposit(Wallet wallet) =>
    !wallet.archived &&
    (wallet.type == WalletType.cash ||
        isEWalletType(wallet.type) ||
        wallet.type == WalletType.bank ||
        (wallet.isSetAside &&
            (wallet.savingsType == SavingsKind.savingsDeposit ||
                wallet.savingsType == SavingsKind.demandDeposit)));

/// The rule for moving money from [from] into [to].
///
/// [openingDeposit] is true only while a new time deposit is being created:
/// that is the one moment money may enter a time deposit. After that an
/// active deposit refuses money in either direction, and a matured one only
/// lets its capital and interest out.
WalletTransferRule transferRuleBetween({
  required Wallet from,
  required Wallet to,
  DateTime? now,
  bool openingDeposit = false,
}) {
  final when = now ?? DateTime.now();

  if (from.id == to.id) {
    return const WalletTransferRule.blocked('Choose a different wallet.');
  }
  if (from.archived || to.archived) {
    return const WalletTransferRule.blocked('That wallet is archived.');
  }

  if (from.isTimeDeposit) {
    final status = from.timeDepositStatusAt(when);
    if (status == TimeDepositStatus.active) {
      return const WalletTransferRule.blocked(
        'This time deposit is still locked until its maturity date.',
      );
    }
    if (status == TimeDepositStatus.closed) {
      return const WalletTransferRule.blocked(
        'This time deposit was already claimed or renewed.',
      );
    }
    if (to.isTimeDeposit) {
      return const WalletTransferRule.blocked(
        'Renew a matured time deposit through its renewal flow.',
      );
    }
    return WalletTransferRule.allowed(
      TransferDirection.betweenWallets(from: from, to: to),
    );
  }

  if (to.isTimeDeposit) {
    if (!openingDeposit) {
      return const WalletTransferRule.blocked(
        'Money cannot be added to a time deposit. Open a new one instead.',
      );
    }
    if (!canFundTimeDeposit(from)) {
      return const WalletTransferRule.blocked(
        'Fund a time deposit from Cash, an e-wallet, a bank, or another '
        'savings deposit.',
      );
    }
  }

  return WalletTransferRule.allowed(
    TransferDirection.betweenWallets(
      from: from,
      to: to,
      openingDeposit: openingDeposit,
    ),
  );
}

/// Whether [wallet] may be a source in an ordinary transfer.
bool canBeTransferSource(Wallet wallet, {DateTime? now}) {
  if (wallet.archived) return false;
  if (!wallet.isTimeDeposit) return true;
  return wallet.timeDepositStatusAt(now ?? DateTime.now()) ==
      TimeDepositStatus.matured;
}

/// Whether [wallet] may receive money in an ordinary transfer. A time
/// deposit never can; money enters only when a new one is opened, or through
/// its own renewal flow.
bool canBeTransferDestination(Wallet wallet) =>
    !wallet.archived && !wallet.isTimeDeposit;
