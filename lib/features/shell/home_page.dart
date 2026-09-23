import 'package:flutter/material.dart';

import '../emulator/screen_view.dart';
import '../keyboard/ace_keyboard.dart';
import '../keyboard/keyboard_map.dart';
import 'portrait_frame.dart';

/// The screen above the keyboard. The drawers over the manual come in Phase 8.
class HomePage extends StatelessWidget {
  const HomePage({super.key, required this.keyboardMap});

  final KeyboardMap keyboardMap;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: PortraitFrame(
          child: Column(
            children: [
              const ScreenView(),
              Expanded(
                child: Align(
                  alignment: Alignment.bottomCenter,
                  child: AceKeyboard(map: keyboardMap),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
