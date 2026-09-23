import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';
import 'package:path_provider/path_provider.dart';

part 'app_database.g.dart';

/// Saved tapes, in `.TAP` block layout. A tape is identified by name and kind,
/// like `frogger` + `dic`.
@DataClassName('TapeRow')
class Tapes extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text()();

  /// `dic` or `byt` (see TapeKind.extension).
  TextColumn get kind => text()();
  BlobColumn get data => blob()();

  /// `seed`, `user`, `import` or `legacy` (see TapeSource).
  TextColumn get source => text()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();

  @override
  List<Set<Column>> get uniqueKeys => [
    {name, kind},
  ];
}

/// App settings as key/value text (see SettingsRepository for the keys).
@DataClassName('SettingRow')
class Settings extends Table {
  TextColumn get key => text()();
  TextColumn get value => text()();

  @override
  Set<Column> get primaryKey => {key};
}

/// Machine snapshots (the versioned binary from the C core). Slot 0 is the
/// automatic save of the running session.
@DataClassName('SnapshotRow')
class Snapshots extends Table {
  IntColumn get slot => integer()();

  /// The snapshot binary's own format version, from its header.
  IntColumn get formatVersion => integer()();
  BlobColumn get data => blob()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {slot};
}

/// The app's SQLite database.
///
/// To change the schema: edit the tables, bump [schemaVersion], run
/// `make db-schema-dump`, add a step to [migration] and run
/// `make db-migration-test`. Never edit a released step
/// (see cards/persistence-migrations.md).
@DriftDatabase(tables: [Tapes, Settings, Snapshots])
class AppDatabase extends _$AppDatabase {
  AppDatabase(super.executor, {this.seedTapes = const {}});

  /// Opens `iace.sqlite` in the app's support directory (not Documents,
  /// which users can see).
  factory AppDatabase.open({Map<String, Uint8List> seedTapes = const {}}) =>
      AppDatabase(
        driftDatabase(
          name: 'iace',
          native: const DriftNativeOptions(
            databaseDirectory: getApplicationSupportDirectory,
          ),
        ),
        seedTapes: seedTapes,
      );

  /// Tapes to add when the database is created, keyed by `name.kind`
  /// (e.g. `frogger.dic`).
  final Map<String, Uint8List> seedTapes;

  @override
  int get schemaVersion => 1;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) async {
      await m.createAll();
      await _seed();
    },
    // v1 is the first schema. From v2 on, `make db-schema-dump` generates
    // app_database.steps.dart; use `onUpgrade: stepByStep(from1To2: ...)`.
    onUpgrade: (m, from, to) async {
      throw UnsupportedError('No migration from schema $from to $to');
    },
    beforeOpen: (details) async {
      await customStatement('PRAGMA foreign_keys = ON');
    },
  );

  Future<void> _seed() async {
    for (final MapEntry(key: file, value: data) in seedTapes.entries) {
      final dot = file.lastIndexOf('.');
      await into(tapes).insert(
        TapesCompanion.insert(
          name: file.substring(0, dot),
          kind: file.substring(dot + 1),
          data: data,
          source: 'seed',
        ),
        mode: InsertMode.insertOrIgnore,
      );
    }
  }
}
