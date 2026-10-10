import 'dart:convert';
import 'dart:typed_data';

import 'package:escpos_kit/escpos_kit.dart' show PosAlign, gbkCode;

/// One printed element of a receipt, as reconstructed from ESC/POS bytes.
sealed class PreviewItem {
  const PreviewItem();
}

class PreviewText extends PreviewItem {
  const PreviewText(
    this.text, {
    this.align = PosAlign.left,
    this.bold = false,
    this.underline = false,
    this.reverse = false,
    this.widthScale = 1,
    this.heightScale = 1,
  });

  final String text;
  final PosAlign align;
  final bool bold;
  final bool underline;
  final bool reverse;
  final int widthScale;
  final int heightScale;

  @override
  String toString() => 'PreviewText($text)';
}

class PreviewBarcode extends PreviewItem {
  const PreviewBarcode(this.data, this.type, {this.align = PosAlign.left});
  final String data;

  /// The `m` of `GS k`, e.g. 73 for CODE128.
  final int type;
  final PosAlign align;
}

class PreviewQr extends PreviewItem {
  const PreviewQr(this.data, {this.moduleSize = 6, this.align = PosAlign.left});
  final String data;
  final int moduleSize;
  final PosAlign align;
}

class PreviewImage extends PreviewItem {
  const PreviewImage(this.width, this.height, this.rows, {this.align = PosAlign.left});

  /// Width in dots (bytes per row × 8).
  final int width;
  final int height;
  final Uint8List rows;
  final PosAlign align;

  bool isBlack(int x, int y) => rows[y * (width >> 3) + (x >> 3)] & (0x80 >> (x & 7)) != 0;
}

class PreviewCut extends PreviewItem {
  const PreviewCut();
}

class PreviewDrawer extends PreviewItem {
  const PreviewDrawer();
}

/// Turns ESC/POS bytes back into something a screen can draw.
///
/// It understands the commands escpos_kit produces (and the common ones other
/// libraries send). Unknown commands are skipped, so a preview is always
/// produced; it is a preview, not an emulator.
List<PreviewItem> previewEscPos(List<int> bytes) => _Interpreter(bytes).run();

class _Interpreter {
  _Interpreter(this.b);

  final List<int> b;
  final List<PreviewItem> out = [];
  final StringBuffer line = StringBuffer();
  int i = 0;

  PosAlign align = PosAlign.left;
  bool bold = false;
  bool underline = false;
  bool reverse = false;
  int widthScale = 1;
  int heightScale = 1;
  bool chinese = false;

  // QR settings collected from GS ( k.
  String qrData = '';
  int qrModule = 6;

  int at(int index) => index < b.length ? b[index] : 0;

  void reset() {
    align = PosAlign.left;
    bold = underline = reverse = false;
    widthScale = heightScale = 1;
  }

  void flush({bool force = false}) {
    if (line.isEmpty && !force) return;
    out.add(PreviewText(
      line.toString(),
      align: align,
      bold: bold,
      underline: underline,
      reverse: reverse,
      widthScale: widthScale,
      heightScale: heightScale,
    ));
    line.clear();
  }

  List<PreviewItem> run() {
    while (i < b.length) {
      final c = b[i];
      if (c == 0x0A) {
        flush(force: true);
        i++;
      } else if (c == 0x0D) {
        i++;
      } else if (c == 0x1B) {
        _esc();
      } else if (c == 0x1D) {
        _gs();
      } else if (c == 0x1C) {
        final n = at(i + 1);
        if (n == 0x26) chinese = true;
        if (n == 0x2E) chinese = false;
        i += 2;
      } else if (c < 0x20) {
        i++;
      } else {
        _text();
      }
    }
    flush();
    return out;
  }

  void _text() {
    final c = b[i];
    if (c < 0x80) {
      line.writeCharCode(c);
      i++;
      return;
    }
    if (chinese && c >= 0x81 && c <= 0xFE && i + 1 < b.length) {
      final rune = _gbkDecode(c << 8 | b[i + 1]);
      line.write(rune == null ? '?' : String.fromCharCode(rune));
      i += 2;
      return;
    }
    line.writeCharCode(c); // Latin-1 is close enough for a preview
    i++;
  }

  void _esc() {
    final cmd = at(i + 1);
    switch (cmd) {
      case 0x40: // ESC @
        flush();
        reset();
        chinese = false;
        i += 2;
      case 0x61: // ESC a n
        // Some libraries send ASCII '0'-'2' instead of 0-2.
        align = PosAlign.values[(at(i + 2) & 0x03).clamp(0, 2)];
        i += 3;
      case 0x45: // ESC E n
        bold = at(i + 2) & 1 == 1;
        i += 3;
      case 0x2D: // ESC - n
        underline = at(i + 2) != 0;
        i += 3;
      case 0x64: // ESC d n
        flush();
        for (var k = 0; k < at(i + 2); k++) {
          out.add(const PreviewText(''));
        }
        i += 3;
      case 0x70: // ESC p m t1 t2
        out.add(const PreviewDrawer());
        i += 5;
      case 0x74 || 0x4D || 0x21 || 0x47 || 0x20 || 0x33: // one-byte parameters
        i += 3;
      default:
        i += 2;
    }
  }

  void _gs() {
    final cmd = at(i + 1);
    switch (cmd) {
      case 0x21: // GS ! n
        final n = at(i + 2);
        widthScale = (n >> 4) + 1;
        heightScale = (n & 0x0F) + 1;
        i += 3;
      case 0x42: // GS B n
        reverse = at(i + 2) & 1 == 1;
        i += 3;
      case 0x56: // GS V m [n]
        flush();
        out.add(const PreviewCut());
        final m = at(i + 2);
        i += (m == 65 || m == 66) ? 4 : 3;
      case 0x68 || 0x77 || 0x48 || 0x66: // barcode settings, one parameter
        i += 3;
      case 0x6B: // GS k
        flush();
        final m = at(i + 2);
        if (m >= 65) {
          final n = at(i + 3);
          var data = String.fromCharCodes(b.sublist(i + 4, (i + 4 + n).clamp(0, b.length)));
          if (m == 73 && data.length >= 2 && data.startsWith('{')) data = data.substring(2);
          out.add(PreviewBarcode(data, m, align: align));
          i += 4 + n;
        } else {
          var end = i + 3;
          while (end < b.length && b[end] != 0) {
            end++;
          }
          out.add(PreviewBarcode(String.fromCharCodes(b.sublist(i + 3, end)), m, align: align));
          i = end + 1;
        }
      case 0x28: // GS ( k
        _gsParen();
      case 0x76: // GS v 0 m xL xH yL yH d...
        flush();
        final widthBytes = at(i + 4) | at(i + 5) << 8;
        final height = at(i + 6) | at(i + 7) << 8;
        final start = i + 8;
        final end = (start + widthBytes * height).clamp(0, b.length);
        final rows = Uint8List(widthBytes * height)..setRange(0, end - start, b, start);
        out.add(PreviewImage(widthBytes * 8, height, rows, align: align));
        i = end;
      default:
        i += 2;
    }
  }

  void _gsParen() {
    final fn = at(i + 2);
    final length = at(i + 3) | at(i + 4) << 8;
    final body = i + 5;
    if (fn == 0x6B && length >= 3 && at(body) == 0x31) {
      final function = at(body + 1);
      if (function == 0x43) qrModule = at(body + 2);
      if (function == 0x50) {
        final end = (body + length).clamp(0, b.length);
        qrData = utf8.decode(b.sublist(body + 3, end), allowMalformed: true);
      }
      if (function == 0x51) {
        flush();
        out.add(PreviewQr(qrData, moduleSize: qrModule, align: align));
      }
    }
    i = body + length;
  }
}

Map<int, int>? _gbkReverse;

/// GBK code → Unicode code point, built once from escpos_kit's table.
int? _gbkDecode(int code) {
  final table = _gbkReverse ??= () {
    final map = <int, int>{};
    for (var rune = 0x80; rune <= 0xFFFF; rune++) {
      if (rune >= 0xD800 && rune <= 0xDFFF) continue;
      final c = gbkCode(rune);
      if (c != null) map.putIfAbsent(c, () => rune);
    }
    return map;
  }();
  return table[code];
}
