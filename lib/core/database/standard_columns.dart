import 'package:drift/drift.dart';
import 'package:goil_payroll_attendance/core/utils/id_generator.dart';

/// STD-L column set (append-only rows): `id`, `created_at`, `created_by`.
///
/// `created_by` is nullable for now; the foreign key to `user_profiles` and the
/// "null only for system rows" rule come with that table and its repository.
mixin StandardLedgerColumns on Table {
  TextColumn get id => text().clientDefault(IdGenerator.newId)();

  DateTimeColumn get createdAt =>
      dateTime().clientDefault(() => DateTime.now().toUtc())();

  TextColumn get createdBy => text().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// STD-M column set (mutable rows): `id`, `created_at`, `updated_at`,
/// `created_by`, `updated_by`. Same nullability note as [StandardLedgerColumns].
mixin StandardMutableColumns on Table {
  TextColumn get id => text().clientDefault(IdGenerator.newId)();

  DateTimeColumn get createdAt =>
      dateTime().clientDefault(() => DateTime.now().toUtc())();

  DateTimeColumn get updatedAt =>
      dateTime().clientDefault(() => DateTime.now().toUtc())();

  TextColumn get createdBy => text().nullable()();

  TextColumn get updatedBy => text().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}
