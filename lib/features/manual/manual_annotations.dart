import 'dart:convert';

import 'package:flutter/services.dart';

/// What tapping an annotation does.
sealed class ManualAction {
  const ManualAction();
}

/// Types [text] into the ACE (lines end with `\n`).
final class TypeAction extends ManualAction {
  const TypeAction(this.text);
  final String text;
}

/// Shows another page of the manual.
final class GotoAction extends ManualAction {
  const GotoAction(this.page);

  /// PDF page number, 1-based.
  final int page;
}

/// Opens a web page.
final class OpenUrlAction extends ManualAction {
  const OpenUrlAction(this.url);
  final Uri url;
}

/// A tappable area on a manual page.
class ManualAnnotation {
  const ManualAnnotation({
    required this.page,
    required this.rect,
    required this.action,
  });

  factory ManualAnnotation.fromJson(Map<String, dynamic> json) =>
      ManualAnnotation(
        page: json['page'] as int,
        rect: Rect.fromLTWH(
          (json['x'] as num).toDouble(),
          (json['y'] as num).toDouble(),
          (json['width'] as num).toDouble(),
          (json['height'] as num).toDouble(),
        ),
        action: switch (json['action']) {
          'type' => TypeAction(json['text'] as String),
          'goto' => GotoAction(json['target'] as int),
          'open' => OpenUrlAction(Uri.parse(json['url'] as String)),
          final other => throw FormatException('unknown action $other'),
        },
      );

  /// PDF page number, 1-based.
  final int page;

  /// Area on the page, in PDF points from the top-left corner.
  final Rect rect;

  final ManualAction action;
}

/// The manual's annotations, from `assets/annotations.json` (generated from
/// the original iACE by `tool/extract_annotations.py`).
class ManualAnnotations {
  ManualAnnotations({
    required this.pageSize,
    required List<ManualAnnotation> all,
  }) {
    for (final a in all) {
      (_byPage[a.page] ??= []).add(a);
    }
  }

  factory ManualAnnotations.fromJson(Map<String, dynamic> json) =>
      ManualAnnotations(
        pageSize: Size(
          (json['pageWidth'] as num).toDouble(),
          (json['pageHeight'] as num).toDouble(),
        ),
        all: [
          for (final a in json['annotations'] as List)
            ManualAnnotation.fromJson(a as Map<String, dynamic>),
        ],
      );

  static Future<ManualAnnotations> load(AssetBundle bundle) async =>
      ManualAnnotations.fromJson(
        jsonDecode(await bundle.loadString('assets/annotations.json'))
            as Map<String, dynamic>,
      );

  /// Size of a manual page in PDF points.
  final Size pageSize;
  final Map<int, List<ManualAnnotation>> _byPage = {};

  List<ManualAnnotation> onPage(int page) => _byPage[page] ?? const [];

  int get count => _byPage.values.fold(0, (sum, list) => sum + list.length);
}
