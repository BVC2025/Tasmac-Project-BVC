import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tasmac_bottle_return/main.dart';

void main() {
  testWidgets('Login screen renders phone and password fields', (WidgetTester tester) async {
    await tester.pumpWidget(const MyApp());

    expect(find.text('Staff Login'), findsOneWidget);
    expect(find.widgetWithText(TextFormField, 'Phone Number'), findsOneWidget);
    expect(find.widgetWithText(TextFormField, 'Password'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Login'), findsOneWidget);
  });

  testWidgets('Login button shows validation errors on empty submit', (WidgetTester tester) async {
    await tester.pumpWidget(const MyApp());

    await tester.tap(find.widgetWithText(FilledButton, 'Login'));
    await tester.pump();

    expect(find.text('Enter phone number'), findsOneWidget);
    expect(find.text('Enter password'), findsOneWidget);
  });
}
