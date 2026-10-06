// Manual verification harness. It is not part of the app.
//
// Opens the real, production-configured database (AppDatabase.open), checks
// that it initializes and migrates, and checks where the file lives. Creates
// no rows and no extra tables.
//   Windows: flutter run -d windows -t tool/verify_db_open.dart
//   Android: flutter run -d <device-id> -t tool/verify_db_open.dart
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:goil_payroll_attendance/core/database/app_database.dart';
import 'package:goil_payroll_attendance/core/database/database_location.dart';

const List<String> _expectedTables = [
  'employee_pay_rates',
  'employees',
  'positions',
  'roles',
  'schedules',
  'shift_assignments',
  'user_profiles',
];

String _normalize(String path) => path.toLowerCase().replaceAll('/', '\\');

bool _isUnder(String path, String? base) {
  if (base == null || base.isEmpty) return false;
  var normalizedBase = _normalize(base);
  if (!normalizedBase.endsWith('\\')) normalizedBase = '$normalizedBase\\';
  return _normalize(path).startsWith(normalizedBase);
}

/// Reads `user_version` straight from the SQLite file header (bytes 60-63),
/// without opening the database. Returns null if the file is missing.
int? _readUserVersionFromFile(String path) {
  final file = File(path);
  if (!file.existsSync() || file.lengthSync() < 64) return null;
  final handle = file.openSync();
  try {
    final header = handle.readSync(64);
    return ByteData.sublistView(header).getUint32(60);
  } finally {
    handle.closeSync();
  }
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final env = Platform.environment;
  final localAppData = env['LOCALAPPDATA'];
  if (Platform.isWindows && localAppData != null && localAppData.isNotEmpty) {
    final before = _readUserVersionFromFile(windowsDatabasePath(localAppData));
    debugPrint('DB_VERIFY user_version_before=${before ?? 'no file yet'}');
  }

  final db = AppDatabase.open();
  var failed = false;

  void check(String name, bool passed) {
    debugPrint('DB_VERIFY $name=${passed ? 'PASS' : 'FAIL'}');
    if (!passed) failed = true;
  }

  try {
    final version = (await db.customSelect('PRAGMA user_version').getSingle())
        .read<int>('user_version');
    final foreignKeys =
        (await db.customSelect('PRAGMA foreign_keys').getSingle()).read<int>(
          'foreign_keys',
        );
    final files = await db.customSelect('PRAGMA database_list').get();
    final path = files
        .firstWhere((row) => row.read<String>('name') == 'main')
        .read<String>('file');
    final tableRows = await db
        .customSelect(
          "SELECT name FROM sqlite_master WHERE type = 'table' "
          "AND name NOT LIKE 'sqlite_%' ORDER BY name",
        )
        .get();
    final tables = tableRows.map((row) => row.read<String>('name')).toList();
    final violations = await db.customSelect('PRAGMA foreign_key_check').get();
    final integrity =
        (await db.customSelect('PRAGMA integrity_check').getSingle())
            .read<String>('integrity_check');

    debugPrint('DB_VERIFY user_version=$version');
    debugPrint('DB_VERIFY foreign_keys=$foreignKeys');
    debugPrint('DB_VERIFY file=$path');
    debugPrint('DB_VERIFY tables=${tables.join(',')}');

    final underOneDrive =
        path.toLowerCase().contains('onedrive') ||
        [
          'OneDrive',
          'OneDriveConsumer',
          'OneDriveCommercial',
        ].any((key) => _isUnder(path, env[key]));

    check(
      'user_version_is_current',
      version == AppDatabase.currentSchemaVersion,
    );
    check('foreign_keys_on', foreignKeys == 1);
    check('file_exists', path.isNotEmpty && File(path).existsSync());
    check('not_under_onedrive', !underOneDrive);
    check(
      'not_beside_executable',
      !_isUnder(path, File(Platform.resolvedExecutable).parent.path),
    );
    if (Platform.isWindows) {
      check('under_local_app_data', _isUnder(path, localAppData));
    }
    check(
      'exactly_the_expected_tables',
      tables.length == _expectedTables.length &&
          _expectedTables.every(tables.contains),
    );
    check('foreign_key_check_clean', violations.isEmpty);
    check('integrity_check_ok', integrity == 'ok');
    debugPrint(failed ? 'DB_VERIFY FAILED' : 'DB_VERIFY OK');
  } catch (error, stack) {
    failed = true;
    debugPrint('DB_VERIFY FAILED: $error\n$stack');
  } finally {
    await db.close();
  }
  exit(failed ? 1 : 0);
}
