import 'package:flutter/material.dart';

import '../app/device_controller.dart';
import '../core/hex.dart';
import '../core/models.dart';
import '../core/session.dart';
import '../core/uuids.dart';
import '../core/virtual_printer.dart';
import 'widgets.dart';

/// One device: live dashboard, GATT browser and a log.
class DevicePage extends StatefulWidget {
  const DevicePage({super.key, required this.create, this.demoPrinter});

  /// Creates the controller; called once.
  final DeviceController Function() create;

  /// In demo mode, the virtual printer the demo printer feeds.
  final VirtualPrinter? demoPrinter;

  @override
  State<DevicePage> createState() => _DevicePageState();
}

class _DevicePageState extends State<DevicePage> {
  late final DeviceController c = widget.create();

  @override
  void initState() {
    super.initState();
    widget.demoPrinter?.reset();
    c.connect();
  }

  @override
  void dispose() {
    c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: c,
      builder: (context, _) {
        final printer = c.printerCharacteristic;
        return Scaffold(
          appBar: AppBar(
            title: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(c.device.displayName),
                Text(
                  _stateLabel(c.state),
                  style: Theme.of(context).textTheme.labelMedium,
                ),
              ],
            ),
          ),
          body: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
            children: [
              _ConnectionCard(controller: c),
              if (c.isHeartRateMonitor) ...[
                const SizedBox(height: 12),
                _HeartRateCard(controller: c),
              ],
              if (printer != null) ...[
                const SizedBox(height: 12),
                _PrinterCard(controller: c, demoPrinter: widget.demoPrinter),
              ],
              if (c.services.isNotEmpty) ...[
                const SizedBox(height: 20),
                Text('Services', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                for (final s in c.services) _ServiceTile(service: s, controller: c),
              ],
              const SizedBox(height: 20),
              Text('Log', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              _LogView(entries: c.log),
            ],
          ),
        );
      },
    );
  }

  static String _stateLabel(SessionState s) => switch (s) {
        SessionState.idle => 'Not connected',
        SessionState.connecting => 'Connecting…',
        SessionState.ready => 'Connected',
        SessionState.reconnecting => 'Reconnecting…',
        SessionState.failed => 'Disconnected',
        SessionState.closed => 'Closed',
      };
}

class _ConnectionCard extends StatelessWidget {
  const _ConnectionCard({required this.controller});

  final DeviceController controller;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final text = Theme.of(context).textTheme;
    final busy = c.state == SessionState.connecting || c.state == SessionState.reconnecting;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                SignalBars(bars: c.device.signalBars),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(c.device.id, style: text.bodyMedium?.copyWith(fontFamily: 'monospace')),
                ),
                if (busy) const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
                if (c.state == SessionState.failed)
                  FilledButton.tonal(onPressed: c.reconnect, child: const Text('Retry')),
              ],
            ),
            if (c.ready) ...[
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  Tag('MTU ${c.mtu}'),
                  Tag('${c.services.length} services'),
                  if (c.manufacturer != null) Tag(c.manufacturer!),
                  if (c.model != null) Tag(c.model!),
                ],
              ),
            ],
            if (c.error != null) ...[
              const SizedBox(height: 12),
              Text(c.error!, style: text.bodySmall?.copyWith(color: Theme.of(context).colorScheme.error)),
            ],
          ],
        ),
      ),
    );
  }
}

class _HeartRateCard extends StatelessWidget {
  const _HeartRateCard({required this.controller});

  final DeviceController controller;

  @override
  Widget build(BuildContext context) {
    final hr = controller.heartRate;
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return Card(
      color: scheme.primaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          children: [
            Icon(Icons.favorite, color: scheme.error, size: 36),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(
                          text: hr == null ? '--' : '${hr.bpm}',
                          style: text.displaySmall?.copyWith(fontWeight: FontWeight.w600),
                        ),
                        TextSpan(text: '  bpm', style: text.titleMedium),
                      ],
                    ),
                    key: const Key('bpm'),
                  ),
                  if (hr != null && hr.rrIntervalsMs.isNotEmpty)
                    Text('RR ${hr.rrIntervalsMs.join(', ')} ms', style: text.bodySmall),
                ],
              ),
            ),
            if (controller.batteryLevel != null)
              Column(
                children: [
                  const Icon(Icons.battery_std),
                  Text('${controller.batteryLevel}%', style: text.labelLarge),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

class _PrinterCard extends StatelessWidget {
  const _PrinterCard({required this.controller, this.demoPrinter});

  final DeviceController controller;
  final VirtualPrinter? demoPrinter;

  @override
  Widget build(BuildContext context) {
    final progress = controller.printProgress;
    final text = Theme.of(context).textTheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.receipt_long),
                const SizedBox(width: 12),
                Expanded(child: Text('Receipt printer', style: text.titleMedium)),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Prints a sample receipt with escpos_kit: Chinese text, aligned columns and a QR code, '
              'sent in chunks that fit the MTU.',
              style: text.bodyMedium,
            ),
            const SizedBox(height: 12),
            if (progress != null) ...[
              LinearProgressIndicator(value: progress),
              const SizedBox(height: 12),
            ],
            Wrap(
              spacing: 8,
              children: [
                FilledButton.icon(
                  onPressed: controller.ready && progress == null ? controller.printSample : null,
                  icon: const Icon(Icons.print),
                  label: const Text('Print sample receipt'),
                ),
                if (demoPrinter != null)
                  OutlinedButton(
                    onPressed: demoPrinter!.lines.isEmpty ? null : () => _showPrintout(context, demoPrinter!),
                    child: const Text('View printout'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  static void _showPrintout(BuildContext context, VirtualPrinter printer) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF2B3439),
      builder: (_) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.85,
        builder: (context, scroll) => SingleChildScrollView(
          controller: scroll,
          padding: const EdgeInsets.symmetric(vertical: 24),
          child: Center(child: ReceiptView(lines: printer.lines)),
        ),
      ),
    );
  }
}

class _ServiceTile extends StatelessWidget {
  const _ServiceTile({required this.service, required this.controller});

  final GattService service;
  final DeviceController controller;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      clipBehavior: Clip.antiAlias,
      child: ExpansionTile(
        initiallyExpanded: !service.isStandard,
        title: Text(service.displayName),
        subtitle: Text(shortUuid(service.uuid), style: text.bodySmall?.copyWith(fontFamily: 'monospace')),
        children: [
          for (final ch in service.characteristics) _CharacteristicRow(characteristic: ch, controller: controller),
        ],
      ),
    );
  }
}

class _CharacteristicRow extends StatelessWidget {
  const _CharacteristicRow({required this.characteristic, required this.controller});

  final GattCharacteristic characteristic;
  final DeviceController controller;

  @override
  Widget build(BuildContext context) {
    final ch = characteristic;
    final p = ch.props;
    final text = Theme.of(context).textTheme;
    final enabled = controller.ready;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 8, 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(ch.displayName, style: text.bodyLarge),
                Text(shortUuid(ch.uuid), style: text.bodySmall?.copyWith(fontFamily: 'monospace')),
                const SizedBox(height: 4),
                Wrap(spacing: 4, runSpacing: 4, children: [for (final l in p.labels) Tag(l)]),
              ],
            ),
          ),
          if (p.read)
            IconButton(
              tooltip: 'Read',
              onPressed: enabled ? () => controller.read(ch) : null,
              icon: const Icon(Icons.download),
            ),
          if (p.canWrite)
            IconButton(
              tooltip: 'Write',
              onPressed: enabled ? () => _write(context) : null,
              icon: const Icon(Icons.upload),
            ),
          if (p.canSubscribe)
            IconButton(
              tooltip: controller.isSubscribed(ch) ? 'Stop notifications' : 'Notify',
              isSelected: controller.isSubscribed(ch),
              onPressed: enabled ? () => controller.toggleNotify(ch) : null,
              icon: const Icon(Icons.notifications_none),
              selectedIcon: const Icon(Icons.notifications_active),
            ),
        ],
      ),
    );
  }

  Future<void> _write(BuildContext context) async {
    final value = await showDialog<List<int>>(
      context: context,
      builder: (_) => _WriteDialog(name: characteristic.displayName),
    );
    if (value != null) await controller.write(characteristic, value);
  }
}

class _WriteDialog extends StatefulWidget {
  const _WriteDialog({required this.name});

  final String name;

  @override
  State<_WriteDialog> createState() => _WriteDialogState();
}

class _WriteDialogState extends State<_WriteDialog> {
  final _input = TextEditingController();
  bool _hex = false;
  String? _error;

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  void _submit() {
    try {
      final bytes = _hex ? parseHex(_input.text) : _input.text.codeUnits.map((u) => u & 0xFF).toList();
      if (bytes.isEmpty) throw const FormatException('Enter something to send');
      Navigator.of(context).pop(bytes);
    } on FormatException catch (e) {
      setState(() => _error = e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Write to ${widget.name}'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SegmentedButton<bool>(
            segments: const [
              ButtonSegment(value: false, label: Text('Text')),
              ButtonSegment(value: true, label: Text('Hex')),
            ],
            selected: {_hex},
            onSelectionChanged: (s) => setState(() {
              _hex = s.first;
              _error = null;
            }),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _input,
            autofocus: true,
            decoration: InputDecoration(
              hintText: _hex ? '01 02 a0' : 'hello',
              errorText: _error,
              border: const OutlineInputBorder(),
            ),
            style: const TextStyle(fontFamily: 'monospace'),
            onSubmitted: (_) => _submit(),
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
        FilledButton(onPressed: _submit, child: const Text('Send')),
      ],
    );
  }
}

class _LogView extends StatelessWidget {
  const _LogView({required this.entries});

  final List<LogEntry> entries;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    if (entries.isEmpty) {
      return Text('Nothing yet.', style: TextStyle(color: scheme.outline));
    }
    String two(int n) => n.toString().padLeft(2, '0');
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final e in entries.take(60))
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Text(
                '${two(e.time.hour)}:${two(e.time.minute)}:${two(e.time.second)}  ${e.text}',
                style: TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 12,
                  color: switch (e.kind) {
                    LogKind.error => scheme.error,
                    LogKind.sent => scheme.primary,
                    LogKind.received => scheme.onSurface,
                    LogKind.info => scheme.onSurfaceVariant,
                  },
                ),
              ),
            ),
        ],
      ),
    );
  }
}
