import 'package:escpos_kit/escpos_kit.dart' show PosAlign;
import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../printing/escpos_preview.dart';
import '../theme.dart';

/// Draws ESC/POS bytes as a strip of thermal paper.
class ReceiptPreview extends StatelessWidget {
  const ReceiptPreview({super.key, required this.bytes, this.columns = 32});

  final List<int> bytes;

  /// Characters per line at normal size (32 for 58 mm paper).
  final int columns;

  static const Color _paper = Color(0xFFFBFBF8);
  static const Color _ink = Color(0xFF1D2125);

  @override
  Widget build(BuildContext context) {
    final items = previewEscPos(bytes);
    return LayoutBuilder(builder: (context, constraints) {
      final width = constraints.maxWidth.clamp(200.0, 320.0);
      // DejaVu Sans Mono glyphs are about 0.6 em wide.
      final fontSize = (width - 24) / columns / 0.602;
      return Center(
        child: Container(
          width: width,
          padding: const EdgeInsets.fromLTRB(12, 16, 12, 20),
          decoration: BoxDecoration(
            color: _paper,
            boxShadow: [
              BoxShadow(color: Colors.black.withValues(alpha: 0.18), blurRadius: 18, offset: const Offset(0, 8)),
            ],
          ),
          child: DefaultTextStyle(
            style: TextStyle(fontFamily: AppTheme.mono, fontSize: fontSize, height: 1.3, color: _ink),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (items.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 24),
                    child: Text('Nothing printed yet', textAlign: TextAlign.center),
                  ),
                for (final item in items) _item(item, fontSize),
              ],
            ),
          ),
        ),
      );
    });
  }

  static Alignment _alignment(PosAlign align) => switch (align) {
        PosAlign.left => Alignment.centerLeft,
        PosAlign.center => Alignment.center,
        PosAlign.right => Alignment.centerRight,
      };

  Widget _item(PreviewItem item, double fontSize) => switch (item) {
        PreviewText t => Align(
            alignment: _alignment(t.align),
            child: Container(
              color: t.reverse ? _ink : null,
              child: Text(
                t.text.isEmpty ? ' ' : t.text,
                softWrap: true,
                style: TextStyle(
                  fontWeight: t.bold ? FontWeight.w700 : FontWeight.w400,
                  fontSize: fontSize * t.heightScale,
                  // Double-width-only text: widen the spacing instead of the glyphs.
                  letterSpacing: fontSize * 0.602 * (t.widthScale - t.heightScale),
                  decoration: t.underline ? TextDecoration.underline : null,
                  color: t.reverse ? _paper : _ink,
                ),
              ),
            ),
          ),
        PreviewQr q => Align(
            alignment: _alignment(q.align),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: QrImageView(
                data: q.data.isEmpty ? ' ' : q.data,
                size: 21.0 * q.moduleSize * 0.9 + 8,
                padding: EdgeInsets.zero,
                backgroundColor: _paper,
                eyeStyle: const QrEyeStyle(eyeShape: QrEyeShape.square, color: _ink),
                dataModuleStyle: const QrDataModuleStyle(dataModuleShape: QrDataModuleShape.square, color: _ink),
              ),
            ),
          ),
        PreviewBarcode b => Align(
            alignment: _alignment(b.align),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Column(
                children: [
                  CustomPaint(size: const Size(180, 44), painter: _BarsPainter(b.data)),
                  const SizedBox(height: 2),
                  Text(b.data, style: TextStyle(fontSize: fontSize * 0.9)),
                ],
              ),
            ),
          ),
        PreviewImage img => Align(
            alignment: _alignment(img.align),
            child: CustomPaint(
              size: Size(img.width * 0.5, img.height * 0.5),
              painter: _BitmapPainter(img),
            ),
          ),
        PreviewCut _ => const Padding(
            padding: EdgeInsets.only(top: 10),
            child: _CutLine(),
          ),
        PreviewDrawer _ => const Padding(
            padding: EdgeInsets.symmetric(vertical: 4),
            child: Text('[cash drawer opened]', textAlign: TextAlign.center),
          ),
      };
}

class _CutLine extends StatelessWidget {
  const _CutLine();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Icon(Icons.content_cut, size: 14, color: Color(0xFF8A9198)),
        const SizedBox(width: 6),
        Expanded(
          child: LayoutBuilder(
            builder: (context, c) => Text(
              '- ' * (c.maxWidth / 9).floor(),
              maxLines: 1,
              overflow: TextOverflow.clip,
              style: const TextStyle(color: Color(0xFF8A9198), fontSize: 10),
            ),
          ),
        ),
      ],
    );
  }
}

/// A barcode-like pattern derived from the data. It is a picture for the
/// preview, not a scannable symbol.
class _BarsPainter extends CustomPainter {
  _BarsPainter(this.data);
  final String data;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = ReceiptPreview._ink;
    final widths = <int>[2, 1, 1, 2];
    for (final unit in data.codeUnits) {
      widths
        ..add(1 + unit % 3)
        ..add(1 + (unit >> 2) % 2)
        ..add(1 + (unit >> 4) % 3)
        ..add(1 + (unit >> 1) % 2);
    }
    widths.addAll([2, 3, 1, 1, 2]);
    final total = widths.fold<int>(0, (a, b) => a + b);
    final unit = size.width / total;
    var x = 0.0;
    for (var i = 0; i < widths.length; i++) {
      final w = widths[i] * unit;
      if (i.isEven) canvas.drawRect(Rect.fromLTWH(x, 0, w, size.height), paint);
      x += w;
    }
  }

  @override
  bool shouldRepaint(_BarsPainter old) => old.data != data;
}

class _BitmapPainter extends CustomPainter {
  _BitmapPainter(this.image);
  final PreviewImage image;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = ReceiptPreview._ink;
    final sx = size.width / image.width;
    final sy = size.height / image.height;
    for (var y = 0; y < image.height; y++) {
      for (var x = 0; x < image.width; x++) {
        if (image.isBlack(x, y)) canvas.drawRect(Rect.fromLTWH(x * sx, y * sy, sx, sy), paint);
      }
    }
  }

  @override
  bool shouldRepaint(_BitmapPainter old) => old.image != image;
}
