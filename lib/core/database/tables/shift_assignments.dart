import 'package:drift/drift.dart';
import 'package:goil_payroll_attendance/core/database/instant_converter.dart';
import 'package:goil_payroll_attendance/core/database/standard_columns.dart';
import 'package:goil_payroll_attendance/core/database/tables/employees.dart';
import 'package:goil_payroll_attendance/core/database/tables/schedules.dart';
// Drift resolves the created_by/updated_by foreign key from
// StandardMutableColumns relative to this file's imports. Without this import
// the constraint is silently dropped from the table.
// ignore: unused_import
import 'package:goil_payroll_attendance/core/database/tables/user_profiles.dart';

/// Design 5.7: assigns an employee to a shift on a date.
///
/// OD-10 is open: `status` is required text with no DEFAULT and no CHECK, and
/// no uniqueness is defined on (employee, date) (several shifts per day,
/// rest days and overnight dating are undecided). The scheduled times are
/// supplied by the caller from configuration; no shift start or length is
/// hard-coded here. Instants are UTC; `shift_date` is an Asia/Manila date.
@TableIndex(
  name: 'idx_shift_assignments_employee_shift_date',
  columns: {#employeeId, #shiftDate},
)
@TableIndex(name: 'idx_shift_assignments_schedule_id', columns: {#scheduleId})
@TableIndex(name: 'idx_shift_assignments_shift_date', columns: {#shiftDate})
class ShiftAssignments extends Table with StandardMutableColumns {
  TextColumn get scheduleId => text().references(
    Schedules,
    #id,
    onUpdate: KeyAction.restrict,
    onDelete: KeyAction.restrict,
  )();

  TextColumn get employeeId => text().references(
    Employees,
    #id,
    onUpdate: KeyAction.restrict,
    onDelete: KeyAction.restrict,
  )();

  /// ISO `YYYY-MM-DD`, Asia/Manila business date.
  TextColumn get shiftDate => text()();

  TextColumn get scheduledStartAt =>
      text().map(const CanonicalInstantConverter())();

  TextColumn get scheduledEndAt =>
      text().map(const CanonicalInstantConverter())();

  /// Allowed values are undecided (OD-10): no CHECK, no default.
  TextColumn get status => text()();

  TextColumn get note => text().nullable()();

  @override
  List<String> get customConstraints => [
    'CHECK (scheduled_end_at > scheduled_start_at)',
  ];
}
