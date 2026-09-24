import 'package:code_assets/code_assets.dart';
import 'package:hooks/hooks.dart';
import 'package:native_toolchain_c/native_toolchain_c.dart';

/// Builds the Jupiter ACE core (native/) into the `ace` code asset.
///
/// z80ops.c, cbops.c and edops.c are #included by z80.c and must not be
/// compiled on their own. miniaudio's iOS backend is Objective-C, so on iOS
/// its implementation is compiled from the .m shim.
void main(List<String> args) async {
  await build(args, (input, output) async {
    if (!input.config.buildCodeAssets) return;
    final os = input.config.code.targetOS;
    final apple = os == OS.iOS || os == OS.macOS;
    final builder = CBuilder.library(
      name: 'ace',
      assetName: 'core/ffi/ace_bindings.g.dart',
      sources: [
        'native/src/ace_core.c',
        'native/src/audio.c',
        'native/src/keyboard.c',
        'native/src/z80.c',
        os == OS.iOS
            ? 'native/src/miniaudio_impl.m'
            : 'native/src/miniaudio_impl.c',
      ],
      includes: ['native/include', 'native/src'],
      std: 'c11',
      frameworks: [
        if (apple) ...[
          'Foundation',
          'CoreFoundation',
          'CoreAudio',
          'AudioToolbox',
        ],
        if (os == OS.iOS) 'AVFoundation',
      ],
      libraries: [
        if (os == OS.android) ...['m', 'dl'],
      ],
    );
    await builder.run(input: input, output: output);
    output.dependencies.add(input.packageRoot.resolve('native/'));
  });
}
