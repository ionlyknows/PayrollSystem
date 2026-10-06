import 'package:drift/drift.dart';
import 'package:goil_payroll_attendance/core/database/standard_columns.dart';
// Drift resolves the created_by/updated_by foreign key from
// StandardMutableColumns relative to this file's imports. Without this import
// the constraint is silently dropped from the table.
// ignore: unused_import
import 'package:goil_payroll_attendance/core/database/tables/user_profiles.dart';

/// Design 5.1: the four approved roles (Owner, Manager, Cashier, Employee).
///
/// Rows are seed data in a later task; none are created in this phase.
/// OD-05 (where the permission matrix lives) is open: no permissions table.
class Roles extends Table with StandardMutableColumns {
  /// Stable machine code, for example `owner`. Unique.
  TextColumn get code => text().unique()();

  TextColumn get name => text()();

  TextColumn get description => text().nullable()();

  BoolColumn get isSystem => boolean()();
}
