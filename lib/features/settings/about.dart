import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

/// Adds the licences of the app and its bundled parts to Flutter's licence
/// page (on top of the Dart packages, which Flutter lists by itself).
void registerLicenses() {
  LicenseRegistry.addLicense(() async* {
    yield LicenseEntryWithLineBreaks([
      'iACE',
    ], await rootBundle.loadString('LICENSE'));
    yield const LicenseEntryWithLineBreaks(
      ['xz80'],
      'Z80 emulation from xz80, copyright (C) 1994 Ian Collier. '
      'Distributed under the GNU General Public License version 2 or later.',
    );
    yield const LicenseEntryWithLineBreaks(
      ['miniaudio'],
      'miniaudio by David Reid. Public domain (Unlicense) or MIT No Attribution, '
      'at your choice.',
    );
    yield const LicenseEntryWithLineBreaks(
      ['Jupiter ACE ROM and manual'],
      'The Jupiter ACE ROM (c) 1982 Jupiter Cantab. The Jupiter ACE User '
      "Manual (c) 1982 Steven Vickers; the scanned edition is from the Jupiter "
      'Ace Archive, www.jupiter-ace.co.uk. "Jupiter ACE" is a trademark of '
      'Andrews UK Ltd, see jupiter-ace.com.',
    );
  });
}

/// Where the source code is published (GPL).
const sourceUrl = 'https://github.com/epatel/iACE2';

Future<void> showAbout(BuildContext context) async {
  final info = await PackageInfo.fromPlatform();
  if (!context.mounted) return;
  showAboutDialog(
    context: context,
    applicationName: 'iACE',
    applicationVersion: '${info.version} (${info.buildNumber})',
    applicationIcon: Image.asset('assets/images/app_icon.png', width: 64),
    applicationLegalese:
        'A Jupiter ACE emulator with the original user manual.\n'
        'Copyright (C) 1999-2026 Edward Patel and contributors.\n'
        'Free software under the GNU General Public License version 2 '
        'or later: you may share and change it under its terms. '
        'Source code: $sourceUrl',
    children: [
      const SizedBox(height: 16),
      for (final (label, url) in [
        ('Source code on GitHub', sourceUrl),
        ('memention.com/iace', 'http://memention.com/iace'),
        ('jupiter-ace.com', 'https://jupiter-ace.com'),
      ])
        TextButton(
          onPressed: () =>
              launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication),
          child: Text(label),
        ),
    ],
  );
}
