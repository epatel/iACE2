import 'package:drift/drift.dart';
import 'package:drift_dev/api/migrations_native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iace/core/db/app_database.dart';

import 'generated/schema.dart';

/// Checks that the database created by the app matches the committed schema
/// dump for its version. When there are more versions, `make db-schema-dump`
/// also generates migration tests next to this file.
void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  late SchemaVerifier verifier;

  setUpAll(() => verifier = SchemaVerifier(GeneratedHelper()));

  test('a new database matches the committed dump of its version', () async {
    final connection = await verifier.startAt(1);
    final db = AppDatabase(connection);
    expect(
      db.schemaVersion,
      1,
      reason: 'new version: run make db-schema-dump and extend these tests',
    );
    await verifier.migrateAndValidate(db, db.schemaVersion);
    await db.close();
  });
}
