# Persistence and migrations

Every persisted format is versioned and has a tested upgrade path from every earlier version.

## SQLite (drift)
- The database is `lib/core/db/app_database.dart`, with generated code in `app_database.g.dart` (committed; `make drift` regenerates it). The file is `iace.sqlite` in **Application Support**, not Documents (users can see Documents). `schemaVersion` is 1.
- Build config is in `build.yaml` (database `app`, `drift_schemas/`, `test/drift/`). `test/drift/app/schema_test.dart` checks that a new database matches the committed dump `drift_schemas/app/drift_schema_v1.json`, using the helpers in `test/drift/app/generated/`.
- At v1, `onUpgrade` throws; there is nothing to upgrade from. The first schema change creates `app_database.steps.dart` (via `make db-schema-dump`). Switch `onUpgrade` to `stepByStep(from1To2: …)` and extend the tests with the generated migration tests.
- To change the schema:
  1. Edit the tables.
  2. Bump `schemaVersion`.
  3. Run `make db-schema-dump` (drift `make-migrations`). This writes `drift_schemas/` and the step-by-step helpers, and generates migration tests.
  4. Write the new step in `onUpgrade` with `stepByStep`.
  5. Run `make db-migration-test`.
- Never modify a released migration step or a committed schema dump.
- Seed data (the Frogger tape) is inserted in `onCreate` and must be idempotent.
- Tables: `tapes` (name, kind `dic|byt`, data BLOB, source `seed|user|import|legacy`, timestamps; unique on name+kind), `settings` (key/value text), `snapshots` (slot, format_version, data BLOB).
- Repositories: `DbTapeLibrary` (features/tapes), `SettingsRepository` (features/settings), and `SnapshotStore` plus `SessionAutosave` (features/emulator). The setting **keys are persisted data**: renaming a key or changing its type needs a migration step. Current keys: `last_page` (int), `sticky_shift`, `reveal_hint_shown` and `legacy_import_done` (bool).
- Autosave: `SessionAutosave` restores slot 0 at launch. An unreadable snapshot is deleted and the machine cold-boots. It saves when the app is hidden and every minute, and skips saving during a tape transfer.

## Snapshot binary
- Layout: `"ACE2SNAP"` magic, then `u16 version`, then little-endian fields: registers one by one, T-states, the interrupt state and pc, the keyboard ports, the beeper level, then 64K RAM. The exact layout is in the comment above `ace_snapshot_save` in `native/src/ace_core.c`. The spooler and tape transfers are not saved.
- `ace_snapshot_load` in C upgrades older versions. Each version needs a C test fixture in `native/test/fixtures/`.
- If a snapshot is unknown or corrupt, do a cold boot. Never crash.

## Legacy import (iACE 1.2 on iOS, same bundle ID)
- `LegacyImporter` (features/legacy) runs once on first launch, on iOS only, and records `legacy_import_done` in `settings`. It also records it if the old files are broken; the errors are logged and returned. Plists are read by `lib/core/plist/plist.dart` (binary `bplist00` and XML). Test fixtures come from `tool/make_test_fixtures.py`.
- Verified on the iPad simulator by planting iACE 1.2 files in a fresh app container. The tapes and settings were imported, and the imported tape loaded and ran.
- Imported tapes replace only `seed` copies (the bundled Frogger); user tapes win. Imported settings never overwrite existing ones.
- `Documents/tapes.dic` is an XML or binary plist dictionary mapping name → data. Import each entry into `tapes` with `source=legacy`.
- NSUserDefaults keys: `lastpage` (int), `toggle_shift_keys` (bool), `reset_msg2` (bool, hint shown).
- Ignore `Caches/state.mem`. It holds a raw C struct, so it isn't portable.

## .TAP exchange
A `.TAP` file is a sequence of blocks, each `[u16 len][len bytes]`, in header+data pairs. A header+data pair corresponds to one `tapes` row.
