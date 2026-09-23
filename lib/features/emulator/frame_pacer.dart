/// Decides how many emulator frames to run on each display tick so the
/// machine runs at [framesPerSecond] regardless of the display refresh rate.
///
/// If the app falls far behind (a long pause, a slow device), it runs at most
/// [maxFramesPerTick] frames and forgets the rest instead of racing to catch up.
class FramePacer {
  FramePacer({this.framesPerSecond = 50, this.maxFramesPerTick = 3});

  final int framesPerSecond;
  final int maxFramesPerTick;

  int _framesRun = 0;

  /// Call when the clock restarts from zero (e.g. a Ticker is started again).
  void reset() => _framesRun = 0;

  /// The number of frames to run now, given the time since the clock started.
  int framesDue(Duration elapsed) {
    final target =
        elapsed.inMicroseconds *
        framesPerSecond ~/
        Duration.microsecondsPerSecond;
    var due = target - _framesRun;
    if (due > maxFramesPerTick) {
      _framesRun = target - maxFramesPerTick;
      due = maxFramesPerTick;
    }
    if (due <= 0) return 0;
    _framesRun += due;
    return due;
  }
}
