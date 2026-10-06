import 'package:drift/drift.dart';
import 'package:goil_payroll_attendance/core/database/standard_columns.dart';
import 'package:goil_payroll_attendance/core/database/tables/roles.dart';

/// Design 5.2: application profile for each Supabase Auth account.
///
/// One role per user (a single `role_id`), as the design currently states;
/// OD-05 and OD-06 (multiple roles, email copy) are open. No credentials of
/// any kind are stored.
@TableIndex(name: 'idx_user_profiles_role_id', columns: {#roleId})
class UserProfiles extends Table with StandardMutableColumns {
  /// The Supabase Auth user id. Unique.
  TextColumn get authUserId => text().unique()();

  TextColumn get roleId => text().references(
    Roles,
    #id,
    onUpdate: KeyAction.restrict,
    onDelete: KeyAction.restrict,
  )();

  TextColumn get displayName => text()();

  BoolColumn get isActive => boolean()();
}
