import 'package:drift/drift.dart';

import '../../core/db/app_database.dart';
import '../../core/ffi/ace_machine.dart';
import 'tap_format.dart';
import 'tape_library.dart';

/// Where a stored tape came from.
enum TapeSource { seed, user, import, legacy }

/// Tapes stored in the database.
class DbTapeLibrary implements TapeLibrary {
  DbTapeLibrary(this._db);

  final AppDatabase _db;

  @override
  Future<Uint8List?> load(String name, TapeKind kind) async {
    final row = await _find(name, kind.extension);
    return row?.data;
  }

  @override
  Future<void> save(String name, TapeKind kind, Uint8List data) =>
      put(name, kind.extension, data, TapeSource.user);

  /// Stores a tape, replacing one with the same name and kind.
  Future<void> put(
    String name,
    String kind,
    Uint8List data,
    TapeSource source,
  ) => _db
      .into(_db.tapes)
      .insert(
        TapesCompanion.insert(
          name: name,
          kind: kind,
          data: data,
          source: source.name,
        ),
        onConflict: DoUpdate(
          (_) => TapesCompanion(
            data: Value(data),
            source: Value(source.name),
            updatedAt: Value(DateTime.now()),
          ),
          target: [_db.tapes.name, _db.tapes.kind],
        ),
      );

  Future<TapeRow?> _find(String name, String kind) => (_db.select(
    _db.tapes,
  )..where((t) => t.name.equals(name) & t.kind.equals(kind))).getSingleOrNull();

  /// Where the tape called [name] came from, or `null` if there is none.
  Future<TapeSource?> sourceOf(String name, String kind) async {
    final row = await _find(name, kind);
    return row == null ? null : TapeSource.values.byName(row.source);
  }

  /// All tapes, by name.
  Future<List<TapeRow>> all() => (_db.select(
    _db.tapes,
  )..orderBy([(t) => OrderingTerm(expression: t.name)])).get();

  /// Adds every file in a `.TAP`, replacing tapes with the same name and
  /// kind. Returns the imported file names. Throws [FormatException] if the
  /// data is not a `.TAP`.
  Future<List<String>> importTap(Uint8List tap) async {
    final files = TapFormat.parse(tap);
    for (final file in files) {
      await put(
        file.name,
        file.kind.extension,
        Uint8List.fromList(file.data),
        TapeSource.import,
      );
    }
    return [for (final f in files) '${f.name}.${f.kind.extension}'];
  }

  Future<void> delete(int id) =>
      (_db.delete(_db.tapes)..where((t) => t.id.equals(id))).go();
}
