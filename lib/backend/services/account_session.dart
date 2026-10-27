import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:google_sign_in/google_sign_in.dart';

import 'reminder_service.dart';

/// Google's picker was closed without choosing an account.
class GoogleSignInCancelled implements Exception {
  const GoogleSignInCancelled();
}

/// Google signed in but gave nothing Firebase can use.
class GoogleSignInFailed implements Exception {
  const GoogleSignInFailed(this.message);

  final String message;
}

const _googleScopes = ['email'];

/// Signs out of FinAssist, the same way for Log Out and Switch account.
Future<void> signOutOfApp() async {
  await FirebaseAuth.instance.signOut();
  await _signOutOfGoogle();
}

/// Google keeps the account picked last and would sign it straight back in
/// without asking, so this is cleared before every Google sign-in.
Future<void> _signOutOfGoogle() async {
  try {
    await GoogleSignIn().signOut();
  } catch (error) {
    debugPrint('Could not sign out of Google: $error');
  }
}

/// Asks Google for an account and returns its sign-in for Firebase.
///
/// With [email], that Google account is used straight away. Without one, or
/// when that account is no longer on this phone, Google's own picker asks.
/// Throws [GoogleSignInCancelled] when the user backs out.
Future<OAuthCredential> googleCredential({String? email}) async {
  await _signOutOfGoogle();

  GoogleSignInAccount? account;
  var asked = false;
  // Only Android can be told which account to use.
  if (email != null && defaultTargetPlatform == TargetPlatform.android) {
    try {
      account = await GoogleSignIn(
        scopes: _googleScopes,
        forceAccountName: email,
      ).signIn();
      asked = true;
    } on PlatformException catch (error) {
      // No internet won't be fixed by the picker; a missing account will.
      if (error.code == 'network_error') rethrow;
      debugPrint('Google account not on this phone: ${error.code}');
    }
  }
  if (!asked) {
    account = await GoogleSignIn(
      scopes: _googleScopes,
      signInOption: SignInOption.standard,
    ).signIn();
  }
  if (account == null) throw const GoogleSignInCancelled();

  final tokens = await account.authentication;
  if (tokens.idToken == null) {
    throw const GoogleSignInFailed(
      'Google did not return an ID token. Please check the Android OAuth '
      'configuration.',
    );
  }
  return GoogleAuthProvider.credential(
    accessToken: tokens.accessToken,
    idToken: tokens.idToken,
  );
}

/// Gives changes made offline a moment to reach the server before another
/// account signs in. Any still waiting are kept for this account and sent
/// the next time it signs in.
Future<void> saveChangesBeforeSwitching() async {
  if (FirebaseAuth.instance.currentUser == null) return;
  try {
    await FirebaseFirestore.instance.waitForPendingWrites().timeout(
      const Duration(seconds: 3),
    );
  } catch (_) {
    // Offline: they stay queued for this account.
  }
}

/// Clears the phone's reminders whenever the signed-in account changes, by
/// any way: Log Out, Switch account, or signing up while signed in. One
/// account's reminders never show while another is signed in; the next
/// account plans its own once its home screen opens.
StreamSubscription<User?> clearRemindersOnAccountChange() {
  String? signedIn = FirebaseAuth.instance.currentUser?.uid;
  return FirebaseAuth.instance.authStateChanges().listen((user) {
    if (signedIn != null && user?.uid != signedIn) {
      unawaited(ReminderService.cancelAll());
    }
    signedIn = user?.uid;
  });
}
