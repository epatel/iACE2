import 'dart:convert';

import 'package:flutter/services.dart';

/// One key on the keyboard photo.
class KeyDef {
  const KeyDef({
    required this.label,
    required this.port,
    required this.mask,
    required this.isShift,
    required this.rect,
  });

  factory KeyDef.fromJson(Map<String, dynamic> json) => KeyDef(
    label: json['label'] as String,
    port: json['port'] as int,
    mask: json['mask'] as int,
    isShift: json['shift'] as bool,
    rect: Rect.fromLTWH(
      (json['x'] as num).toDouble(),
      (json['y'] as num).toDouble(),
      (json['width'] as num).toDouble(),
      (json['height'] as num).toDouble(),
    ),
  );

  /// The legend on the key, e.g. `A`, `ENTER`, `SYMBOL SHIFT`.
  final String label;

  /// Keyboard matrix half-row (0..7) and bit mask.
  final int port;
  final int mask;

  /// SHIFT or SYMBOL SHIFT, which can be made sticky.
  final bool isShift;

  /// Position on the keyboard photo, in photo pixels.
  final Rect rect;

  bool get isSpace => port == 7 && mask == 1;

  @override
  String toString() => 'KeyDef($label)';
}

/// The on-screen keyboard: the photo and where each key is on it.
/// Generated from the original iACE by `tool/extract_keyboard_map.py`.
class KeyboardMap {
  KeyboardMap({
    required this.image,
    required this.imageSize,
    required this.keys,
  }) : hitRects = _hitRects(keys);

  factory KeyboardMap.fromJson(Map<String, dynamic> json) => KeyboardMap(
    image: json['image'] as String,
    imageSize: Size(
      (json['imageWidth'] as num).toDouble(),
      (json['imageHeight'] as num).toDouble(),
    ),
    keys: [
      for (final key in json['keys'] as List)
        KeyDef.fromJson(key as Map<String, dynamic>),
    ],
  );

  static Future<KeyboardMap> load(AssetBundle bundle) async =>
      KeyboardMap.fromJson(
        jsonDecode(await bundle.loadString('assets/keyboard_map.json'))
            as Map<String, dynamic>,
      );

  final String image;
  final Size imageSize;
  final List<KeyDef> keys;

  /// Where each key can be tapped, in photo pixels: the key grown on every side
  /// to halfway to its neighbour, so neighbouring tap areas touch. Towards
  /// the photo's edges it grows by [outerMargin].
  final Map<KeyDef, Rect> hitRects;

  static const outerMargin = 12.0;

  static Map<KeyDef, Rect> _hitRects(List<KeyDef> keys) {
    bool overlapsX(Rect a, Rect b) => a.left < b.right && b.left < a.right;
    bool overlapsY(Rect a, Rect b) => a.top < b.bottom && b.top < a.bottom;

    return {
      for (final key in keys)
        key: () {
          final r = key.rect;
          var left = r.left - outerMargin, right = r.right + outerMargin;
          var top = r.top - outerMargin, bottom = r.bottom + outerMargin;
          for (final other in keys) {
            final o = other.rect;
            if (identical(other, key)) continue;
            if (overlapsY(r, o)) {
              if (o.right <= r.left) {
                left = [left, (o.right + r.left) / 2].reduce(_max);
              }
              if (o.left >= r.right) {
                right = [right, (r.right + o.left) / 2].reduce(_min);
              }
            }
            if (overlapsX(r, o)) {
              if (o.bottom <= r.top) {
                top = [top, (o.bottom + r.top) / 2].reduce(_max);
              }
              if (o.top >= r.bottom) {
                bottom = [bottom, (r.bottom + o.top) / 2].reduce(_min);
              }
            }
          }
          return Rect.fromLTRB(left, top, right, bottom);
        }(),
    };
  }

  static double _max(double a, double b) => a > b ? a : b;
  static double _min(double a, double b) => a < b ? a : b;

  /// The top of the highest key, in photo pixels. Everything above is the
  /// case with the logo, which may be cropped away when space is short.
  double get keysTop =>
      keys.map((k) => k.rect.top).reduce((a, b) => a < b ? a : b);

  KeyDef byLabel(String label) => keys.firstWhere((k) => k.label == label);
}
