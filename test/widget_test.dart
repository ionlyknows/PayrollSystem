import 'package:flutter_test/flutter_test.dart';
import 'package:goil_payroll_attendance/main.dart';

void main() {
  testWidgets('App boots and shows the app name', (WidgetTester tester) async {
    await tester.pumpWidget(const GOilApp());

    expect(find.text('G-Oil Payroll & Attendance'), findsOneWidget);
  });
}
