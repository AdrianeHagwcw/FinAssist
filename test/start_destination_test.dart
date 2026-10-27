import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:testapp/frontend/screens/splash_screen.dart';

class _Session extends Fake implements FirebaseAuth {
  User? user;

  @override
  User? get currentUser => user;

  @override
  Stream<User?> authStateChanges() => Stream.value(user);
}

class _User extends Fake implements User {
  _User(this.refresh);

  final Future<void> Function() refresh;

  @override
  Future<void> reload() => refresh();
}

void main() {
  test('a session cleared during failed refresh opens login', () async {
    final session = _Session();
    session.user = _User(() async {
      session.user = null;
      throw FirebaseAuthException(code: 'user-token-expired');
    });

    expect(
      await resolveStartDestination(auth: session),
      StartDestination.signedOut,
    );
  });

  test(
    'a connection error with a retained session still offers retry',
    () async {
      final session = _Session();
      final error = FirebaseAuthException(code: 'network-request-failed');
      session.user = _User(() async => throw error);

      await expectLater(
        resolveStartDestination(auth: session),
        throwsA(same(error)),
      );
    },
  );

  test('a session cleared during successful refresh opens login', () async {
    final session = _Session();
    session.user = _User(() async => session.user = null);

    expect(
      await resolveStartDestination(auth: session),
      StartDestination.signedOut,
    );
  });
}
