import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pro_profit/widgets/app_logo.dart';

void main() {
  testWidgets('AppLogo renders correctly', (WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: AppLogo(),
        ),
      ),
    );
    expect(find.text('Pro Profit'), findsOneWidget);
    expect(find.byType(Icon), findsOneWidget);
  });
}
