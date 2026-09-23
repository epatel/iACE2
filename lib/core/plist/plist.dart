import 'dart:convert';
import 'dart:typed_data';

import 'package:xml/xml.dart';

/// Reads Apple property lists, binary (`bplist00`) or XML, into Dart values:
/// `Map<String, Object?>`, `List<Object?>`, `String`, `int`, `double`,
/// `bool`, `Uint8List` (data) and `DateTime`.
///
/// Only what iACE 1.x wrote is needed (NSDictionary files and
/// NSUserDefaults), so UIDs and sets are not supported.
Object? parsePlist(Uint8List bytes) {
  if (bytes.length >= 8 &&
      ascii.decode(bytes.sublist(0, 8), allowInvalid: true) == 'bplist00') {
    return _BinaryPlist(bytes).root();
  }
  return _parseXml(utf8.decode(bytes));
}

class PlistFormatException implements Exception {
  PlistFormatException(this.message);
  final String message;
  @override
  String toString() => 'PlistFormatException: $message';
}

// XML

Object? _parseXml(String text) {
  final document = XmlDocument.parse(text);
  final plist = document.findAllElements('plist').firstOrNull;
  final root = plist?.childElements.firstOrNull;
  if (root == null) throw PlistFormatException('no <plist> root');
  return _xmlValue(root);
}

Object? _xmlValue(XmlElement e) {
  switch (e.name.local) {
    case 'dict':
      final result = <String, Object?>{};
      final children = e.childElements.toList();
      for (var i = 0; i + 1 < children.length; i += 2) {
        if (children[i].name.local != 'key') {
          throw PlistFormatException('expected <key> in <dict>');
        }
        result[children[i].innerText] = _xmlValue(children[i + 1]);
      }
      return result;
    case 'array':
      return [for (final child in e.childElements) _xmlValue(child)];
    case 'string':
      return e.innerText;
    case 'integer':
      return int.parse(e.innerText.trim());
    case 'real':
      return double.parse(e.innerText.trim());
    case 'true':
      return true;
    case 'false':
      return false;
    case 'data':
      return base64.decode(e.innerText.replaceAll(RegExp(r'\s'), ''));
    case 'date':
      return DateTime.parse(e.innerText.trim());
    default:
      throw PlistFormatException('unsupported element <${e.name.local}>');
  }
}

// Binary

class _BinaryPlist {
  _BinaryPlist(this.bytes) : data = ByteData.sublistView(bytes) {
    if (bytes.length < 40) throw PlistFormatException('too short');
    final trailer = bytes.length - 32;
    offsetSize = bytes[trailer + 6];
    refSize = bytes[trailer + 7];
    objectCount = _uint(trailer + 8, 8);
    rootObject = _uint(trailer + 16, 8);
    offsetTable = _uint(trailer + 24, 8);
    if (offsetTable + objectCount * offsetSize > trailer) {
      throw PlistFormatException('bad offset table');
    }
  }

  final Uint8List bytes;
  final ByteData data;
  late final int offsetSize;
  late final int refSize;
  late final int objectCount;
  late final int rootObject;
  late final int offsetTable;
  int _depth = 0;

  Object? root() => _object(rootObject);

  int _uint(int offset, int size) {
    if (offset < 0 || offset + size > bytes.length) {
      throw PlistFormatException('read past end');
    }
    var value = 0;
    for (var i = 0; i < size; i++) {
      value = (value << 8) | bytes[offset + i];
    }
    return value;
  }

  Object? _object(int ref) {
    if (ref >= objectCount) throw PlistFormatException('bad object ref');
    if (++_depth > 64) throw PlistFormatException('nested too deep');
    try {
      final offset = _uint(offsetTable + ref * offsetSize, offsetSize);
      final marker = bytes[offset];
      final type = marker >> 4;
      final info = marker & 0x0f;
      switch (type) {
        case 0x0:
          return switch (info) {
            0x8 => false,
            0x9 => true,
            _ => null,
          };
        case 0x1: // int, 2^info bytes, big-endian (8-byte ints are signed)
          final size = 1 << info;
          if (size == 8) return data.getInt64(offset + 1);
          return _uint(offset + 1, size);
        case 0x2:
          return info == 2
              ? data.getFloat32(offset + 1)
              : data.getFloat64(offset + 1);
        case 0x3:
          final seconds = data.getFloat64(offset + 1);
          return DateTime.utc(2001)
              .add(Duration(microseconds: (seconds * 1e6).round()));
        case 0x4:
          final (length, start) = _length(info, offset);
          return Uint8List.fromList(bytes.sublist(start, start + length));
        case 0x5:
          final (length, start) = _length(info, offset);
          return latin1.decode(bytes.sublist(start, start + length));
        case 0x6:
          final (length, start) = _length(info, offset);
          final units = [
            for (var i = 0; i < length; i++) data.getUint16(start + i * 2),
          ];
          return String.fromCharCodes(units);
        case 0xa:
          final (count, start) = _length(info, offset);
          return [
            for (var i = 0; i < count; i++)
              _object(_uint(start + i * refSize, refSize)),
          ];
        case 0xd:
          final (count, start) = _length(info, offset);
          final result = <String, Object?>{};
          for (var i = 0; i < count; i++) {
            final key = _object(_uint(start + i * refSize, refSize));
            final value = _object(
              _uint(start + (count + i) * refSize, refSize),
            );
            if (key is! String) throw PlistFormatException('non-string key');
            result[key] = value;
          }
          return result;
        default:
          throw PlistFormatException(
            'unsupported object type 0x${type.toRadixString(16)}',
          );
      }
    } on RangeError {
      throw PlistFormatException('read past end');
    } finally {
      _depth--;
    }
  }

  /// Length from the marker's low nibble, or from a following int object.
  (int, int) _length(int info, int offset) {
    if (info != 0xf) return (info, offset + 1);
    final intMarker = bytes[offset + 1];
    if (intMarker >> 4 != 0x1) throw PlistFormatException('bad length');
    final size = 1 << (intMarker & 0x0f);
    return (_uint(offset + 2, size), offset + 2 + size);
  }
}
