import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

part 'app_database.g.dart';

/// Local (offline-first) SQLite database foundation.
///
/// Intentionally has no tables yet. Business tables are added in later
/// approved tasks, each with a schema version bump and a tested migration.
@DriftDatabase(tables: [])
class AppDatabase extends _$AppDatabase {
  AppDatabase(super.e);

  /// Opens the on-device database file.
  factory AppDatabase.open() =>
      AppDatabase(driftDatabase(name: 'goil_payroll'));

  static const int currentSchemaVersion = 1;

  @override
  int get schemaVersion => currentSchemaVersion;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (Migrator m) async {
      await m.createAll();
    },
    onUpgrade: (Migrator m, int from, int to) async {
      // No earlier schema versions exist yet. Each future version adds an
      // explicit, non-destructive, tested step here.
      throw StateError('No migration path from schema $from to $to.');
    },
    beforeOpen: (OpeningDetails details) async {
      // Section 3.5: local SQLite must run with foreign keys enabled.
      await customStatement('PRAGMA foreign_keys = ON');
    },
  );
}
