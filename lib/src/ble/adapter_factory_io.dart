import 'dart:io' show Platform;

import '../demo/demo_adapter.dart';
import 'ble_adapter.dart';
import 'reactive_ble_adapter.dart';

/// Whether this platform has a Bluetooth plugin implementation.
bool get hasRealBluetooth => Platform.isAndroid || Platform.isIOS;

/// The adapter to start with: real Bluetooth on phones, demo devices elsewhere.
BleAdapter createAdapter({bool demo = false}) =>
    demo || !hasRealBluetooth ? DemoBleAdapter() : ReactiveBleAdapter();
