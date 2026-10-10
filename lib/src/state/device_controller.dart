import 'dart:async';

import 'package:escpos_kit/escpos_kit.dart';
import 'package:flutter/foundation.dart';

import '../ble/ble_adapter.dart';
import '../ble/uuids.dart';
import '../printing/ble_printer.dart';
import '../protocols/hex.dart';
import '../protocols/sensors.dart';

/// One line of the device log.
class LogEntry {
  LogEntry(this.message, {this.kind = LogKind.info}) : time = DateTime.now();
  final DateTime time;
  final String message;
  final LogKind kind;
}

enum LogKind { info, read, write, notify, error }

/// Connection, GATT browsing and live values for one device.
class DeviceController extends ChangeNotifier {
  DeviceController(this.adapter, this.device, {this.preferredMtu = 247});

  final BleAdapter adapter;
  final ScannedDevice device;
  final int preferredMtu;

  BleConnectionState connection = BleConnectionState.disconnected;
  List<GattService> services = const [];
  int mtu = 23;
  String? error;

  /// Last value seen per characteristic (read or notified).
  final Map<GattCharacteristic, List<int>> values = {};

  /// Recent heart rate readings, oldest first.
  final List<int> heartRateHistory = [];
  HeartRateMeasurement? heartRate;
  double? temperature;
  double? humidity;
  int? battery;

  /// Print progress 0..1 while a job is being sent, otherwise null.
  double? printProgress;

  final List<LogEntry> log = [];
  final Map<GattCharacteristic, StreamSubscription<List<int>>> _notifications = {};
  StreamSubscription<BleConnectionState>? _connectionSub;
  bool _disposed = false;

  static const int historyLength = 60;

  bool get isConnected => connection == BleConnectionState.connected;
  bool isSubscribed(GattCharacteristic c) => _notifications.containsKey(c);

  GattCharacteristic? get printerCharacteristic => findPrinterCharacteristic(services);

  GattCharacteristic? find(String service, String characteristic) {
    for (final s in services) {
      for (final c in s.characteristics) {
        if (c.matches(service, characteristic)) return c;
      }
    }
    return null;
  }

  void _log(String message, [LogKind kind = LogKind.info]) {
    log.add(LogEntry(message, kind: kind));
    if (log.length > 500) log.removeRange(0, log.length - 500);
  }

  void _changed() {
    if (!_disposed) notifyListeners();
  }

  Future<void> connect() async {
    if (_connectionSub != null) return;
    error = null;
    _log('Connecting to ${device.displayName} (${device.id})');
    _changed();
    final ready = Completer<void>();
    _connectionSub = adapter.connect(device.id).listen(
      (state) async {
        connection = state;
        _log('Connection: ${state.name}');
        _changed();
        if (state == BleConnectionState.connected && !ready.isCompleted) {
          ready.complete();
          await _afterConnect();
        } else if (state == BleConnectionState.disconnected) {
          _cleanUp();
        }
      },
      onError: (Object e) {
        error = '$e';
        _log('$e', LogKind.error);
        if (!ready.isCompleted) ready.complete();
        _changed();
      },
    );
    await ready.future;
  }

  Future<void> _afterConnect() async {
    try {
      mtu = await adapter.requestMtu(device.id, preferredMtu);
      _log('MTU $mtu');
    } catch (e) {
      _log('MTU request failed, using 23: $e', LogKind.error);
    }
    try {
      services = await adapter.discoverServices(device.id);
      final count = services.fold<int>(0, (n, s) => n + s.characteristics.length);
      _log('Found ${services.length} services, $count characteristics');
    } catch (e) {
      error = 'Service discovery failed: $e';
      _log(error!, LogKind.error);
    }
    _changed();
    await _readBasics();
  }

  /// Reads the values the overview shows, where the device has them.
  Future<void> _readBasics() async {
    final batteryChar = find(Gatt.batteryService, Gatt.batteryLevel);
    if (batteryChar != null && batteryChar.props.read) await read(batteryChar);
  }

  Future<void> disconnect() async {
    _log('Disconnecting');
    final sub = _connectionSub;
    _cleanUp();
    connection = BleConnectionState.disconnected;
    _changed();
    await sub?.cancel();
  }

  void _cleanUp() {
    for (final sub in _notifications.values) {
      sub.cancel();
    }
    _notifications.clear();
    _connectionSub = null;
  }

  Future<void> read(GattCharacteristic c) async {
    try {
      final value = await adapter.read(device.id, c);
      _store(c, value);
      _log('Read ${c.name}: ${_describe(value)}', LogKind.read);
    } catch (e) {
      _log('Read ${c.name} failed: $e', LogKind.error);
    }
    _changed();
  }

  Future<void> write(GattCharacteristic c, List<int> value, {bool? withResponse}) async {
    final response = withResponse ?? c.props.write;
    try {
      await adapter.write(device.id, c, value, withResponse: response);
      _log('Wrote ${c.name}: ${_describe(value)}', LogKind.write);
    } catch (e) {
      _log('Write ${c.name} failed: $e', LogKind.error);
    }
    _changed();
  }

  Future<void> toggleNotifications(GattCharacteristic c) async {
    final existing = _notifications.remove(c);
    if (existing != null) {
      await existing.cancel();
      _log('Stopped notifications from ${c.name}');
      _changed();
      return;
    }
    try {
      _notifications[c] = adapter.subscribe(device.id, c).listen(
        (value) {
          _store(c, value);
          _log('${c.name}: ${_describe(value)}', LogKind.notify);
          _changed();
        },
        onError: (Object e) {
          _notifications.remove(c);
          _log('Notifications from ${c.name} failed: $e', LogKind.error);
          _changed();
        },
      );
      _log('Subscribed to ${c.name}');
    } catch (e) {
      _log('Subscribe to ${c.name} failed: $e', LogKind.error);
    }
    _changed();
  }

  /// Prints [receipt] (the sample receipt by default) on this device.
  Future<void> printReceipt([Receipt? receipt]) async {
    final target = printerCharacteristic;
    if (target == null) {
      _log('No writable printer characteristic on this device', LogKind.error);
      _changed();
      return;
    }
    final job = receipt ?? sampleReceipt();
    final printer = BlePrinter(adapter, device.id, target, mtu: mtu);
    final bytes = job.bytes;
    _log('Printing ${bytes.length} bytes in ${(bytes.length / printer.chunkSize).ceil()} writes '
        'of up to ${printer.chunkSize} bytes');
    printProgress = 0;
    _changed();
    try {
      await printer.send(bytes, onProgress: (p) {
        printProgress = p;
        _changed();
      });
      _log('Print job sent', LogKind.write);
    } catch (e) {
      _log('Printing failed: $e', LogKind.error);
    }
    printProgress = null;
    _changed();
  }

  void _store(GattCharacteristic c, List<int> value) {
    values[c] = value;
    try {
      switch (shortUuid(c.uuid)) {
        case Gatt.heartRateMeasurement:
          final m = HeartRateMeasurement.parse(value);
          heartRate = m;
          heartRateHistory.add(m.bpm);
          if (heartRateHistory.length > historyLength) heartRateHistory.removeAt(0);
        case Gatt.batteryLevel:
          battery = parseBatteryLevel(value);
        case Gatt.temperature:
          temperature = parseTemperature(value);
        case Gatt.humidity:
          humidity = parseHumidity(value);
      }
    } on FormatException catch (e) {
      _log('Could not parse ${c.name}: ${e.message}', LogKind.error);
    }
  }

  static String _describe(List<int> value) {
    final text = asPrintableText(value);
    final hex = value.length > 24 ? '${toHex(value.sublist(0, 24))} …' : toHex(value);
    return text == null ? '[$hex]' : '"$text" [$hex]';
  }

  @override
  void dispose() {
    _disposed = true;
    _connectionSub?.cancel();
    _cleanUp();
    super.dispose();
  }
}
