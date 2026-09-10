import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

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

  static Future<void> createInitialProfile(User user) async {
    await _profileReference(user.uid).set({
      'email': user.email,
      'setupCompleted': false,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  static Future<void> saveFinancialSetup({
    required String incomeSource,
    required double income,
    required String incomeFrequency,
    required double budget,
  }) async {
    final user = _auth.currentUser;

    if (user == null) {
      throw StateError('No authenticated user.');
    }

    final profileReference = _profileReference(user.uid);
    final existingProfile = await profileReference.get();
    final profileData = <String, dynamic>{
      'email': user.email,
      'income': income,
      'incomeSource': incomeSource,
      'incomeFrequency': incomeFrequency,
      'dailyBudget': budget,
      'budget': budget,
      'dailyBudgetStartedAt': Timestamp.fromDate(DateTime.now()),
      'setupCompleted': true,
      'updatedAt': FieldValue.serverTimestamp(),
    };

    if (!existingProfile.exists ||
        !existingProfile.data()!.containsKey('createdAt')) {
      profileData['createdAt'] = FieldValue.serverTimestamp();
    }

    await profileReference.set(profileData, SetOptions(merge: true));
    await profileReference.get(const GetOptions(source: Source.server));
  }

  static Future<void> updateIncome({
    required double income,
    required String incomeSource,
  }) async {
    await _updateProfile({'income': income, 'incomeSource': incomeSource});
  }

  static Future<void> addOtherIncome({
    required double amount,
    required String incomeSource,
  }) async {
    final user = _auth.currentUser;

    if (user == null) {
      throw StateError('No authenticated user.');
    }

    final profile = await _profileReference(user.uid).get();
    final profileData = profile.data();
    final currentDailyIncome =
        (profileData?['dailyIncome'] as num?)?.toDouble() ??
        (profileData?['otherIncome'] as num?)?.toDouble() ??
        0;

    await _updateProfile({
      'dailyIncome': currentDailyIncome + amount,
      'lastDailyIncomeSource': incomeSource,
    });

    await _profileReference(
      user.uid,
    ).collection('dailyIncomeTransactions').add({
      'amount': amount,
      'source': incomeSource,
      'type': 'income',
      'date': FieldValue.serverTimestamp(),
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  static Future<void> updateBudget(double budget) async {
    await _updateProfile({
      'dailyBudget': budget,
      'budget': budget,
      'dailyBudgetStartedAt': Timestamp.fromDate(DateTime.now()),
    });
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
    final existingBudget = await budgetReference.get();
    final existingData = existingBudget.data();
    final budgetData = <String, dynamic>{
      'category': category,
      'amount': amount,
      'period': period,
      'updatedAt': FieldValue.serverTimestamp(),
    };

    if (existingData?['createdAt'] == null) {
      budgetData['createdAt'] = FieldValue.serverTimestamp();
    }

    await budgetReference.set(budgetData);
  }

  static Future<void> deleteCategoryBudget(String category) async {
    final user = _auth.currentUser;

    if (user == null) {
      throw StateError('No authenticated user.');
    }

    await _profileReference(
      user.uid,
    ).collection('categoryBudgets').doc(_categoryBudgetId(category)).delete();
  }

  static String _categoryBudgetId(String category) {
    return category.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '_');
  }

  static Future<void> markNotificationsSeen() async {
    await _updateProfile({
      'notificationsLastSeenAt': Timestamp.fromDate(DateTime.now()),
    });
  }

  static Future<bool> hasUnreadNotifications() async {
    final user = _auth.currentUser;

    if (user == null) return false;

    final profile = await _profileReference(user.uid).get();
    final lastSeen = (profile.data()?['notificationsLastSeenAt'] as Timestamp?)
        ?.toDate();
    final latestExpense = await _profileReference(
      user.uid,
    ).collection('expenses').orderBy('date', descending: true).limit(1).get();

    if (latestExpense.docs.isEmpty) return false;
    if (lastSeen == null) return true;

    final latestExpenseData = latestExpense.docs.first.data();
    final latestDate =
        (latestExpenseData['createdAt'] as Timestamp?)?.toDate() ??
        (latestExpenseData['date'] as Timestamp?)?.toDate();
    return latestDate != null && latestDate.isAfter(lastSeen);
  }

  static Future<DocumentSnapshot<Map<String, dynamic>>>
  getDailyBudgetProfile() async {
    final user = _auth.currentUser;

    if (user == null) {
      throw StateError('No authenticated user.');
    }

    final profileReference = _profileReference(user.uid);
    final profile = await profileReference.get();
    final profileData = profile.data() ?? <String, dynamic>{};
    final storedStart = profileData['dailyBudgetStartedAt'];
    final start = storedStart is Timestamp
        ? storedStart.toDate()
        : DateTime.now();
    final now = DateTime.now();

    var nextStart = start;
    while (!now.isBefore(nextStart.add(const Duration(days: 1)))) {
      nextStart = nextStart.add(const Duration(days: 1));
    }

    if (storedStart is! Timestamp || nextStart != start) {
      await profileReference.set({
        'dailyBudgetStartedAt': Timestamp.fromDate(nextStart),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      return profileReference.get(const GetOptions(source: Source.server));
    }

    return profile;
  }

  static Future<void> _updateProfile(Map<String, dynamic> fields) async {
    final user = _auth.currentUser;

    if (user == null) {
      throw StateError('No authenticated user.');
    }

    await _profileReference(user.uid).set({
      ...fields,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    await _profileReference(
      user.uid,
    ).get(const GetOptions(source: Source.server));
  }
}
