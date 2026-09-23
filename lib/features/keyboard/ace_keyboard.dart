import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'keyboard_controller.dart';
import 'keyboard_map.dart';

/// The Jupiter ACE keyboard photo with touchable keys.
///
/// It fills the available width. If the height is too small for the whole
/// photo, the top (the case with the logo) is cropped. If even the keys do not
/// fit, the keyboard is scaled down and centred instead, so keys are never cut.
class AceKeyboard extends StatelessWidget {
  const AceKeyboard({super.key, required this.map});

  final KeyboardMap map;

  /// Extra touch area around each key, in photo pixels. Half the gap between
  /// keys, so a touch between two keys goes to the nearest one.
  static const touchSlop = 8.0;

  /// Photo pixels kept above the top row of keys.
  static const keysMargin = 16.0;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final keysHeight = map.imageSize.height - map.keysTop + keysMargin;
        var scale = constraints.maxWidth / map.imageSize.width;
        if (constraints.hasBoundedHeight &&
            keysHeight * scale > constraints.maxHeight) {
          scale = constraints.maxHeight / keysHeight;
        }
        final width = map.imageSize.width * scale;
        final fullHeight = map.imageSize.height * scale;
        final height = constraints.hasBoundedHeight
            ? constraints.maxHeight.clamp(keysHeight * scale, fullHeight)
            : fullHeight;
        final cropTop = fullHeight - height;

        return Center(
          child: SizedBox(
            width: width,
            height: height,
            child: ClipRect(
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Positioned(
                    left: 0,
                    top: -cropTop,
                    width: width,
                    height: fullHeight,
                    child: Image.asset(map.image, fit: BoxFit.fill),
                  ),
                  for (final key in map.keys)
                    Positioned.fromRect(
                      rect: _scaled(
                        key.rect.inflate(touchSlop),
                        scale,
                      ).translate(0, -cropTop),
                      child: _KeyButton(keyDef: key, scale: scale),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  static Rect _scaled(Rect r, double s) =>
      Rect.fromLTRB(r.left * s, r.top * s, r.right * s, r.bottom * s);
}

class _KeyButton extends StatelessWidget {
  const _KeyButton({required this.keyDef, required this.scale});

  final KeyDef keyDef;
  final double scale;

  @override
  Widget build(BuildContext context) {
    final keyboard = context.read<KeyboardController>();
    final down = context.select<KeyboardController, bool>(
      (k) => k.isDown(keyDef),
    );
    return Semantics(
      key: ValueKey('ace-key-${keyDef.label}'),
      button: true,
      label: keyDef.label,
      selected: down,
      child: Listener(
        behavior: HitTestBehavior.opaque,
        onPointerDown: (_) => keyboard.press(keyDef),
        onPointerUp: (_) => keyboard.release(keyDef),
        onPointerCancel: (_) => keyboard.release(keyDef),
        child: Padding(
          padding: EdgeInsets.all(AceKeyboard.touchSlop * scale),
          child: AnimatedOpacity(
            opacity: down ? 1 : 0,
            duration: const Duration(milliseconds: 60),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.35),
                borderRadius: BorderRadius.circular(6 * scale),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
