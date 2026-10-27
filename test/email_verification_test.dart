import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:testapp/frontend/screens/email_verification_screen.dart';
import 'package:testapp/frontend/theme/app_theme.dart';

/// Only the email is read on screen; anything else would need Firebase.
class _FakeUser implements User {
  @override
  String? get email => 'ada@example.com';

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  testWidgets('says what to do next, with the email it goes to', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: EmailVerificationScreen(user: _FakeUser()),
      ),
    );

    expect(find.text('Check your email'), findsOneWidget);
    expect(find.text('Send a verification link to'), findsOneWidget);
    expect(
      tester
          .widget<Text>(find.byKey(const Key('verification-email-address')))
          .data,
      'ada@example.com',
    );
    // One main button for the next step, and where the email usually hides.
    expect(
      find.descendant(
        of: find.byKey(const Key('verification-main-button')),
        matching: find.text('Send verification email'),
      ),
      findsOneWidget,
    );
    expect(find.text("I've already verified it"), findsOneWidget);
    expect(
      find.text("Can't find it? Check your Spam or Promotions folder."),
      findsOneWidget,
    );
    expect(find.text('Back to Log In'), findsOneWidget);
    // The address is shown, not a box to type in.
    expect(find.byType(TextField), findsNothing);
  });
}
