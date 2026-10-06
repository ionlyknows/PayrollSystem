import 'package:drift/drift.dart';
import 'package:goil_payroll_attendance/core/database/instant_converter.dart';
import 'package:goil_payroll_attendance/core/database/standard_columns.dart';
import 'package:goil_payroll_attendance/core/database/tables/employees.dart';
import 'package:goil_payroll_attendance/core/database/tables/user_profiles.dart';

/// Design 5.5: effective-dated daily rate per employee (integer centavos).
///
/// KNOWN LIMITATION (PM decision, Phase 4.6.4): the database enforces only
///   * the foreign key to `employees`,
///   * `daily_rate > 0`,
///   * `effective_to IS NULL OR effective_to >= effective_from`,
///   * at most one open-ended, non-voided rate per employee (partial unique
///     index below).
/// It does NOT stop two CLOSED ranges for the same employee from overlapping.
/// The design (5.5, section 7) assigns that check to a repository inside the
/// inserting transaction, and the cloud re-validates on sync. No trigger is
/// added here. Whether `effective_to` is inclusive or exclusive (OD-09) is
/// still open; nothing in this schema depends on the answer.
///
/// Controlled post-insert mutations (design 3.3 and 5.5), and nothing else:
///   * closing: set `effective_to`, `updated_at`, `updated_by`;
///   * voiding: set `voided_at`, `voided_by`, `void_reason`.
/// `updated_at` and `updated_by` stay NULL on insert. This is enforced by
/// the repository layer later, not by triggers. There are no closed_at or
/// closed_by columns.
///
/// No pay rate is ever hard-coded; rows only come from user input.
@TableIndex(
  name: 'idx_employee_pay_rates_employee_effective_from',
  columns: {#employeeId, #effectiveFrom},
)
class EmployeePayRates extends Table with StandardLedgerColumns {
  TextColumn get employeeId => text().references(
    Employees,
    #id,
    onUpdate: KeyAction.restrict,
    onDelete: KeyAction.restrict,
  )();

  /// Integer centavos (PHP 480.00 = 48000). Must be greater than 0.
  IntColumn get dailyRate => integer()();

  /// ISO `YYYY-MM-DD`, Asia/Manila business date.
  TextColumn get effectiveFrom => text()();

  /// Null means open-ended (currently in force).
  TextColumn get effectiveTo => text().nullable()();

  TextColumn get reason => text().nullable()();

  /// Set only by the closing update of `effective_to`. Null on insert.
  TextColumn get updatedAt =>
      text().map(const CanonicalInstantConverter()).nullable()();

  /// Set only by the closing update. Null on insert.
  TextColumn get updatedBy => text().nullable().references(
    UserProfiles,
    #id,
    onUpdate: KeyAction.restrict,
    onDelete: KeyAction.restrict,
  )();

  /// Voids a mistaken row without deleting it.
  TextColumn get voidedAt =>
      text().map(const CanonicalInstantConverter()).nullable()();

  TextColumn get voidedBy => text().nullable().references(
    UserProfiles,
    #id,
    onUpdate: KeyAction.restrict,
    onDelete: KeyAction.restrict,
  )();

  TextColumn get voidReason => text().nullable()();

  @override
  List<String> get customConstraints => [
    'CHECK (daily_rate > 0)',
    'CHECK (effective_to IS NULL OR effective_to >= effective_from)',
  ];
}

/// Design 5.5: at most one open-ended, non-voided rate per employee.
final Index employeePayRatesOpenEndedUniqueIndex = Index(
  'uq_employee_pay_rates_open_ended',
  'CREATE UNIQUE INDEX uq_employee_pay_rates_open_ended '
      'ON employee_pay_rates (employee_id) '
      'WHERE effective_to IS NULL AND voided_at IS NULL',
);
