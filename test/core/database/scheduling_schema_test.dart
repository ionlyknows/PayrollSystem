import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:goil_payroll_attendance/core/database/app_database.dart';
import 'package:goil_payroll_attendance/core/database/drift_transaction_runner.dart';

final RegExp _uuidV4 = RegExp(
  r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
);

const String _missing = '00000000-0000-4000-8000-000000000000';

const List<String> _v3Tables = [
  'employee_pay_rates',
  'employees',
  'positions',
  'roles',
  'schedules',
  'shift_assignments',
  'user_profiles',
];

const List<String> _v2Indexes = [
  'idx_user_profiles_role_id',
  'idx_employees_position_id',
  'idx_employees_employment_status',
  'idx_employee_pay_rates_employee_effective_from',
  'uq_employees_user_profile_id',
  'uq_employee_pay_rates_open_ended',
];

const List<String> _v3Indexes = [
  'idx_schedules_start_end',
  'idx_schedules_status',
  'idx_shift_assignments_employee_shift_date',
  'idx_shift_assignments_schedule_id',
  'idx_shift_assignments_shift_date',
];

// Raw schema version 2 DDL (the five identity tables and their indexes), used
// to build a genuine v2 database without any schema-dump tooling.
const List<String> _v2Ddl = [
  'CREATE TABLE roles ('
      'id TEXT NOT NULL, created_at TEXT NOT NULL, updated_at TEXT NOT NULL, '
      'created_by TEXT NULL REFERENCES user_profiles (id) '
      'ON UPDATE RESTRICT ON DELETE RESTRICT, '
      'updated_by TEXT NULL REFERENCES user_profiles (id) '
      'ON UPDATE RESTRICT ON DELETE RESTRICT, '
      'code TEXT NOT NULL UNIQUE, name TEXT NOT NULL, description TEXT NULL, '
      'is_system INTEGER NOT NULL CHECK (is_system IN (0, 1)), '
      'PRIMARY KEY (id))',
  'CREATE TABLE user_profiles ('
      'id TEXT NOT NULL, created_at TEXT NOT NULL, updated_at TEXT NOT NULL, '
      'created_by TEXT NULL REFERENCES user_profiles (id) '
      'ON UPDATE RESTRICT ON DELETE RESTRICT, '
      'updated_by TEXT NULL REFERENCES user_profiles (id) '
      'ON UPDATE RESTRICT ON DELETE RESTRICT, '
      'auth_user_id TEXT NOT NULL UNIQUE, '
      'role_id TEXT NOT NULL REFERENCES roles (id) '
      'ON UPDATE RESTRICT ON DELETE RESTRICT, '
      'display_name TEXT NOT NULL, '
      'is_active INTEGER NOT NULL CHECK (is_active IN (0, 1)), '
      'PRIMARY KEY (id))',
  'CREATE TABLE positions ('
      'id TEXT NOT NULL, created_at TEXT NOT NULL, updated_at TEXT NOT NULL, '
      'created_by TEXT NULL REFERENCES user_profiles (id) '
      'ON UPDATE RESTRICT ON DELETE RESTRICT, '
      'updated_by TEXT NULL REFERENCES user_profiles (id) '
      'ON UPDATE RESTRICT ON DELETE RESTRICT, '
      'code TEXT NOT NULL UNIQUE, name TEXT NOT NULL, description TEXT NULL, '
      'is_active INTEGER NOT NULL CHECK (is_active IN (0, 1)), '
      'PRIMARY KEY (id))',
  'CREATE TABLE employees ('
      'id TEXT NOT NULL, created_at TEXT NOT NULL, updated_at TEXT NOT NULL, '
      'created_by TEXT NULL REFERENCES user_profiles (id) '
      'ON UPDATE RESTRICT ON DELETE RESTRICT, '
      'updated_by TEXT NULL REFERENCES user_profiles (id) '
      'ON UPDATE RESTRICT ON DELETE RESTRICT, '
      'employee_code TEXT NOT NULL UNIQUE, '
      'user_profile_id TEXT NULL REFERENCES user_profiles (id) '
      'ON UPDATE RESTRICT ON DELETE RESTRICT, '
      'first_name TEXT NOT NULL, middle_name TEXT NULL, '
      'last_name TEXT NOT NULL, '
      'position_id TEXT NULL REFERENCES positions (id) '
      'ON UPDATE RESTRICT ON DELETE RESTRICT, '
      'hire_date TEXT NOT NULL, separation_date TEXT NULL, '
      'employment_status TEXT NOT NULL, phone TEXT NULL, address TEXT NULL, '
      'PRIMARY KEY (id))',
  'CREATE TABLE employee_pay_rates ('
      'id TEXT NOT NULL, created_at TEXT NOT NULL, '
      'created_by TEXT NULL REFERENCES user_profiles (id) '
      'ON UPDATE RESTRICT ON DELETE RESTRICT, '
      'employee_id TEXT NOT NULL REFERENCES employees (id) '
      'ON UPDATE RESTRICT ON DELETE RESTRICT, '
      'daily_rate INTEGER NOT NULL, effective_from TEXT NOT NULL, '
      'effective_to TEXT NULL, reason TEXT NULL, updated_at TEXT NULL, '
      'updated_by TEXT NULL REFERENCES user_profiles (id) '
      'ON UPDATE RESTRICT ON DELETE RESTRICT, '
      'voided_at TEXT NULL, '
      'voided_by TEXT NULL REFERENCES user_profiles (id) '
      'ON UPDATE RESTRICT ON DELETE RESTRICT, '
      'void_reason TEXT NULL, PRIMARY KEY (id), '
      'CHECK (daily_rate > 0), '
      'CHECK (effective_to IS NULL OR effective_to >= effective_from))',
  'CREATE INDEX idx_user_profiles_role_id ON user_profiles (role_id)',
  'CREATE INDEX idx_employees_position_id ON employees (position_id)',
  'CREATE INDEX idx_employees_employment_status '
      'ON employees (employment_status)',
  'CREATE INDEX idx_employee_pay_rates_employee_effective_from '
      'ON employee_pay_rates (employee_id, effective_from)',
  'CREATE UNIQUE INDEX uq_employees_user_profile_id '
      'ON employees (user_profile_id) WHERE user_profile_id IS NOT NULL',
  'CREATE UNIQUE INDEX uq_employee_pay_rates_open_ended '
      'ON employee_pay_rates (employee_id) '
      'WHERE effective_to IS NULL AND voided_at IS NULL',
];

const List<String> _v2Seed = [
  "INSERT INTO roles (id, created_at, updated_at, code, name, is_system) "
      "VALUES ('role-1', '2026-01-01T00:00:00.000Z', "
      "'2026-01-01T00:00:00.000Z', 'owner', 'Owner', 1)",
  "INSERT INTO user_profiles (id, created_at, updated_at, auth_user_id, "
      "role_id, display_name, is_active) VALUES ('prof-1', "
      "'2026-01-01T00:00:00.000Z', '2026-01-01T00:00:00.000Z', 'auth-1', "
      "'role-1', 'Owner User', 1)",
  "INSERT INTO employees (id, created_at, updated_at, employee_code, "
      "first_name, last_name, hire_date, employment_status) VALUES ('emp-1', "
      "'2026-01-01T00:00:00.000Z', '2026-01-01T00:00:00.000Z', 'E-001', "
      "'Juan', 'Dela Cruz', '2026-01-05', 'test_status')",
  "INSERT INTO employee_pay_rates (id, created_at, employee_id, daily_rate, "
      "effective_from) VALUES ('rate-1', '2026-01-01T00:00:00.000Z', 'emp-1', "
      "48000, '2026-01-05')",
];

void _createV2(dynamic raw) {
  for (final sql in _v2Ddl) {
    raw.execute(sql);
  }
  for (final sql in _v2Seed) {
    raw.execute(sql);
  }
  raw.execute('PRAGMA user_version = 2');
}

Matcher _failsWith(String message) => throwsA(
  predicate<Object>(
    (e) => e.toString().toLowerCase().contains(message),
    'throws an error containing "$message"',
  ),
);

Future<List<String>> _names(AppDatabase db, String type) async {
  final rows = await db
      .customSelect(
        "SELECT name FROM sqlite_master WHERE type = '$type' "
        "AND name NOT LIKE 'sqlite_%' ORDER BY name",
      )
      .get();
  return rows.map((r) => r.read<String>('name')).toList();
}

Future<int> _pragmaInt(AppDatabase db, String pragma) async {
  final row = await db.customSelect('PRAGMA $pragma').getSingle();
  return row.read<int>(pragma);
}

Future<Map<String, Map<String, String>>> _foreignKeys(
  AppDatabase db,
  String table,
) async {
  final rows = await db.customSelect('PRAGMA foreign_key_list($table)').get();
  return {
    for (final r in rows)
      r.read<String>('from'): {
        'table': r.read<String>('table'),
        'to': r.read<String>('to'),
        'on_delete': r.read<String>('on_delete'),
        'on_update': r.read<String>('on_update'),
      },
  };
}

Future<Map<String, Map<String, Object?>>> _columns(
  AppDatabase db,
  String table,
) async {
  final rows = await db.customSelect('PRAGMA table_info($table)').get();
  return {
    for (final r in rows)
      r.read<String>('name'): {
        'notnull': r.read<int>('notnull'),
        'type': r.read<String>('type'),
        'dflt_value': r.data['dflt_value'],
      },
  };
}

Future<String> _insertRole(AppDatabase db) async {
  final row = await db
      .into(db.roles)
      .insertReturning(
        RolesCompanion.insert(code: 'owner', name: 'Owner', isSystem: true),
      );
  return row.id;
}

Future<String> _insertProfile(AppDatabase db, String roleId) async {
  final row = await db
      .into(db.userProfiles)
      .insertReturning(
        UserProfilesCompanion.insert(
          authUserId: 'auth-1',
          roleId: roleId,
          displayName: 'Test User',
          isActive: true,
        ),
      );
  return row.id;
}

Future<String> _insertEmployee(AppDatabase db, {String code = 'E-001'}) async {
  final row = await db
      .into(db.employees)
      .insertReturning(
        EmployeesCompanion.insert(
          employeeCode: code,
          firstName: 'Juan',
          lastName: 'Dela Cruz',
          hireDate: '2026-01-05',
          employmentStatus: 'test_status',
        ),
      );
  return row.id;
}

// `test_status` is an arbitrary placeholder: schedule status values are
// undecided (OD-10).
Future<String> _insertSchedule(
  AppDatabase db, {
  String start = '2026-01-05',
  String end = '2026-01-18',
  String? publishedBy,
}) async {
  final row = await db
      .into(db.schedules)
      .insertReturning(
        SchedulesCompanion.insert(
          startDate: start,
          endDate: end,
          status: 'test_status',
          publishedBy: Value(publishedBy),
        ),
      );
  return row.id;
}

// Arbitrary fixture instants; no real shift start or length is implied.
final DateTime _fixtureStart = DateTime.utc(2026, 1, 5, 0, 0);
final DateTime _fixtureEnd = DateTime.utc(2026, 1, 5, 12, 0);

Future<String> _insertShift(
  AppDatabase db,
  String scheduleId,
  String employeeId, {
  DateTime? start,
  DateTime? end,
}) async {
  final row = await db
      .into(db.shiftAssignments)
      .insertReturning(
        ShiftAssignmentsCompanion.insert(
          scheduleId: scheduleId,
          employeeId: employeeId,
          shiftDate: '2026-01-05',
          scheduledStartAt: start ?? _fixtureStart,
          scheduledEndAt: end ?? _fixtureEnd,
          status: 'test_status',
        ),
      );
  return row.id;
}

/// True when the insert is accepted, false when only the CHECK rejects it.
Future<bool> _accepted(
  AppDatabase db,
  String scheduleId,
  String employeeId,
  DateTime start,
  DateTime end,
) async {
  try {
    await _insertShift(db, scheduleId, employeeId, start: start, end: end);
    return true;
  } catch (e) {
    if (e.toString().toLowerCase().contains('check constraint')) {
      return false;
    }
    rethrow;
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

  group('fresh v3 schema', () {
    test('opens at schema version 3 with foreign keys enabled', () async {
      expect(AppDatabase.currentSchemaVersion, 3);
      expect(await _pragmaInt(db, 'user_version'), 3);
      expect(await _pragmaInt(db, 'foreign_keys'), 1);
    });

    test('contains exactly the approved v3 tables', () async {
      expect(await _names(db, 'table'), unorderedEquals(_v3Tables));
    });

    test('creates the v2 and v3 indexes', () async {
      expect(
        await _names(db, 'index'),
        containsAll([..._v2Indexes, ..._v3Indexes]),
      );
    });

    test('schedules has exactly the documented columns', () async {
      final columns = await _columns(db, 'schedules');
      expect(
        columns.keys,
        unorderedEquals([
          'id',
          'created_at',
          'updated_at',
          'created_by',
          'updated_by',
          'name',
          'start_date',
          'end_date',
          'status',
          'published_at',
          'published_by',
        ]),
      );
      expect(columns['name']!['notnull'], 0);
      expect(columns['start_date']!['notnull'], 1);
      expect(columns['end_date']!['notnull'], 1);
      expect(columns['status']!['notnull'], 1);
      expect(columns['status']!['dflt_value'], isNull);
      expect(columns['published_at']!['notnull'], 0);
      expect(columns['published_by']!['notnull'], 0);
    });

    test('shift_assignments has exactly the documented columns', () async {
      final columns = await _columns(db, 'shift_assignments');
      expect(
        columns.keys,
        unorderedEquals([
          'id',
          'created_at',
          'updated_at',
          'created_by',
          'updated_by',
          'schedule_id',
          'employee_id',
          'shift_date',
          'scheduled_start_at',
          'scheduled_end_at',
          'status',
          'note',
        ]),
      );
      for (final required in [
        'schedule_id',
        'employee_id',
        'shift_date',
        'scheduled_start_at',
        'scheduled_end_at',
        'status',
      ]) {
        expect(columns[required]!['notnull'], 1, reason: required);
      }
      expect(columns['note']!['notnull'], 0);
      expect(columns['status']!['dflt_value'], isNull);
    });
  });

  group('conventions', () {
    test('ids are UUID v4; dates are text; instants are UTC text', () async {
      final scheduleId = await _insertSchedule(db);
      final employeeId = await _insertEmployee(db);
      final shiftId = await _insertShift(db, scheduleId, employeeId);

      expect(scheduleId, matches(_uuidV4));
      expect(shiftId, matches(_uuidV4));

      final schedule = await db
          .customSelect(
            'SELECT start_date, typeof(start_date) AS t, created_at '
            'FROM schedules',
          )
          .getSingle();
      expect(schedule.read<String>('start_date'), '2026-01-05');
      expect(schedule.read<String>('t'), 'text');
      expect(schedule.read<String>('created_at'), endsWith('Z'));

      final shift = await db
          .customSelect(
            'SELECT shift_date, scheduled_start_at, scheduled_end_at, '
            'typeof(scheduled_start_at) AS t FROM shift_assignments',
          )
          .getSingle();
      expect(shift.read<String>('shift_date'), '2026-01-05');
      expect(shift.read<String>('t'), 'text');
      expect(shift.read<String>('scheduled_start_at'), endsWith('Z'));
      expect(shift.read<String>('scheduled_end_at'), endsWith('Z'));
    });
  });

  group('schedules', () {
    test('insert and retrieve with optional columns left null', () async {
      await _insertSchedule(db);

      final row = (await db.select(db.schedules).get()).single;
      expect(row.startDate, '2026-01-05');
      expect(row.endDate, '2026-01-18');
      expect(row.status, 'test_status');
      expect(row.name, isNull);
      expect(row.publishedAt, isNull);
      expect(row.publishedBy, isNull);
    });

    test('published_by may reference a user profile', () async {
      final roleId = await _insertRole(db);
      final profileId = await _insertProfile(db, roleId);
      await _insertSchedule(db, publishedBy: profileId);

      final row = (await db.select(db.schedules).get()).single;
      expect(row.publishedBy, profileId);
    });

    test('end_date before start_date is rejected', () async {
      await expectLater(
        _insertSchedule(db, start: '2026-01-18', end: '2026-01-05'),
        _failsWith('check constraint'),
      );
    });

    test('end_date equal to start_date is accepted', () async {
      await _insertSchedule(db, start: '2026-01-05', end: '2026-01-05');
      expect(await db.select(db.schedules).get(), hasLength(1));
    });

    test('a required column cannot be left out', () async {
      await expectLater(
        db.customStatement(
          'INSERT INTO schedules (id, created_at, updated_at, start_date, '
          "end_date) VALUES ('s1', '2026-01-01T00:00:00.000Z', "
          "'2026-01-01T00:00:00.000Z', '2026-01-05', '2026-01-18')",
        ),
        _failsWith('not null constraint'),
      );
    });

    test('any status text is accepted (no CHECK, OD-10)', () async {
      for (final status in ['a', 'b', 'anything']) {
        await db
            .into(db.schedules)
            .insert(
              SchedulesCompanion.insert(
                startDate: '2026-01-05',
                endDate: '2026-01-18',
                status: status,
              ),
            );
      }
      expect(await db.select(db.schedules).get(), hasLength(3));
    });
  });

  group('shift_assignments', () {
    test('insert and retrieve with note left null', () async {
      final scheduleId = await _insertSchedule(db);
      final employeeId = await _insertEmployee(db);
      await _insertShift(db, scheduleId, employeeId);

      final row = (await db.select(db.shiftAssignments).get()).single;
      expect(row.scheduleId, scheduleId);
      expect(row.employeeId, employeeId);
      expect(row.shiftDate, '2026-01-05');
      expect(row.scheduledStartAt.toUtc(), _fixtureStart);
      expect(row.scheduledEndAt.toUtc(), _fixtureEnd);
      expect(row.status, 'test_status');
      expect(row.note, isNull);
    });

    test('a required column cannot be left out', () async {
      final scheduleId = await _insertSchedule(db);
      final employeeId = await _insertEmployee(db);

      await expectLater(
        db.customStatement(
          'INSERT INTO shift_assignments (id, created_at, updated_at, '
          'schedule_id, employee_id, shift_date, scheduled_start_at, '
          "scheduled_end_at) VALUES ('a1', '2026-01-01T00:00:00.000Z', "
          "'2026-01-01T00:00:00.000Z', '$scheduleId', '$employeeId', "
          "'2026-01-05', '2026-01-05T00:00:00.000Z', "
          "'2026-01-05T12:00:00.000Z')",
        ),
        _failsWith('not null constraint'),
      );
    });

    test(
      'end equal to or before start is rejected; after is accepted',
      () async {
        final scheduleId = await _insertSchedule(db);
        final employeeId = await _insertEmployee(db);

        await expectLater(
          _insertShift(db, scheduleId, employeeId, end: _fixtureStart),
          _failsWith('check constraint'),
        );
        await expectLater(
          _insertShift(
            db,
            scheduleId,
            employeeId,
            end: _fixtureStart.subtract(const Duration(hours: 1)),
          ),
          _failsWith('check constraint'),
        );
        await _insertShift(db, scheduleId, employeeId);
        expect(await db.select(db.shiftAssignments).get(), hasLength(1));
      },
    );

    test('instant CHECK is correct at whole-second and millisecond '
        'precision', () async {
      final scheduleId = await _insertSchedule(db);
      final employeeId = await _insertEmployee(db);
      final base = DateTime.utc(2026, 1, 5, 6, 0, 0);

      // Whole-second start, fractional end later: accepted.
      expect(
        await _accepted(
          db,
          scheduleId,
          employeeId,
          base,
          DateTime.utc(2026, 1, 5, 6, 0, 0, 500),
        ),
        isTrue,
      );
      // Fractional start, whole-second end earlier: rejected.
      expect(
        await _accepted(
          db,
          scheduleId,
          employeeId,
          DateTime.utc(2026, 1, 5, 6, 0, 0, 500),
          base,
        ),
        isFalse,
      );
      // One millisecond later: accepted. One millisecond earlier: rejected.
      expect(
        await _accepted(
          db,
          scheduleId,
          employeeId,
          base,
          DateTime.utc(2026, 1, 5, 6, 0, 0, 1),
        ),
        isTrue,
      );
      expect(
        await _accepted(
          db,
          scheduleId,
          employeeId,
          base,
          DateTime.utc(2026, 1, 5, 5, 59, 59, 999),
        ),
        isFalse,
      );
    });

    test('several assignments for one employee and date are not blocked '
        '(no uniqueness is defined; OD-10)', () async {
      final scheduleId = await _insertSchedule(db);
      final employeeId = await _insertEmployee(db);
      await _insertShift(db, scheduleId, employeeId);
      await _insertShift(db, scheduleId, employeeId);

      expect(await db.select(db.shiftAssignments).get(), hasLength(2));
    });
  });

  group('foreign keys', () {
    test('schedules foreign keys are RESTRICT to user_profiles', () async {
      final fks = await _foreignKeys(db, 'schedules');
      expect(
        fks.keys,
        unorderedEquals(['published_by', 'created_by', 'updated_by']),
      );
      for (final fk in fks.values) {
        expect(fk['table'], 'user_profiles');
        expect(fk['to'], 'id');
        expect(fk['on_delete'], 'RESTRICT');
        expect(fk['on_update'], 'RESTRICT');
      }
    });

    test('shift_assignments foreign keys are RESTRICT', () async {
      final fks = await _foreignKeys(db, 'shift_assignments');
      expect(
        fks.keys,
        unorderedEquals([
          'schedule_id',
          'employee_id',
          'created_by',
          'updated_by',
        ]),
      );
      expect(fks['schedule_id']!['table'], 'schedules');
      expect(fks['employee_id']!['table'], 'employees');
      expect(fks['created_by']!['table'], 'user_profiles');
      expect(fks['updated_by']!['table'], 'user_profiles');
      for (final fk in fks.values) {
        expect(fk['to'], 'id');
        expect(fk['on_delete'], 'RESTRICT');
        expect(fk['on_update'], 'RESTRICT');
      }
    });

    test('a schedule needs an existing published_by profile', () async {
      await expectLater(
        _insertSchedule(db, publishedBy: _missing),
        _failsWith('foreign key constraint'),
      );
    });

    test('a schedule created_by must reference an existing profile', () async {
      await expectLater(
        db
            .into(db.schedules)
            .insert(
              SchedulesCompanion.insert(
                startDate: '2026-01-05',
                endDate: '2026-01-18',
                status: 'test_status',
                createdBy: const Value(_missing),
              ),
            ),
        _failsWith('foreign key constraint'),
      );
    });

    test('a shift assignment needs an existing schedule', () async {
      final employeeId = await _insertEmployee(db);
      await expectLater(
        _insertShift(db, _missing, employeeId),
        _failsWith('foreign key constraint'),
      );
    });

    test('a shift assignment needs an existing employee', () async {
      final scheduleId = await _insertSchedule(db);
      await expectLater(
        _insertShift(db, scheduleId, _missing),
        _failsWith('foreign key constraint'),
      );
    });

    test('a shift assignment updated_by must reference an existing '
        'profile', () async {
      final scheduleId = await _insertSchedule(db);
      final employeeId = await _insertEmployee(db);
      await expectLater(
        db
            .into(db.shiftAssignments)
            .insert(
              ShiftAssignmentsCompanion.insert(
                scheduleId: scheduleId,
                employeeId: employeeId,
                shiftDate: '2026-01-05',
                scheduledStartAt: _fixtureStart,
                scheduledEndAt: _fixtureEnd,
                status: 'test_status',
                updatedBy: const Value(_missing),
              ),
            ),
        _failsWith('foreign key constraint'),
      );
    });

    test('a schedule with assignments cannot be deleted (RESTRICT)', () async {
      final scheduleId = await _insertSchedule(db);
      final employeeId = await _insertEmployee(db);
      await _insertShift(db, scheduleId, employeeId);

      await expectLater(
        db.delete(db.schedules).go(),
        _failsWith('foreign key constraint'),
      );
      expect(await db.select(db.schedules).get(), hasLength(1));
    });

    test('an employee with assignments cannot be deleted (RESTRICT)', () async {
      final scheduleId = await _insertSchedule(db);
      final employeeId = await _insertEmployee(db);
      await _insertShift(db, scheduleId, employeeId);

      await expectLater(
        db.delete(db.employees).go(),
        _failsWith('foreign key constraint'),
      );
    });

    test('a profile referenced by published_by cannot be deleted '
        '(RESTRICT)', () async {
      final roleId = await _insertRole(db);
      final profileId = await _insertProfile(db, roleId);
      await _insertSchedule(db, publishedBy: profileId);

      await expectLater(
        db.delete(db.userProfiles).go(),
        _failsWith('foreign key constraint'),
      );
    });
  });

  group('transaction rollback', () {
    test('a failed child insert rolls back the parent schedule', () async {
      final runner = DriftTransactionRunner(db);
      final employeeId = await _insertEmployee(db);

      await expectLater(
        runner.run<void>(() async {
          final scheduleId = await _insertSchedule(db);
          await _insertShift(db, scheduleId, employeeId);
          // Invalid employee violates the foreign key.
          await _insertShift(db, scheduleId, _missing);
        }),
        _failsWith('foreign key constraint'),
      );

      expect(await db.select(db.schedules).get(), isEmpty);
      expect(await db.select(db.shiftAssignments).get(), isEmpty);
    });

    test('a successful transaction persists its work', () async {
      final runner = DriftTransactionRunner(db);
      final employeeId = await _insertEmployee(db);

      await runner.run(() async {
        final scheduleId = await _insertSchedule(db);
        await _insertShift(db, scheduleId, employeeId);
      });

      expect(await db.select(db.schedules).get(), hasLength(1));
      expect(await db.select(db.shiftAssignments).get(), hasLength(1));
    });
  });

  group('migrations to schema version 3', () {
    test('v1 (empty) upgrades to v3 with all tables and indexes', () async {
      final migrated = AppDatabase(
        NativeDatabase.memory(
          setup: (raw) {
            raw.execute('PRAGMA user_version = 1');
          },
        ),
      );
      addTearDown(migrated.close);

      expect(await _names(migrated, 'table'), unorderedEquals(_v3Tables));
      expect(
        await _names(migrated, 'index'),
        containsAll([..._v2Indexes, ..._v3Indexes]),
      );
      expect(await _pragmaInt(migrated, 'user_version'), 3);
      expect(await _pragmaInt(migrated, 'foreign_keys'), 1);
    });

    test('v2 with data upgrades to v3 and keeps its data', () async {
      final migrated = AppDatabase(NativeDatabase.memory(setup: _createV2));
      addTearDown(migrated.close);

      expect(await _names(migrated, 'table'), unorderedEquals(_v3Tables));
      expect(
        await _names(migrated, 'index'),
        containsAll([..._v2Indexes, ..._v3Indexes]),
      );
      expect(await _pragmaInt(migrated, 'user_version'), 3);
      expect(await _pragmaInt(migrated, 'foreign_keys'), 1);

      final roles = await migrated.select(migrated.roles).get();
      expect(roles.single.id, 'role-1');
      // Existing rows are read-compatible and are never rewritten.
      final storedCreatedAt = await migrated
          .customSelect("SELECT created_at FROM roles WHERE id = 'role-1'")
          .getSingle();
      expect(
        storedCreatedAt.read<String>('created_at'),
        '2026-01-01T00:00:00.000Z',
      );
      final profiles = await migrated.select(migrated.userProfiles).get();
      expect(profiles.single.id, 'prof-1');
      final employees = await migrated.select(migrated.employees).get();
      expect(employees.single.id, 'emp-1');
      final rates = await migrated.select(migrated.employeePayRates).get();
      expect(rates.single.dailyRate, 48000);
    });

    test('a migrated v2 database accepts schedules and shifts for existing '
        'rows', () async {
      final migrated = AppDatabase(NativeDatabase.memory(setup: _createV2));
      addTearDown(migrated.close);

      final scheduleId = await _insertSchedule(migrated, publishedBy: 'prof-1');
      await _insertShift(migrated, scheduleId, 'emp-1');

      expect(await migrated.select(migrated.schedules).get(), hasLength(1));
      expect(
        await migrated.select(migrated.shiftAssignments).get(),
        hasLength(1),
      );
    });

    test('a migrated database enforces the new constraints', () async {
      final migrated = AppDatabase(NativeDatabase.memory(setup: _createV2));
      addTearDown(migrated.close);

      await expectLater(
        _insertSchedule(migrated, start: '2026-01-18', end: '2026-01-05'),
        _failsWith('check constraint'),
      );
      await expectLater(
        _insertShift(migrated, _missing, 'emp-1'),
        _failsWith('foreign key constraint'),
      );
    });
  });
}
