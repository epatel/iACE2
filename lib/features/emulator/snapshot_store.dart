import 'package:drift/drift.dart';

import '../../core/db/app_database.dart';

/// Machine snapshots in the database. Slot [autosaveSlot] holds the running
/// session.
class SnapshotStore {
  SnapshotStore(this._db);

  static const autosaveSlot = 0;

  final AppDatabase _db;

  Future<void> save(Uint8List snapshot, {int slot = autosaveSlot}) => _db
      .into(_db.snapshots)
      .insertOnConflictUpdate(
        SnapshotsCompanion.insert(
          slot: Value(slot),
          formatVersion: formatVersionOf(snapshot),
          data: snapshot,
          createdAt: Value(DateTime.now()),
        ),
      );

  Future<Uint8List?> load({int slot = autosaveSlot}) async {
    final row = await (_db.select(
      _db.snapshots,
    )..where((s) => s.slot.equals(slot))).getSingleOrNull();
    return row?.data;
  }

  Future<void> clear({int slot = autosaveSlot}) =>
      (_db.delete(_db.snapshots)..where((s) => s.slot.equals(slot))).go();

  /// The version in a snapshot's header ("ACE2SNAP", then u16 LE), or 0.
  static int formatVersionOf(Uint8List snapshot) =>
      snapshot.length >= 10 ? snapshot[8] | (snapshot[9] << 8) : 0;
}
