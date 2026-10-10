import 'dart:async';

import 'package:flutter/foundation.dart';

import '../core/adapter.dart';
import '../core/models.dart';
import '../core/scan_list.dart';

/// State of the scan screen.
class ScanController extends ChangeNotifier {
  ScanController(this.adapter, {this.scanDuration = const Duration(seconds: 12)}) {
    _statusSub = adapter.status.listen((s) {
      status = s;
      if (s != AdapterStatus.on && scanning) {
        scanning = false;
      }
      _notify();
    });
  }

  final BleAdapter adapter;
  final Duration scanDuration;

  AdapterStatus status = AdapterStatus.unknown;
  bool scanning = false;
  String? error;
  ScanFilter _filter = const ScanFilter();

  final ScanList _list = ScanList();
  StreamSubscription<AdapterStatus>? _statusSub;
  StreamSubscription<DiscoveredDevice>? _scanSub;
  bool _disposed = false;

  ScanFilter get filter => _filter;
  List<DiscoveredDevice> get devices => _list.devices(_filter);
  int get totalSeen => _list.length;

  set filter(ScanFilter value) {
    _filter = value;
    _notify();
  }

  Future<void> start() async {
    await stop();
    _list.clear();
    error = null;
    scanning = true;
    _notify();
    _scanSub = adapter.scan(timeout: scanDuration).listen(
      (device) {
        if (_list.add(device)) _notify();
      },
      onError: (Object e) {
        error = e is BleException ? e.message : e.toString();
        _notify();
      },
      onDone: () {
        _scanSub = null;
        scanning = false;
        _notify();
      },
    );
  }

  Future<void> stop() async {
    final sub = _scanSub;
    _scanSub = null;
    if (sub != null) await sub.cancel();
    if (scanning) {
      scanning = false;
      _notify();
    }
  }

  Future<void> turnOn() => adapter.turnOn();

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _scanSub?.cancel();
    _statusSub?.cancel();
    super.dispose();
  }
}
