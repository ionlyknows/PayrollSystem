import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:goil_payroll_attendance/core/routing/app_router.dart';

void main() {
  testWidgets('Unknown route shows the not-found placeholder', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        initialRoute: '/does-not-exist',
        onGenerateRoute: AppRouter.onGenerateRoute,
      ),
    );

    expect(find.text('Page not found'), findsOneWidget);
  });
}
