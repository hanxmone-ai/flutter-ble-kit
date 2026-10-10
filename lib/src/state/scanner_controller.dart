import 'dart:async';

import 'package:flutter/foundation.dart';

import '../ble/ble_adapter.dart';

/// Scans for devices and keeps the list the scanner screen shows.
class ScannerController extends ChangeNotifier {
  ScannerController(this.adapter, {this.scanDuration = const Duration(seconds: 15)}) {
    _stateSub = adapter.state.listen((s) {
      bleState = s;
      if (s != BleState.ready && scanning) stop();
      notifyListeners();
    });
  }

  final BleAdapter adapter;

  /// Scanning stops by itself after this long, to save battery.
  final Duration scanDuration;

  BleState bleState = BleState.unknown;
  bool scanning = false;
  String? error;

  /// Hide devices that do not advertise a name.
  bool namedOnly = false;

  /// Filters by name or id, case-insensitive.
  String query = '';

  final Map<String, ScannedDevice> _devices = {};
  StreamSubscription<BleState>? _stateSub;
  StreamSubscription<ScannedDevice>? _scanSub;
  Timer? _stopTimer;

  /// Devices to show, strongest signal first.
  List<ScannedDevice> get devices {
    final q = query.trim().toLowerCase();
    final list = _devices.values.where((d) {
      if (namedOnly && d.name.isEmpty) return false;
      if (q.isEmpty) return true;
      return d.name.toLowerCase().contains(q) || d.id.toLowerCase().contains(q);
    }).toList()
      ..sort((a, b) => b.rssi.compareTo(a.rssi));
    return list;
  }

  int get totalSeen => _devices.length;

  Future<void> start() async {
    if (scanning) return;
    error = null;
    if (!await adapter.requestPermissions()) {
      error = 'Bluetooth permission was refused. Allow "Nearby devices" in the app settings.';
      notifyListeners();
      return;
    }
    _devices.clear();
    scanning = true;
    notifyListeners();
    _scanSub = adapter.scan().listen(
      (d) {
        _devices[d.id] = d;
        notifyListeners();
      },
      onError: (Object e) {
        error = 'Scan failed: $e';
        stop();
      },
    );
    _stopTimer = Timer(scanDuration, stop);
  }

  Future<void> stop() async {
    _stopTimer?.cancel();
    _stopTimer = null;
    final sub = _scanSub;
    _scanSub = null;
    if (scanning) {
      scanning = false;
      notifyListeners();
    }
    await sub?.cancel();
  }

  void setNamedOnly(bool value) {
    namedOnly = value;
    notifyListeners();
  }

  void setQuery(String value) {
    query = value;
    notifyListeners();
  }

  @override
  void dispose() {
    _stopTimer?.cancel();
    _scanSub?.cancel();
    _stateSub?.cancel();
    super.dispose();
  }
}
