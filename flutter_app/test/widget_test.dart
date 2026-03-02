import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';

import 'package:personal_ai_assistant/screens/login_screen.dart';

void main() {
  testWidgets('Login screen renders key fields', (WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(home: LoginScreen()));

    expect(find.text('Personal AI Assistant'), findsOneWidget);
    expect(find.text('Server URL (Cloudflare URL)'), findsOneWidget);
    expect(find.text('Login'), findsOneWidget);
  });
}
