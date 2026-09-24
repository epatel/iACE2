import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../emulator/emulator_controller.dart';
import '../emulator/screen_view.dart';
import '../keyboard/ace_keyboard.dart';
import '../keyboard/keyboard_map.dart';
import '../manual/manual_annotations.dart';
import '../manual/manual_controller.dart';
import '../manual/manual_view.dart';
import 'portrait_frame.dart';

/// The screen above either the keyboard or the manual.
///
/// Temporary layout until the drawers over the manual arrive (Phase 8).
class HomePage extends StatefulWidget {
  const HomePage({
    super.key,
    required this.keyboardMap,
    this.manual,
    this.annotations,
  });

  final KeyboardMap keyboardMap;
  final ManualController? manual;
  final ManualAnnotations? annotations;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  bool _showManual = false;

  void _onManualAction(ManualAction action) {
    switch (action) {
      case TypeAction(:final text):
        context.read<EmulatorController>().type(text);
      case OpenUrlAction(:final url):
        launchUrl(url, mode: LaunchMode.externalApplication);
      case GotoAction():
        break; // handled by the manual
    }
  }

  @override
  Widget build(BuildContext context) {
    final manual = widget.manual;
    final annotations = widget.annotations;
    final hasManual = manual != null && annotations != null;
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: PortraitFrame(
          child: Column(
            children: [
              const ScreenView(),
              if (hasManual)
                SegmentedButton<bool>(
                  segments: const [
                    ButtonSegment(value: false, label: Text('Keyboard')),
                    ButtonSegment(value: true, label: Text('Manual')),
                  ],
                  selected: {_showManual},
                  onSelectionChanged: (s) =>
                      setState(() => _showManual = s.first),
                ),
              Expanded(
                child: _showManual && hasManual
                    ? ManualView(
                        controller: manual,
                        annotations: annotations,
                        onAction: _onManualAction,
                      )
                    : Align(
                        alignment: Alignment.bottomCenter,
                        child: AceKeyboard(map: widget.keyboardMap),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
