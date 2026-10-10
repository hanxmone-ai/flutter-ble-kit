import 'package:flutter/material.dart';

import '../ble/ble_adapter.dart';
import '../ble/uuids.dart';
import '../state/scanner_controller.dart';
import 'device_page.dart';
import 'theme.dart';
import 'widgets/signal_bars.dart';

class ScannerPage extends StatefulWidget {
  const ScannerPage({
    super.key,
    required this.adapter,
    required this.demo,
    this.onDemoChanged,
  });

  final BleAdapter adapter;
  final bool demo;

  /// Null when switching is not possible (web, tests).
  final ValueChanged<bool>? onDemoChanged;

  @override
  State<ScannerPage> createState() => _ScannerPageState();
}

class _ScannerPageState extends State<ScannerPage> {
  late final ScannerController _scanner = ScannerController(widget.adapter);

  @override
  void initState() {
    super.initState();
    // Start right away: an empty list with a scan button is a wasted screen.
    WidgetsBinding.instance.addPostFrameCallback((_) => _scanner.start());
  }

  @override
  void dispose() {
    _scanner.dispose();
    super.dispose();
  }

  Future<void> _open(ScannedDevice device) async {
    await _scanner.stop();
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => DevicePage(adapter: widget.adapter, device: device)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListenableBuilder(
      listenable: _scanner,
      builder: (context, _) {
        final devices = _scanner.devices;
        return Scaffold(
          appBar: AppBar(
            title: const Text('BLE Kit'),
            actions: [
              if (widget.onDemoChanged != null)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: FilterChip(
                    label: const Text('Demo devices'),
                    selected: widget.demo,
                    onSelected: widget.onDemoChanged,
                  ),
                ),
            ],
          ),
          body: Column(
            children: [
              if (widget.demo)
                const _Banner(
                  icon: Icons.science_outlined,
                  text: 'Simulated devices: a heart rate strap, a receipt printer and a climate sensor. '
                      'Everything else in the app is the real code path.',
                ),
              if (_scanner.bleState != BleState.ready && _scanner.bleState != BleState.unknown)
                _Banner(icon: Icons.bluetooth_disabled, text: _stateMessage(_scanner.bleState), warning: true),
              if (_scanner.error != null)
                _Banner(icon: Icons.error_outline, text: _scanner.error!, warning: true),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        decoration: const InputDecoration(
                          prefixIcon: Icon(Icons.search),
                          hintText: 'Filter by name or address',
                          isDense: true,
                          border: OutlineInputBorder(),
                        ),
                        onChanged: _scanner.setQuery,
                      ),
                    ),
                    const SizedBox(width: 8),
                    FilterChip(
                      label: const Text('Named'),
                      selected: _scanner.namedOnly,
                      onSelected: _scanner.setNamedOnly,
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
                child: Row(
                  children: [
                    Text(
                      _scanner.scanning
                          ? 'Scanning… ${_scanner.totalSeen} found'
                          : '${_scanner.totalSeen} devices',
                      style: theme.textTheme.labelLarge,
                    ),
                    const Spacer(),
                    if (_scanner.scanning)
                      const SizedBox.square(dimension: 14, child: CircularProgressIndicator(strokeWidth: 2)),
                  ],
                ),
              ),
              Expanded(
                child: devices.isEmpty
                    ? _Empty(scanning: _scanner.scanning)
                    : ListView.separated(
                        padding: const EdgeInsets.fromLTRB(16, 4, 16, 96),
                        itemCount: devices.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 8),
                        itemBuilder: (context, i) => _DeviceTile(
                          device: devices[i],
                          onTap: devices[i].connectable ? () => _open(devices[i]) : null,
                        ),
                      ),
              ),
            ],
          ),
          floatingActionButton: FloatingActionButton.extended(
            onPressed: _scanner.scanning ? _scanner.stop : _scanner.start,
            icon: Icon(_scanner.scanning ? Icons.stop : Icons.radar),
            label: Text(_scanner.scanning ? 'Stop' : 'Scan'),
          ),
        );
      },
    );
  }

  static String _stateMessage(BleState state) => switch (state) {
        BleState.poweredOff => 'Bluetooth is off. Turn it on to scan.',
        BleState.unauthorized => 'The app is not allowed to use Bluetooth. Check the app permissions.',
        BleState.locationServicesDisabled => 'Location services are off. Android 11 and older need them to scan.',
        BleState.unsupported => 'This device has no Bluetooth LE. Try the demo devices.',
        BleState.ready || BleState.unknown => '',
      };
}

class _Banner extends StatelessWidget {
  const _Banner({required this.icon, required this.text, this.warning = false});

  final IconData icon;
  final String text;
  final bool warning;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final bg = warning ? scheme.errorContainer : scheme.secondaryContainer;
    final fg = warning ? scheme.onErrorContainer : scheme.onSecondaryContainer;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(16, 4, 16, 4),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(12)),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: fg),
          const SizedBox(width: 10),
          Expanded(child: Text(text, style: TextStyle(color: fg))),
        ],
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty({required this.scanning});
  final bool scanning;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.bluetooth_searching, size: 48, color: theme.colorScheme.outline),
            const SizedBox(height: 12),
            Text(
              scanning ? 'Looking for devices nearby…' : 'No devices. Tap Scan to look again.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyLarge,
            ),
          ],
        ),
      ),
    );
  }
}

class _DeviceTile extends StatelessWidget {
  const _DeviceTile({required this.device, this.onTap});

  final ScannedDevice device;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final services = [for (final s in device.serviceUuids) uuidName(s) ?? shortUuid(s)];
    final company = device.companyId;
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      device.displayName,
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: device.name.isEmpty ? theme.colorScheme.outline : null,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(device.id, style: AppTheme.monoStyle(context, size: 11.5)),
                    if (services.isNotEmpty || company != null) ...[
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        children: [
                          for (final s in services) Chip(label: Text(s)),
                          if (company != null)
                            Chip(label: Text('Company 0x${company.toRadixString(16).padLeft(4, '0').toUpperCase()}')),
                          if (!device.connectable) const Chip(label: Text('Not connectable')),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  SignalBars(rssi: device.rssi),
                  if (onTap != null) ...[
                    const SizedBox(height: 10),
                    Icon(Icons.chevron_right, color: theme.colorScheme.outline),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
