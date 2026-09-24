import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../../core/plist/plist.dart';
import '../settings/settings_repository.dart';
import '../tapes/db_tape_library.dart';

/// What [LegacyImporter.run] did.
typedef LegacyImportResult = ({
  bool ran,
  int tapes,
  List<String> settings,
  List<String> errors,
});

/// One-time import of iACE 1.x data, on iOS where 2.x updates the same app
/// (bundle id com.memention.iACE):
///
/// * `Documents/tapes.dic`: a plist dictionary of `name.dic|byt` → tape data.
/// * `Library/Preferences/com.memention.iACE.plist`: NSUserDefaults with
///   `lastpage`, `toggle_shift_keys` and `reset_msg2`.
///
/// The old `Caches/state.mem` is a raw C struct and is not imported.
class LegacyImporter {
  LegacyImporter({
    required this.tapes,
    required this.settings,
    required this.documentsDir,
    required this.preferencesFile,
  });

  /// Where iACE 1.x kept its preferences, relative to the app's Library.
  static const preferencesPath = 'Preferences/com.memention.iACE.plist';

  final DbTapeLibrary tapes;
  final SettingsRepository settings;
  final Directory documentsDir;
  final File preferencesFile;

  Future<LegacyImportResult> run() async {
    if (await settings.getBool(SettingsRepository.legacyImportDone) == true) {
      return (ran: false, tapes: 0, settings: <String>[], errors: <String>[]);
    }
    final errors = <String>[];
    var tapeCount = 0;
    final imported = <String>[];

    try {
      tapeCount = await _importTapes();
    } on Object catch (e) {
      errors.add('tapes.dic: $e');
    }
    try {
      imported.addAll(await _importPreferences());
    } on Object catch (e) {
      errors.add('preferences: $e');
    }
    for (final error in errors) {
      debugPrint('LegacyImporter: $error');
    }

    // Done even with errors: a broken old file will not get better by retrying.
    await settings.setBool(SettingsRepository.legacyImportDone, true);
    return (ran: true, tapes: tapeCount, settings: imported, errors: errors);
  }

  Future<int> _importTapes() async {
    final file = File(p.join(documentsDir.path, 'tapes.dic'));
    if (!await file.exists()) return 0;
    final plist = parsePlist(await file.readAsBytes());
    if (plist is! Map<String, Object?>) {
      throw const FormatException('not a dictionary');
    }
    var count = 0;
    for (final MapEntry(key: fileName, value: data) in plist.entries) {
      final dot = fileName.lastIndexOf('.');
      if (dot <= 0 || data is! Uint8List) continue;
      final name = fileName.substring(0, dot);
      final kind = fileName.substring(dot + 1);
      if (kind != 'dic' && kind != 'byt') continue;
      // A user's tape wins over the bundled copy; anything else is kept.
      final existing = await tapes.sourceOf(name, kind);
      if (existing != null && existing != TapeSource.seed) continue;
      await tapes.put(name, kind, data, TapeSource.legacy);
      count++;
    }
    return count;
  }

  Future<List<String>> _importPreferences() async {
    if (!await preferencesFile.exists()) return [];
    final plist = parsePlist(await preferencesFile.readAsBytes());
    if (plist is! Map<String, Object?>) {
      throw const FormatException('not a dictionary');
    }
    final imported = <String>[];
    Future<void> copy(
      String oldKey,
      String newKey, [
      Object? Function(Object?) convert = _same,
    ]) async {
      final value = convert(plist[oldKey]);
      if (value == null || await settings.contains(newKey)) return;
      switch (value) {
        case int():
          await settings.setInt(newKey, value);
        case bool():
          await settings.setBool(newKey, value);
        default:
          return;
      }
      imported.add(newKey);
    }

    // iACE 1.x counted pages from its blank first view: its page k is PDF page k - 1.
    await copy(
      'lastpage',
      SettingsRepository.lastPage,
      (v) => v is int && v > 1 ? v - 1 : null,
    );
    await copy('toggle_shift_keys', SettingsRepository.stickyShift);
    await copy('reset_msg2', SettingsRepository.revealHintShown);
    return imported;
  }

  static Object? _same(Object? value) => value;
}
