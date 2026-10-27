import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:testapp/screens/login_screen.dart';
import 'package:testapp/services/saved_accounts.dart';
import 'package:testapp/theme/app_icons.dart';
import 'package:testapp/theme/app_theme.dart';
import 'package:testapp/utils/auth_errors.dart';
import 'package:testapp/widgets/switch_account_sheet.dart';

/// Switch account lists the accounts used on this phone, so the user picks
/// one instead of only being logged out. The account signed in stays signed
/// in until the other one logs in.
void main() {
  const ada = SavedAccount(uid: 'a', email: 'ada@example.com', name: 'Ada');
  // Signs in only through Google.
  const ben = SavedAccount(
    uid: 'b',
    email: 'ben@gmail.com',
    name: 'Ben',
    usesPassword: false,
    usesGoogle: true,
  );
  // A password, with Google linked too.
  const cy = SavedAccount(uid: 'c', email: 'cy@example.com', usesGoogle: true);

  group('accounts kept on this phone', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    test('the last one signed in comes first, each listed once', () async {
      await SavedAccounts.remember(ada);
      await SavedAccounts.remember(ben);
      // Ada's email changed: still one entry, with the new email.
      await SavedAccounts.remember(
        const SavedAccount(uid: 'a', email: 'ada@new.com', name: 'Ada L'),
      );

      final saved = await SavedAccounts.load();
      expect(
        [for (final a in saved) a.email],
        ['ada@new.com', 'ben@gmail.com'],
      );
      expect(saved.last.usesGoogle, isTrue);
      expect(saved.last.usesPassword, isFalse);
    });

    test('only a few are kept, and one can be removed', () async {
      for (var i = 0; i < SavedAccounts.limit + 2; i++) {
        await SavedAccounts.remember(
          SavedAccount(uid: '$i', email: 'u$i@example.com'),
        );
      }
      expect(await SavedAccounts.load(), hasLength(SavedAccounts.limit));

      await SavedAccounts.forget(
        const SavedAccount(uid: '6', email: 'u6@example.com'),
      );
      final saved = await SavedAccounts.load();
      expect(saved.first.email, 'u5@example.com');
      expect(saved, hasLength(SavedAccounts.limit - 1));
    });
  });

  group('Switch account sheet', () {
    Future<(Future<AccountChoice?>, List<SavedAccount>)> pumpSheet(
      WidgetTester tester, {
      List<SavedAccount> saved = const [ada, ben, cy],
    }) async {
      final forgotten = <SavedAccount>[];
      late Future<AccountChoice?> choice;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () => choice = showSwitchAccountSheet(
                context,
                current: ada,
                saved: saved,
                onForget: forgotten.add,
              ),
              child: const Text('open'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      return (choice, forgotten);
    }

    testWidgets('shows who is signed in and the other accounts', (
      tester,
    ) async {
      await pumpSheet(tester);

      expect(find.text('Switch account'), findsOneWidget);
      // The signed-in account is listed once, marked, and can't be removed.
      expect(find.text('Ada'), findsOneWidget);
      expect(find.byIcon(Icons.check_circle), findsOneWidget);
      expect(find.byKey(const Key('forget-ada@example.com')), findsNothing);
      // Google is named only where it is the only way in.
      expect(find.text('ben@gmail.com · Google'), findsOneWidget);
      expect(find.text('cy@example.com'), findsOneWidget);
      expect(find.text('Add another account'), findsOneWidget);
      expect(
        find.text('You stay signed in as Ada until the other account logs in.'),
        findsOneWidget,
      );
    });

    testWidgets('with only one account, another can still be added', (
      tester,
    ) async {
      final (choice, _) = await pumpSheet(tester, saved: const [ada]);

      expect(find.text('Ada'), findsOneWidget);
      await tester.tap(find.text('Add another account'));
      await tester.pumpAndSettle();

      final picked = await choice;
      expect(picked, isNotNull);
      expect(picked?.account, isNull);
    });

    testWidgets('picking an account returns it', (tester) async {
      final (choice, _) = await pumpSheet(tester);

      await tester.tap(find.byKey(const Key('switch-to-ben@gmail.com')));
      await tester.pumpAndSettle();

      expect((await choice)?.account, ben);
      expect(find.text('Switch account'), findsNothing);
    });

    testWidgets('an account can be removed from this phone', (tester) async {
      final (_, forgotten) = await pumpSheet(tester);

      await tester.tap(find.byKey(const Key('forget-cy@example.com')));
      await tester.pumpAndSettle();

      expect(find.text('cy@example.com'), findsNothing);
      expect(forgotten, [cy]);
      // The sheet stays open to pick another.
      expect(find.text('Switch account'), findsOneWidget);
    });

    testWidgets('closing it switches nothing', (tester) async {
      final (choice, _) = await pumpSheet(tester, saved: const [ada]);

      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();

      expect(await choice, isNull);
    });
  });

  group('password step', () {
    Future<Future<PasswordStep?>> pumpDialog(
      WidgetTester tester,
      SavedAccount account,
      Future<String?> Function(String password) logIn,
    ) async {
      late Future<PasswordStep?> step;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () => step = showAccountPasswordDialog(
                context,
                account: account,
                logIn: logIn,
              ),
              child: const Text('open'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      return step;
    }

    testWidgets('a wrong password keeps it open to try again', (tester) async {
      final tried = <String>[];
      final step = await pumpDialog(tester, ada, (password) async {
        tried.add(password);
        return password == 'right' ? null : 'Incorrect password.';
      });

      expect(find.text('Log in as Ada'), findsOneWidget);
      expect(find.text('ada@example.com'), findsOneWidget);
      // Nothing to try with an empty field.
      await tester.tap(find.byKey(const Key('switch-log-in')));
      await tester.pump();
      expect(find.text('Please enter your password.'), findsOneWidget);
      expect(tried, isEmpty);

      await tester.enterText(find.byKey(const Key('switch-password')), 'nope');
      await tester.tap(find.byKey(const Key('switch-log-in')));
      await tester.pumpAndSettle();
      expect(find.text('Incorrect password.'), findsOneWidget);
      expect(find.text('Log in as Ada'), findsOneWidget);

      await tester.enterText(find.byKey(const Key('switch-password')), 'right');
      await tester.tap(find.byKey(const Key('switch-log-in')));
      await tester.pumpAndSettle();

      expect(tried, ['nope', 'right']);
      expect(await step, PasswordStep.loggedIn);
    });

    testWidgets('Cancel changes nothing', (tester) async {
      final step = await pumpDialog(tester, ada, (_) async => null);

      expect(find.byKey(const Key('switch-use-google')), findsNothing);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(await step, isNull);
    });

    testWidgets('an account with Google linked can use it instead', (
      tester,
    ) async {
      final step = await pumpDialog(tester, cy, (_) async => null);

      expect(find.text('Log in as cy@example.com'), findsOneWidget);
      await tester.tap(find.byKey(const Key('switch-use-google')));
      await tester.pumpAndSettle();

      expect(await step, PasswordStep.useGoogle);
    });
  });

  testWidgets('Add another account can go back to the account signed in', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => const LoginScreen(addingAccount: true),
              ),
            ),
            child: const Text('profile'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('profile'));
    await tester.pumpAndSettle();

    expect(find.text('Add an account'), findsOneWidget);
    expect(find.text('Log in with another account'), findsOneWidget);

    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(find.text('profile'), findsOneWidget);
  });

  test('sign-in problems are said plainly', () {
    expect(signInProblem('invalid-credential'), 'Incorrect password.');
    // From Google, a bad credential is not a wrong password.
    expect(
      signInProblem('invalid-credential', google: true),
      'Could not log in. Please try again.',
    );
    expect(
      signInProblem('network-request-failed'),
      'No internet connection. Connect and try again.',
    );
    expect(
      signInProblem('too-many-requests'),
      'Too many tries. Wait a few minutes, or reset your password.',
    );
  });

  group('Log In', () {
    Future<void> pumpLogIn(WidgetTester tester, {bool adding = false}) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: LoginScreen(addingAccount: adding),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('a new phone is welcomed, with a way to sign up', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({});
      await pumpLogIn(tester);

      expect(find.text('Welcome to FinAssist'), findsOneWidget);
      expect(find.text('or use another account'), findsNothing);
      expect(find.text('Continue with Google'), findsOneWidget);
      expect(find.byKey(const Key('create-account')), findsOneWidget);
    });

    testWidgets('a returning user taps their account instead of typing', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({});
      await SavedAccounts.remember(ada);
      await pumpLogIn(tester);

      expect(find.text('Welcome back'), findsOneWidget);
      expect(find.text('Ada'), findsOneWidget);

      await tester.tap(find.byKey(const Key('continue-as-ada@example.com')));
      await tester.pump();

      final fields = tester.widgetList<TextField>(find.byType(TextField));
      expect(fields.first.controller?.text, 'ada@example.com');
      // Only the password is left, and the keyboard is already there.
      expect(fields.last.focusNode?.hasFocus, isTrue);
    });

    testWidgets('the password starts hidden, with the eye crossed out', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({});
      await pumpLogIn(tester);

      Finder eye(String asset) => find.byWidgetPredicate(
        (widget) =>
            widget is Image &&
            widget.image is AssetImage &&
            (widget.image as AssetImage).assetName == asset,
      );
      TextField password() =>
          tester.widgetList<TextField>(find.byType(TextField)).last;

      expect(password().obscureText, isTrue);
      expect(eye(AppIcons.hidden), findsOneWidget);
      expect(eye(AppIcons.shown), findsNothing);

      // Only when the user asks to see it.
      await tester.tap(find.byType(PasswordEye));
      await tester.pump();
      expect(password().obscureText, isFalse);
      expect(eye(AppIcons.shown), findsOneWidget);
      expect(eye(AppIcons.hidden), findsNothing);
    });

    testWidgets('adding another account lists none of them', (tester) async {
      SharedPreferences.setMockInitialValues({});
      await SavedAccounts.remember(ada);
      await pumpLogIn(tester, adding: true);

      expect(find.text('Add an account'), findsOneWidget);
      expect(find.text('Ada'), findsNothing);
    });
  });
}
