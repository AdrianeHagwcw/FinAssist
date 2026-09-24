import 'package:flutter_test/flutter_test.dart';

import 'package:testapp/utils/auth_errors.dart';

void main() {
  group('googleSignInMessage', () {
    test('a build that is not registered points to email sign-in', () {
      final message = googleSignInMessage(
        'sign_in_failed',
        'com.google.android.gms.common.api.ApiException: 10: null',
      );

      expect(message, contains('not set up for this copy'));
      expect(message, contains('email and password'));
      expect(message, isNot(contains('ApiException')));
    });

    test('no connection is named as the reason', () {
      expect(
        googleSignInMessage('network_error', ''),
        contains('internet connection'),
      );
      expect(
        googleSignInMessage(
          'sign_in_failed',
          'com.google.android.gms.common.api.ApiException: 7: ',
        ),
        contains('internet connection'),
      );
    });

    test('a cancelled sign-in is not reported as a failure', () {
      expect(
        googleSignInMessage(
          'sign_in_failed',
          'com.google.android.gms.common.api.ApiException: 12501: ',
        ),
        'Google sign-in was cancelled.',
      );
    });

    test('Play services trouble asks for an update', () {
      expect(
        googleSignInMessage(
          'sign_in_failed',
          'com.google.android.gms.common.api.ApiException: 12500: ',
        ),
        contains('Google Play services'),
      );
    });

    test('anything else still leaves a way in', () {
      final message = googleSignInMessage('sign_in_failed', 'null null');

      expect(message, contains('email and password'));
      expect(message, isNot(contains('null')));
    });
  });
}
