import 'dart:convert';

import 'package:escpos_kit/escpos_kit.dart' show PosAlign, gbkCode;

/// One printed line, with the style it was printed in.
class PrintedLine {
  const PrintedLine(
    this.text, {
    this.align = PosAlign.left,
    this.bold = false,
    this.widthScale = 1,
    this.heightScale = 1,
    this.kind = PrintedKind.text,
  });

  final String text;
  final PosAlign align;
  final bool bold;
  final int widthScale;
  final int heightScale;
  final PrintedKind kind;
}

enum PrintedKind { text, barcode, qr, image, cut }

/// Turns an ESC/POS byte stream back into lines of text.
///
/// The demo printer uses it to show what a real printer would print, and the
/// tests use it to check receipts end to end. It understands the commands
/// escpos_kit sends; other commands are skipped by their known lengths.
class VirtualPrinter {
  final List<PrintedLine> lines = [];
  final List<int> _pending = [];
  final List<int> _text = [];
  PosAlign _align = PosAlign.left;
  bool _bold = false;
  int _w = 1;
  int _h = 1;
  bool _chinese = false;
  List<int> _qrData = const [];

  /// Number of bytes received in total.
  int received = 0;

  /// Feeds bytes in as they arrive; they may be split anywhere.
  void feed(List<int> bytes) {
    received += bytes.length;
    _pending.addAll(bytes);
    var i = 0;
    while (i < _pending.length) {
      final used = _step(i);
      if (used == 0) break; // incomplete command, wait for more bytes
      i += used;
    }
    _pending.removeRange(0, i);
  }

  /// The printed text, one string per line, for tests and logs.
  List<String> get textLines => [for (final l in lines) if (l.kind == PrintedKind.text) l.text];

  void reset() {
    lines.clear();
    _pending.clear();
    _text.clear();
    received = 0;
    _resetStyle();
  }

  void _resetStyle() {
    _align = PosAlign.left;
    _bold = false;
    _w = 1;
    _h = 1;
  }

  /// Handles the command or character at [i]; returns bytes consumed, or 0
  /// when more bytes are needed.
  int _step(int i) {
    final p = _pending;
    final b = p[i];
    int avail(int n) => i + n <= p.length ? n : 0;

    if (b == 0x0A) {
      _flushLine();
      return 1;
    }
    if (b == 0x1B) {
      if (avail(2) == 0) return 0;
      final c = p[i + 1];
      switch (c) {
        case 0x40: // ESC @
          _resetStyle();
          return 2;
        case 0x61: // ESC a n
          if (avail(3) == 0) return 0;
          final n = p[i + 2] >= 0x30 ? p[i + 2] - 0x30 : p[i + 2]; // '0'..'2' also allowed
          _align = PosAlign.values[n.clamp(0, 2)];
          return 3;
        case 0x45: // ESC E n
          if (avail(3) == 0) return 0;
          _bold = p[i + 2] & 1 == 1;
          return 3;
        case 0x64: // ESC d n
          if (avail(3) == 0) return 0;
          _flushLine(keepEmpty: false);
          for (var k = 0; k < p[i + 2]; k++) {
            _emit('');
          }
          return 3;
        case 0x70: // ESC p m t1 t2
          return avail(5);
        case 0x2D || 0x4D || 0x74 || 0x21 || 0x47 || 0x7B: // one-parameter commands
          return avail(3);
        default:
          return 2;
      }
    }
    if (b == 0x1D) {
      if (avail(2) == 0) return 0;
      final c = p[i + 1];
      switch (c) {
        case 0x21: // GS ! n
          if (avail(3) == 0) return 0;
          _w = (p[i + 2] >> 4) + 1;
          _h = (p[i + 2] & 0x0F) + 1;
          return 3;
        case 0x56: // GS V m n
          if (avail(4) == 0) return 0;
          _flushLine(keepEmpty: false);
          lines.add(const PrintedLine('', kind: PrintedKind.cut));
          return 4;
        case 0x6B: // GS k m n data (function B)
          if (avail(4) == 0) return 0;
          final n = p[i + 3];
          if (avail(4 + n) == 0) return 0;
          var data = String.fromCharCodes(p.sublist(i + 4, i + 4 + n));
          if (data.startsWith('{B')) data = data.substring(2);
          _flushLine(keepEmpty: false);
          lines.add(PrintedLine(data, align: _align, kind: PrintedKind.barcode));
          return 4 + n;
        case 0x28: // GS ( k pL pH cn fn ...
          if (avail(5) == 0) return 0;
          final len = p[i + 3] | p[i + 4] << 8;
          if (avail(5 + len) == 0) return 0;
          if (p[i + 2] == 0x6B && len >= 3) {
            final fn = p[i + 6];
            if (fn == 0x50) _qrData = p.sublist(i + 8, i + 5 + len);
            if (fn == 0x51) {
              _flushLine(keepEmpty: false);
              lines.add(PrintedLine(_decodeUtf8(_qrData), align: _align, kind: PrintedKind.qr));
            }
          }
          return 5 + len;
        case 0x76: // GS v 0 m xL xH yL yH data
          if (avail(8) == 0) return 0;
          final widthBytes = p[i + 4] | p[i + 5] << 8;
          final height = p[i + 6] | p[i + 7] << 8;
          final total = 8 + widthBytes * height;
          if (avail(total) == 0) return 0;
          _flushLine(keepEmpty: false);
          lines.add(PrintedLine('${widthBytes * 8}×$height', align: _align, kind: PrintedKind.image));
          return total;
        case 0x42 || 0x48 || 0x68 || 0x77: // one-parameter commands
          return avail(3);
        default:
          return 2;
      }
    }
    if (b == 0x1C) {
      if (avail(2) == 0) return 0;
      if (p[i + 1] == 0x26) _chinese = true;
      if (p[i + 1] == 0x2E) _chinese = false;
      return 2;
    }
    if (_chinese && b >= 0x81 && b <= 0xFE) {
      if (avail(2) == 0) return 0;
      _text.add(_gbkToRune(b << 8 | p[i + 1]));
      return 2;
    }
    if (b >= 0x20) _text.add(b < 0x80 ? b : 0xFFFD);
    return 1;
  }

  void _flushLine({bool keepEmpty = true}) {
    if (_text.isEmpty && !keepEmpty) return;
    _emit(String.fromCharCodes(_text));
    _text.clear();
  }

  void _emit(String text) {
    lines.add(PrintedLine(text, align: _align, bold: _bold, widthScale: _w, heightScale: _h));
  }
}

Map<int, int>? _reverseGbk;

int _gbkToRune(int code) {
  final map = _reverseGbk ??= _buildReverseGbk();
  return map[code] ?? 0xFFFD;
}

Map<int, int> _buildReverseGbk() {
  final map = <int, int>{};
  void add(int rune) {
    final code = gbkCode(rune);
    if (code != null) map[code] = rune;
  }

  for (var rune = 0x4E00; rune <= 0x9FA5; rune++) {
    add(rune);
  }
  // Punctuation and symbols receipts commonly use.
  for (final rune in '，。、：；！？（）【】《》“”‘’·—…￥％＋－×÷＝①②③'.runes) {
    add(rune);
  }
  for (var rune = 0xFF01; rune <= 0xFF5E; rune++) {
    add(rune); // full-width ASCII
  }
  return map;
}

String _decodeUtf8(List<int> bytes) => utf8.decode(bytes, allowMalformed: true);
