import 'package:escpos_kit/escpos_kit.dart' show PosAlign;
import 'package:flutter/material.dart';

import '../core/virtual_printer.dart';

/// Four signal-strength bars, like a phone's status bar.
class SignalBars extends StatelessWidget {
  const SignalBars({super.key, required this.bars, this.size = 22});

  final int bars;
  final double size;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      label: 'Signal $bars of 4',
      child: SizedBox(
        width: size,
        height: size,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            for (var i = 0; i < 4; i++)
              Container(
                width: size / 5.5,
                height: size * (i + 1) / 4,
                decoration: BoxDecoration(
                  color: i < bars ? scheme.primary : scheme.outlineVariant,
                  borderRadius: BorderRadius.circular(1.5),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Small rounded label.
class Tag extends StatelessWidget {
  const Tag(this.text, {super.key, this.highlight = false});

  final String text;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: highlight ? scheme.primaryContainer : scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        text,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: highlight ? scheme.onPrimaryContainer : scheme.onSurfaceVariant,
            ),
      ),
    );
  }
}

/// Draws what the virtual printer printed, on a strip of receipt paper.
class ReceiptView extends StatelessWidget {
  const ReceiptView({super.key, required this.lines});

  final List<PrintedLine> lines;

  @override
  Widget build(BuildContext context) {
    const ink = Color(0xFF1D2125);
    const base = TextStyle(fontFamily: 'monospace', fontSize: 12.5, height: 1.45, color: ink);
    return Container(
      width: 300,
      padding: const EdgeInsets.fromLTRB(18, 20, 18, 24),
      decoration: BoxDecoration(
        color: const Color(0xFFFBFBF9),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.18), blurRadius: 18, offset: const Offset(0, 8))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final line in lines) _line(line, base),
        ],
      ),
    );
  }

  Widget _line(PrintedLine line, TextStyle base) {
    final align = switch (line.align) {
      PosAlign.left => TextAlign.left,
      PosAlign.center => TextAlign.center,
      PosAlign.right => TextAlign.right,
    };
    switch (line.kind) {
      case PrintedKind.text:
        return Text(
          line.text,
          textAlign: align,
          softWrap: false,
          overflow: TextOverflow.clip,
          style: base.copyWith(
            fontWeight: line.bold ? FontWeight.w700 : FontWeight.w400,
            fontSize: base.fontSize! * line.heightScale,
            letterSpacing: line.widthScale > 1 ? 2.0 * (line.widthScale - 1) : 0,
          ),
        );
      case PrintedKind.qr:
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(
            children: [
              const Icon(Icons.qr_code_2, size: 96, color: Color(0xFF1D2125)),
              Text(line.text, style: base.copyWith(fontSize: 9), textAlign: TextAlign.center),
            ],
          ),
        );
      case PrintedKind.barcode:
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Text('▌▍▌▌▍▍▌▍▌▌▍▌▍▍▌\n${line.text}', style: base, textAlign: TextAlign.center),
        );
      case PrintedKind.image:
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Text('[image ${line.text}]', style: base, textAlign: TextAlign.center),
        );
      case PrintedKind.cut:
        return const Padding(
          padding: EdgeInsets.only(top: 10),
          child: Row(
            children: [
              Icon(Icons.content_cut, size: 14, color: Color(0xFF9AA1A6)),
              SizedBox(width: 6),
              Expanded(child: Divider(color: Color(0xFF9AA1A6))),
            ],
          ),
        );
    }
  }
}
