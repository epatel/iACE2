import 'package:flutter/gestures.dart' show kTouchSlop;
import 'package:flutter/material.dart' hide DrawerController;
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../emulator/emulator_controller.dart';
import '../emulator/screen_view.dart';
import '../keyboard/ace_keyboard.dart';
import '../keyboard/keyboard_controller.dart';
import '../keyboard/keyboard_map.dart';
import '../manual/manual_annotations.dart';
import '../manual/manual_controller.dart';
import '../manual/manual_view.dart';
import '../settings/settings_lid.dart';
import 'drawer_controller.dart';
import 'portrait_frame.dart';

/// The manual, with the screen and keyboard as drawers that slide down over
/// it (iACE 1.x). Tap the manual to open the drawers, tap the screen to close
/// them, or drag either drawer.
class HomePage extends StatefulWidget {
  const HomePage({
    super.key,
    required this.keyboardMap,
    this.manual,
    this.annotations,
    this.drawersOpen = false,
    this.showRevealHint = false,
  });

  final KeyboardMap keyboardMap;
  final ManualController? manual;
  final ManualAnnotations? annotations;

  /// Start with the drawers open (iACE 1.x started closed).
  final bool drawersOpen;
  final bool showRevealHint;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with TickerProviderStateMixin {
  late final DrawerController _drawers = DrawerController(
    vsync: this,
    startOpen: widget.drawersOpen,
  );

  /// Finger travel on the keyboard drawer before it counts as a drag. The
  /// drag recognizer wins at once when it is alone in the arena, so without
  /// this every key press would start a drag.
  double _keyboardDragTravel = 0;
  bool _keyboardDragging = false;

  void _onKeyboardDragUpdate(DragUpdateDetails d, double unit) {
    if (!_keyboardDragging) {
      _keyboardDragTravel += d.delta.dy;
      if (_keyboardDragTravel.abs() < kTouchSlop) return;
      _keyboardDragging = true;
      context.read<KeyboardController>().cancelAll();
      _drawers.dragKeyboard(_keyboardDragTravel / unit);
      return;
    }
    _drawers.dragKeyboard(d.delta.dy / unit);
  }

  void _onKeyboardDragEnd(DragEndDetails d, double unit) {
    if (_keyboardDragging) {
      _drawers.fling(d.velocity.pixelsPerSecond.dy / unit);
    }
    _keyboardDragging = false;
    _keyboardDragTravel = 0;
  }

  @override
  void dispose() {
    _drawers.dispose();
    super.dispose();
  }

  void _onManualAction(ManualAction action) {
    switch (action) {
      case TypeAction(:final text):
        context.read<EmulatorController>().type(text);
        _drawers.open();
      case OpenUrlAction(:final url):
        launchUrl(url, mode: LaunchMode.externalApplication);
      case GotoAction():
        break; // handled by the manual
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        bottom: false,
        child: PortraitFrame(
          child: ChangeNotifierProvider<DrawerController?>.value(
            value: _drawers,
            child: LayoutBuilder(
              builder: (context, constraints) {
                final unit = constraints.maxWidth / DrawerController.width;
                final photo = widget.keyboardMap.imageSize;
                final photoScale = constraints.maxWidth / photo.width;
                _drawers.setLayout(
                  height: constraints.maxHeight / unit,
                  keyboardHeight: photo.height * photoScale / unit,
                );
                return ListenableBuilder(
                  listenable: _drawers,
                  builder: (context, _) => _layout(unit, photoScale),
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  Widget _layout(double unit, double photoScale) {
    final manual = widget.manual;
    final annotations = widget.annotations;
    const shadow = [
      BoxShadow(color: Colors.black54, blurRadius: 8, offset: Offset(0, 8)),
    ];
    return Stack(
      children: [
        Positioned(
          left: 0,
          right: 0,
          top: _drawers.manualTop * unit,
          bottom: 0,
          child: GestureDetector(
            key: const ValueKey('manual-area'),
            onTap: _drawers.open,
            child: manual != null && annotations != null
                ? ManualView(
                    controller: manual,
                    annotations: annotations,
                    onAction: _onManualAction,
                  )
                : const ColoredBox(color: Colors.white),
          ),
        ),
        Positioned(
          left: 0,
          right: 0,
          top: _drawers.keyboardY * unit,
          height: _drawers.keyboardHeight * unit,
          child: GestureDetector(
            key: const ValueKey('keyboard-drawer'),
            onVerticalDragUpdate: (d) => _onKeyboardDragUpdate(d, unit),
            onVerticalDragEnd: (d) => _onKeyboardDragEnd(d, unit),
            child: DecoratedBox(
              decoration: const BoxDecoration(boxShadow: shadow),
              child: Stack(
                children: [
                  Positioned.fill(child: AceKeyboard(map: widget.keyboardMap)),
                  Positioned.fill(
                    child: SettingsLid(
                      scale: photoScale,
                      showHint: widget.showRevealHint,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        Positioned(
          left: 0,
          right: 0,
          top: _drawers.screenY * unit,
          height: DrawerController.screenHeight * unit,
          child: GestureDetector(
            key: const ValueKey('screen-drawer'),
            onTap: _drawers.close,
            onVerticalDragUpdate: (d) => _drawers.dragScreen(d.delta.dy / unit),
            onVerticalDragEnd: (d) =>
                _drawers.fling(d.velocity.pixelsPerSecond.dy / unit),
            child: DecoratedBox(
              decoration: const BoxDecoration(
                color: Colors.black,
                boxShadow: shadow,
              ),
              child: Padding(
                padding: EdgeInsets.all(20 * unit),
                child: const Center(child: ScreenView()),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
