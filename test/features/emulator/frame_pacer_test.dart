import 'package:flutter_test/flutter_test.dart';
import 'package:iace/features/emulator/frame_pacer.dart';

void main() {
  test('runs 50 frames per second at 60 Hz ticks', () {
    final pacer = FramePacer();
    var frames = 0;
    for (var tick = 1; tick <= 60; tick++) {
      frames += pacer.framesDue(Duration(microseconds: tick * 1000000 ~/ 60));
    }
    expect(frames, 50);
  });

  test('runs 50 frames per second at 120 Hz ticks', () {
    final pacer = FramePacer();
    var frames = 0;
    for (var tick = 1; tick <= 240; tick++) {
      final due = pacer.framesDue(
        Duration(microseconds: tick * 1000000 ~/ 120),
      );
      expect(due, lessThanOrEqualTo(1));
      frames += due;
    }
    expect(frames, 100);
  });

  test('does not race to catch up after a stall', () {
    final pacer = FramePacer();
    expect(pacer.framesDue(const Duration(milliseconds: 20)), 1);
    expect(pacer.framesDue(const Duration(seconds: 5)), 3);
    // Back on schedule from the new position.
    expect(pacer.framesDue(const Duration(seconds: 5, milliseconds: 20)), 1);
  });

  test('reset starts counting from zero again', () {
    final pacer = FramePacer();
    pacer.framesDue(const Duration(seconds: 1));
    pacer.reset();
    expect(pacer.framesDue(const Duration(milliseconds: 40)), 2);
  });
}
