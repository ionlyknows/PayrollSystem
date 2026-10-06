import 'package:drift/drift.dart';
import 'package:goil_payroll_attendance/core/database/instant_converter.dart';
import 'package:goil_payroll_attendance/core/database/tables/user_profiles.dart';
import 'package:goil_payroll_attendance/core/utils/id_generator.dart';

/// STD-L column set (append-only rows): `id`, `created_at`, `created_by`.
///
/// `created_by` is nullable with a real foreign key to `user_profiles.id`
/// (RESTRICT). The design (section 3.3) allows null only for system-generated
/// rows; that rule is enforced later at the repository/audit layer, not by the
/// schema (PM decision for Phase 4.6.4).
///
/// Instants use [CanonicalInstantConverter] (fixed-width UTC text).
mixin StandardLedgerColumns on Table {
  TextColumn get id => text().clientDefault(IdGenerator.newId)();

  TextColumn get createdAt => text()
      .map(const CanonicalInstantConverter())
      .clientDefault(canonicalNowUtc)();

  TextColumn get createdBy => text().nullable().references(
    UserProfiles,
    #id,
    onUpdate: KeyAction.restrict,
    onDelete: KeyAction.restrict,
  )();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// STD-M column set (mutable rows): `id`, `created_at`, `updated_at`,
/// `created_by`, `updated_by`. Same nullability and foreign-key rule as
/// [StandardLedgerColumns].
mixin StandardMutableColumns on Table {
  TextColumn get id => text().clientDefault(IdGenerator.newId)();

  TextColumn get createdAt => text()
      .map(const CanonicalInstantConverter())
      .clientDefault(canonicalNowUtc)();

  TextColumn get updatedAt => text()
      .map(const CanonicalInstantConverter())
      .clientDefault(canonicalNowUtc)();

  TextColumn get createdBy => text().nullable().references(
    UserProfiles,
    #id,
    onUpdate: KeyAction.restrict,
    onDelete: KeyAction.restrict,
  )();

  TextColumn get updatedBy => text().nullable().references(
    UserProfiles,
    #id,
    onUpdate: KeyAction.restrict,
    onDelete: KeyAction.restrict,
  )();

  @override
  Set<Column<Object>> get primaryKey => {id};
}
