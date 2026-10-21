import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tasmac_bottle_return/screens/login_screen.dart';
import 'package:tasmac_bottle_return/theme/app_theme.dart';

Widget _app() => MaterialApp(theme: buildAppTheme(), home: const LoginScreen());

void main() {
  testWidgets('Login screen renders User ID and password fields', (WidgetTester tester) async {
    await tester.pumpWidget(_app());

    expect(find.text('Staff Login'), findsOneWidget);
    expect(find.widgetWithText(TextFormField, 'User ID'), findsOneWidget);
    expect(find.widgetWithText(TextFormField, 'Password'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Login'), findsOneWidget);
  });

  testWidgets('Login button shows validation errors on empty submit', (WidgetTester tester) async {
    await tester.pumpWidget(_app());

    await tester.ensureVisible(find.widgetWithText(FilledButton, 'Login'));
    await tester.tap(find.widgetWithText(FilledButton, 'Login'));
    await tester.pump();

    expect(find.text('Enter User ID'), findsOneWidget);
    expect(find.text('Enter password'), findsOneWidget);
  });
}
