import 'dart:async';

import 'package:flutter/gestures.dart' show kTouchSlop;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../emulator/screen_view.dart';
import '../keyboard/ace_keyboard.dart';
import '../keyboard/keyboard_controller.dart';
import '../keyboard/keyboard_map.dart';
import '../settings/settings_lid.dart';
import '../settings/settings_repository.dart';

/// Where things go on a phone (all in logical pixels).
///
/// As on tablets, the screen is a black drawer over the top of the keyboard
/// photo (hiding the logo). The settings panel lies below the keyboard, where
/// tablets have the manual, and the keyboard lifts by the panel's height to
/// reveal it, sliding further under the screen but never hiding a key.
class PhoneLayout {
  PhoneLayout({
    required Size size,
    required Size photo,
    required double photoKeysTop,
  }) : width = size.width,
       height = size.height {
    final s = width / photo.width;
    keyboardHeight = photo.height * s;
    keysTop = (photoKeysTop - AceKeyboard.keysMargin) * s;
    keyboardTop = height - keyboardHeight;
    screenMinHeight = width * 3 / 4 + 2 * screenPadding;
    final room = keyboardTop + keysTop - screenMinHeight;
    panelHeight = (width * panelAspect).clamp(0.0, room < 0 ? 0.0 : room);
    screenHeight = [
      screenMinHeight,
      keyboardTop - panelHeight + keysTop,
    ].reduce((a, b) => a > b ? a : b);
  }

  /// Height / width of the settings panel (its 378 x 178 design).
  static const panelAspect = 178 / 378;
  static const screenPadding = 8.0;

  final double width;
  final double height;
  late final double keyboardHeight;

  /// Top of the first key row, from the top of the keyboard photo.
  late final double keysTop;

  /// Top of the keyboard when the settings are hidden.
  late final double keyboardTop;
  late final double screenMinHeight;
  late final double panelHeight;

  /// Height of the screen drawer: down to the keys when the panel is open.
  late final double screenHeight;
}

/// The phone layout: screen above keyboard, settings under the keyboard, no
/// manual (the settings panel links to it online).
class PhoneHome extends StatefulWidget {
  const PhoneHome({
    super.key,
    required this.keyboardMap,
    this.showRevealHint = false,
  });

  final KeyboardMap keyboardMap;

  /// Lift the keyboard a little once, to show there is something under it.
  final bool showRevealHint;

  @override
  State<PhoneHome> createState() => _PhoneHomeState();
}

class _PhoneHomeState extends State<PhoneHome>
    with SingleTickerProviderStateMixin {
  /// How far the keyboard is lifted: 0 closed, 1 settings fully shown.
  late final AnimationController _lift = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 250),
  );
  double _panelHeight = 1;
  double _dragTravel = 0;
  bool _dragging = false;
  bool _hintShown = false;
  Timer? _hintTimer;

  @override
  void initState() {
    super.initState();
    if (widget.showRevealHint) {
      _hintTimer = Timer(const Duration(milliseconds: 900), _peek);
    }
  }

  @override
  void dispose() {
    _hintTimer?.cancel();
    _lift.dispose();
    super.dispose();
  }

  Future<void> _peek() async {
    if (!mounted || _lift.value > 0) return;
    await _lift.animateTo(0.3, curve: Curves.easeOut);
    if (!mounted) return;
    await _lift.animateTo(0, curve: Curves.easeIn);
  }

  void _onOpened() {
    if (_hintShown) return;
    _hintShown = true;
    context.read<SettingsRepository?>()?.setBool(
      SettingsRepository.revealHintShown,
      true,
    );
  }

  void _onDragUpdate(DragUpdateDetails d) {
    if (!_dragging) {
      _dragTravel += d.delta.dy;
      if (_dragTravel.abs() < kTouchSlop) return;
      _dragging = true;
      context.read<KeyboardController>().cancelAll();
      _lift.stop();
      _lift.value -= _dragTravel / _panelHeight;
      return;
    }
    _lift.value -= d.delta.dy / _panelHeight;
  }

  void _onDragEnd(DragEndDetails d) {
    if (_dragging) {
      final velocity = d.velocity.pixelsPerSecond.dy;
      final open = velocity < -300 || (velocity <= 300 && _lift.value > 0.5);
      _lift.animateTo(open ? 1 : 0, curve: Curves.easeOut);
      if (open) _onOpened();
    }
    _dragging = false;
    _dragTravel = 0;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final layout = PhoneLayout(
              size: constraints.biggest,
              photo: widget.keyboardMap.imageSize,
              photoKeysTop: widget.keyboardMap.keysTop,
            );
            _panelHeight = layout.panelHeight > 0 ? layout.panelHeight : 1;
            return AnimatedBuilder(
              animation: _lift,
              builder: (context, _) => Stack(
                children: [
                  Positioned(
                    key: const ValueKey('phone-settings'),
                    left: 0,
                    right: 0,
                    bottom: 0,
                    height: layout.panelHeight,
                    child: const SettingsPanel(showManualLink: true),
                  ),
                  Positioned(
                    left: 0,
                    right: 0,
                    top: layout.keyboardTop - _lift.value * layout.panelHeight,
                    height: layout.keyboardHeight,
                    child: GestureDetector(
                      key: const ValueKey('keyboard-drawer'),
                      onVerticalDragUpdate: _onDragUpdate,
                      onVerticalDragEnd: _onDragEnd,
                      child: DecoratedBox(
                        // The shadow falls on the settings below the keyboard.
                        decoration: const BoxDecoration(
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black87,
                              blurRadius: 10,
                              offset: Offset(0, 4),
                            ),
                          ],
                        ),
                        child: AceKeyboard(map: widget.keyboardMap),
                      ),
                    ),
                  ),
                  Positioned(
                    left: 0,
                    right: 0,
                    top: 0,
                    height: layout.screenHeight,
                    child: const DecoratedBox(
                      decoration: BoxDecoration(
                        color: Colors.black,
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black54,
                            blurRadius: 8,
                            offset: Offset(0, 6),
                          ),
                        ],
                      ),
                      child: Padding(
                        padding: EdgeInsets.all(PhoneLayout.screenPadding),
                        child: Center(child: ScreenView()),
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}
