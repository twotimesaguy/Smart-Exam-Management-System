import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_application_1/main.dart';

void main() {
  testWidgets('app boots into dashboard navigation', (WidgetTester tester) async {
    await tester.pumpWidget(const IntelligentExamApp());

    expect(find.text('Allocation'), findsOneWidget);
    expect(find.text('Attendance'), findsOneWidget);
    expect(find.text('Malpractice'), findsOneWidget);
  });
}
