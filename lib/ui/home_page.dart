import 'package:flutter/material.dart';

import '../app/scan_controller.dart';
import '../core/models.dart';
import '../core/uuids.dart';
import 'widgets.dart';

/// Scan screen: lists nearby devices, strongest first.
class HomePage extends StatefulWidget {
  const HomePage({
    super.key,
    required this.controller,
    required this.demoMode,
    this.onDemoModeChanged,
    required this.devicePageBuilder,
  });

  final ScanController controller;
  final bool demoMode;

  /// Null when demo mode cannot be turned off (no Bluetooth on this platform).
  final ValueChanged<bool>? onDemoModeChanged;

  /// Builds the screen for a tapped device.
  final DevicePageBuilder devicePageBuilder;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _open(DiscoveredDevice device) async {
    final scan = widget.controller;
    await scan.stop(); // scanning while connecting slows both down on Android
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => widget.devicePageBuilder(device)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    return ListenableBuilder(
      listenable: c,
      builder: (context, _) {
        final devices = c.devices;
        final text = Theme.of(context).textTheme;
        return Scaffold(
          appBar: AppBar(
            title: const Text('BLE Kit'),
            actions: [
              if (widget.demoMode)
                const Padding(
                  padding: EdgeInsets.only(right: 4),
                  child: Tag('DEMO', highlight: true),
                ),
              if (widget.onDemoModeChanged != null)
                Row(
                  children: [
                    const Text('Demo'),
                    Switch(value: widget.demoMode, onChanged: widget.onDemoModeChanged),
                  ],
                ),
              const SizedBox(width: 8),
            ],
          ),
          body: Column(
            children: [
              if (c.status != AdapterStatus.on && c.status != AdapterStatus.unknown)
                _StatusBanner(status: c.status, onTurnOn: c.turnOn),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _search,
                        decoration: const InputDecoration(
                          prefixIcon: Icon(Icons.search),
                          hintText: 'Filter by name or id',
                          isDense: true,
                          border: OutlineInputBorder(),
                        ),
                        onChanged: (q) => c.filter = c.filter.copyWith(query: q),
                      ),
                    ),
                    const SizedBox(width: 8),
                    FilterChip(
                      label: const Text('Named'),
                      selected: c.filter.namedOnly,
                      onSelected: (v) => c.filter = c.filter.copyWith(namedOnly: v),
                    ),
                  ],
                ),
              ),
              if (c.scanning) const LinearProgressIndicator(minHeight: 2) else const SizedBox(height: 2),
              if (c.error != null)
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(c.error!, style: text.bodyMedium?.copyWith(color: Theme.of(context).colorScheme.error)),
                ),
              Expanded(
                child: devices.isEmpty
                    ? _Empty(scanning: c.scanning, seen: c.totalSeen)
                    : ListView.separated(
                        padding: const EdgeInsets.only(bottom: 96),
                        itemCount: devices.length,
                        separatorBuilder: (_, __) => const Divider(height: 1, indent: 72),
                        itemBuilder: (context, i) => _DeviceTile(device: devices[i], onTap: _open),
                      ),
              ),
            ],
          ),
          floatingActionButton: FloatingActionButton.extended(
            onPressed: c.status == AdapterStatus.on || c.status == AdapterStatus.unknown
                ? (c.scanning ? c.stop : c.start)
                : null,
            icon: Icon(c.scanning ? Icons.stop : Icons.bluetooth_searching),
            label: Text(c.scanning ? 'Stop' : 'Scan'),
          ),
        );
      },
    );
  }
}

typedef DevicePageBuilder = Widget Function(DiscoveredDevice device);

class _DeviceTile extends StatelessWidget {
  const _DeviceTile({required this.device, required this.onTap});

  final DiscoveredDevice device;
  final ValueChanged<DiscoveredDevice> onTap;

  @override
  Widget build(BuildContext context) {
    final services = [
      for (final s in device.serviceUuids)
        if (uuidName(s) case final name?) name,
    ];
    final text = Theme.of(context).textTheme;
    return ListTile(
      enabled: device.connectable,
      onTap: device.connectable ? () => onTap(device) : null,
      leading: SizedBox(width: 40, child: Center(child: SignalBars(bars: device.signalBars))),
      title: Text(device.displayName),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(device.id, style: text.bodySmall?.copyWith(fontFamily: 'monospace')),
          if (services.isNotEmpty || !device.connectable)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Wrap(
                spacing: 6,
                runSpacing: 4,
                children: [
                  for (final s in services) Tag(s, highlight: true),
                  if (!device.connectable) const Tag('Not connectable'),
                ],
              ),
            ),
        ],
      ),
      trailing: Text('${device.rssi} dBm', style: text.labelMedium),
    );
  }
}

class _StatusBanner extends StatelessWidget {
  const _StatusBanner({required this.status, required this.onTurnOn});

  final AdapterStatus status;
  final Future<void> Function() onTurnOn;

  @override
  Widget build(BuildContext context) {
    final message = switch (status) {
      AdapterStatus.off => 'Bluetooth is off.',
      AdapterStatus.unauthorized => 'Bluetooth permission was denied. Allow it in Settings.',
      AdapterStatus.unavailable => 'This device has no Bluetooth LE.',
      _ => 'Bluetooth is not ready.',
    };
    return MaterialBanner(
      content: Text(message),
      leading: const Icon(Icons.bluetooth_disabled),
      actions: [
        if (status == AdapterStatus.off) TextButton(onPressed: onTurnOn, child: const Text('Turn on')),
        if (status != AdapterStatus.off) const SizedBox.shrink(),
      ],
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty({required this.scanning, required this.seen});

  final bool scanning;
  final int seen;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final message = scanning
        ? 'Looking for devices…'
        : seen > 0
            ? 'No devices match the filter.'
            : 'Tap Scan to find Bluetooth LE devices nearby.';
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.bluetooth, size: 48, color: Theme.of(context).colorScheme.outline),
            const SizedBox(height: 12),
            Text(message, style: text.bodyLarge, textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}
