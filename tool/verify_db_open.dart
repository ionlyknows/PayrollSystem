// Manual verification harness. It is not part of the app.
//
// Opens the real, production-configured database (AppDatabase.open), checks
// that it initializes, and checks where the file lives. Creates no tables.
//   Windows: flutter run -d windows -t tool/verify_db_open.dart
//   Android: flutter run -d <device-id> -t tool/verify_db_open.dart
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:goil_payroll_attendance/core/database/app_database.dart';

String _normalize(String path) => path.toLowerCase().replaceAll('/', '\\');

bool _isUnder(String path, String? base) {
  if (base == null || base.isEmpty) return false;
  var normalizedBase = _normalize(base);
  if (!normalizedBase.endsWith('\\')) normalizedBase = '$normalizedBase\\';
  return _normalize(path).startsWith(normalizedBase);
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
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

    debugPrint('DB_VERIFY user_version=$version');
    debugPrint('DB_VERIFY foreign_keys=$foreignKeys');
    debugPrint('DB_VERIFY file=$path');

    final env = Platform.environment;
    final underOneDrive =
        path.toLowerCase().contains('onedrive') ||
        [
          'OneDrive',
          'OneDriveConsumer',
          'OneDriveCommercial',
        ].any((key) => _isUnder(path, env[key]));

    check('user_version_is_1', version == 1);
    check('foreign_keys_on', foreignKeys == 1);
    check('file_exists', path.isNotEmpty && File(path).existsSync());
    check('not_under_onedrive', !underOneDrive);
    check(
      'not_beside_executable',
      !_isUnder(path, File(Platform.resolvedExecutable).parent.path),
    );
    if (Platform.isWindows) {
      check('under_local_app_data', _isUnder(path, env['LOCALAPPDATA']));
    }
    debugPrint(failed ? 'DB_VERIFY FAILED' : 'DB_VERIFY OK');
  } catch (error, stack) {
    failed = true;
    debugPrint('DB_VERIFY FAILED: $error\n$stack');
  } finally {
    await db.close();
  }
  exit(failed ? 1 : 0);
}
