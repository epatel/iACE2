import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/ffi/ace_machine.dart';
import 'emulator_controller.dart';

/// The ACE's 256x192 screen with hard pixel edges, in a black border.
///
/// The picture is scaled by a whole number when that fills at least 90% of
/// the width, so every ACE pixel gets the same number of screen pixels.
class ScreenView extends StatelessWidget {
  const ScreenView({super.key});

  @override
  Widget build(BuildContext context) {
    final screen = context.read<EmulatorController>().screen;
    final devicePixelRatio = MediaQuery.devicePixelRatioOf(context);
    return AspectRatio(
      aspectRatio: AceMachine.width / AceMachine.height,
      child: ColoredBox(
        color: Colors.black,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final width = pixelPerfectWidth(
              constraints.maxWidth,
              devicePixelRatio,
            );
            return Center(
              child: SizedBox(
                width: width,
                height: width * AceMachine.height / AceMachine.width,
                child: ValueListenableBuilder<ui.Image?>(
                  valueListenable: screen,
                  builder: (context, image, _) => RawImage(
                    image: image,
                    fit: BoxFit.fill,
                    filterQuality: FilterQuality.none,
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  /// The largest width, in logical pixels, that is a whole multiple of the
  /// ACE's 256 physical pixels, if that is at least 90% of [available].
  static double pixelPerfectWidth(double available, double devicePixelRatio) {
    final scale = (available * devicePixelRatio / AceMachine.width).floor();
    final width = scale * AceMachine.width / devicePixelRatio;
    return scale >= 1 && width >= available * 0.9 ? width : available;
  }
}
