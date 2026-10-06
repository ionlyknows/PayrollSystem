import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:goil_payroll_attendance/core/database/app_database.dart';
import 'package:goil_payroll_attendance/core/database/drift_transaction_runner.dart';
import 'package:goil_payroll_attendance/core/database/transaction_runner.dart';

// Test-only stand-ins that show the intended pattern. They are not business
// repositories and they use no tables.
abstract interface class _SchemaVersionReader {
  Future<int> readUserVersion();
}

class _DriftSchemaVersionReader implements _SchemaVersionReader {
  _DriftSchemaVersionReader(this._db);

  final AppDatabase _db;

  @override
  Future<int> readUserVersion() async {
    final row = await _db.customSelect('PRAGMA user_version').getSingle();
    return row.read<int>('user_version');
  }
}

void main() {
  late AppDatabase db;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
  });

  tearDown(() async {
    await db.close();
  });

  test('the AppDatabase can be obtained and queried', () async {
    final row = await db.customSelect('SELECT 1 AS one').getSingle();

    expect(row.read<int>('one'), 1);
    expect(db.schemaVersion, AppDatabase.currentSchemaVersion);
  });

  test('a repository implementation receives the database', () async {
    final _SchemaVersionReader reader = _DriftSchemaVersionReader(db);

    expect(await reader.readUserVersion(), AppDatabase.currentSchemaVersion);
  });

  test('a basic transaction runs and returns its result', () async {
    final TransactionRunner runner = DriftTransactionRunner(db);

    final answer = await runner.run(() async {
      final row = await db.customSelect('SELECT 41 + 1 AS answer').getSingle();
      return row.read<int>('answer');
    });

    expect(answer, 42);
  });

  test('repository work can run inside a transaction', () async {
    final TransactionRunner runner = DriftTransactionRunner(db);
    final _SchemaVersionReader reader = _DriftSchemaVersionReader(db);

    final version = await runner.run(reader.readUserVersion);

    expect(version, AppDatabase.currentSchemaVersion);
  });

  test('an error inside a transaction reaches the caller', () async {
    final TransactionRunner runner = DriftTransactionRunner(db);

    await expectLater(
      runner.run<void>(() async {
        throw StateError('boom');
      }),
      throwsStateError,
    );

    // The database is still usable after a failed transaction.
    final row = await db.customSelect('SELECT 1 AS one').getSingle();
    expect(row.read<int>('one'), 1);
  });

  test('domain, presentation and the transaction interface avoid Drift', () {
    final runnerFile = File('lib/core/database/transaction_runner.dart');
    expect(runnerFile.existsSync(), isTrue);

    final checked = <File>[
      runnerFile,
      ...Directory('lib/features')
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) {
            final path = f.path.replaceAll('\\', '/');
            return path.endsWith('.dart') &&
                (path.contains('/domain/') || path.contains('/presentation/'));
          }),
    ];

    final offenders = [
      for (final file in checked)
        if (file.readAsStringSync().contains('package:drift')) file.path,
    ];

    expect(offenders, isEmpty);
  });
}
