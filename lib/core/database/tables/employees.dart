import 'package:drift/drift.dart';
import 'package:goil_payroll_attendance/core/database/standard_columns.dart';
import 'package:goil_payroll_attendance/core/database/tables/positions.dart';
import 'package:goil_payroll_attendance/core/database/tables/user_profiles.dart';

/// Design 5.3: the people who are paid.
///
/// Only the columns the design lists are present. OD-06 and OD-07 are open:
/// no personal or identification fields beyond the design, no value list
/// for `employment_status`, and no rule yet on login requirements. Dates are
/// ISO `YYYY-MM-DD` text interpreted in Asia/Manila.
@TableIndex(name: 'idx_employees_position_id', columns: {#positionId})
@TableIndex(
  name: 'idx_employees_employment_status',
  columns: {#employmentStatus},
)
class Employees extends Table with StandardMutableColumns {
  /// Human-facing code. Unique.
  TextColumn get employeeCode => text().unique()();

  /// Null when the employee has no login.
  TextColumn get userProfileId => text().nullable().references(
    UserProfiles,
    #id,
    onUpdate: KeyAction.restrict,
    onDelete: KeyAction.restrict,
  )();

  TextColumn get firstName => text()();

  TextColumn get middleName => text().nullable()();

  TextColumn get lastName => text()();

  /// Current position only (OD-08).
  TextColumn get positionId => text().nullable().references(
    Positions,
    #id,
    onUpdate: KeyAction.restrict,
    onDelete: KeyAction.restrict,
  )();

  TextColumn get hireDate => text()();

  TextColumn get separationDate => text().nullable()();

  /// Required text. Allowed values are undecided (OD-07): no CHECK, no
  /// default.
  TextColumn get employmentStatus => text()();

  TextColumn get phone => text().nullable()();

  TextColumn get address => text().nullable()();
}

/// Design 5.3: at most one employee per user profile, where one is set.
final Index employeesUserProfileUniqueIndex = Index(
  'uq_employees_user_profile_id',
  'CREATE UNIQUE INDEX uq_employees_user_profile_id '
      'ON employees (user_profile_id) WHERE user_profile_id IS NOT NULL',
);
