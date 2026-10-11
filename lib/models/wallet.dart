import 'package:cloud_firestore/cloud_firestore.dart';
/// Kind of money holder. Decides the wallet's icon and default name.
enum WalletType {
  cash('Cash', 'assets/icons/icons8-banknotes-96.png'),
  gcash('GCash', 'assets/icons/icons8-mobile-payment-96.png'),
  maya('Maya', 'assets/icons/icons8-wallet-96.png'),
  bank('Bank', 'assets/icons/bank-96.png'),
  other('Other', 'assets/icons/icons8-money-box-96.png');

  const WalletType(this.label, this.iconAsset);

  final String label;

  /// Colored icon file for this wallet type.
  final String iconAsset;

  /// Reads a stored type name, falling back to [other] for unknown values.
  static WalletType fromName(String? name) {
    return WalletType.values.firstWhere(
      (type) => type.name == name,
      orElse: () => WalletType.other,
    );
  }
}

/// What a wallet is for.
///
/// Money kept for bills and for savings sits in its own wallet, so the balance
/// the user sees is only what is theirs to spend. Those two are left out of
/// the total balance and out of Safe to Spend.
enum WalletPurpose {
  spending,
  bills('Bills', 'assets/icons/icons8-receipt-96.png'),
  savings('Savings', 'assets/icons/icons8-money-box-96.png');

  const WalletPurpose([this.defaultName, this.iconAsset]);

  /// The name given to the wallet the app creates for this purpose.
  final String? defaultName;

  /// Icon shown instead of the wallet type's own.
  final String? iconAsset;

  static WalletPurpose fromName(String? name) {
    return WalletPurpose.values.firstWhere(
      (purpose) => purpose.name == name,
      orElse: () => WalletPurpose.spending,
    );
  }
}

/// A wallet the user is adding during onboarding, before it is saved.
/// What a savings record is: where the money is kept, not what it is for.
/// A goal says what it is for, and claims part of a record through its own
/// saved amount.
enum SavingsKind {
  general('General savings', 'Cash, an envelope, money kept by hand'),
  account('Savings account', 'Money you keep in a bank or e-wallet account'),
  timeDeposit('Time deposit', 'Money you agreed to leave until a set date'),
  government(
    'Government savings',
    'SSS, Pag-IBIG MP2 or GSIS. You cannot take it out anytime.',
  );

  const SavingsKind(this.label, this.hint);

  final String label;

  /// One line under the choice, so the difference is plain.
  final String hint;

  /// Money that cannot simply be withdrawn today. It is still savings, but
  /// it should never read as cash the user could spend this week.
  bool get isLockedAway =>
      this == SavingsKind.timeDeposit || this == SavingsKind.government;

  /// Reads a stored name, including the kinds used before these three:
  /// an emergency fund is a goal now, so its money is general savings.
  static SavingsKind fromName(String? name) {
    switch (name) {
      case 'account':
      case 'savingsAccount':
        return SavingsKind.account;
      case 'timeDeposit':
        return SavingsKind.timeDeposit;
      case 'government':
        return SavingsKind.government;
      default:
        return SavingsKind.general;
    }
  }
}

class WalletDraft {
  const WalletDraft({
    required this.type,
    required this.name,
    required this.startingBalance,
    this.receivesIncome = false,
    this.purpose = WalletPurpose.spending,
    this.savingsKind,
  });

  final WalletType type;

  /// Custom name such as "BPI Savings"; defaults to the type label.
  final String name;
  final double startingBalance;

  /// Whether the user's main income is paid into this wallet.
  final bool receivesIncome;
  final WalletPurpose purpose;
  final String? savingsKind;

  WalletDraft copyWith({bool? receivesIncome, String? name}) {
    return WalletDraft(
      type: type,
      name: name ?? this.name,
      startingBalance: startingBalance,
      receivesIncome: receivesIncome ?? this.receivesIncome,
      purpose: purpose,
      savingsKind: savingsKind,
    );
  }
}

/// A saved wallet, as stored in `users/{uid}/wallets`.
class Wallet {
  const Wallet({
    required this.id,
    required this.name,
    required this.type,
    required this.balance,
    required this.startingBalance,
    required this.receivesIncome,
    required this.archived,
    required this.sortOrder,
    this.purpose = WalletPurpose.spending,
    this.savingsKind,
    this.maturityDate,
  });

  /// Reads a stored wallet document.
  ///
  /// Every field falls back to a safe value, so one malformed record written
  /// by an older build can't break the whole wallet list.
  factory Wallet.fromMap(String id, Map<String, dynamic>? data) {
    final map = data ?? const <String, dynamic>{};
    final type = WalletType.fromName(_asString(map['type']));
    final name = _asString(map['name'])?.trim();

    return Wallet(
      id: id,
      name: name == null || name.isEmpty ? type.label : name,
      type: type,
      balance: _asDouble(map['balance']),
      startingBalance: _asDouble(map['startingBalance']),
      receivesIncome: map['receivesIncome'] == true,
      archived: map['archived'] == true,
      sortOrder: _asDouble(map['sortOrder']).toInt(),
      purpose: WalletPurpose.fromName(_asString(map['purpose'])),
      savingsKind: _asString(map['savingsKind']),
      maturityDate: _asDate(map['maturityDate']),
    );
  }

  final String id;
  final String name;
  final WalletType type;

  /// Current money in this wallet, kept in step with its transactions.
  final double balance;

  /// What the wallet held when it was first added.
  final double startingBalance;

  /// Whether the user's main income is paid into this wallet.
  final bool receivesIncome;

  /// Archived wallets stay in Firestore so old transactions keep their name,
  /// but they are hidden from the wallet list and the total balance.
  final bool archived;

  /// Position in the wallet list, lowest first.
  final int sortOrder;

  /// What the wallet holds money for. Bills and savings wallets are money the
  /// user has already committed, so they are shown apart from spending money.
  final WalletPurpose purpose;
  final String? savingsKind;

  /// When a time deposit or government savings comes due. Null otherwise.
  final DateTime? maturityDate;

  /// True once that day has arrived and the money is still recorded here.
  /// The user still has to say what they did with it; nothing moves on its
  /// own, because FinAssist cannot see a real account.
  bool maturedBy(DateTime now) {
    final due = maturityDate;
    if (due == null || balance <= 0 || archived) return false;
    final day = DateTime(due.year, due.month, due.day);
    final today = DateTime(now.year, now.month, now.day);
    return !day.isAfter(today);
  }

  /// True for the bills and savings wallets, whose money is no longer the
  /// user's to spend.
  bool get isSetAside => purpose != WalletPurpose.spending;

  /// Savings the user cannot simply take out: a time deposit before its date,
  /// or money with SSS, GSIS or Pag-IBIG. Counting it with ordinary savings
  /// would promise money that is years away.
  bool get isLockedSavings =>
      purpose == WalletPurpose.savings &&
      SavingsKind.fromName(savingsKind).isLockedAway;

  String get iconAsset => purpose.iconAsset ?? type.iconAsset;

  static String? _asString(Object? value) => value is String ? value : null;

  static double _asDouble(Object? value) => value is num ? value.toDouble() : 0;

  /// Reads a Firestore timestamp, a DateTime, or nothing at all.
  static DateTime? _asDate(Object? value) {
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    return null;
  }
}

/// Orders wallets the way they are shown: by [Wallet.sortOrder], then by name
/// so wallets saved without an order still come out in a stable sequence.
void sortWallets(List<Wallet> wallets) {
  wallets.sort((a, b) {
    final byOrder = a.sortOrder.compareTo(b.sortOrder);
    return byOrder != 0
        ? byOrder
        : a.name.toLowerCase().compareTo(b.name.toLowerCase());
  });
}

/// The money the user still has to spend: every wallet that isn't archived,
/// leaving out the bills and savings wallets, whose money is already
/// committed. This is the figure shown as the total balance.
double totalWalletBalance(Iterable<Wallet> wallets) {
  return wallets
      .where((wallet) => !wallet.archived && !wallet.isSetAside)
      .fold<double>(0, (total, wallet) => total + wallet.balance);
}

/// What is held in the bills and savings wallets, shown beside the total
/// balance so the user can still see it is there.
double setAsideWalletBalance(Iterable<Wallet> wallets) {
  return wallets
      .where((wallet) => !wallet.archived && wallet.isSetAside)
      .fold<double>(0, (total, wallet) => total + wallet.balance);
}

/// The balance of the wallet kept for [purpose], or zero when the user has
/// none yet.
double walletBalanceFor(Iterable<Wallet> wallets, WalletPurpose purpose) {
  return wallets
      .where((wallet) => !wallet.archived && wallet.purpose == purpose)
      .fold<double>(0, (total, wallet) => total + wallet.balance);
}

/// Savings the user could reach today, which is what the savings balance on
/// Home means. A time deposit or government savings is left out.
double reachableSavingsBalance(Iterable<Wallet> wallets) {
  return wallets
      .where(
        (wallet) =>
            !wallet.archived &&
            wallet.purpose == WalletPurpose.savings &&
            !wallet.isLockedSavings,
      )
      .fold<double>(0, (total, wallet) => total + wallet.balance);
}

/// Savings held somewhere the user cannot draw on yet, shown on its own so
/// the figure above it stays true.
double lockedSavingsBalance(Iterable<Wallet> wallets) {
  return wallets
      .where((wallet) => !wallet.archived && wallet.isLockedSavings)
      .fold<double>(0, (total, wallet) => total + wallet.balance);
}

/// The [Wallet.sortOrder] a newly added wallet should take.
int nextWalletSortOrder(Iterable<Wallet> wallets) {
  var highest = -1;
  for (final wallet in wallets) {
    if (wallet.sortOrder > highest) highest = wallet.sortOrder;
  }
  return highest + 1;
}

/// The wallet that receives the user's income, or null if none is marked.
Wallet? incomeWallet(Iterable<Wallet> wallets) {
  for (final wallet in wallets) {
    if (wallet.receivesIncome && !wallet.archived) return wallet;
  }
  return null;
}

/// Which wallets need their `receivesIncome` flag changed so that only
/// [selectedId] receives income. Wallets already correct are left out, so the
/// resulting write touches as few documents as possible.
Map<String, bool> incomeWalletUpdates(
  Iterable<Wallet> wallets,
  String selectedId,
) {
  final updates = <String, bool>{};
  for (final wallet in wallets) {
    final shouldReceive = wallet.id == selectedId;
    if (wallet.receivesIncome != shouldReceive) {
      updates[wallet.id] = shouldReceive;
    }
  }
  return updates;
}
