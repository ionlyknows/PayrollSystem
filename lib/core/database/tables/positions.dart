import 'package:drift/drift.dart';
import 'package:goil_payroll_attendance/core/database/standard_columns.dart';
// Drift resolves the created_by/updated_by foreign key from
// StandardMutableColumns relative to this file's imports. Without this import
// the constraint is silently dropped from the table.
// ignore: unused_import
import 'package:goil_payroll_attendance/core/database/tables/user_profiles.dart';

/// Design 5.4: job titles. A position is not a role.
///
/// OD-08 is open: no position history and no default pay rate on a position.
class Positions extends Table with StandardMutableColumns {
  /// Unique.
  TextColumn get code => text().unique()();

  TextColumn get name => text()();

  TextColumn get description => text().nullable()();

  BoolColumn get isActive => boolean()();
}
