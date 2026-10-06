import 'package:drift/drift.dart' show Value, Variable;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:goil_payroll_attendance/core/database/app_database.dart';
import 'package:goil_payroll_attendance/core/database/instant_converter.dart';

final RegExp _canonical = RegExp(
  r'^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{6}Z$',
);

// (year, month, day, hour, minute, second, millisecond, microsecond)
final DateTime _t0 = DateTime.utc(2026, 10, 6, 10);
final DateTime _plus1us = DateTime.utc(2026, 10, 6, 10, 0, 0, 0, 1);

Matcher _failsWith(String message) => throwsA(
  predicate<Object>(
    (e) => e.toString().toLowerCase().contains(message),
    'throws an error containing "$message"',
  ),
);

Future<String> _insertEmployee(AppDatabase db) async {
  final row = await db
      .into(db.employees)
      .insertReturning(
        EmployeesCompanion.insert(
          employeeCode: 'E-001',
          firstName: 'Juan',
          lastName: 'Dela Cruz',
          hireDate: '2026-01-05',
          employmentStatus: 'test_status',
        ),
      );
  return row.id;
}

Future<String> _insertSchedule(AppDatabase db, {DateTime? publishedAt}) async {
  final row = await db
      .into(db.schedules)
      .insertReturning(
        SchedulesCompanion.insert(
          startDate: '2026-10-05',
          endDate: '2026-10-18',
          status: 'test_status',
          publishedAt: Value(publishedAt),
        ),
      );
  return row.id;
}

Future<String> _insertShift(
  AppDatabase db,
  String scheduleId,
  String employeeId,
  DateTime start,
  DateTime end,
) async {
  final row = await db
      .into(db.shiftAssignments)
      .insertReturning(
        ShiftAssignmentsCompanion.insert(
          scheduleId: scheduleId,
          employeeId: employeeId,
          shiftDate: '2026-10-06',
          scheduledStartAt: start,
          scheduledEndAt: end,
          status: 'test_status',
        ),
      );
  return row.id;
}

/// True when accepted; false when only the CHECK rejects it.
Future<bool> _accepted(
  AppDatabase db,
  String scheduleId,
  String employeeId,
  DateTime start,
  DateTime end,
) async {
  try {
    await _insertShift(db, scheduleId, employeeId, start, end);
    return true;
  } catch (e) {
    if (e.toString().toLowerCase().contains('check constraint')) {
      return false;
    }
    rethrow;
  }
}

void main() {
  group('CanonicalInstantConverter', () {
    const converter = CanonicalInstantConverter();

    test('writes exactly six fractional digits and a Z suffix', () {
      expect(
        converter.toSql(DateTime.utc(2026, 10, 6, 10)),
        '2026-10-06T10:00:00.000000Z',
      );
      expect(
        converter.toSql(DateTime.utc(2026, 10, 6, 10, 0, 0, 1)),
        '2026-10-06T10:00:00.001000Z',
      );
      expect(
        converter.toSql(DateTime.utc(2026, 10, 6, 10, 0, 0, 123)),
        '2026-10-06T10:00:00.123000Z',
      );
      expect(
        converter.toSql(DateTime.utc(2026, 10, 6, 10, 0, 0, 123, 456)),
        '2026-10-06T10:00:00.123456Z',
      );
      expect(converter.toSql(_plus1us), '2026-10-06T10:00:00.000001Z');
    });

    test('converts any zone to UTC before writing', () {
      final parsed = converter.fromSql('2026-10-06T18:00:00.000+08:00');
      expect(parsed.isUtc, isTrue);
      expect(converter.toSql(parsed), '2026-10-06T10:00:00.000000Z');
    });

    test('reads older valid ISO-8601 forms', () {
      expect(converter.fromSql('2026-10-06T10:00:00Z'), _t0);
      expect(
        converter.fromSql('2026-10-06T10:00:00.123Z'),
        DateTime.utc(2026, 10, 6, 10, 0, 0, 123),
      );
      expect(
        converter.fromSql('2026-10-06T10:00:00.123456Z'),
        DateTime.utc(2026, 10, 6, 10, 0, 0, 123, 456),
      );
      expect(converter.fromSql('2026-10-06T10:00:00Z').isUtc, isTrue);
    });

    test('text order equals chronological order', () {
      final instants = [
        DateTime.utc(2026, 10, 6, 10, 0, 0, 123, 456),
        _t0,
        _plus1us,
        DateTime.utc(2026, 10, 6, 10, 0, 0, 1),
        DateTime.utc(2026, 10, 6, 10, 0, 0, 0, 999),
        DateTime.utc(2026, 10, 6, 10, 0, 1),
        DateTime.utc(2026, 10, 6, 9, 59, 59, 999, 999),
        DateTime.utc(2026, 10, 6, 10, 0, 0, 123),
      ];
      final byText = [...instants]
        ..sort((a, b) => converter.toSql(a).compareTo(converter.toSql(b)));
      final byTime = [...instants]..sort((a, b) => a.compareTo(b));
      expect(byText, byTime);
    });
  });

  group('stored instants and the shift CHECK', () {
    late AppDatabase db;
    late String scheduleId;
    late String employeeId;

    setUp(() async {
      db = AppDatabase(NativeDatabase.memory());
      scheduleId = await _insertSchedule(db);
      employeeId = await _insertEmployee(db);
    });

    tearDown(() async {
      await db.close();
    });

    test('A: equal instants are rejected', () async {
      expect(await _accepted(db, scheduleId, employeeId, _t0, _t0), isFalse);
    });

    test('B: end 1 microsecond earlier is rejected', () async {
      expect(
        await _accepted(db, scheduleId, employeeId, _plus1us, _t0),
        isFalse,
      );
    });

    test('C: end 1 microsecond later is accepted', () async {
      expect(
        await _accepted(db, scheduleId, employeeId, _t0, _plus1us),
        isTrue,
      );
    });

    test('D: millisecond ordering is correct', () async {
      final ms1 = DateTime.utc(2026, 10, 6, 10, 0, 0, 1);
      final ms123 = DateTime.utc(2026, 10, 6, 10, 0, 0, 123);
      final ms122 = DateTime.utc(2026, 10, 6, 10, 0, 0, 122);
      final us999 = DateTime.utc(2026, 10, 6, 10, 0, 0, 0, 999);

      expect(await _accepted(db, scheduleId, employeeId, _t0, ms1), isTrue);
      expect(await _accepted(db, scheduleId, employeeId, ms1, _t0), isFalse);
      expect(await _accepted(db, scheduleId, employeeId, ms122, ms123), isTrue);
      expect(
        await _accepted(db, scheduleId, employeeId, ms123, ms122),
        isFalse,
      );
      // 999 microseconds is earlier than 1 millisecond.
      expect(await _accepted(db, scheduleId, employeeId, us999, ms1), isTrue);
      expect(await _accepted(db, scheduleId, employeeId, ms1, us999), isFalse);
    });

    test('E: whole-second ordering is correct', () async {
      final later = DateTime.utc(2026, 10, 6, 10, 0, 1);
      final earlier = DateTime.utc(2026, 10, 6, 9, 59, 59);

      expect(await _accepted(db, scheduleId, employeeId, _t0, later), isTrue);
      expect(
        await _accepted(db, scheduleId, employeeId, _t0, earlier),
        isFalse,
      );
      expect(await _accepted(db, scheduleId, employeeId, later, _t0), isFalse);
    });

    test('F: new values are stored in the canonical six-digit form', () async {
      final examples = <DateTime, String>{
        DateTime.utc(2026, 10, 6, 10): '2026-10-06T10:00:00.000000Z',
        DateTime.utc(2026, 10, 6, 10, 0, 0, 1): '2026-10-06T10:00:00.001000Z',
        DateTime.utc(2026, 10, 6, 10, 0, 0, 123): '2026-10-06T10:00:00.123000Z',
        DateTime.utc(2026, 10, 6, 10, 0, 0, 123, 456):
            '2026-10-06T10:00:00.123456Z',
      };

      for (final entry in examples.entries) {
        final id = await _insertShift(
          db,
          scheduleId,
          employeeId,
          entry.key,
          entry.key.add(const Duration(hours: 1)),
        );
        final row = await db
            .customSelect(
              'SELECT scheduled_start_at FROM shift_assignments WHERE id = ?',
              variables: [Variable.withString(id)],
            )
            .getSingle();
        expect(row.read<String>('scheduled_start_at'), entry.value);
      }
    });

    test('every instant column is stored in the canonical form', () async {
      final stamp = DateTime.utc(2026, 10, 6, 10, 0, 0, 123, 456);

      final role = await db
          .into(db.roles)
          .insertReturning(
            RolesCompanion.insert(code: 'owner', name: 'Owner', isSystem: true),
          );
      await db
          .into(db.userProfiles)
          .insert(
            UserProfilesCompanion.insert(
              authUserId: 'auth-1',
              roleId: role.id,
              displayName: 'Test User',
              isActive: true,
            ),
          );
      await db
          .into(db.positions)
          .insert(
            PositionsCompanion.insert(
              code: 'cashier',
              name: 'Cashier',
              isActive: true,
            ),
          );
      await db
          .into(db.employeePayRates)
          .insert(
            EmployeePayRatesCompanion.insert(
              employeeId: employeeId,
              dailyRate: 48000,
              effectiveFrom: '2026-01-01',
              updatedAt: Value(stamp),
              voidedAt: Value(stamp),
            ),
          );
      await _insertSchedule(db, publishedAt: stamp);
      await _insertShift(db, scheduleId, employeeId, _t0, _plus1us);

      const columns = <String, List<String>>{
        'roles': ['created_at', 'updated_at'],
        'user_profiles': ['created_at', 'updated_at'],
        'positions': ['created_at', 'updated_at'],
        'employees': ['created_at', 'updated_at'],
        'schedules': ['created_at', 'updated_at', 'published_at'],
        'shift_assignments': [
          'created_at',
          'updated_at',
          'scheduled_start_at',
          'scheduled_end_at',
        ],
        'employee_pay_rates': ['created_at', 'updated_at', 'voided_at'],
      };

      for (final table in columns.entries) {
        for (final column in table.value) {
          final rows = await db
              .customSelect(
                'SELECT $column AS v FROM ${table.key} '
                'WHERE $column IS NOT NULL',
              )
              .get();
          expect(
            rows,
            isNotEmpty,
            reason: '${table.key}.$column has no non-NULL value',
          );
          for (final r in rows) {
            expect(
              r.read<String>('v'),
              matches(_canonical),
              reason: '${table.key}.$column',
            );
          }
        }
      }
    });

    test('microsecond values round-trip through the database', () async {
      final start = DateTime.utc(2026, 10, 6, 10, 0, 0, 123, 456);
      final end = DateTime.utc(2026, 10, 6, 11, 0, 0, 654, 321);
      await _insertShift(db, scheduleId, employeeId, start, end);

      final row = (await db.select(db.shiftAssignments).get()).single;
      expect(row.scheduledStartAt, start);
      expect(row.scheduledEndAt, end);
      expect(row.scheduledStartAt.isUtc, isTrue);
    });

    test('existing shorter ISO-8601 text is read and not rewritten', () async {
      await db.customStatement(
        'INSERT INTO shift_assignments (id, created_at, updated_at, '
        'schedule_id, employee_id, shift_date, scheduled_start_at, '
        "scheduled_end_at, status) VALUES ('legacy-1', "
        "'2026-01-01T00:00:00.000Z', '2026-01-01T00:00:00.000Z', "
        "'$scheduleId', '$employeeId', '2026-10-06', "
        "'2026-10-06T10:00:00Z', '2026-10-06T12:00:00.123Z', 'test_status')",
      );

      final row = await (db.select(
        db.shiftAssignments,
      )..where((t) => t.id.equals('legacy-1'))).getSingle();
      expect(row.createdAt, DateTime.utc(2026, 1, 1));
      expect(row.scheduledStartAt, DateTime.utc(2026, 10, 6, 10));
      expect(row.scheduledEndAt, DateTime.utc(2026, 10, 6, 12, 0, 0, 123));

      final stored = await db
          .customSelect(
            'SELECT created_at, scheduled_start_at, scheduled_end_at '
            "FROM shift_assignments WHERE id = 'legacy-1'",
          )
          .getSingle();
      expect(stored.read<String>('created_at'), '2026-01-01T00:00:00.000Z');
      expect(stored.read<String>('scheduled_start_at'), '2026-10-06T10:00:00Z');
      expect(
        stored.read<String>('scheduled_end_at'),
        '2026-10-06T12:00:00.123Z',
      );
    });

    test('the CHECK is still exactly end > start', () async {
      final sql = await db
          .customSelect(
            "SELECT sql FROM sqlite_master WHERE name = 'shift_assignments'",
          )
          .getSingle();
      expect(
        sql.read<String>('sql'),
        contains('CHECK (scheduled_end_at > scheduled_start_at)'),
      );
      await expectLater(
        _insertShift(db, scheduleId, employeeId, _t0, _t0),
        _failsWith('check constraint'),
      );
    });
  });
}
