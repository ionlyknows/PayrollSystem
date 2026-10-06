import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';
import 'package:goil_payroll_attendance/core/database/database_location.dart';
import 'package:goil_payroll_attendance/core/database/tables/employee_pay_rates.dart';
import 'package:goil_payroll_attendance/core/database/tables/employees.dart';
import 'package:goil_payroll_attendance/core/database/tables/positions.dart';
import 'package:goil_payroll_attendance/core/database/tables/roles.dart';
import 'package:goil_payroll_attendance/core/database/tables/user_profiles.dart';
import 'package:goil_payroll_attendance/core/utils/id_generator.dart';

part 'app_database.g.dart';

/// Local (offline-first) SQLite database.
///
/// Schema version 2 holds the identity/employee slice only: roles,
/// user_profiles, positions, employees and employee_pay_rates. Further
/// business tables are added in later approved tasks, each with a schema
/// version bump and a tested migration.
@DriftDatabase(
  tables: [Roles, UserProfiles, Positions, Employees, EmployeePayRates],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase(super.e);

  /// Opens the on-device database file (location: see database_location.dart).
  factory AppDatabase.open() => AppDatabase(
    driftDatabase(name: databaseName, native: databaseStorageOptions()),
  );

  static const int currentSchemaVersion = 2;

  @override
  int get schemaVersion => currentSchemaVersion;

  /// Generated tables and annotated indexes, plus the two partial unique
  /// indexes that `@TableIndex` cannot express (they need a WHERE clause).
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
    ...super.allSchemaEntities,
    employeesUserProfileUniqueIndex,
    employeePayRatesOpenEndedUniqueIndex,
  ];

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (Migrator m) async {
      await m.createAll();
    },
    onUpgrade: (Migrator m, int from, int to) async {
      // Schema 0 never existed, so there is no path from it.
      if (from < 1) {
        throw StateError('No migration path from schema $from to $to.');
      }
      // Each version adds one explicit, non-destructive step. Never drop or
      // rewrite existing tables or columns here.
      if (from < 2) {
        await _migrateFrom1To2(m);
      }
    },
    beforeOpen: (OpeningDetails details) async {
      // Section 3.5: local SQLite must run with foreign keys enabled.
      await customStatement('PRAGMA foreign_keys = ON');
    },
  );

  /// Schema 1 was an empty database (no tables). Version 2 adds exactly the
  /// five approved identity/employee tables and their indexes. Only CREATE
  /// statements are issued, so existing data is never touched.
  Future<void> _migrateFrom1To2(Migrator m) async {
    await m.createTable(roles);
    await m.createTable(userProfiles);
    await m.createTable(positions);
    await m.createTable(employees);
    await m.createTable(employeePayRates);
    for (final index in allSchemaEntities.whereType<Index>()) {
      await m.createIndex(index);
    }
  }
}
