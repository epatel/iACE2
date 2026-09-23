import 'dart:io';

import 'package:ffigen/ffigen.dart';

/// Generates lib/core/ffi/ace_bindings.g.dart from native/include/ace_api.h.
/// Run with `make ffigen`.
Future<void> main() async {
  final packageRoot = Platform.script.resolve('../');
  bool isAce(String name) => name.startsWith('ace_') || name.startsWith('ACE_');
  await FfiGenerator(
    output: Output(
      dart: DartOutput(
        path: packageRoot.resolve('lib/core/ffi/ace_bindings.g.dart'),
      ),
    ),
    input: Input(
      entryPoints: [packageRoot.resolve('native/include/ace_api.h')],
    ),
    visitors: [
      Visitor(
        func: (node) => node.isIncluded = isAce(node.name),
        struct: (node) => node.isIncluded = isAce(node.name),
        enumClass: (node) => node.isIncluded = isAce(node.name),
        unnamedEnumConstant: (node) => node.isIncluded = isAce(node.name),
      ),
    ],
  ).generate();
}
