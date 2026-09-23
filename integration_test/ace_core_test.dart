import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iace/core/ffi/ace_machine.dart';
import 'package:integration_test/integration_test.dart';

/// Runs the C core on a real device or simulator, to check that the native
/// asset is bundled and its symbols resolve.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  test('native core boots on device and does arithmetic', () async {
    final rom = (await rootBundle.load('assets/ace.rom')).buffer.asUint8List();
    final machine = AceMachine(rom);
    for (var i = 0; i < 100; i++) {
      machine.runFrame();
    }
    machine.spool('2 2 + .\n');
    for (var i = 0; i < 1000 && machine.isSpooling; i++) {
      machine.runFrame();
    }
    for (var i = 0; i < 25; i++) {
      machine.runFrame();
    }
    expect(machine.screenText(), contains('2 2 + . 4  OK'));
    machine.dispose();
  });
}
