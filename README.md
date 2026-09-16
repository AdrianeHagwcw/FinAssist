# FinAssist

## Social sign-in setup

The login screen uses `google_sign_in`. The Google button will open the
provider sign-in flow once the app is registered with Google.

### Google

1. Create an Android OAuth client in Google Cloud Console for application ID
	`com.example.testapp` and add the debug/release SHA-1 fingerprints.
2. Create an iOS OAuth client using the bundle ID from Xcode, then add the
	generated `GoogleService-Info.plist` to `ios/Runner` if Google asks for it.
3. Register the web client ID when running on web. The plugin can also receive
	it through `GoogleSignIn(serverClientId: '...')` if an ID token is needed by
	a backend.

After platform configuration, run `flutter clean`, `flutter pub get`, and
launch the app on a configured device or emulator.

## Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Learn Flutter](https://docs.flutter.dev/get-started/learn-flutter)
- [Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Flutter learning resources](https://docs.flutter.dev/reference/learning-resources)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.
