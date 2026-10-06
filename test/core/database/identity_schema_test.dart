import 'dart:io';

import 'package:drift/drift.dart' show OrderingTerm, Value, innerJoin;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:goil_payroll_attendance/core/database/app_database.dart';
import 'package:goil_payroll_attendance/core/database/drift_transaction_runner.dart';

final RegExp _uuidV4 = RegExp(
  r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
);

const List<String> _expectedTables = [
  'employee_pay_rates',
  'employees',
  'positions',
  'roles',
  'user_profiles',
];

/// Matches an error whose text contains [message] (case-insensitive).
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

Future<String> _insertRole(
  AppDatabase db, {
  String code = 'owner',
  String name = 'Owner',
  String? createdBy,
  String? updatedBy,
}) async {
  final row = await db
      .into(db.roles)
      .insertReturning(
        RolesCompanion.insert(
          code: code,
          name: name,
          isSystem: true,
          createdBy: Value(createdBy),
          updatedBy: Value(updatedBy),
        ),
      );
  return row.id;
}

Future<String> _insertPosition(
  AppDatabase db, {
  String code = 'cashier',
}) async {
  final row = await db
      .into(db.positions)
      .insertReturning(
        PositionsCompanion.insert(code: code, name: 'Cashier', isActive: true),
      );
  return row.id;
}

Future<String> _insertProfile(
  AppDatabase db,
  String roleId, {
  String authUserId = 'auth-1',
}) async {
  final row = await db
      .into(db.userProfiles)
      .insertReturning(
        UserProfilesCompanion.insert(
          authUserId: authUserId,
          roleId: roleId,
          displayName: 'Test User',
          isActive: true,
        ),
      );
  return row.id;
}

// `test_status` is an arbitrary placeholder: the allowed employment status
// values are undecided (OD-07).
Future<String> _insertEmployee(
  AppDatabase db, {
  String code = 'E-001',
  String? positionId,
  String? userProfileId,
}) async {
  final row = await db
      .into(db.employees)
      .insertReturning(
        EmployeesCompanion.insert(
          employeeCode: code,
          firstName: 'Juan',
          lastName: 'Dela Cruz',
          hireDate: '2026-01-05',
          employmentStatus: 'test_status',
          positionId: Value(positionId),
          userProfileId: Value(userProfileId),
        ),
      );
  return row.id;
}

Future<String> _insertPayRate(
  AppDatabase db,
  String employeeId, {
  int dailyRate = 48000,
  String from = '2026-01-01',
  String? to,
  DateTime? voidedAt,
}) async {
  final row = await db
      .into(db.employeePayRates)
      .insertReturning(
        EmployeePayRatesCompanion.insert(
          employeeId: employeeId,
          dailyRate: dailyRate,
          effectiveFrom: from,
          effectiveTo: Value(to),
          voidedAt: Value(voidedAt),
        ),
      );
  return row.id;
}

void main() {
  late AppDatabase db;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
  });

  tearDown(() async {
    await db.close();
  });

  group('schema', () {
    test('opens at schema version 2 with foreign keys enabled', () async {
      expect(AppDatabase.currentSchemaVersion, 2);
      expect(await _pragmaInt(db, 'user_version'), 2);
      expect(await _pragmaInt(db, 'foreign_keys'), 1);
    });

    test('contains exactly the five approved tables', () async {
      expect(await _names(db, 'table'), unorderedEquals(_expectedTables));
    });

    test('creates the approved indexes', () async {
      expect(
        await _names(db, 'index'),
        containsAll([
          'idx_user_profiles_role_id',
          'idx_employees_position_id',
          'idx_employees_employment_status',
          'idx_employee_pay_rates_employee_effective_from',
          'uq_employees_user_profile_id',
          'uq_employee_pay_rates_open_ended',
        ]),
      );
    });
  });

  group('conventions', () {
    test('primary keys are UUID v4 and unique per row', () async {
      final a = await _insertRole(db, code: 'owner');
      final b = await _insertRole(db, code: 'manager', name: 'Manager');

      expect(a, matches(_uuidV4));
      expect(b, matches(_uuidV4));
      expect(a, isNot(b));
    });

    test('instants are stored as UTC ISO 8601 text ending in Z', () async {
      await _insertRole(db);
      final row = await db
          .customSelect('SELECT created_at, updated_at FROM roles')
          .getSingle();

      for (final column in ['created_at', 'updated_at']) {
        final stored = row.read<String>(column);
        expect(stored, endsWith('Z'));
        expect(DateTime.parse(stored).isUtc, isTrue);
      }
    });

    test('booleans, dates and money use the approved storage types', () async {
      await _insertRole(db);
      final employeeId = await _insertEmployee(db);
      await _insertPayRate(db, employeeId, dailyRate: 48000);

      final role = await db
          .customSelect('SELECT is_system, typeof(is_system) AS t FROM roles')
          .getSingle();
      expect(role.read<int>('is_system'), 1);
      expect(role.read<String>('t'), 'integer');

      final employee = await db
          .customSelect(
            'SELECT hire_date, typeof(hire_date) AS t FROM employees',
          )
          .getSingle();
      expect(employee.read<String>('hire_date'), '2026-01-05');
      expect(employee.read<String>('t'), 'text');

      final rate = await db
          .customSelect(
            'SELECT daily_rate, typeof(daily_rate) AS t '
            'FROM employee_pay_rates',
          )
          .getSingle();
      expect(rate.read<int>('daily_rate'), 48000);
      expect(rate.read<String>('t'), 'integer');
    });
  });

  group('relationships', () {
    test('roles can be inserted and retrieved', () async {
      await _insertRole(db);

      final rows = await db.select(db.roles).get();
      expect(rows, hasLength(1));
      expect(rows.single.code, 'owner');
      expect(rows.single.isSystem, isTrue);
    });

    test('positions can be inserted and retrieved', () async {
      await _insertPosition(db);

      final rows = await db.select(db.positions).get();
      expect(rows, hasLength(1));
      expect(rows.single.code, 'cashier');
      expect(rows.single.isActive, isTrue);
    });

    test('a user profile belongs to a role', () async {
      final roleId = await _insertRole(db);
      await _insertProfile(db, roleId);

      final rows = await db.select(db.userProfiles).join([
        innerJoin(db.roles, db.roles.id.equalsExp(db.userProfiles.roleId)),
      ]).get();

      expect(rows, hasLength(1));
      expect(rows.single.readTable(db.roles).code, 'owner');
    });

    test('an employee belongs to a position', () async {
      final positionId = await _insertPosition(db);
      await _insertEmployee(db, positionId: positionId);

      final rows = await db.select(db.employees).join([
        innerJoin(
          db.positions,
          db.positions.id.equalsExp(db.employees.positionId),
        ),
      ]).get();

      expect(rows, hasLength(1));
      expect(rows.single.readTable(db.positions).code, 'cashier');
    });

    test('an employee may have no position and no login', () async {
      await _insertEmployee(db);

      final employee = (await db.select(db.employees).get()).single;
      expect(employee.positionId, isNull);
      expect(employee.userProfileId, isNull);
    });

    test('an employee can be linked to a user profile', () async {
      final roleId = await _insertRole(db);
      final profileId = await _insertProfile(db, roleId);
      await _insertEmployee(db, userProfileId: profileId);

      final employee = (await db.select(db.employees).get()).single;
      expect(employee.userProfileId, profileId);
    });

    test('a pay rate belongs to an employee', () async {
      final employeeId = await _insertEmployee(db);
      await _insertPayRate(db, employeeId);

      final rows = await db.select(db.employeePayRates).join([
        innerJoin(
          db.employees,
          db.employees.id.equalsExp(db.employeePayRates.employeeId),
        ),
      ]).get();

      expect(rows, hasLength(1));
      expect(rows.single.readTable(db.employees).employeeCode, 'E-001');
    });

    test('created_by is nullable and may reference a user profile', () async {
      final roleId = await _insertRole(db);
      final profileId = await _insertProfile(db, roleId);

      final managerRole = await _insertRole(
        db,
        code: 'manager',
        name: 'Manager',
        createdBy: profileId,
        updatedBy: profileId,
      );

      final row = await (db.select(
        db.roles,
      )..where((t) => t.id.equals(managerRole))).getSingle();
      expect(row.createdBy, profileId);
      expect(row.updatedBy, profileId);
    });
  });

  group('required fields and uniqueness', () {
    test('a required column cannot be left out', () async {
      await expectLater(
        db.customStatement(
          'INSERT INTO employees (id, created_at, updated_at, employee_code, '
          "first_name, last_name, hire_date) VALUES ('e1', "
          "'2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z', 'E1', 'A', 'B', "
          "'2026-01-01')",
        ),
        _failsWith('not null constraint'),
      );
    });

    test('role code is unique', () async {
      await _insertRole(db, code: 'owner');
      await expectLater(
        _insertRole(db, code: 'owner', name: 'Another'),
        _failsWith('unique constraint'),
      );
    });

    test('position code is unique', () async {
      await _insertPosition(db, code: 'cashier');
      await expectLater(
        _insertPosition(db, code: 'cashier'),
        _failsWith('unique constraint'),
      );
    });

    test('user profile auth_user_id is unique', () async {
      final roleId = await _insertRole(db);
      await _insertProfile(db, roleId, authUserId: 'auth-1');
      await expectLater(
        _insertProfile(db, roleId, authUserId: 'auth-1'),
        _failsWith('unique constraint'),
      );
    });

    test('employee code is unique', () async {
      await _insertEmployee(db, code: 'E-001');
      await expectLater(
        _insertEmployee(db, code: 'E-001'),
        _failsWith('unique constraint'),
      );
    });

    test('a user profile can belong to at most one employee', () async {
      final roleId = await _insertRole(db);
      final profileId = await _insertProfile(db, roleId);
      await _insertEmployee(db, code: 'E-001', userProfileId: profileId);

      await expectLater(
        _insertEmployee(db, code: 'E-002', userProfileId: profileId),
        _failsWith('unique constraint'),
      );
    });

    test('several employees may have no user profile', () async {
      await _insertEmployee(db, code: 'E-001');
      await _insertEmployee(db, code: 'E-002');

      expect(await db.select(db.employees).get(), hasLength(2));
    });
  });

  group('foreign keys', () {
    const missing = '00000000-0000-4000-8000-000000000000';

    test('a user profile needs an existing role', () async {
      await expectLater(
        _insertProfile(db, missing),
        _failsWith('foreign key constraint'),
      );
    });

    test('an employee needs an existing position when one is given', () async {
      await expectLater(
        _insertEmployee(db, positionId: missing),
        _failsWith('foreign key constraint'),
      );
    });

    test(
      'an employee needs an existing user profile when one is given',
      () async {
        await expectLater(
          _insertEmployee(db, userProfileId: missing),
          _failsWith('foreign key constraint'),
        );
      },
    );

    test('a pay rate needs an existing employee', () async {
      await expectLater(
        _insertPayRate(db, missing),
        _failsWith('foreign key constraint'),
      );
    });

    test('created_by must reference an existing user profile', () async {
      await expectLater(
        _insertRole(db, createdBy: missing),
        _failsWith('foreign key constraint'),
      );
    });

    test('a pay rate voided_by must reference an existing profile', () async {
      final employeeId = await _insertEmployee(db);

      await expectLater(
        db
            .into(db.employeePayRates)
            .insert(
              EmployeePayRatesCompanion.insert(
                employeeId: employeeId,
                dailyRate: 48000,
                effectiveFrom: '2026-01-01',
                voidedBy: const Value(missing),
              ),
            ),
        _failsWith('foreign key constraint'),
      );
    });

    test(
      'positions created_by must reference an existing user profile',
      () async {
        await expectLater(
          db
              .into(db.positions)
              .insert(
                PositionsCompanion.insert(
                  code: 'cashier',
                  name: 'Cashier',
                  isActive: true,
                  createdBy: const Value(missing),
                ),
              ),
          _failsWith('foreign key constraint'),
        );
      },
    );

    test('roles updated_by must reference an existing user profile', () async {
      await expectLater(
        _insertRole(db, updatedBy: missing),
        _failsWith('foreign key constraint'),
      );
    });

    test('a referenced role cannot be deleted (RESTRICT)', () async {
      final roleId = await _insertRole(db);
      await _insertProfile(db, roleId);

      await expectLater(
        db.delete(db.roles).go(),
        _failsWith('foreign key constraint'),
      );
      expect(await db.select(db.roles).get(), hasLength(1));
    });

    test('a referenced position cannot be deleted (RESTRICT)', () async {
      final positionId = await _insertPosition(db);
      await _insertEmployee(db, positionId: positionId);

      await expectLater(
        db.delete(db.positions).go(),
        _failsWith('foreign key constraint'),
      );
    });

    test('an employee with pay rates cannot be deleted (RESTRICT)', () async {
      final employeeId = await _insertEmployee(db);
      await _insertPayRate(db, employeeId);

      await expectLater(
        db.delete(db.employees).go(),
        _failsWith('foreign key constraint'),
      );
    });
  });

  group('pay rate history', () {
    test('the daily rate must be greater than zero', () async {
      final employeeId = await _insertEmployee(db);

      await expectLater(
        _insertPayRate(db, employeeId, dailyRate: 0),
        _failsWith('check constraint'),
      );
      await expectLater(
        _insertPayRate(db, employeeId, dailyRate: -100),
        _failsWith('check constraint'),
      );
    });

    test('effective_to cannot be before effective_from', () async {
      final employeeId = await _insertEmployee(db);

      await expectLater(
        _insertPayRate(db, employeeId, from: '2026-02-01', to: '2026-01-31'),
        _failsWith('check constraint'),
      );
    });

    test('effective_to may equal effective_from or be open-ended', () async {
      final employeeId = await _insertEmployee(db);

      await _insertPayRate(
        db,
        employeeId,
        from: '2026-01-01',
        to: '2026-01-01',
      );
      await _insertPayRate(db, employeeId, from: '2026-03-01');

      expect(await db.select(db.employeePayRates).get(), hasLength(2));
    });

    test('only one open-ended non-voided rate per employee', () async {
      final employeeId = await _insertEmployee(db);
      await _insertPayRate(db, employeeId, from: '2026-01-01');

      await expectLater(
        _insertPayRate(db, employeeId, from: '2026-06-01'),
        _failsWith('unique constraint'),
      );
    });

    test('different employees may each have an open-ended rate', () async {
      final first = await _insertEmployee(db, code: 'E-001');
      final second = await _insertEmployee(db, code: 'E-002');

      await _insertPayRate(db, first);
      await _insertPayRate(db, second);

      expect(await db.select(db.employeePayRates).get(), hasLength(2));
    });

    test('a voided open-ended rate does not block a new one', () async {
      final employeeId = await _insertEmployee(db);
      await _insertPayRate(
        db,
        employeeId,
        from: '2026-01-01',
        voidedAt: DateTime.utc(2026, 2, 1),
      );

      await _insertPayRate(db, employeeId, from: '2026-02-01');

      expect(await db.select(db.employeePayRates).get(), hasLength(2));
    });

    test('closing the current rate then adding a later one works', () async {
      final employeeId = await _insertEmployee(db);
      final firstId = await _insertPayRate(db, employeeId, from: '2026-01-01');

      await (db.update(
        db.employeePayRates,
      )..where((t) => t.id.equals(firstId))).write(
        const EmployeePayRatesCompanion(effectiveTo: Value('2026-06-30')),
      );
      await _insertPayRate(
        db,
        employeeId,
        dailyRate: 52000,
        from: '2026-07-01',
      );

      final rows = await (db.select(
        db.employeePayRates,
      )..orderBy([(t) => OrderingTerm.asc(t.effectiveFrom)])).get();
      expect(rows.map((r) => r.dailyRate), [48000, 52000]);
    });

    // Documents the limitation approved by the Project Manager for 4.6.4.
    // Replace this test when the repository enforces non-overlap (design 5.5)
    // and OD-09 is decided.
    test('KNOWN LIMITATION: overlapping closed ranges are not rejected by '
        'the database', () async {
      final employeeId = await _insertEmployee(db);

      await _insertPayRate(
        db,
        employeeId,
        from: '2026-01-01',
        to: '2026-03-31',
      );
      await _insertPayRate(
        db,
        employeeId,
        from: '2026-02-01',
        to: '2026-04-30',
      );

      expect(await db.select(db.employeePayRates).get(), hasLength(2));
    });
  });

  group('pay rate audit columns (design 5.5)', () {
    const missing = '00000000-0000-4000-8000-000000000000';

    test('updated_at and updated_by are nullable and null on insert', () async {
      final employeeId = await _insertEmployee(db);
      await _insertPayRate(db, employeeId);

      final row = (await db.select(db.employeePayRates).get()).single;
      expect(row.updatedAt, isNull);
      expect(row.updatedBy, isNull);
    });

    test(
      'the table has the audit columns and no closed_at/closed_by',
      () async {
        final info = await db
            .customSelect('PRAGMA table_info(employee_pay_rates)')
            .get();
        final notNull = {
          for (final r in info) r.read<String>('name'): r.read<int>('notnull'),
        };

        expect(notNull['updated_at'], 0);
        expect(notNull['updated_by'], 0);
        expect(notNull.containsKey('closed_at'), isFalse);
        expect(notNull.containsKey('closed_by'), isFalse);
      },
    );

    test('updated_by has a RESTRICT foreign key to user_profiles', () async {
      final fks = await db
          .customSelect('PRAGMA foreign_key_list(employee_pay_rates)')
          .get();
      final updatedBy = fks.where(
        (r) => r.read<String>('from') == 'updated_by',
      );

      expect(updatedBy, hasLength(1));
      expect(updatedBy.single.read<String>('table'), 'user_profiles');
      expect(updatedBy.single.read<String>('to'), 'id');
      expect(updatedBy.single.read<String>('on_delete'), 'RESTRICT');
      expect(updatedBy.single.read<String>('on_update'), 'RESTRICT');
    });

    test('closing records effective_to, updated_at and updated_by', () async {
      final roleId = await _insertRole(db);
      final profileId = await _insertProfile(db, roleId);
      final employeeId = await _insertEmployee(db);
      final rateId = await _insertPayRate(db, employeeId, from: '2026-01-01');

      await (db.update(
        db.employeePayRates,
      )..where((t) => t.id.equals(rateId))).write(
        EmployeePayRatesCompanion(
          effectiveTo: const Value('2026-06-30'),
          updatedAt: Value(DateTime.utc(2026, 7, 1)),
          updatedBy: Value(profileId),
        ),
      );

      final row = await (db.select(
        db.employeePayRates,
      )..where((t) => t.id.equals(rateId))).getSingle();
      expect(row.effectiveTo, '2026-06-30');
      expect(row.updatedAt, isNotNull);
      expect(row.updatedBy, profileId);

      final stored = await db
          .customSelect('SELECT updated_at FROM employee_pay_rates')
          .getSingle();
      expect(stored.read<String>('updated_at'), endsWith('Z'));
    });

    test('updated_by accepts a valid user profile on insert', () async {
      final roleId = await _insertRole(db);
      final profileId = await _insertProfile(db, roleId);
      final employeeId = await _insertEmployee(db);

      await db
          .into(db.employeePayRates)
          .insert(
            EmployeePayRatesCompanion.insert(
              employeeId: employeeId,
              dailyRate: 48000,
              effectiveFrom: '2026-01-01',
              updatedBy: Value(profileId),
            ),
          );

      final row = (await db.select(db.employeePayRates).get()).single;
      expect(row.updatedBy, profileId);
    });

    test('an invalid updated_by is rejected on insert', () async {
      final employeeId = await _insertEmployee(db);

      await expectLater(
        db
            .into(db.employeePayRates)
            .insert(
              EmployeePayRatesCompanion.insert(
                employeeId: employeeId,
                dailyRate: 48000,
                effectiveFrom: '2026-01-01',
                updatedBy: const Value(missing),
              ),
            ),
        _failsWith('foreign key constraint'),
      );
    });

    test('an invalid updated_by is rejected on update', () async {
      final employeeId = await _insertEmployee(db);
      final rateId = await _insertPayRate(db, employeeId);

      await expectLater(
        (db.update(db.employeePayRates)..where((t) => t.id.equals(rateId)))
            .write(const EmployeePayRatesCompanion(updatedBy: Value(missing))),
        _failsWith('foreign key constraint'),
      );
    });

    test('a referenced profile cannot be deleted while updated_by uses it '
        '(RESTRICT)', () async {
      final roleId = await _insertRole(db);
      final profileId = await _insertProfile(db, roleId);
      final employeeId = await _insertEmployee(db);
      await db
          .into(db.employeePayRates)
          .insert(
            EmployeePayRatesCompanion.insert(
              employeeId: employeeId,
              dailyRate: 48000,
              effectiveFrom: '2026-01-01',
              updatedBy: Value(profileId),
            ),
          );

      await expectLater(
        db.delete(db.userProfiles).go(),
        _failsWith('foreign key constraint'),
      );
    });
  });

  group('transaction rollback', () {
    test('a failure after a valid insert rolls the insert back', () async {
      final runner = DriftTransactionRunner(db);

      await expectLater(
        runner.run<void>(() async {
          await _insertRole(db, code: 'owner');
          expect(await db.select(db.roles).get(), hasLength(1));

          throw StateError('forced failure');
        }),
        throwsStateError,
      );

      expect(await db.select(db.roles).get(), isEmpty);
    });

    test('a constraint failure rolls back earlier valid work', () async {
      final runner = DriftTransactionRunner(db);

      await expectLater(
        runner.run<void>(() async {
          final positionId = await _insertPosition(db);
          await _insertEmployee(db, code: 'E-001', positionId: positionId);
          // Duplicate employee code violates the unique constraint.
          await _insertEmployee(db, code: 'E-001');
        }),
        _failsWith('unique constraint'),
      );

      expect(await db.select(db.positions).get(), isEmpty);
      expect(await db.select(db.employees).get(), isEmpty);
    });

    test('a successful transaction persists its work', () async {
      final runner = DriftTransactionRunner(db);

      await runner.run(() async {
        await _insertRole(db);
      });

      expect(await db.select(db.roles).get(), hasLength(1));
    });
  });

  group('migration from schema version 1', () {
    test('an empty version 1 database is upgraded to version 2', () async {
      final migrated = AppDatabase(
        NativeDatabase.memory(
          setup: (raw) {
            raw.execute('PRAGMA user_version = 1');
          },
        ),
      );
      addTearDown(migrated.close);

      expect(await _names(migrated, 'table'), unorderedEquals(_expectedTables));
      expect(
        await _names(migrated, 'index'),
        containsAll([
          'uq_employees_user_profile_id',
          'uq_employee_pay_rates_open_ended',
        ]),
      );
      expect(await _pragmaInt(migrated, 'user_version'), 2);
      expect(await _pragmaInt(migrated, 'foreign_keys'), 1);
    });

    test('a migrated database enforces the same constraints', () async {
      final migrated = AppDatabase(
        NativeDatabase.memory(
          setup: (raw) {
            raw.execute('PRAGMA user_version = 1');
          },
        ),
      );
      addTearDown(migrated.close);

      await expectLater(
        _insertProfile(migrated, '00000000-0000-4000-8000-000000000000'),
        _failsWith('foreign key constraint'),
      );
    });

    test('a migrated file keeps its data when reopened', () async {
      final dir = Directory.systemTemp.createTempSync('goil_migration_test_');
      addTearDown(() {
        try {
          dir.deleteSync(recursive: true);
        } on FileSystemException {
          // Best effort: the OS temp folder is cleaned up eventually.
        }
      });
      final file = File('${dir.path}${Platform.pathSeparator}goil.sqlite');

      final first = AppDatabase(
        NativeDatabase(
          file,
          setup: (raw) {
            raw.execute('PRAGMA user_version = 1');
          },
        ),
      );
      final roleId = await _insertRole(first);
      await first.close();

      final second = AppDatabase(NativeDatabase(file));
      addTearDown(second.close);

      final roles = await second.select(second.roles).get();
      expect(roles.single.id, roleId);
      expect(await _pragmaInt(second, 'user_version'), 2);
      expect(await _names(second, 'table'), unorderedEquals(_expectedTables));
    });
  });
}
