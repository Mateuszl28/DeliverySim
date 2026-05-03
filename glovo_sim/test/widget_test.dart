import 'package:flutter_test/flutter_test.dart';

import 'package:glovo_sim/main.dart';

void main() {
  testWidgets('App boots', (WidgetTester tester) async {
    await tester.pumpWidget(const GlovoSimApp());
    expect(find.text('Jesteś offline'), findsOneWidget);
  });
}
