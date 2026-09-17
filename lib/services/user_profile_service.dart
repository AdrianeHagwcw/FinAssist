import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../models/onboarding_data.dart';
import 'firestore_write.dart';

// Profile writes are not awaited and reads use Firestore's default source, so
// they work from the local cache while offline and sync when back online.
class UserProfileService {
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

    final snapshot = await _profileReference(user.uid).get();
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
      'priorities': data.priorities.map((priority) => priority.name).toList(),
      'setupCompleted': true,
      'onboardingVersion': 2,
      'updatedAt': FieldValue.serverTimestamp(),
    };

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
    for (var index = 0; index < data.wallets.length; index++) {
      final wallet = data.wallets[index];
      batch.set(walletsCollection.doc(), {
        'name': wallet.name,
        'type': wallet.type.name,
        'balance': wallet.startingBalance,
        'startingBalance': wallet.startingBalance,
        'receivesIncome': wallet.receivesIncome,
        'archived': false,
        'sortOrder': index,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
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

  static Future<void> saveCategoryBudget({
    required String category,
    required double amount,
    required String period,
  }) async {
    final user = _auth.currentUser;

    if (user == null) {
      throw StateError('No authenticated user.');
    }

    final budgetReference = _profileReference(
      user.uid,
    ).collection('categoryBudgets').doc(_categoryBudgetId(category));
    final budgetData = <String, dynamic>{
      'category': category,
      'amount': amount,
      'period': period,
      'updatedAt': FieldValue.serverTimestamp(),
    };

    if (await _isMissingCreatedAt(budgetReference)) {
      budgetData['createdAt'] = FieldValue.serverTimestamp();
    }

    commitFirestoreWrite(
      budgetReference.set(budgetData, SetOptions(merge: true)),
      'save category budget',
    );
  }

  static Future<void> deleteCategoryBudget(String category) async {
    final user = _auth.currentUser;

    if (user == null) {
      throw StateError('No authenticated user.');
    }

    commitFirestoreWrite(
      _profileReference(
        user.uid,
      ).collection('categoryBudgets').doc(_categoryBudgetId(category)).delete(),
      'delete category budget',
    );
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

  static String _categoryBudgetId(String category) {
    return category.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '_');
  }
}
