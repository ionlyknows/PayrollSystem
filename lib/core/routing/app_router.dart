import 'package:flutter/material.dart';
import 'package:goil_payroll_attendance/core/constants/app_constants.dart';
import 'package:goil_payroll_attendance/core/routing/app_routes.dart';
import 'package:goil_payroll_attendance/core/widgets/placeholder_page.dart';

/// Minimal route generator. Feature routes will be added in later tasks.
class AppRouter {
  AppRouter._();

  static Route<dynamic> onGenerateRoute(RouteSettings settings) {
    switch (settings.name) {
      case AppRoutes.home:
        return MaterialPageRoute<void>(
          settings: settings,
          builder: (_) => const PlaceholderPage(title: AppConstants.appName),
        );
      default:
        return MaterialPageRoute<void>(
          settings: settings,
          builder: (_) => const PlaceholderPage(title: 'Page not found'),
        );
    }
  }
}
