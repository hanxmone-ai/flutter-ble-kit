import 'package:flutter/material.dart';

import '../ble/adapter_factory.dart';
import '../ble/ble_adapter.dart';
import '../demo/demo_adapter.dart';
import 'scanner_page.dart';
import 'theme.dart';

class BleKitApp extends StatefulWidget {
  const BleKitApp({super.key, this.adapter});

  /// Fixed adapter, for tests. When null the app picks real Bluetooth where
  /// available and lets the user switch to demo devices.
  final BleAdapter? adapter;

  @override
  State<BleKitApp> createState() => _BleKitAppState();
}

class _BleKitAppState extends State<BleKitApp> {
  late BleAdapter _adapter = widget.adapter ?? createAdapter();

  bool get _demo => _adapter is DemoBleAdapter;

  void _setDemo(bool demo) {
    setState(() => _adapter = createAdapter(demo: demo));
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'BLE Kit',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      home: ScannerPage(
        key: ValueKey(_adapter),
        adapter: _adapter,
        demo: _demo,
        onDemoChanged: widget.adapter == null && hasRealBluetooth ? _setDemo : null,
      ),
    );
  }
}
