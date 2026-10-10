import 'package:flutter/material.dart';

/// Four bars showing signal strength, plus the dBm value.
class SignalBars extends StatelessWidget {
  const SignalBars({super.key, required this.rssi});

  final int rssi;

  /// 0-4 bars: -55 dBm or better is excellent, below -90 is barely usable.
  static int barsFor(int rssi) => switch (rssi) {
        >= -55 => 4,
        >= -67 => 3,
        >= -78 => 2,
        >= -90 => 1,
        _ => 0,
      };

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final bars = barsFor(rssi);
    return Semantics(
      label: 'Signal $rssi dBm, $bars of 4 bars',
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (var i = 0; i < 4; i++)
            Container(
              width: 4,
              height: 6.0 + i * 4,
              margin: const EdgeInsets.only(right: 2),
              decoration: BoxDecoration(
                color: i < bars ? scheme.primary : scheme.outlineVariant,
                borderRadius: BorderRadius.circular(1.5),
              ),
            ),
          const SizedBox(width: 6),
          Text('$rssi', style: Theme.of(context).textTheme.labelSmall),
        ],
      ),
    );
  }
}
