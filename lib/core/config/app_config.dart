/// Runtime environment of the application.
enum AppEnvironment { development, production }

/// Application/environment configuration placeholders.
///
/// The application version is defined only by `version:` in `pubspec.yaml`.
/// It is intentionally not duplicated here.
///
/// Backend and storage configuration will be added in later approved tasks.
class AppConfig {
  AppConfig._();

  /// Placeholder environment.
  static const AppEnvironment environment = AppEnvironment.development;
}
