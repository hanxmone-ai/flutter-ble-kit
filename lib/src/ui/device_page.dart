import 'package:flutter/material.dart';

import '../ble/ble_adapter.dart';
import '../ble/uuids.dart';
import '../demo/demo_adapter.dart';
import '../protocols/hex.dart';
import '../state/device_controller.dart';
import 'theme.dart';
import 'widgets/receipt_preview.dart';
import 'widgets/sparkline.dart';

class DevicePage extends StatefulWidget {
  const DevicePage({super.key, required this.adapter, required this.device});

  final BleAdapter adapter;
  final ScannedDevice device;

  @override
  State<DevicePage> createState() => _DevicePageState();
}

class _DevicePageState extends State<DevicePage> {
  late final DeviceController _device = DeviceController(widget.adapter, widget.device);

  @override
  void initState() {
    super.initState();
    _device.connect();
  }

  @override
  void dispose() {
    _device.dispose(); // also drops the connection
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _device,
      builder: (context, _) => DefaultTabController(
        length: 3,
        child: Scaffold(
          appBar: AppBar(
            title: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(widget.device.displayName),
                Text(widget.device.id, style: AppTheme.monoStyle(context, size: 11)),
              ],
            ),
            actions: [
              Padding(
                padding: const EdgeInsets.only(right: 12),
                child: _ConnectionChip(
                  state: _device.connection,
                  onConnect: _device.connect,
                  onDisconnect: _device.disconnect,
                ),
              ),
            ],
            bottom: const TabBar(
              tabs: [Tab(text: 'Overview'), Tab(text: 'GATT'), Tab(text: 'Log')],
            ),
          ),
          body: TabBarView(
            children: [
              _Overview(device: _device, adapter: widget.adapter),
              _GattTab(device: _device),
              _LogTab(device: _device),
            ],
          ),
        ),
      ),
    );
  }
}

class _ConnectionChip extends StatelessWidget {
  const _ConnectionChip({required this.state, required this.onConnect, required this.onDisconnect});

  final BleConnectionState state;
  final VoidCallback onConnect;
  final VoidCallback onDisconnect;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return switch (state) {
      BleConnectionState.connected => ActionChip(
          avatar: Icon(Icons.link, size: 16, color: scheme.primary),
          label: const Text('Disconnect'),
          onPressed: onDisconnect,
        ),
      BleConnectionState.connecting || BleConnectionState.disconnecting => const Chip(
          avatar: SizedBox.square(dimension: 14, child: CircularProgressIndicator(strokeWidth: 2)),
          label: Text('Connecting'),
        ),
      BleConnectionState.disconnected => ActionChip(
          avatar: const Icon(Icons.link_off, size: 16),
          label: const Text('Connect'),
          onPressed: onConnect,
        ),
    };
  }
}

// ---------------------------------------------------------------- overview

class _Overview extends StatelessWidget {
  const _Overview({required this.device, required this.adapter});

  final DeviceController device;
  final BleAdapter adapter;

  @override
  Widget build(BuildContext context) {
    final cards = <Widget>[
      if (device.error != null) _ErrorCard(message: device.error!),
      if (device.connection == BleConnectionState.connecting)
        const _InfoCard(icon: Icons.bluetooth_searching, text: 'Connecting and discovering services…'),
      if (device.isConnected) ...[
        _SummaryCard(device: device),
        if (device.find(Gatt.heartRateService, Gatt.heartRateMeasurement) != null) _HeartRateCard(device: device),
        if (device.find(Gatt.environmentalSensing, Gatt.temperature) != null) _ClimateCard(device: device),
        if (device.printerCharacteristic != null) _PrinterCard(device: device, adapter: adapter),
        if (device.services.isNotEmpty &&
            device.find(Gatt.heartRateService, Gatt.heartRateMeasurement) == null &&
            device.find(Gatt.environmentalSensing, Gatt.temperature) == null &&
            device.printerCharacteristic == null)
          const _InfoCard(
            icon: Icons.account_tree_outlined,
            text: 'No dashboard for this device type. Open the GATT tab to read, write and subscribe.',
          ),
      ],
      if (device.connection == BleConnectionState.disconnected && device.error == null)
        const _InfoCard(icon: Icons.link_off, text: 'Disconnected.'),
    ];
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: cards.length,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (_, i) => cards[i],
    );
  }
}

class _InfoCard extends StatelessWidget {
  const _InfoCard({required this.icon, required this.text});
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Card(
        child: ListTile(leading: Icon(icon), title: Text(text)),
      );
}

class _ErrorCard extends StatelessWidget {
  const _ErrorCard({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      color: scheme.errorContainer,
      child: ListTile(
        leading: Icon(Icons.error_outline, color: scheme.onErrorContainer),
        title: Text(message, style: TextStyle(color: scheme.onErrorContainer)),
      ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.device});
  final DeviceController device;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final characteristics = device.services.fold<int>(0, (n, s) => n + s.characteristics.length);
    Widget stat(String label, String value) => Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: theme.textTheme.labelMedium?.copyWith(color: theme.colorScheme.outline)),
              const SizedBox(height: 2),
              Text(value, style: theme.textTheme.titleLarge),
            ],
          ),
        );
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            stat('Services', '${device.services.length}'),
            stat('Characteristics', '$characteristics'),
            stat('MTU', '${device.mtu}'),
            stat('Battery', device.battery == null ? '–' : '${device.battery}%'),
          ],
        ),
      ),
    );
  }
}

class _HeartRateCard extends StatelessWidget {
  const _HeartRateCard({required this.device});
  final DeviceController device;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c = device.find(Gatt.heartRateService, Gatt.heartRateMeasurement)!;
    final live = device.isSubscribed(c);
    final hr = device.heartRate;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.favorite, color: theme.colorScheme.error, size: 20),
                const SizedBox(width: 8),
                Text('Heart rate', style: theme.textTheme.titleMedium),
                const Spacer(),
                FilledButton.tonal(
                  onPressed: () => device.toggleNotifications(c),
                  child: Text(live ? 'Stop' : 'Start live'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text(hr == null ? '--' : '${hr.bpm}', style: theme.textTheme.displayMedium),
                const SizedBox(width: 6),
                Text('bpm', style: theme.textTheme.titleMedium),
                const Spacer(),
                if (hr != null && hr.rrIntervalsMs.isNotEmpty)
                  Text(
                    'RR ${hr.rrIntervalsMs.last.round()} ms',
                    style: AppTheme.monoStyle(context, size: 13),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Sparkline(values: device.heartRateHistory, capacity: DeviceController.historyLength),
            if (hr?.sensorContact == false)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text('No skin contact', style: TextStyle(color: theme.colorScheme.error)),
              ),
          ],
        ),
      ),
    );
  }
}

class _ClimateCard extends StatelessWidget {
  const _ClimateCard({required this.device});
  final DeviceController device;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final temp = device.find(Gatt.environmentalSensing, Gatt.temperature)!;
    final humidity = device.find(Gatt.environmentalSensing, Gatt.humidity);
    final live = device.isSubscribed(temp);
    Widget reading(String label, String value) => Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: theme.textTheme.labelMedium),
              Text(value, style: theme.textTheme.headlineMedium),
            ],
          ),
        );
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.thermostat, size: 20),
                const SizedBox(width: 8),
                Text('Climate', style: theme.textTheme.titleMedium),
                const Spacer(),
                FilledButton.tonal(
                  onPressed: () {
                    device.toggleNotifications(temp);
                    if (humidity != null && device.isSubscribed(humidity) == live) {
                      device.toggleNotifications(humidity);
                    }
                  },
                  child: Text(live ? 'Stop' : 'Start live'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                reading('Temperature', device.temperature == null ? '--' : '${device.temperature!.toStringAsFixed(2)} °C'),
                reading('Humidity', device.humidity == null ? '--' : '${device.humidity!.toStringAsFixed(1)} %'),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _PrinterCard extends StatelessWidget {
  const _PrinterCard({required this.device, required this.adapter});
  final DeviceController device;
  final BleAdapter adapter;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final target = device.printerCharacteristic!;
    final progress = device.printProgress;
    final a = adapter;
    final demo = a is DemoBleAdapter ? a : null;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.receipt_long, size: 20),
                const SizedBox(width: 8),
                Text('Receipt printer', style: theme.textTheme.titleMedium),
                const Spacer(),
                FilledButton.icon(
                  onPressed: progress == null
                      ? () {
                          demo?.clearPaper();
                          device.printReceipt();
                        }
                      : null,
                  icon: const Icon(Icons.print, size: 18),
                  label: const Text('Print test receipt'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Writes ESC/POS from escpos_kit to ${target.name} '
              '(${shortUuid(target.uuid)}) in ${device.mtu - 3}-byte chunks'
              '${target.props.writeWithoutResponse ? ', without response' : ''}.',
              style: theme.textTheme.bodySmall,
            ),
            if (progress != null) ...[
              const SizedBox(height: 12),
              LinearProgressIndicator(value: progress),
            ],
            if (demo != null) ...[
              const SizedBox(height: 16),
              ValueListenableBuilder<List<int>>(
                valueListenable: demo.paper,
                builder: (context, bytes, _) => bytes.isEmpty
                    ? Text(
                        'The simulated printer shows what it receives here.',
                        style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline),
                      )
                    : ReceiptPreview(bytes: bytes),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// -------------------------------------------------------------------- GATT

class _GattTab extends StatelessWidget {
  const _GattTab({required this.device});
  final DeviceController device;

  @override
  Widget build(BuildContext context) {
    if (!device.isConnected) {
      return const Center(child: Text('Connect to browse services.'));
    }
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        for (final service in device.services)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Card(
              clipBehavior: Clip.antiAlias,
              child: ExpansionTile(
                initiallyExpanded: true,
                title: Text(service.name),
                subtitle: Text(shortUuid(service.uuid), style: AppTheme.monoStyle(context, size: 11)),
                children: [
                  for (final c in service.characteristics) _CharacteristicTile(device: device, characteristic: c),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

class _CharacteristicTile extends StatelessWidget {
  const _CharacteristicTile({required this.device, required this.characteristic});

  final DeviceController device;
  final GattCharacteristic characteristic;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c = characteristic;
    final value = device.values[c];
    final text = value == null ? null : asPrintableText(value);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 8, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Divider(height: 1),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(c.name, style: theme.textTheme.titleSmall),
                    Text(shortUuid(c.uuid), style: AppTheme.monoStyle(context, size: 11)),
                  ],
                ),
              ),
              if (c.props.read)
                IconButton(
                  tooltip: 'Read',
                  icon: const Icon(Icons.download_outlined),
                  onPressed: () => device.read(c),
                ),
              if (c.props.canWrite)
                IconButton(
                  tooltip: 'Write',
                  icon: const Icon(Icons.upload_outlined),
                  onPressed: () => _showWriteDialog(context),
                ),
              if (c.props.canSubscribe)
                IconButton(
                  tooltip: device.isSubscribed(c) ? 'Stop notifications' : 'Subscribe',
                  isSelected: device.isSubscribed(c),
                  icon: const Icon(Icons.notifications_none),
                  selectedIcon: const Icon(Icons.notifications_active),
                  onPressed: () => device.toggleNotifications(c),
                ),
            ],
          ),
          Wrap(
            spacing: 4,
            children: [for (final p in c.props.labels) Chip(label: Text(p))],
          ),
          if (value != null) ...[
            const SizedBox(height: 6),
            SelectableText(
              text == null ? toHex(value) : '"$text"\n${toHex(value)}',
              style: AppTheme.monoStyle(context, color: theme.colorScheme.onSurface),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _showWriteDialog(BuildContext context) async {
    final result = await showDialog<(List<int>, bool)>(
      context: context,
      builder: (_) => _WriteDialog(characteristic: characteristic),
    );
    if (result != null) await device.write(characteristic, result.$1, withResponse: result.$2);
  }
}

class _WriteDialog extends StatefulWidget {
  const _WriteDialog({required this.characteristic});
  final GattCharacteristic characteristic;

  @override
  State<_WriteDialog> createState() => _WriteDialogState();
}

class _WriteDialogState extends State<_WriteDialog> {
  final _controller = TextEditingController();
  bool _hex = true;
  late bool _withResponse = widget.characteristic.props.write;
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    try {
      final bytes = _hex ? parseHex(_controller.text) : _controller.text.codeUnits;
      if (bytes.isEmpty) {
        setState(() => _error = 'Enter a value');
        return;
      }
      Navigator.of(context).pop((bytes, _withResponse));
    } on FormatException catch (e) {
      setState(() => _error = e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final props = widget.characteristic.props;
    return AlertDialog(
      title: Text('Write ${widget.characteristic.name}'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SegmentedButton<bool>(
            segments: const [
              ButtonSegment(value: true, label: Text('Hex')),
              ButtonSegment(value: false, label: Text('Text')),
            ],
            selected: {_hex},
            onSelectionChanged: (s) => setState(() => _hex = s.first),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _controller,
            autofocus: true,
            style: AppTheme.monoStyle(context, size: 14, color: Theme.of(context).colorScheme.onSurface),
            decoration: InputDecoration(
              hintText: _hex ? '01 A0 FF' : 'Hello',
              errorText: _error,
              border: const OutlineInputBorder(),
            ),
            onSubmitted: (_) => _submit(),
          ),
          if (props.write && props.writeWithoutResponse)
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              value: _withResponse,
              onChanged: (v) => setState(() => _withResponse = v ?? true),
              title: const Text('Wait for response'),
            ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
        FilledButton(onPressed: _submit, child: const Text('Write')),
      ],
    );
  }
}

// --------------------------------------------------------------------- log

class _LogTab extends StatelessWidget {
  const _LogTab({required this.device});
  final DeviceController device;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final entries = device.log.reversed.toList();
    Color colorFor(LogKind kind) => switch (kind) {
          LogKind.error => scheme.error,
          LogKind.write => scheme.tertiary,
          LogKind.notify => scheme.primary,
          LogKind.read => scheme.secondary,
          LogKind.info => scheme.onSurfaceVariant,
        };
    String two(int n) => n.toString().padLeft(2, '0');
    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: entries.length,
      itemBuilder: (context, i) {
        final e = entries[i];
        final t = e.time;
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Text.rich(
            TextSpan(children: [
              TextSpan(
                text: '${two(t.hour)}:${two(t.minute)}:${two(t.second)}  ',
                style: AppTheme.monoStyle(context, size: 11.5, color: scheme.outline),
              ),
              TextSpan(
                text: e.message,
                style: AppTheme.monoStyle(context, size: 11.5, color: colorFor(e.kind)),
              ),
            ]),
          ),
        );
      },
    );
  }
}
