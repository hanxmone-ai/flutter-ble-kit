import 'package:flutter/material.dart';

/// Signal teal on graphite: an instrument-panel look that reads well in a
/// dark room next to hardware.
abstract final class AppTheme {
  static const Color brand = Color(0xFF0F766E);
  static const String mono = 'DejaVuSansMono';

  static ThemeData light() => _build(Brightness.light);
  static ThemeData dark() => _build(Brightness.dark);

  static ThemeData _build(Brightness brightness) {
    final scheme = ColorScheme.fromSeed(
      seedColor: brand,
      brightness: brightness,
      surface: brightness == Brightness.dark ? const Color(0xFF12171A) : const Color(0xFFF4F6F5),
    );
    final base = ThemeData(colorScheme: scheme, useMaterial3: true, brightness: brightness);
    return base.copyWith(
      scaffoldBackgroundColor: scheme.surface,
      appBarTheme: AppBarTheme(
        backgroundColor: scheme.surface,
        foregroundColor: scheme.onSurface,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: scheme.surfaceContainerLow,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.6)),
        ),
      ),
      chipTheme: base.chipTheme.copyWith(
        labelStyle: const TextStyle(fontSize: 12),
        visualDensity: VisualDensity.compact,
        side: BorderSide(color: scheme.outlineVariant),
      ),
    );
  }

  /// Monospace style for UUIDs, addresses and hex values.
  static TextStyle monoStyle(BuildContext context, {double size = 12.5, Color? color}) =>
      TextStyle(
        fontFamily: mono,
        fontSize: size,
        height: 1.35,
        color: color ?? Theme.of(context).colorScheme.onSurfaceVariant,
      );
}
