import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:testapp/backend/services/account_deletion.dart';
import 'package:testapp/frontend/providers/app_settings_provider.dart';
import 'package:testapp/frontend/screens/profile_screen.dart';
import 'package:testapp/frontend/theme/app_theme.dart';
import 'package:testapp/frontend/widgets/delete_account_dialog.dart';

/// Opens [dialog] from a button, the way Settings does, and returns what it
/// closed with.
Future<List<Object?>> open(WidgetTester tester, Widget dialog) async {
  final closedWith = <Object?>[];
  tester.view.physicalSize = const Size(800, 1800);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    ChangeNotifierProvider(
      create: (_) => AppSettingsProvider(),
      child: MaterialApp(
        theme: AppTheme.light,
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () async => closedWith.add(
                  await showDialog<Object?>(
                    context: context,
                    builder: (_) => dialog,
                  ),
                ),
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Open'));
  await tester.pumpAndSettle();
  return closedWith;
}

void main() {
  test('a wrong password, offline and anything else are told apart', () {
    expect(
      AccountDeletion.authProblem('wrong-password'),
      AccountProblem.wrongPassword,
    );
    expect(
      AccountDeletion.authProblem('invalid-credential'),
      AccountProblem.wrongPassword,
    );
    expect(
      AccountDeletion.authProblem('network-request-failed'),
      AccountProblem.offline,
    );
    expect(
      AccountDeletion.authProblem('internal-error'),
      AccountProblem.failed,
    );
  });

  group('Edit account information', () {
    testWidgets('a Google account shows its email but cannot change it', (
      tester,
    ) async {
      await open(
        tester,
        EditAccountInformationDialog(
          initialName: 'Dave',
          initialEmail: 'dave@gmail.com',
          usesPassword: false,
          onSave: (_, _, _) async =>
              (message: 'Account information updated.', wrongPassword: false),
        ),
      );

      final email = tester.widget<TextField>(
        find.descendant(
          of: find.byKey(const Key('account-email-field')),
          matching: find.byType(TextField),
        ),
      );
      expect(email.enabled, isFalse);
      expect(find.textContaining('Change it there'), findsOneWidget);
    });

    testWidgets('changing the email asks for the password, and keeps the '
        'dialog open when it is wrong', (tester) async {
      String? passwordGiven;
      final closed = await open(
        tester,
        EditAccountInformationDialog(
          initialName: 'Dave',
          initialEmail: 'dave@mail.com',
          usesPassword: true,
          onSave: (_, _, password) async {
            passwordGiven = password;
            return password == 'right'
                ? (message: 'Check your new email.', wrongPassword: false)
                : (message: 'That password is not right.', wrongPassword: true);
          },
        ),
      );

      // Only the name changing asks for nothing more.
      expect(find.byKey(const Key('account-password-field')), findsNothing);
      await tester.enterText(
        find.byKey(const Key('account-email-field')),
        'dave@new.com',
      );
      await tester.pump();
      expect(find.byKey(const Key('account-password-field')), findsOneWidget);

      // Left blank, it is asked for.
      await tester.tap(find.byKey(const Key('account-save')));
      await tester.pumpAndSettle();
      expect(
        find.text('Enter your password to change your email.'),
        findsOneWidget,
      );

      await tester.enterText(
        find.byKey(const Key('account-password-field')),
        'wrong',
      );
      await tester.tap(find.byKey(const Key('account-save')));
      await tester.pumpAndSettle();
      expect(find.text('That password is not right.'), findsOneWidget);
      expect(closed, isEmpty, reason: 'still open to try again');

      await tester.enterText(
        find.byKey(const Key('account-password-field')),
        'right',
      );
      await tester.tap(find.byKey(const Key('account-save')));
      await tester.pumpAndSettle();
      expect(passwordGiven, 'right');
      expect(closed, ['Check your new email.']);
    });
  });

  group('Delete account', () {
    testWidgets('asks for the password, says when it is wrong, then deletes', (
      tester,
    ) async {
      final tried = <String?>[];
      final closed = await open(
        tester,
        DeleteAccountDialog(
          usesPassword: true,
          onDelete: (password) async {
            tried.add(password);
            return password == 'right' ? null : AccountProblem.wrongPassword;
          },
        ),
      );

      expect(find.text('Delete your account?'), findsOneWidget);
      expect(find.textContaining('Export your transactions'), findsOneWidget);

      await tester.tap(find.byKey(const Key('delete-account-confirm')));
      await tester.pump();
      expect(find.text('Enter your password.'), findsOneWidget);
      expect(tried, isEmpty);

      await tester.enterText(
        find.byKey(const Key('delete-account-password')),
        'wrong',
      );
      await tester.tap(find.byKey(const Key('delete-account-confirm')));
      await tester.pumpAndSettle();
      expect(find.text('That password is not right.'), findsOneWidget);
      expect(closed, isEmpty);

      await tester.enterText(
        find.byKey(const Key('delete-account-password')),
        'right',
      );
      await tester.tap(find.byKey(const Key('delete-account-confirm')));
      await tester.pumpAndSettle();
      expect(tried, ['wrong', 'right']);
      expect(closed, [true]);
    });

    testWidgets('a Google account confirms with Google; closing it is no '
        'error', (tester) async {
      final closed = await open(
        tester,
        DeleteAccountDialog(
          usesPassword: false,
          onDelete: (password) async {
            expect(password, isNull);
            return AccountProblem.cancelled;
          },
        ),
      );

      expect(find.byKey(const Key('delete-account-password')), findsNothing);
      expect(find.textContaining('Google will ask you'), findsOneWidget);

      await tester.tap(find.byKey(const Key('delete-account-confirm')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('delete-account-error')), findsNothing);
      expect(closed, isEmpty);

      // Keeping the account closes with nothing deleted.
      await tester.tap(find.text('Keep My Account'));
      await tester.pumpAndSettle();
      expect(closed, [null]);
    });
  });
}
