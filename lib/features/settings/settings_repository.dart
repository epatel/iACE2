import '../../core/db/app_database.dart';

/// Typed access to the `settings` table.
///
/// The keys below are stored in user databases: renaming or re-typing one
/// needs a database migration step (see cards/persistence-migrations.md).
class SettingsRepository {
  SettingsRepository(this._db);

  final AppDatabase _db;

  /// Manual page last shown (int).
  static const lastPage = 'last_page';

  /// SHIFT / SYMBOL SHIFT latch when tapped (bool).
  static const stickyShift = 'sticky_shift';

  /// The "pull the lid" hint has been dismissed (bool).
  static const revealHintShown = 'reveal_hint_shown';

  /// The one-time import from iACE 1.x has run (bool).
  static const legacyImportDone = 'legacy_import_done';

  Future<String?> get(String key) async {
    final row = await (_db.select(
      _db.settings,
    )..where((s) => s.key.equals(key))).getSingleOrNull();
    return row?.value;
  }

  Future<void> set(String key, String value) => _db
      .into(_db.settings)
      .insertOnConflictUpdate(SettingsCompanion.insert(key: key, value: value));

  Future<bool> contains(String key) async => await get(key) != null;

  Future<int?> getInt(String key) async => int.tryParse(await get(key) ?? '');

  Future<void> setInt(String key, int value) => set(key, '$value');

  Future<bool?> getBool(String key) async => switch (await get(key)) {
    'true' => true,
    'false' => false,
    _ => null,
  };

  Future<void> setBool(String key, bool value) => set(key, '$value');
}
