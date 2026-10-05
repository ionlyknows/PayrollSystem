import 'package:flutter/material.dart';
import 'package:goil_payroll_attendance/core/constants/app_constants.dart';
import 'package:goil_payroll_attendance/core/routing/app_router.dart';
import 'package:goil_payroll_attendance/core/routing/app_routes.dart';
import 'package:goil_payroll_attendance/core/theme/app_theme.dart';

void main() {
  runApp(const GOilApp());
}

class GOilApp extends StatelessWidget {
  const GOilApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: AppConstants.appName,
      theme: AppTheme.light,
      initialRoute: AppRoutes.home,
      onGenerateRoute: AppRouter.onGenerateRoute,
    );
  }
}
