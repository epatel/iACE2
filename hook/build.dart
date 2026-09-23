import 'package:code_assets/code_assets.dart';
import 'package:hooks/hooks.dart';
import 'package:native_toolchain_c/native_toolchain_c.dart';

/// Builds the Jupiter ACE core (native/) into the `ace` code asset.
///
/// z80ops.c, cbops.c and edops.c are #included by z80.c and must not be
/// compiled on their own.
void main(List<String> args) async {
  await build(args, (input, output) async {
    if (!input.config.buildCodeAssets) return;
    final builder = CBuilder.library(
      name: 'ace',
      assetName: 'core/ffi/ace_bindings.g.dart',
      sources: [
        'native/src/ace_core.c',
        'native/src/keyboard.c',
        'native/src/z80.c',
      ],
      includes: ['native/include', 'native/src'],
      std: 'c11',
    );
    await builder.run(input: input, output: output);
    output.dependencies.add(input.packageRoot.resolve('native/'));
  });
}
