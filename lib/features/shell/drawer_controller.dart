import 'dart:ui' show lerpDouble;

import 'package:flutter/animation.dart';
import 'package:flutter/foundation.dart';

/// Positions of the screen and keyboard drawers that slide down over the
/// manual, as in iACE 1.x.
///
/// Positions are the drawers' top edges in *units*: the layout is 768 units
/// wide (the original iPad width), so a unit is `width / 768` logical pixels.
/// The screen drawer is drawn over the keyboard drawer.
class DrawerController extends ChangeNotifier {
  DrawerController({required TickerProvider vsync, this.startOpen = false})
    : _animation = AnimationController(
        vsync: vsync,
        duration: const Duration(milliseconds: 300),
      ) {
    _animation.addListener(_onAnimate);
    if (startOpen) {
      _screenY = screenOpenY;
      _keyboardY = double.infinity; // clamped once the height is known
    }
  }

  static const width = 768.0;
  static const screenHeight = 585.0;
  static const closedY = -500.0;
  static const screenOpenY = 0.0;

  /// How far the keyboard drawer may be below the screen drawer.
  static const maxGap = 582.0;

  /// Space kept for the manual below an open keyboard.
  static const minManualHeight = 224.0;

  final bool startOpen;
  final AnimationController _animation;

  double _height = 1024;
  double _keyboardHeight = 676;
  double _screenY = closedY;
  double _keyboardY = closedY;
  double _fromScreen = 0, _fromKeyboard = 0, _toScreen = 0, _toKeyboard = 0;

  double get screenY => _screenY;
  double get keyboardY => _keyboardY;
  double get keyboardHeight => _keyboardHeight;
  double get height => _height;

  /// Where the keyboard drawer sits when open: 20 units above the bottom
  /// (y = 317 on a 1024-unit-tall iPad), and never further than [maxGap]
  /// below the open screen drawer.
  double get keyboardOpenY =>
      (_height - _keyboardHeight - 20).clamp(screenOpenY, maxGap);

  /// Top of the manual: below the keyboard drawer, leaving it at least
  /// [minManualHeight].
  double get manualTop =>
      (_keyboardY + _keyboardHeight).clamp(0, _height - minManualHeight);

  bool get isOpen => _screenY >= screenOpenY && _keyboardY >= keyboardOpenY;

  /// Sets the layout size in units. Called by the shell on every layout.
  void setLayout({required double height, required double keyboardHeight}) {
    if (height == _height && keyboardHeight == _keyboardHeight) return;
    _height = height;
    _keyboardHeight = keyboardHeight;
    _keyboardY = _keyboardY.clamp(closedY, keyboardOpenY);
    _screenY = _screenY.clamp(closedY, screenOpenY);
  }

  /// Drags the screen drawer; the keyboard drawer follows to stay within
  /// [maxGap] below it and never above it.
  void dragScreen(double dy) {
    _animation.stop();
    _screenY = (_screenY + dy).clamp(closedY, screenOpenY);
    _keyboardY = _keyboardY
        .clamp(_screenY, _screenY + maxGap)
        .clamp(closedY, keyboardOpenY);
    notifyListeners();
  }

  /// Drags the keyboard drawer; the screen drawer follows.
  void dragKeyboard(double dy) {
    _animation.stop();
    _keyboardY = (_keyboardY + dy).clamp(closedY, keyboardOpenY);
    _screenY = _screenY
        .clamp(_keyboardY - maxGap, _keyboardY)
        .clamp(closedY, screenOpenY);
    notifyListeners();
  }

  /// A fast flick (units per second) opens or closes both drawers.
  void fling(double velocity) {
    if (velocity > 700) open();
    if (velocity < -700) close();
  }

  void open() => _animateTo(screenOpenY, keyboardOpenY);

  void close() => _animateTo(closedY, closedY);

  void _animateTo(double screen, double keyboard) {
    _fromScreen = _screenY;
    _fromKeyboard = _keyboardY;
    _toScreen = screen;
    _toKeyboard = keyboard;
    _animation.forward(from: 0);
  }

  void _onAnimate() {
    final t = Curves.easeOut.transform(_animation.value);
    _screenY = lerpDouble(_fromScreen, _toScreen, t)!;
    _keyboardY = lerpDouble(_fromKeyboard, _toKeyboard, t)!;
    notifyListeners();
  }

  @override
  void dispose() {
    _animation.dispose();
    super.dispose();
  }
}
