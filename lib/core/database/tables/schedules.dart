import 'package:drift/drift.dart';
import 'package:goil_payroll_attendance/core/database/instant_converter.dart';
import 'package:goil_payroll_attendance/core/database/standard_columns.dart';
import 'package:goil_payroll_attendance/core/database/tables/user_profiles.dart';

/// Design 5.6: a named container for shift assignments over a date range.
///
/// OD-10 is open: `status` is required text with no DEFAULT and no CHECK, no
/// uniqueness is defined, and nothing is decided about payroll-period
/// alignment or overlapping schedules. Dates are ISO `YYYY-MM-DD` text
/// interpreted in Asia/Manila. OD-09 does not apply to this table.
@TableIndex(name: 'idx_schedules_start_end', columns: {#startDate, #endDate})
@TableIndex(name: 'idx_schedules_status', columns: {#status})
class Schedules extends Table with StandardMutableColumns {
  TextColumn get name => text().nullable()();

  /// ISO `YYYY-MM-DD`, Asia/Manila business date.
  TextColumn get startDate => text()();

  /// ISO `YYYY-MM-DD`, Asia/Manila business date.
  TextColumn get endDate => text()();

  /// Allowed values are undecided (OD-10): no CHECK, no default.
  TextColumn get status => text()();

  TextColumn get publishedAt =>
      text().map(const CanonicalInstantConverter()).nullable()();

  TextColumn get publishedBy => text().nullable().references(
    UserProfiles,
    #id,
    onUpdate: KeyAction.restrict,
    onDelete: KeyAction.restrict,
  )();

  @override
  List<String> get customConstraints => ['CHECK (end_date >= start_date)'];
}
