import 'package:flutter/material.dart' hide DrawerController;
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/ffi/ace_machine.dart';
import '../emulator/emulator_controller.dart';
import '../keyboard/keyboard_controller.dart';
import '../shell/drawer_controller.dart';
import '../tapes/db_tape_library.dart';
import '../tapes/tape_browser.dart';
import 'about.dart';
import 'settings_repository.dart';

/// The settings panel hidden under a piece of the keyboard's case, as in
/// iACE 1.x: drag the lid aside to reveal it. Dropped near its place, the lid
/// snaps back; tapping it slides it open or closed.
class SettingsLid extends StatefulWidget {
  const SettingsLid({super.key, required this.scale, this.showHint = false});

  /// Logical pixels per keyboard-photo pixel.
  final double scale;

  /// Show the "Drag this part to reveal some settings" hint.
  final bool showHint;

  /// The lid's place on the keyboard photo, in photo pixels.
  static const lidRect = Rect.fromLTWH(30, 6, 378, 178);

  @override
  State<SettingsLid> createState() => _SettingsLidState();
}

class _SettingsLidState extends State<SettingsLid>
    with SingleTickerProviderStateMixin {
  Offset _lid = Offset.zero; // lid offset from its place, in photo pixels
  late bool _hint = widget.showHint;
  late final AnimationController _slide = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 300),
  );
  Animation<Offset>? _slideAnimation;

  /// Far enough right to clear the panel (the lid may stick out past the
  /// keyboard's edge).
  static const _openOffset = Offset(400, 0);

  @override
  void initState() {
    super.initState();
    _slide.addListener(() => setState(() => _lid = _slideAnimation!.value));
  }

  @override
  void dispose() {
    _slide.dispose();
    super.dispose();
  }

  void _dismissHint() {
    if (!_hint) return;
    setState(() => _hint = false);
    context.read<SettingsRepository?>()?.setBool(
      SettingsRepository.revealHintShown,
      true,
    );
  }

  void _slideTo(Offset target) {
    _slideAnimation = Tween(
      begin: _lid,
      end: target,
    ).chain(CurveTween(curve: Curves.easeOut)).animate(_slide);
    _slide.forward(from: 0);
  }

  bool get _isOpen => _lid.distance > SettingsLid.lidRect.width * 0.4;

  @override
  Widget build(BuildContext context) {
    final s = widget.scale;
    final rect = SettingsLid.lidRect;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Positioned(
          left: rect.left * s,
          top: rect.top * s,
          width: rect.width * s,
          height: rect.height * s,
          child: const SettingsPanel(),
        ),
        Positioned(
          left: (rect.left + _lid.dx) * s,
          top: (rect.top + _lid.dy) * s,
          width: rect.width * s,
          height: rect.height * s,
          child: Semantics(
            button: true,
            label: _isOpen ? 'Close settings' : 'Open settings',
            child: GestureDetector(
              key: const ValueKey('settings-lid'),
              onTap: () {
                _dismissHint();
                _slideTo(_isOpen ? Offset.zero : _openOffset);
              },
              onPanStart: (_) {
                _slide.stop();
                _dismissHint();
              },
              onPanUpdate: (d) => setState(() {
                _lid += d.delta / s;
                _lid = Offset(
                  _lid.dx.clamp(-rect.left, 780 - rect.left - 40),
                  _lid.dy.clamp(-rect.top, 300),
                );
              }),
              onPanEnd: (_) {
                if (!_isOpen) _slideTo(Offset.zero);
              },
              child: DecoratedBox(
                decoration: BoxDecoration(
                  boxShadow: _lid == Offset.zero
                      ? null
                      : const [
                          BoxShadow(
                            color: Colors.black54,
                            blurRadius: 7,
                            offset: Offset(0, 8),
                          ),
                        ],
                ),
                child: Image.asset(
                  'assets/images/settingslid.jpg',
                  fit: BoxFit.fill,
                ),
              ),
            ),
          ),
        ),
        if (_hint)
          // Right of the lid, pointing at it, so it is hidden under the open
          // screen drawer together with the lid.
          Positioned(
            left: 412 * s,
            top: 60 * s,
            width: 360 * s,
            child: IgnorePointer(
              child: Image.asset('assets/images/reveal.png', fit: BoxFit.fill),
            ),
          ),
      ],
    );
  }
}

/// Sticky shift, volume, reset, tapes and About. On tablets it lies under
/// the keyboard's lid; on phones under the keyboard, where the manual is on
/// tablets, and then it also links to the manual online ([showManualLink]).
class SettingsPanel extends StatelessWidget {
  const SettingsPanel({super.key, this.showManualLink = false});

  final bool showManualLink;

  Future<void> _confirmReset(BuildContext context) async {
    final emulator = context.read<EmulatorController>();
    final reset = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Reset'),
        content: const Text('Do you want to reset the Jupiter ACE?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('No'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Yes'),
          ),
        ],
      ),
    );
    if (reset == true) emulator.reset();
  }

  /// The tablet drawers, if any: opened after a tape is loaded.
  static DrawerController? _drawers(BuildContext context) {
    try {
      return context.read<DrawerController?>();
    } on ProviderNotFoundException {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final keyboard = context.watch<KeyboardController>();
    final volume = context.watch<VolumeSetting>();
    final tapes = context.read<DbTapeLibrary?>();
    const text = TextStyle(color: Colors.white, fontSize: 13);
    return Material(
      color: const Color(0xFF2B2B2E),
      child: FittedBox(
        child: SizedBox(
          width: 378,
          height: 178,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 12, 8),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                Row(
                  children: [
                    const Expanded(
                      child: Text('Sticky shift keys', style: text),
                    ),
                    Switch(
                      key: const ValueKey('sticky-shift'),
                      value: keyboard.stickyShift,
                      onChanged: (v) => keyboard.stickyShift = v,
                    ),
                  ],
                ),
                Row(
                  children: [
                    const Icon(Icons.volume_up, color: Colors.white, size: 18),
                    Expanded(
                      child: Slider(
                        key: const ValueKey('volume'),
                        value: volume.value,
                        onChanged: (v) => volume.value = v,
                      ),
                    ),
                  ],
                ),
                Row(
                  spacing: 8,
                  children: [
                    Expanded(
                      child: _PanelButton(
                        'Reset',
                        () => _confirmReset(context),
                      ),
                    ),
                    Expanded(
                      child: _PanelButton(
                        'Tapes',
                        tapes == null
                            ? null
                            : () => TapeBrowser.show(
                                context,
                                tapes: tapes,
                                onLoad: _drawers(context)?.open,
                              ),
                      ),
                    ),
                    if (showManualLink)
                      Expanded(
                        child: _PanelButton(
                          'Manual',
                          () => launchUrl(
                            Uri.parse(manualUrl),
                            mode: LaunchMode.externalApplication,
                          ),
                        ),
                      ),
                    Expanded(
                      child: _PanelButton('About', () => showAbout(context)),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PanelButton extends StatelessWidget {
  const _PanelButton(this.label, this.onPressed);

  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        foregroundColor: Colors.white,
        side: const BorderSide(color: Colors.white),
        padding: const EdgeInsets.symmetric(horizontal: 4),
        visualDensity: VisualDensity.compact,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
      child: FittedBox(child: Text(label, maxLines: 1)),
    );
  }
}

/// The beeper volume: applied to the machine at once and saved.
class VolumeSetting extends ValueNotifier<double> {
  VolumeSetting({required double initial, required this.machine, this.settings})
    : super(initial) {
    machine.volume = initial;
  }

  final AceMachine machine;
  final SettingsRepository? settings;

  @override
  set value(double v) {
    super.value = v.clamp(0.0, 1.0);
    machine.volume = super.value;
    settings?.setDouble(SettingsRepository.volume, super.value);
  }
}
