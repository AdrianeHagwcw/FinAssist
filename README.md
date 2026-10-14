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

## Transaction history

Recorded transactions are read-only in Home, Transactions, and wallet history.
Tapping or long-pressing a history entry does not edit or delete it. Related
bill and debt workflows remain responsible for their linked records.

## Firebase AI Logic (Gemini)

FinAssist uses the official `firebase_ai` Flutter SDK through Firebase AI
Logic. It keeps the existing `Firebase.initializeApp` call and uses the
`gemini-3.1-flash-lite` model through the Google AI provider. No Gemini API key
is stored in the Flutter app.

### Firebase Console setup

1. Confirm the Firebase project ID. The checked-in FlutterFire configuration
   currently targets `test-app-51384`; `test-app` may be its display name. If
   that is not the project you intend to use, re-run FlutterFire configuration
   for the correct project before using AI.
2. In **AI Services → AI Logic**, finish the Gemini setup for that same
   project, enable the Gemini Developer API provider/model as prompted, and
   review applicable quotas and billing.
3. In **Security → App Check**, register the apps that will use AI. Development
   builds use runtime debug providers on Android, iOS, macOS, and web. Run the
   app, copy the generated debug token from the platform/browser log, and add
   it under that app's **Manage debug tokens** screen. Do not put a generated
   token in source control or ship it in a release.
4. Release builds use Play Integrity on Android and App Attest with Device
   Check fallback on Apple platforms. For web release builds, register a
   reCAPTCHA v3 provider and supply its site key at build time:

   ```powershell
   flutter build web --dart-define=APP_CHECK_RECAPTCHA_V3_SITE_KEY=<site-key>
   ```

   The web debug provider does not require a checked-in token. If the release
   site key is missing, App Check is skipped on web with an explicit log
   message; Firebase services may be rejected if App Check enforcement is on.
5. Review App Check metrics before enabling enforcement. Enforcement is a
   Firebase Console action and is not changed by this repository.

`firebase_ai` 4.0.0 supports Android, iOS, macOS, and web. Gemini is not
available on the project's Windows/Linux targets; their existing local
financial-assistant behaviors remain available.

### Financial data and scoring

The chatbot first applies a local financial-topic gate. With an internet
connection, Gemini answers in-scope questions using recent finance-scoped chat
turns and (when loaded) a small current-month aggregate summary. When offline,
or when the Gemini request fails, the existing rule-based assistant answers
from the user's saved records. Interactive purchase-affordability and goal
creation flows continue to use their verified local calculations so their
follow-up choices and app actions remain available. Transaction IDs, notes,
wallet names, and raw transaction history are not sent to Gemini. The Insights
request sends aggregate metrics only, and generated suggestions cannot replace
or recalculate the numbers shown by the app.

For a stated purchase price and time horizon, the chatbot also calculates
straight-line daily and monthly saving targets locally, including Taglish
house-saving questions. If a matching active savings goal exists, its recorded
balance is included; otherwise the estimate clearly assumes no amount is set
aside. Gemini receives the verified target and aggregate income/expense data
to add practical affordability guidance, while the app-calculated target
remains the numeric source of truth.

Explicit requests to record an expense or income, move money between wallets,
or create a savings goal are recognized locally. The chatbot opens the
corresponding existing FinAssist form with any confidently recognized details
prefilled. For a new expense, category and wallet selection are required and
are not silently defaulted; if the description is missing, the chatbot asks
what the expense was for. The user can edit the values and must tap the form's
Save/Confirm control; neither Gemini nor the chat parser writes or transfers
money directly. Ambiguous fields are left unselected for the user to choose,
and unsupported requests do not initiate an action.

The topic gate runs in the client and can be bypassed by a modified client;
it is not a security boundary. If server-enforced topic policy is required,
put the model call behind an authenticated, App-Check-verified callable
function or HTTPS service. That service should validate the topic, derive only
the minimum aggregates from the authenticated user's data, call Vertex AI
using server credentials, and return explanations/suggestions without
exposing credentials to Flutter. No function or Firestore rule is deployed
from this repository.

Insights use the app's recorded income and eligible expenses (excluding
transfers and debt movements). The savings rate is net cash flow divided by
recorded income; it is not a claim that money was moved to savings. Budget
utilization remains unavailable because the current Firestore schema contains
planned Bills/Savings allocations, but no actual spending-budget limit. The
rule-based health indicator is shown only with income and a comparable prior
month-to-date spending period: 40 points for non-negative cash flow, up to 40
points scaled from a 0–20% net cash-flow savings rate, and 20 points when
comparable spending is flat or lower. It is a transparent guide, not a credit
score or accuracy claim. A forecast is the arithmetic average of the previous
three completed months and is unavailable unless each month has eligible
expense history; large variation is labeled uncertain.

### Local verification

```powershell
flutter pub get
flutter analyze
flutter test
flutter run -d <device>
```

## Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Learn Flutter](https://docs.flutter.dev/get-started/learn-flutter)
- [Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Flutter learning resources](https://docs.flutter.dev/reference/learning-resources)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.
