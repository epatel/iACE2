import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/ffi/ace_machine.dart';
import 'emulator_controller.dart';

/// The ACE's 256x192 screen, scaled up with hard pixel edges.
class ScreenView extends StatelessWidget {
  const ScreenView({super.key});

  @override
  Widget build(BuildContext context) {
    final screen = context.read<EmulatorController>().screen;
    return AspectRatio(
      aspectRatio: AceMachine.width / AceMachine.height,
      child: ColoredBox(
        color: Colors.black,
        child: ValueListenableBuilder<ui.Image?>(
          valueListenable: screen,
          builder: (context, image, _) => RawImage(
            image: image,
            fit: BoxFit.contain,
            filterQuality: FilterQuality.none,
          ),
        ),
      ),
    );
  }
}
