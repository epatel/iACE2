# Persistence and migrations

Every persisted format is versioned and has a tested upgrade path from every earlier version.

## SQLite (drift)
- The database is in `lib/core/db/`. `schemaVersion` starts at 1.
- To change the schema:
  1. Edit the tables.
  2. Bump `schemaVersion`.
  3. Run `make db-schema-dump` (drift `make-migrations`). This writes `drift_schemas/` and the step-by-step helpers, and generates migration tests.
  4. Write the new step in `onUpgrade` with `stepByStep`.
  5. Run `make db-migration-test`.
- Never modify a released migration step or a committed schema dump.
- Seed data (the Frogger tape) is inserted in `onCreate` and must be idempotent.
- Tables: `tapes` (name, kind `dic|byt`, data BLOB, source `seed|user|import|legacy`, timestamps), `settings` (key/value), `snapshots` (slot, format_version, data BLOB).

## Snapshot binary
- Layout: `"ACE2SNAP"` magic, then `u16 version`, then little-endian fields: registers one by one, T-states, the interrupt state and pc, the keyboard ports, the beeper level, then 64K RAM. The exact layout is in the comment above `ace_snapshot_save` in `native/src/ace_core.c`. The spooler and tape transfers are not saved.
- `ace_snapshot_load` in C upgrades older versions. Each version needs a C test fixture in `native/test/fixtures/`.
- If a snapshot is unknown or corrupt, do a cold boot. Never crash.

## Legacy import (iACE 1.2 on iOS, same bundle ID)
- This runs once on first launch and records `legacy_import_done` in `settings`.
- `Documents/tapes.dic` is an XML or binary plist dictionary mapping name → data. Import each entry into `tapes` with `source=legacy`.
- NSUserDefaults keys: `lastpage` (int), `toggle_shift_keys` (bool), `reset_msg2` (bool, hint shown).
- Ignore `Caches/state.mem`. It holds a raw C struct, so it isn't portable.

## .TAP exchange
A `.TAP` file is a sequence of blocks, each `[u16 len][len bytes]`, in header+data pairs. A header+data pair corresponds to one `tapes` row.
