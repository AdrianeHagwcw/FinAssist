import 'package:flutter_test/flutter_test.dart';

import 'package:testapp/main.dart';

void main() {
  testWidgets('shows the login screen on startup', (WidgetTester tester) async {
    await tester.pumpWidget(const MyApp());

    expect(find.text('Welcome Back!'), findsOneWidget);
  });
}
