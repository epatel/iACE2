import 'dart:async';

import 'package:flutter/widgets.dart';

import 'emulator_controller.dart';
import 'snapshot_store.dart';

/// Keeps the running machine across app launches: restores the last session
/// at start, and saves it when the app is hidden and every [interval].
class SessionAutosave {
  SessionAutosave({
    required this.controller,
    required this.store,
    this.interval = const Duration(minutes: 1),
  });

  final EmulatorController controller;
  final SnapshotStore store;
  final Duration interval;

  AppLifecycleListener? _lifecycle;
  Timer? _timer;
  Future<void>? _saving;

  /// Restores the saved session. Returns false (leaving the freshly booted
  /// machine) if there is none or it can't be read.
  Future<bool> restore() async {
    final snapshot = await store.load();
    if (snapshot == null) return false;
    if (controller.machine.loadSnapshot(snapshot)) return true;
    debugPrint('SessionAutosave: ignoring unreadable snapshot');
    await store.clear();
    return false;
  }

  /// Starts saving on app hide and periodically.
  void start() {
    _lifecycle ??= AppLifecycleListener(onHide: save);
    _timer ??= Timer.periodic(interval, (_) => save());
  }

  /// Saves the session now. Skipped during a tape transfer.
  Future<void> save() {
    final snapshot = controller.machine.saveSnapshot();
    if (snapshot == null) return Future.value();
    final previous = _saving ?? Future.value();
    return _saving = previous.then((_) => store.save(snapshot));
  }

  void dispose() {
    _lifecycle?.dispose();
    _timer?.cancel();
  }
}
