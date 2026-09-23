import 'package:flutter/foundation.dart';

import '../emulator/emulator_controller.dart';
import 'keyboard_map.dart';

/// Turns on-screen key presses into keyboard matrix changes.
///
/// Several keys can be held at once (e.g. SHIFT with a letter). With
/// [stickyShift], tapping SHIFT or SYMBOL SHIFT latches it until tapped again.
/// While text is being typed from the manual, keys are ignored, except that
/// releasing SPACE (BREAK) stops the typing, as in iACE 1.x.
///
/// The ROM only accepts a key that is down for at least 3 frames, so a quick
/// tap is held for [minHoldFrames] before it is released.
class KeyboardController extends ChangeNotifier {
  KeyboardController({required this.emulator, this._stickyShift = false}) {
    emulator.addFrameListener(_onFrame);
  }

  static const minHoldFrames = 4;

  final EmulatorController emulator;

  final Map<KeyDef, int> _held = {};
  final Map<KeyDef, int> _pressedAtFrame = {};
  final List<KeyDef> _pendingReleases = [];
  final Set<KeyDef> _latched = {};
  bool _stickyShift;

  bool get stickyShift => _stickyShift;

  set stickyShift(bool value) {
    if (value == _stickyShift) return;
    _stickyShift = value;
    for (final key in _latched) {
      _setKey(key, down: false);
    }
    _latched.clear();
    notifyListeners();
  }

  /// Whether [key] is shown as pressed (held or latched).
  bool isDown(KeyDef key) => _held.containsKey(key) || _latched.contains(key);

  void press(KeyDef key) {
    if (emulator.machine.isSpooling) return;
    if (key.isShift && _stickyShift) {
      if (_latched.remove(key)) {
        _setKey(key, down: false);
      } else {
        _latched.add(key);
        _setKey(key, down: true);
      }
    } else {
      _held[key] = (_held[key] ?? 0) + 1;
      _pressedAtFrame[key] = emulator.frameCount;
      _setKey(key, down: true);
    }
    notifyListeners();
  }

  void release(KeyDef key) {
    if (emulator.machine.isSpooling) {
      if (key.isSpace) emulator.machine.cancelSpool();
      _held.remove(key);
      notifyListeners();
      return;
    }
    if (key.isShift && _stickyShift) return;
    if (!_held.containsKey(key)) return;
    if (_heldFrames(key) < minHoldFrames) {
      _pendingReleases.add(key);
    } else {
      _releaseNow(key);
    }
  }

  int _heldFrames(KeyDef key) =>
      emulator.frameCount - (_pressedAtFrame[key] ?? emulator.frameCount);

  void _onFrame() {
    if (_pendingReleases.isEmpty) return;
    for (final key in List.of(_pendingReleases)) {
      if (_heldFrames(key) >= minHoldFrames) {
        _pendingReleases.remove(key);
        _releaseNow(key);
      }
    }
  }

  void _releaseNow(KeyDef key) {
    final count = (_held[key] ?? 0) - 1;
    if (count > 0) {
      _held[key] = count;
      return;
    }
    if (_held.remove(key) != null) {
      _pressedAtFrame.remove(key);
      _setKey(key, down: false);
      notifyListeners();
    }
  }

  void _setKey(KeyDef key, {required bool down}) =>
      emulator.machine.key(key.port, key.mask, down: down);

  @override
  void dispose() {
    emulator.removeFrameListener(_onFrame);
    super.dispose();
  }
}
