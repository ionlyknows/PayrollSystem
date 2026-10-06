import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';
import 'package:goil_payroll_attendance/core/database/database_location.dart';
import 'package:goil_payroll_attendance/core/database/instant_converter.dart';
import 'package:goil_payroll_attendance/core/database/tables/employee_pay_rates.dart';
import 'package:goil_payroll_attendance/core/database/tables/employees.dart';
import 'package:goil_payroll_attendance/core/database/tables/positions.dart';
import 'package:goil_payroll_attendance/core/database/tables/roles.dart';
import 'package:goil_payroll_attendance/core/database/tables/schedules.dart';
import 'package:goil_payroll_attendance/core/database/tables/shift_assignments.dart';
import 'package:goil_payroll_attendance/core/database/tables/user_profiles.dart';
import 'package:goil_payroll_attendance/core/utils/id_generator.dart';

part 'app_database.g.dart';

/// Local (offline-first) SQLite database.
///
/// Schema version 3 holds the identity/employee slice (roles, user_profiles,
/// positions, employees, employee_pay_rates) and the scheduling slice
/// (schedules, shift_assignments). Further business tables are added in later
/// approved tasks, each with a schema version bump and a tested migration.
@DriftDatabase(
  tables: [
    Roles,
    UserProfiles,
    Positions,
    Employees,
    EmployeePayRates,
    Schedules,
    ShiftAssignments,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase(super.e);

  /// Opens the on-device database file (location: see database_location.dart).
  factory AppDatabase.open() => AppDatabase(
    driftDatabase(name: databaseName, native: databaseStorageOptions()),
  );

  static const int currentSchemaVersion = 3;

  /// Indexes that existed in schema version 2. Frozen: never edit this list.
  static const List<String> _schemaV2IndexNames = [
    'idx_user_profiles_role_id',
    'idx_employees_position_id',
    'idx_employees_employment_status',
    'idx_employee_pay_rates_employee_effective_from',
    'uq_employees_user_profile_id',
    'uq_employee_pay_rates_open_ended',
  ];

  /// Indexes added in schema version 3 (schedules, shift_assignments).
  static const List<String> _schemaV3IndexNames = [
    'idx_schedules_start_end',
    'idx_schedules_status',
    'idx_shift_assignments_employee_shift_date',
    'idx_shift_assignments_schedule_id',
    'idx_shift_assignments_shift_date',
  ];

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
      if (from < 3) {
        await _migrateFrom2To3(m);
      }
    },
    beforeOpen: (OpeningDetails details) async {
      // Section 3.5: local SQLite must run with foreign keys enabled.
      await customStatement('PRAGMA foreign_keys = ON');
    },
  );

  /// Creates exactly the named indexes. Throws if a name is not defined in the
  /// current schema, so a typo can never silently skip an index.
  Future<void> _createIndexesNamed(Migrator m, List<String> names) async {
    final byName = {
      for (final index in allSchemaEntities.whereType<Index>())
        index.entityName: index,
    };
    for (final name in names) {
      final index = byName[name];
      if (index == null) {
        throw StateError('Index $name is not defined in the current schema.');
      }
      await m.createIndex(index);
    }
  }

  /// Schema 1 was an empty database (no tables). Version 2 adds exactly the
  /// five approved identity/employee tables and their (version 2) indexes.
  /// Only CREATE statements are issued, so existing data is never touched.
  Future<void> _migrateFrom1To2(Migrator m) async {
    await m.createTable(roles);
    await m.createTable(userProfiles);
    await m.createTable(positions);
    await m.createTable(employees);
    await m.createTable(employeePayRates);
    await _createIndexesNamed(m, _schemaV2IndexNames);
  }

  /// Version 3 adds exactly schedules and shift_assignments and their
  /// indexes. Only CREATE statements are issued; no existing table changes.
  Future<void> _migrateFrom2To3(Migrator m) async {
    await m.createTable(schedules);
    await m.createTable(shiftAssignments);
    await _createIndexesNamed(m, _schemaV3IndexNames);
  }
}
