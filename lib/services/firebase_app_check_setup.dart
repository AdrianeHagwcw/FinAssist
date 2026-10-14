import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:flutter/foundation.dart';

const _webRecaptchaSiteKey = String.fromEnvironment(
  'APP_CHECK_RECAPTCHA_V3_SITE_KEY',
);

/// Activates App Check after Firebase initialization and before app services.
///
/// Debug providers create runtime tokens that must be registered manually in
/// Firebase Console. No generated token is stored in the application.
Future<void> activateFirebaseAppCheck() async {
  if (kIsWeb) {
    if (kDebugMode) {
      await FirebaseAppCheck.instance.activate(providerWeb: WebDebugProvider());
      return;
    }

    if (_webRecaptchaSiteKey.isEmpty) {
      debugPrint(
        'Firebase App Check is not activated on web: '
        'provide APP_CHECK_RECAPTCHA_V3_SITE_KEY at build time.',
      );
      return;
    }

    await FirebaseAppCheck.instance.activate(
      providerWeb: ReCaptchaV3Provider(_webRecaptchaSiteKey),
    );
    return;
  }

  switch (defaultTargetPlatform) {
    case TargetPlatform.android:
      await FirebaseAppCheck.instance.activate(
        providerAndroid: kDebugMode
            ? const AndroidDebugProvider()
            : const AndroidPlayIntegrityProvider(),
      );
    case TargetPlatform.iOS:
    case TargetPlatform.macOS:
      await FirebaseAppCheck.instance.activate(
        providerApple: kDebugMode
            ? const AppleDebugProvider()
            : const AppleAppAttestWithDeviceCheckFallbackProvider(),
      );
    case TargetPlatform.windows:
    case TargetPlatform.linux:
    case TargetPlatform.fuchsia:
      debugPrint(
        'Firebase App Check is not configured for '
        '${defaultTargetPlatform.name}.',
      );
  }
}
