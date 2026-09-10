# FinAssist

## Social sign-in setup

The login screen uses `google_sign_in` and `flutter_facebook_auth`. The buttons
will open the provider sign-in flow once the app is registered with both
providers.

### Google

1. Create an Android OAuth client in Google Cloud Console for application ID
	`com.example.testapp` and add the debug/release SHA-1 fingerprints.
2. Create an iOS OAuth client using the bundle ID from Xcode, then add the
	generated `GoogleService-Info.plist` to `ios/Runner` if Google asks for it.
3. Register the web client ID when running on web. The plugin can also receive
	it through `GoogleSignIn(serverClientId: '...')` if an ID token is needed by
	a backend.

### Facebook

1. Create a Facebook app and enable Facebook Login.
2. Add the Android package `com.example.testapp`, its key hashes, and the iOS
	bundle ID in the Facebook developer dashboard.
3. Follow the plugin setup to add the Facebook App ID and Client Token to
	Android and iOS configuration files. Do not commit those provider values
	if this repository is public.

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
