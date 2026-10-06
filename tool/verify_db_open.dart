// Manual verification harness. It is not part of the app.
//
// Opens the real, production-configured database (AppDatabase.open) and
// checks that it initializes. Creates no tables. Run on Windows with:
//   flutter run -d windows -t tool/verify_db_open.dart
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:goil_payroll_attendance/core/database/app_database.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final db = AppDatabase.open();
  var exitCode = 0;
  try {
    final version = await db.customSelect('PRAGMA user_version').getSingle();
    final fk = await db.customSelect('PRAGMA foreign_keys').getSingle();
    final files = await db.customSelect('PRAGMA database_list').get();
    debugPrint('DB_VERIFY user_version=${version.read<int>('user_version')}');
    debugPrint('DB_VERIFY foreign_keys=${fk.read<int>('foreign_keys')}');
    for (final row in files) {
      debugPrint('DB_VERIFY file=${row.read<String>('file')}');
    }
    debugPrint('DB_VERIFY OK');
  } catch (error, stack) {
    debugPrint('DB_VERIFY FAILED: $error\n$stack');
    exitCode = 1;
  } finally {
    await db.close();
  }
  exit(exitCode);
}
