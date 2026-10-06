import 'dart:io';

import 'package:drift_flutter/drift_flutter.dart';

/// Name of the live database. The file is `<name>.sqlite`. Do not change.
const String databaseName = 'goil_payroll';

/// Folder created under the Windows local application-data directory.
const String windowsDatabaseFolder = 'GOilPayroll';

/// Full path of the live database file on Windows, given the value of the
/// `LOCALAPPDATA` environment variable.
String windowsDatabasePath(String localAppData) {
  final base = localAppData.endsWith('\\')
      ? localAppData.substring(0, localAppData.length - 1)
      : localAppData;
  return '$base\\$windowsDatabaseFolder\\$databaseName.sqlite';
}

/// Storage options for the live database.
///
/// Windows: `%LOCALAPPDATA%\GOilPayroll`, a local folder that OneDrive does
/// not sync. Other platforms: null, which keeps the drift_flutter default
/// (app-private storage on Android).
DriftNativeOptions? databaseStorageOptions() {
  if (!Platform.isWindows) return null;

  return DriftNativeOptions(
    databasePath: () async {
      final localAppData = Platform.environment['LOCALAPPDATA'];
      if (localAppData == null || localAppData.isEmpty) {
        throw StateError(
          'LOCALAPPDATA is not set; cannot locate local application data.',
        );
      }
      final path = windowsDatabasePath(localAppData);
      await Directory(File(path).parent.path).create(recursive: true);
      return path;
    },
  );
}
