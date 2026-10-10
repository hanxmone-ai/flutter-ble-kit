import 'dart:async';

import 'package:flutter/foundation.dart';

import '../core/adapter.dart';
import '../core/hex.dart';
import '../core/models.dart';
import '../core/parsers.dart';
import '../core/printer.dart';
import '../core/session.dart';
import '../core/uuids.dart';

enum LogKind { sent, received, info, error }

class LogEntry {
  LogEntry(this.kind, this.text, {DateTime? time}) : time = time ?? DateTime.now();

  final LogKind kind;
  final String text;
  final DateTime time;
}

/// State of the device screen: the session, live values and a log.
class DeviceController extends ChangeNotifier {
  DeviceController({
    required this.adapter,
    required this.device,
    Future<void> Function(Duration)? sleep,
  })  : _sleep = sleep,
        session = DeviceSession(adapter, device.id, sleep: sleep);

  static const int maxLogEntries = 200;

  final BleAdapter adapter;
  final DiscoveredDevice device;
  final DeviceSession session;
  final Future<void> Function(Duration)? _sleep;

  final List<LogEntry> log = [];
  HeartRate? heartRate;
  int? batteryLevel;
  String? manufacturer;
  String? model;

  /// 0 to 1 while printing, otherwise null.
  double? printProgress;
  String? error;

  final Map<String, StreamSubscription<List<int>>> _subscriptions = {};
  StreamSubscription<SessionState>? _stateSub;
  SessionState _previous = SessionState.idle;
  bool _disposed = false;

  SessionState get state => session.state;
  bool get ready => state == SessionState.ready;
  List<GattService> get services => session.services;
  int get mtu => session.connection?.mtu ?? 23;
  bool isSubscribed(GattCharacteristic c) => _subscriptions.containsKey(c.key);

  bool get isHeartRateMonitor =>
      findCharacteristic(services, KnownUuids.heartRate, KnownUuids.heartRateMeasurement) != null;

  GattCharacteristic? get printerCharacteristic =>
      BlePrinter.looksLikePrinter(services) ? BlePrinter.findDataCharacteristic(services) : null;

  Future<void> connect() async {
    _stateSub ??= session.states.listen(_onState);
    error = null;
    _info('Connecting to ${device.displayName}…');
    try {
      await session.open();
    } catch (e) {
      _fail('Connection failed', e);
    }
  }

  void _onState(SessionState s) {
    if (s == SessionState.reconnecting) {
      _cancelSubscriptions();
      _info('Link lost, reconnecting…');
    }
    if (s == SessionState.ready) {
      _info(_previous == SessionState.reconnecting
          ? 'Reconnected'
          : 'Connected · MTU $mtu · ${services.length} services');
      unawaited(_autoStart());
    }
    if (s == SessionState.failed && _previous == SessionState.reconnecting) {
      _info('Gave up reconnecting');
    }
    _previous = s;
    _notify();
  }

  /// Reads and subscribes to the values the dashboard shows.
  Future<void> _autoStart() async {
    final hr = findCharacteristic(services, KnownUuids.heartRate, KnownUuids.heartRateMeasurement);
    if (hr != null && !isSubscribed(hr)) await toggleNotify(hr);
    final battery = findCharacteristic(services, KnownUuids.battery, KnownUuids.batteryLevel);
    if (battery != null && battery.props.read) await read(battery);
    for (final uuid in [KnownUuids.manufacturerName, KnownUuids.modelNumber]) {
      final c = findCharacteristic(services, KnownUuids.deviceInformation, uuid);
      if (c != null && c.props.read) await read(c, quiet: true);
    }
  }

  Future<void> reconnect() async {
    if (state == SessionState.failed || state == SessionState.idle) await connect();
  }

  Future<void> read(GattCharacteristic c, {bool quiet = false}) async {
    final connection = session.connection;
    if (connection == null) return;
    try {
      final value = await connection.read(c);
      if (!quiet) _add(LogEntry(LogKind.received, '${c.displayName} ⇐ ${_describe(value)}'));
      _interpret(c, value);
    } catch (e) {
      _fail('Read ${c.displayName} failed', e);
    }
  }

  Future<void> write(GattCharacteristic c, List<int> value) async {
    final connection = session.connection;
    if (connection == null) return;
    try {
      final withoutResponse = !c.props.write && c.props.writeWithoutResponse;
      await connection.write(c, value, withoutResponse: withoutResponse);
      _add(LogEntry(LogKind.sent, '${c.displayName} ⇒ ${_describe(value)}'));
    } catch (e) {
      _fail('Write ${c.displayName} failed', e);
    }
  }

  Future<void> toggleNotify(GattCharacteristic c) async {
    final existing = _subscriptions.remove(c.key);
    if (existing != null) {
      unawaited(existing.cancel());
      _info('Notifications off · ${c.displayName}');
      return;
    }
    final connection = session.connection;
    if (connection == null) return;
    _subscriptions[c.key] = connection.subscribe(c).listen(
      (value) {
        _interpret(c, value);
        _add(LogEntry(LogKind.received, '${c.displayName} ⇐ ${_describe(value)}'));
      },
      onError: (Object e) => _fail('Notifications from ${c.displayName} failed', e),
    );
    _info('Notifications on · ${c.displayName}');
  }

  Future<void> printSample() async {
    final connection = session.connection;
    final c = printerCharacteristic;
    if (connection == null || c == null || printProgress != null) return;
    printProgress = 0;
    _notify();
    final receipt = sampleReceipt();
    try {
      await BlePrinter(connection, c, sleep: _sleep).printReceipt(
        receipt,
        onProgress: (sent, total) {
          printProgress = sent / total;
          _notify();
        },
      );
      _add(LogEntry(LogKind.sent, 'Printed ${receipt.bytes.length} bytes in chunks of '
          '${(mtu - 3).clamp(20, 180)}'));
    } catch (e) {
      _fail('Printing failed', e);
    } finally {
      printProgress = null;
      _notify();
    }
  }

  void _interpret(GattCharacteristic c, List<int> value) {
    try {
      if (c.matches(KnownUuids.heartRate, KnownUuids.heartRateMeasurement)) {
        heartRate = parseHeartRate(value);
      } else if (c.matches(KnownUuids.battery, KnownUuids.batteryLevel)) {
        batteryLevel = parseBatteryLevel(value);
      } else if (c.matches(KnownUuids.deviceInformation, KnownUuids.manufacturerName)) {
        manufacturer = parseUtf8String(value);
      } else if (c.matches(KnownUuids.deviceInformation, KnownUuids.modelNumber)) {
        model = parseUtf8String(value);
      }
    } on FormatException catch (e) {
      _add(LogEntry(LogKind.error, 'Could not parse ${c.displayName}: ${e.message}'));
    }
    _notify();
  }

  static String _describe(List<int> value) {
    final text = asciiOrNull(value);
    return text == null ? toHex(value) : '"$text"  (${toHex(value)})';
  }

  void _info(String text) => _add(LogEntry(LogKind.info, text));

  void _fail(String what, Object e) {
    final message = e is BleException ? e.message : e.toString();
    error = '$what: $message';
    _add(LogEntry(LogKind.error, error!));
  }

  void _add(LogEntry entry) {
    log.insert(0, entry);
    if (log.length > maxLogEntries) log.removeLast();
    _notify();
  }

  void _cancelSubscriptions() {
    for (final s in _subscriptions.values) {
      s.cancel();
    }
    _subscriptions.clear();
  }

  Future<void> disconnect() async {
    _cancelSubscriptions();
    await session.close();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _cancelSubscriptions();
    _stateSub?.cancel();
    session.close();
    super.dispose();
  }
}
