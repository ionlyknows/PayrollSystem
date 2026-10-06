import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:goil_payroll_attendance/core/database/app_database.dart';

void main() {
  late AppDatabase db;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
  });

  tearDown(() async {
    await db.close();
  });

  test('declares schema version 2', () {
    expect(db.schemaVersion, 2);
  });

  test('creates the database at schema version 2', () async {
    final row = await db.customSelect('PRAGMA user_version').getSingle();
    expect(row.read<int>('user_version'), 2);
  });

  test('has foreign keys enabled', () async {
    final row = await db.customSelect('PRAGMA foreign_keys').getSingle();
    expect(row.read<int>('foreign_keys'), 1);
  });

  test('writes a UTC instant as ISO 8601 text ending in Z (OD-02)', () async {
    await db.customStatement('CREATE TEMP TABLE instant_check (at TEXT)');
    final instant = DateTime.utc(2026, 10, 6, 12, 30, 15);
    await db.customInsert(
      'INSERT INTO instant_check (at) VALUES (?)',
      variables: [Variable.withDateTime(instant)],
    );

    final row = await db
        .customSelect('SELECT at FROM instant_check')
        .getSingle();
    final stored = row.read<String>('at');

    expect(stored, endsWith('Z'));
    expect(DateTime.parse(stored), instant);
  });
}
