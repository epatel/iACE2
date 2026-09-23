import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

import '../../core/ffi/ace_machine.dart';
import '../tapes/tape_library.dart';
import 'frame_pacer.dart';

/// Runs an [AceMachine] in real time and publishes its screen.
///
/// Frames are paced by a [Ticker] at 50 Hz. The machine pauses while the app
/// is hidden. Tape requests from the ROM are answered from [tapes].
class EmulatorController extends ChangeNotifier {
  EmulatorController({required this.machine, required this.tapes}) {
    _ticker = Ticker(_onTick, debugLabel: 'EmulatorController');
    _lifecycle = AppLifecycleListener(onHide: pause, onShow: resume);
  }

  final AceMachine machine;
  final TapeLibrary tapes;

  late final Ticker _ticker;
  late final AppLifecycleListener _lifecycle;
  final _pacer = FramePacer(framesPerSecond: AceMachine.framesPerSecond);

  final ValueNotifier<ui.Image?> _screen = ValueNotifier(null);
  bool _screenDecoding = false;
  bool _screenPending = false;
  bool _tapeLoading = false;
  bool _wantsRunning = false;
  bool _disposed = false;
  int _frameCount = 0;

  /// The latest screen image, [AceMachine.width] x [AceMachine.height].
  ValueListenable<ui.Image?> get screen => _screen;

  /// Frames run since the controller was created.
  int get frameCount => _frameCount;

  bool get isRunning => _ticker.isActive;

  void start() {
    _wantsRunning = true;
    resume();
  }

  void stop() {
    _wantsRunning = false;
    pause();
  }

  @visibleForTesting
  void pause() {
    if (!_ticker.isActive) return;
    _ticker.stop();
    notifyListeners();
  }

  @visibleForTesting
  void resume() {
    if (!_wantsRunning || _ticker.isActive || _disposed) return;
    _pacer.reset();
    _ticker.start();
    notifyListeners();
  }

  void _onTick(Duration elapsed) {
    final frames = _pacer.framesDue(elapsed);
    for (var i = 0; i < frames; i++) {
      runFrame();
    }
  }

  /// Runs one frame and handles what it reports. Public for tests.
  @visibleForTesting
  void runFrame() {
    final flags = machine.runFrame();
    _frameCount++;
    if (flags & FrameFlags.tapeLoad != 0) _loadTape();
    if (flags & FrameFlags.tapeSaved != 0) _saveTape();
    if (flags & FrameFlags.screenDirty != 0) _updateScreen();
  }

  void _loadTape() {
    if (_tapeLoading) return;
    final request = machine.tapeRequest();
    if (request == null) return;
    _tapeLoading = true;
    tapes.load(request.name, request.kind).catchError((Object _) => null).then((
      tape,
    ) {
      _tapeLoading = false;
      if (!_disposed) machine.supplyTape(tape);
    });
  }

  void _saveTape() {
    final saved = machine.savedTape();
    if (saved == null) return;
    unawaited(tapes.save(saved.name, saved.kind, saved.data));
  }

  /// Turns the framebuffer into an image. At most one decode runs at a time;
  /// changes during a decode are picked up when it finishes.
  void _updateScreen() {
    if (_screenDecoding) {
      _screenPending = true;
      return;
    }
    _screenDecoding = true;
    _screenPending = false;
    unawaited(_decodeScreen(Uint8List.fromList(machine.framebuffer)));
  }

  Future<void> _decodeScreen(Uint8List pixels) async {
    final buffer = await ui.ImmutableBuffer.fromUint8List(pixels);
    final descriptor = ui.ImageDescriptor.raw(
      buffer,
      width: AceMachine.width,
      height: AceMachine.height,
      pixelFormat: ui.PixelFormat.rgba8888,
    );
    final codec = await descriptor.instantiateCodec();
    final frame = await codec.getNextFrame();
    codec.dispose();
    descriptor.dispose();
    buffer.dispose();

    _screenDecoding = false;
    if (_disposed) {
      frame.image.dispose();
      return;
    }
    final old = _screen.value;
    _screen.value = frame.image;
    old?.dispose();
    if (_screenPending) _updateScreen();
  }

  /// Types [text] into the machine (see [AceMachine.spool]).
  void type(String text) => machine.spool(text);

  void reset() => machine.reset();

  @override
  void dispose() {
    _disposed = true;
    _ticker.dispose();
    _lifecycle.dispose();
    _screen.value?.dispose();
    _screen.dispose();
    machine.dispose();
    super.dispose();
  }
}
