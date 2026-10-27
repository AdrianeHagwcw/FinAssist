/// Plain-language messages for the Google sign-in failures Android reports.
///
/// The plugin passes Android's raw error through, such as
/// "com.google.android.gms.common.api.ApiException: 10", which means nothing
/// to the person holding the phone. Each message here says what to do next,
/// and email sign-in is always offered as the way through.
String googleSignInMessage(String code, [String details = '']) {
  final text = '$code $details';

  if (code == 'network_error' || text.contains('ApiException: 7')) {
    return 'Google sign-in needs an internet connection. '
        'Connect and try again, or log in with your email and password.';
  }
  // DEVELOPER_ERROR: this build of the app is not registered for Google
  // sign-in, so only email and password can work here.
  if (text.contains('ApiException: 10')) {
    return 'Google sign-in is not set up for this copy of the app. '
        'Please log in with your email and password.';
  }
  if (text.contains('ApiException: 12501')) {
    return 'Google sign-in was cancelled.';
  }
  if (text.contains('ApiException: 12500')) {
    return 'Google sign-in could not start on this phone. '
        'Update Google Play services, or log in with your email and password.';
  }
  return 'Google sign-in did not go through. '
      'Please log in with your email and password.';
}

/// Plain-language messages for Firebase sign-in failures when switching to
/// another account. [google] is set when the account came from Google, where
/// a bad credential is not a wrong password.
String signInProblem(String code, {bool google = false}) => switch (code) {
  'wrong-password' ||
  'invalid-credential' ||
  'invalid-login-credentials' when !google => 'Incorrect password.',
  'user-not-found' => 'No account uses this email anymore.',
  'user-disabled' => 'This account has been disabled.',
  'account-exists-with-different-credential' =>
    'This email logs in with a password. Use the password instead.',
  'too-many-requests' =>
    'Too many tries. Wait a few minutes, or reset your password.',
  'network-request-failed' => 'No internet connection. Connect and try again.',
  _ => 'Could not log in. Please try again.',
};
