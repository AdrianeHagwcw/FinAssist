import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'account_session.dart';
import 'reminder_service.dart';
import 'saved_accounts.dart';

/// Why the account could not be deleted, or its owner not confirmed.
enum AccountProblem { wrongPassword, cancelled, offline, failed }

/// Deletes the signed-in account: everything it recorded, then its login.
class AccountDeletion {
  /// Every collection kept under `users/{uid}`, now or by an earlier version
  /// of the app, so nothing is left behind. Goals are handled on their own,
  /// for the money saved toward each, which is kept under the goal.
  static const collections = [
    'transactions',
    'wallets',
    'bills',
    'billInstances',
    'debts',
    'allocationCycles',
    'categoryBudgets',
    'expenses',
    'dailyIncomeTransactions',
  ];

  /// Firestore takes up to 500 changes at once.
  static const _perBatch = 400;

  /// Checks it is really the owner: their password for an email account,
  /// Google for a Google one. Returns the problem, or null when confirmed.
  static Future<AccountProblem?> confirm(User user, {String? password}) async {
    try {
      final AuthCredential credential = password != null
          ? EmailAuthProvider.credential(email: user.email!, password: password)
          : await googleCredential(email: user.email);
      await user.reauthenticateWithCredential(credential);
      return null;
    } on GoogleSignInCancelled {
      return AccountProblem.cancelled;
    } on FirebaseAuthException catch (error) {
      return authProblem(error.code);
    } catch (_) {
      return AccountProblem.failed;
    }
  }

  /// What a sign-in error means for the user.
  static AccountProblem authProblem(String code) => switch (code) {
    'wrong-password' ||
    'invalid-credential' ||
    'invalid-login-credentials' ||
    'user-mismatch' => AccountProblem.wrongPassword,
    'network-request-failed' => AccountProblem.offline,
    _ => AccountProblem.failed,
  };

  /// Deletes everything [user] recorded, then the login. Call [confirm]
  /// first, and [signOutDeleted] after. The login goes only once every
  /// record has, so a dropped connection never leaves an account with half
  /// its data. Returns the problem, or null once the account is gone.
  ///
  /// [firestore] is the user's own app's, for a check run outside the app.
  static Future<AccountProblem?> deleteEverything(
    User user, {
    FirebaseFirestore? firestore,
  }) async {
    final store = firestore ?? FirebaseFirestore.instance;
    final profile = store.collection('users').doc(user.uid);
    // From the server, not what this phone has cached, so nothing is missed.
    const fromServer = GetOptions(source: Source.server);

    try {
      final records = <DocumentReference<Map<String, dynamic>>>[];
      for (final name in collections) {
        final snapshot = await profile.collection(name).get(fromServer);
        records.addAll(snapshot.docs.map((doc) => doc.reference));
      }
      final goals = await profile.collection('goals').get(fromServer);
      for (final goal in goals.docs) {
        final contributions = await goal.reference
            .collection('contributions')
            .get(fromServer);
        records
          ..addAll(contributions.docs.map((doc) => doc.reference))
          ..add(goal.reference);
      }
      records.add(profile);

      for (var start = 0; start < records.length; start += _perBatch) {
        final batch = store.batch();
        for (final record in records.skip(start).take(_perBatch)) {
          batch.delete(record);
        }
        await batch.commit().timeout(const Duration(seconds: 30));
      }

      await user.delete();
    } on FirebaseAuthException catch (error) {
      return authProblem(error.code);
    } on FirebaseException catch (error) {
      return error.code == 'unavailable'
          ? AccountProblem.offline
          : AccountProblem.failed;
    } on TimeoutException {
      return AccountProblem.offline;
    } catch (_) {
      return AccountProblem.failed;
    }

    return null;
  }

  /// After [deleteEverything]: the account leaves Switch account's list and
  /// the phone's reminders, and the app signs out.
  static Future<void> signOutDeleted(User user) async {
    final saved = SavedAccount.of(user);
    if (saved != null) await SavedAccounts.forget(saved);
    await ReminderService.cancelAll();
    await signOutOfApp();
  }
}
