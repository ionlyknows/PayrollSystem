/// Runtime environment of the application.
enum AppEnvironment { development, production }

/// Application/environment configuration placeholders.
///
/// Backend and storage configuration will be added in later approved tasks.
class AppConfig {
  AppConfig._();

  /// Placeholder version. Not yet linked to pubspec.yaml.
  static const String appVersion = '0.1.0';

  /// Placeholder environment.
  static const AppEnvironment environment = AppEnvironment.development;
}
