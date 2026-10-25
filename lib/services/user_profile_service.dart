import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../models/onboarding_data.dart';
import '../models/goal.dart';
import '../models/wallet.dart';
import 'bill_service.dart';
import 'firestore_write.dart';
import 'goal_service.dart';
import '../utils/money_format.dart';
import '../utils/text_limits.dart';

// Profile writes are not awaited and reads use Firestore's default source, so
// they work from the local cache while offline and sync when back online. The
// setup check reads the saved copy first; see [isSetupCompleted].
class UserProfileService {
  static void updatePreferences(Map<String, dynamic> values) {
    final user = _auth.currentUser;
    if (user == null) throw StateError('No authenticated user.');
    commitFirestoreWrite(
      _profileReference(user.uid).set({
        ...values,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true)),
      'update financial preferences',
    );
  }

  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  static final FirebaseAuth _auth = FirebaseAuth.instance;

  static DocumentReference<Map<String, dynamic>> _profileReference(String uid) {
    return _firestore.collection('users').doc(uid);
  }

  static Future<bool> isSetupCompleted() async {
    final user = _auth.currentUser;

    if (user == null) {
      throw StateError('No authenticated user.');
    }

    final profile = _profileReference(user.uid);
    // Finishing setup is never undone, so a copy saved on this phone that
    // says so is enough, and the app opens without waiting for the network.
    // Anything else is asked of the server: setup may have been finished on
    // another phone.
    try {
      final saved = await profile.get(const GetOptions(source: Source.cache));
      if (saved.data()?['setupCompleted'] == true) return true;
    } catch (_) {
      // Nothing saved on this phone yet.
    }

    final snapshot = await profile.get();
    return snapshot.data()?['setupCompleted'] == true;
  }

  /// The signed-in user's profile document, updating live. Used by screens
  /// that show a saved answer, such as which income source a wallet receives.
  static Stream<DocumentSnapshot<Map<String, dynamic>>> watchProfile() {
    final user = _auth.currentUser;

    if (user == null) {
      throw StateError('No authenticated user.');
    }

    return _profileReference(user.uid).snapshots();
  }

  static Future<void> createInitialProfile(User user) async {
    await _profileReference(user.uid).set({
      'email': user.email,
      'setupCompleted': false,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  /// Everything typed in setup, checked again before it is saved: names
  /// readable and within their limits, amounts real numbers no bigger than
  /// [maximumAmount]. The screens already refuse these, so this only stops a
  /// value that got in some other way.
  static void _checkLimits(OnboardingData data) {
    // The same rule as the screens: a word in it, and no account number.
    void name(String value, int maxLength, String field) {
      final problem = itemNameProblem(value, maxLength: maxLength);
      if (problem != null) throw ArgumentError.value(value, field, problem);
    }

    void amount(double value, String field, {bool allowZero = true}) {
      final low = allowZero ? 0 : minimumAmount;
      if (!value.isFinite || value < low || value > maximumAmount) {
        throw ArgumentError.value(
          value,
          field,
          'Must be from $low to $maximumAmount.',
        );
      }
    }

    final nameProblem = personNameProblem(data.name);
    if (nameProblem != null) {
      throw ArgumentError.value(data.name, 'name', nameProblem);
    }
    for (final wallet in data.wallets) {
      name(wallet.name, maxSavedWalletNameLength, 'wallet.name');
      amount(wallet.startingBalance, 'wallet.startingBalance');
    }
    for (final savings in data.savingsAccounts) {
      name(savings.name, maxItemNameLength, 'savings.name');
      amount(savings.balance, 'savings.balance');
    }
    for (final bill in data.bills) {
      name(bill.name, maxItemNameLength, 'bill.name');
      amount(bill.amount, 'bill.amount', allowZero: false);
    }
    for (final goal in data.goals) {
      name(goal.name, maxItemNameLength, 'goal.name');
      amount(goal.targetAmount, 'goal.targetAmount', allowZero: false);
      if (goal.planAmount != null) {
        amount(goal.planAmount!, 'goal.planAmount');
      }
      for (final funded in goal.fundingByWalletDraftId.values) {
        amount(funded, 'goal.fundingByWalletDraftId');
      }
      final custom = goal.customInterval;
      if (goal.frequency == ContributionFrequency.custom &&
          custom != null &&
          !custom.isValid) {
        throw ArgumentError.value(custom.count, 'goal.customInterval');
      }
    }
  }

  /// Saves the onboarding answers and starting wallets in one batch, then
  /// marks setup as completed.
  static Future<void> completeOnboarding(OnboardingData data) async {
    final user = _auth.currentUser;

    if (user == null) {
      throw StateError('No authenticated user.');
    }
    _checkLimits(data);
    for (final wallet in data.wallets) {
      final rate = wallet.annualInterestRatePercent;
      if (rate != null && !isValidAnnualInterestRatePercent(rate)) {
        throw ArgumentError.value(
          rate,
          'annualInterestRatePercent',
          'Must be between 0 and '
              '${maximumAnnualInterestRatePercent.toInt()}%.',
        );
      }
    }
    final draftIds = <String>{};
    for (final wallet in data.wallets) {
      final id = wallet.id;
      if (id != null && !draftIds.add(id)) {
        throw ArgumentError.value(id, 'wallet.id', 'Must be unique.');
      }
    }
    final walletDraftsById = {
      for (final wallet in data.wallets)
        if (wallet.id != null) wallet.id!: wallet,
    };
    final allocatedByDraftId = <String, double>{};
    for (final goal in data.goals) {
      if (goal.allocated < 0 || !goal.allocated.isFinite) {
        throw ArgumentError.value(goal.allocated, 'goal.allocated');
      }
      if (goal.allocated > goal.targetAmount + 0.005) {
        throw ArgumentError('A goal cannot be funded beyond its target.');
      }
      if (goal.fundingByWalletDraftId.isEmpty) {
        if (goal.allocated > 0 &&
            (goal.fundedBy == null ||
                !data.savingsAccounts.any(
                  (savings) => savings.name == goal.fundedBy,
                ))) {
          throw ArgumentError(
            'A funded goal must identify its wallet or savings record.',
          );
        }
        continue;
      }
      // Cash, accounts, or both: every wallet is checked on its own, and
      // the stored source must match the wallets actually used.
      final sourceTypes = <WalletType>[];
      for (final entry in goal.fundingByWalletDraftId.entries) {
        final source = walletDraftsById[entry.key];
        if (source == null) {
          throw ArgumentError.value(
            entry.key,
            'goal.fundingByWalletDraftId',
            'Must identify a wallet added during setup.',
          );
        }
        if (entry.value < 0 || !entry.value.isFinite) {
          throw ArgumentError.value(entry.value, 'goal.fundingByWalletDraftId');
        }
        if (source.type != WalletType.cash &&
            !isBankOrEWalletType(source.type)) {
          throw ArgumentError(
            'A goal can only be funded from cash, a bank, or an e-wallet.',
          );
        }
        if (entry.value > 0 && !source.balanceRecorded) {
          throw ArgumentError(
            'A goal cannot be funded from a wallet without a recorded balance.',
          );
        }
        sourceTypes.add(source.type);
        allocatedByDraftId.update(
          entry.key,
          (allocated) => allocated + entry.value,
          ifAbsent: () => entry.value,
        );
      }
      if (goal.fundingSource != GoalFundingSource.fromTypes(sourceTypes)) {
        throw ArgumentError(
          'A goal funding source must match its selected cash, bank, or e-wallet.',
        );
      }
    }
    for (final entry in allocatedByDraftId.entries) {
      final wallet = walletDraftsById[entry.key]!;
      if (entry.value > wallet.startingBalance + 0.005) {
        throw ArgumentError(
          'Goals cannot allocate more than ${wallet.name} contains.',
        );
      }
    }
    for (final savings in data.savingsAccounts) {
      final rate = savings.annualInterestRatePercent;
      if (rate != null && !isValidAnnualInterestRatePercent(rate)) {
        throw ArgumentError.value(
          rate,
          'annualInterestRatePercent',
          'Must be between 0 and '
              '${maximumAnnualInterestRatePercent.toInt()}%.',
        );
      }
      if (savings.kind.isInterestBearing && rate == null) {
        throw ArgumentError(
          'Interest-bearing savings require an interest rate.',
        );
      }
      if (savings.kind.isInterestBearing && savings.depositStartDate == null) {
        throw ArgumentError('Interest-bearing savings require a start date.');
      }
      if (savings.kind == SavingsKind.timeDeposit &&
          (savings.maturityDate == null ||
              !savings.maturityDate!.isAfter(savings.depositStartDate!))) {
        throw ArgumentError(
          'A time deposit maturity date must be after its start date.',
        );
      }
    }

    final profileReference = _profileReference(user.uid);
    final profileData = <String, dynamic>{
      'email': user.email,
      'name': data.name,
      'notificationsEnabled': data.notificationsEnabled,
      'plannedAllocations': {'bills': 0, 'savings': 0},
      'priorities': data.priorities.map((priority) => priority.name).toList(),
      'setupCompleted': true,
      'onboardingVersion': 2,
      'updatedAt': FieldValue.serverTimestamp(),
    };

    if (data.incomeSource != null) {
      profileData['incomeSource'] = data.incomeSource;
    }
    if (data.incomeFrequency != null) {
      profileData['incomeFrequency'] = data.incomeFrequency;
    }

    if (data.lastPaydayAt != null) {
      profileData['lastPaydayAt'] = Timestamp.fromDate(data.lastPaydayAt!);
    }

    if (data.monthlyIncome != null) {
      // Existing profile consumers treat `income` as an amount per payday.
      profileData['income'] = data.incomePerPayPeriod;
    }

    if (await _isMissingCreatedAt(profileReference)) {
      profileData['createdAt'] = FieldValue.serverTimestamp();
    }

    final batch = _firestore.batch()
      ..set(profileReference, profileData, SetOptions(merge: true));

    final billsCollection = profileReference.collection('bills');
    for (final bill in data.bills) {
      BillService.addBillToBatch(
        batch,
        reference: billsCollection.doc(),
        name: bill.name,
        amount: bill.amount,
        category: bill.category,
        firstDueDate: bill.firstDueDate,
        recurrence: bill.recurrence,
      );
    }

    final walletsCollection = profileReference.collection('wallets');
    final walletIdsByDraftId = <String, String>{};

    for (var index = 0; index < data.wallets.length; index++) {
      final wallet = data.wallets[index];
      final reference = walletsCollection.doc();
      if (wallet.id != null) walletIdsByDraftId[wallet.id!] = reference.id;

      batch.set(reference, {
        'name': wallet.name,
        'type': wallet.type.name,
        'balance': wallet.startingBalance,
        'balanceRecorded': wallet.balanceRecorded,
        'startingBalance': wallet.startingBalance,
        'receivesIncome': wallet.receivesIncome,
        if (wallet.annualInterestRatePercent != null)
          'annualInterestRatePercent': wallet.annualInterestRatePercent,
        'archived': false,
        'sortOrder': index,
        'purpose': wallet.purpose.name,
        if (wallet.savingsKind != null) 'savingsKind': wallet.savingsKind,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    }

    var sortOrder = data.wallets.length;
    // Each savings record becomes a wallet held aside from spending. The id
    // is kept so a goal funded by it can point at the right one.
    final savingsWalletIds = <String, String>{};
    for (final savings in data.savingsAccounts) {
      final reference = walletsCollection.doc();
      savingsWalletIds[savings.name] = reference.id;
      batch.set(reference, {
        'name': savings.name,
        'type': WalletType.other.name,
        'balance': savings.balance,
        'startingBalance': savings.balance,
        'receivesIncome': false,
        'archived': false,
        'sortOrder': sortOrder++,
        'purpose': WalletPurpose.savings.name,
        'savingsKind': savings.kind.name,
        if (savings.annualInterestRatePercent != null)
          'annualInterestRatePercent': savings.annualInterestRatePercent,
        if (savings.depositStartDate != null)
          'depositStartDate': Timestamp.fromDate(savings.depositStartDate!),
        if (savings.maturityDate != null)
          'maturityDate': Timestamp.fromDate(savings.maturityDate!),
        if (savings.kind == SavingsKind.savingsDeposit)
          'interestPayoutMonths': savings.interestPayout.months,
        if (savings.note != null) 'note': savings.note,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    }

    final goalsCollection = profileReference.collection('goals');
    for (var index = 0; index < data.goals.length; index++) {
      final goal = data.goals[index];
      // An allocation earmarks part of each wallet for this goal. The
      // wallets keep their balances; only the goal's own figures change.
      final fundingWalletId = goal.fundingWalletDraftId == null
          ? (goal.fundedBy == null ? null : savingsWalletIds[goal.fundedBy])
          : walletIdsByDraftId[goal.fundingWalletDraftId];
      final savedByWallet = setupGoalMoneyByWallet(
        goal,
        walletIdsByDraftId: walletIdsByDraftId,
        fundingWalletId: fundingWalletId,
      );
      final allocated = savedByWallet.values.fold<double>(
        0,
        (total, amount) => total + amount,
      );

      GoalService.addGoalToBatch(
        batch,
        reference: goalsCollection.doc(),
        name: goal.name,
        targetAmount: goal.targetAmount,
        targetDate: goal.targetDate,
        priority: index,
        kind: goal.kind,
        frequency: goal.frequency,
        customInterval: goal.customInterval,
        planAmount: goal.planAmount,
        note: goal.note,
        walletId: fundingWalletId,
        fundingSource:
            goal.fundingSource ??
            (goal.fundedBy == null ? null : GoalFundingSource.savings),
        savedAmount: allocated,
        savedByWallet: savedByWallet,
      );
    }

    commitFirestoreWrite(batch.commit(), 'complete onboarding');

    // Keeps the Home greeting in sync. Needs a connection, so a failure is
    // only logged; the name is also stored in the profile above.
    if (data.name.isNotEmpty && data.name != user.displayName) {
      commitFirestoreWrite(
        user.updateDisplayName(data.name),
        'update display name',
      );
    }
  }

  /// Whether [reference] has no `createdAt` yet. If the document can't be
  /// read (offline and not cached), returns false so an existing `createdAt`
  /// is never overwritten by a merge write.
  static Future<bool> _isMissingCreatedAt(
    DocumentReference<Map<String, dynamic>> reference,
  ) async {
    try {
      final snapshot = await reference.get();
      return snapshot.data()?['createdAt'] == null;
    } on FirebaseException {
      return false;
    }
  }
}

/// Where a setup goal's money is, by the saved wallets' ids: each draft
/// wallet's amount under the id it was saved with. A goal set up before
/// amounts were kept per wallet has all of it in [fundingWalletId].
///
/// Every amount lands once, on its own wallet: an amount whose draft wallet
/// was not saved is left out rather than moved onto another.
Map<String, double> setupGoalMoneyByWallet(
  OnboardingGoal goal, {
  required Map<String, String> walletIdsByDraftId,
  required String? fundingWalletId,
}) {
  final byWallet = <String, double>{};
  if (goal.fundingByWalletDraftId.isNotEmpty) {
    goal.fundingByWalletDraftId.forEach((draftId, amount) {
      final walletId = walletIdsByDraftId[draftId];
      if (amount > 0 && walletId != null) {
        byWallet[walletId] = (byWallet[walletId] ?? 0) + amount;
      }
    });
  } else if (fundingWalletId != null && goal.allocated > 0) {
    byWallet[fundingWalletId] = goal.allocated;
  }
  return byWallet;
}
