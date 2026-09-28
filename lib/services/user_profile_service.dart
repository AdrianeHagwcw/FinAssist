import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../models/app_transaction.dart';
import '../models/onboarding_data.dart';
import '../models/wallet.dart';
import 'firestore_write.dart';

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

  /// Saves the onboarding answers and starting wallets in one batch, then
  /// marks setup as completed.
  static Future<void> completeOnboarding(OnboardingData data) async {
    final user = _auth.currentUser;

    if (user == null) {
      throw StateError('No authenticated user.');
    }

    final profileReference = _profileReference(user.uid);
    final profileData = <String, dynamic>{
      'email': user.email,
      'name': data.name,
      'notificationsEnabled': data.notificationsEnabled,
      'incomeSource': data.incomeSource,
      'incomeFrequency': data.incomeFrequency,
      'plannedAllocations': {
        'bills': data.plannedBills,
        'savings': data.plannedSavings,
        'others': data.plannedOthers,
      },
      'priorities': data.priorities.map((priority) => priority.name).toList(),
      'setupCompleted': true,
      'onboardingVersion': 2,
      'updatedAt': FieldValue.serverTimestamp(),
    };

    if (data.lastPaydayAt != null) {
      profileData['lastPaydayAt'] = Timestamp.fromDate(data.lastPaydayAt!);
    }

    if (data.income != null) {
      profileData['income'] = data.income;
    }

    if (data.dailyBudget != null) {
      profileData['dailyBudget'] = data.dailyBudget;
      profileData['budget'] = data.dailyBudget;
      profileData['dailyBudgetStartedAt'] = Timestamp.fromDate(DateTime.now());
    }

    if (await _isMissingCreatedAt(profileReference)) {
      profileData['createdAt'] = FieldValue.serverTimestamp();
    }

    final batch = _firestore.batch()
      ..set(profileReference, profileData, SetOptions(merge: true));

    final walletsCollection = profileReference.collection('wallets');

    // The wallet the pay lands in also funds what the user set aside at
    // setup, so its id and balance are needed below.
    var incomeIndex = data.wallets.indexWhere((wallet) => wallet.receivesIncome);
    if (incomeIndex < 0 && data.wallets.isNotEmpty) incomeIndex = 0;

    final incomeWallet = incomeIndex < 0 ? null : data.wallets[incomeIndex];
    final available = incomeWallet?.startingBalance ?? 0;
    final toBills = _within(data.plannedBills, available);
    final toSavings = _within(data.plannedSavings, available - toBills);

    final references = <DocumentReference<Map<String, dynamic>>>[];

    for (var index = 0; index < data.wallets.length; index++) {
      final wallet = data.wallets[index];
      final reference = walletsCollection.doc();
      references.add(reference);

      // What was set aside is out of this wallet from the first day, so the
      // balance the user sees is only what they may spend.
      final moved = index == incomeIndex ? toBills + toSavings : 0.0;

      batch.set(reference, {
        'name': wallet.name,
        'type': wallet.type.name,
        'balance': wallet.startingBalance - moved,
        'startingBalance': wallet.startingBalance,
        'receivesIncome': wallet.receivesIncome,
        'archived': false,
        'sortOrder': index,
        'purpose': WalletPurpose.spending.name,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    }

    if (incomeIndex >= 0) {
      final transactions = profileReference.collection('transactions');
      var sortOrder = data.wallets.length;

      for (final (purpose, amount) in [
        (WalletPurpose.bills, toBills),
        (WalletPurpose.savings, toSavings),
      ]) {
        if (amount <= 0) continue;

        final wallet = walletsCollection.doc();
        batch.set(wallet, {
          'name': purpose.defaultName,
          'type': WalletType.other.name,
          'balance': amount,
          'startingBalance': 0,
          'receivesIncome': false,
          'archived': false,
          'sortOrder': sortOrder++,
          'purpose': purpose.name,
          'createdAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        });

        // Recorded as a transfer so the ledger explains the balances.
        batch.set(transactions.doc(), {
          'type': TransactionType.transfer.name,
          'amount': amount,
          'label': TransactionType.transfer.label,
          'walletId': references[incomeIndex].id,
          'toWalletId': wallet.id,
          'note': 'Set aside for ${purpose.defaultName?.toLowerCase()}',
          'date': Timestamp.fromDate(DateTime.now()),
          'legacy': false,
          'createdAt': FieldValue.serverTimestamp(),
        });
      }
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

  /// [amount] kept within zero and [ceiling], so setting money aside can never
/// take more than the wallet holds.
static double _within(double amount, double ceiling) {
  if (!amount.isFinite || amount <= 0) return 0;
  if (!ceiling.isFinite || ceiling <= 0) return 0;
  return amount < ceiling ? amount : ceiling;
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
