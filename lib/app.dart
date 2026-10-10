import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'app/device_controller.dart';
import 'app/scan_controller.dart';
import 'ble/flutter_blue_plus_adapter.dart';
import 'core/adapter.dart';
import 'core/demo_adapter.dart';
import 'ui/device_page.dart';
import 'ui/home_page.dart';

/// Whether this platform has a Bluetooth stack the app can use.
bool get platformHasBle =>
    !kIsWeb &&
    (defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS ||
        defaultTargetPlatform == TargetPlatform.macOS);

class BleKitApp extends StatefulWidget {
  const BleKitApp({super.key, this.demo, this.realAdapter, this.startInDemo});

  /// Simulated devices; created on demand when null.
  final DemoDevices? demo;

  /// The real adapter; defaults to flutter_blue_plus when the platform has BLE.
  final BleAdapter? realAdapter;

  /// Start in demo mode. Defaults to true when there is no real adapter.
  final bool? startInDemo;

  @override
  State<BleKitApp> createState() => _BleKitAppState();
}

class _BleKitAppState extends State<BleKitApp> {
  late final DemoDevices _demo = widget.demo ?? DemoDevices();
  late final BleAdapter? _real = widget.realAdapter ?? (platformHasBle ? FlutterBluePlusAdapter() : null);
  late bool _demoMode = widget.startInDemo ?? _real == null;
  late ScanController _scan = ScanController(_adapter);

  BleAdapter get _adapter => _demoMode ? _demo.adapter : _real!;

  void _setDemoMode(bool on) {
    if (on == _demoMode) return;
    final old = _scan;
    setState(() {
      _demoMode = on;
      _scan = ScanController(_adapter);
    });
    old.stop().whenComplete(old.dispose);
  }

  @override
  void dispose() {
    _scan.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const seed = Color(0xFF0F766E);
    return MaterialApp(
      title: 'BLE Kit',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(colorSchemeSeed: seed, useMaterial3: true),
      darkTheme: ThemeData(colorSchemeSeed: seed, brightness: Brightness.dark, useMaterial3: true),
      home: HomePage(
        key: ValueKey(_demoMode),
        controller: _scan,
        demoMode: _demoMode,
        onDemoModeChanged: _real == null ? null : _setDemoMode,
        devicePageBuilder: (device) {
          final adapter = _adapter;
          return DevicePage(
            create: () => DeviceController(adapter: adapter, device: device),
            demoPrinter: _demoMode ? _demo.printer : null,
          );
        },
      ),
    );
  }
}
