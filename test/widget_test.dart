import 'package:flutter_test/flutter_test.dart';
import 'package:pro_profit/main.dart';

void main() {
  testWidgets('App starts without crashing', (WidgetTester tester) async {
    await tester.pumpWidget(const ProProfitApp());
    expect(find.text('Pro Profit'), findsOneWidget);
  });
}
