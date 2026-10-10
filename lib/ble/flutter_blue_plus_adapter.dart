import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import '../core/adapter.dart';
import '../core/models.dart';
import '../core/uuids.dart';

/// [BleAdapter] on real hardware, backed by flutter_blue_plus.
///
/// This is the only file that knows about the plugin; swapping to another
/// Bluetooth package means rewriting this file and nothing else.
class FlutterBluePlusAdapter implements BleAdapter {
  @override
  Stream<AdapterStatus> get status => FlutterBluePlus.adapterState.map(_mapAdapterState);

  static AdapterStatus _mapAdapterState(BluetoothAdapterState s) => switch (s) {
        BluetoothAdapterState.on => AdapterStatus.on,
        BluetoothAdapterState.off || BluetoothAdapterState.turningOff || BluetoothAdapterState.turningOn =>
          AdapterStatus.off,
        BluetoothAdapterState.unauthorized => AdapterStatus.unauthorized,
        BluetoothAdapterState.unavailable => AdapterStatus.unavailable,
        BluetoothAdapterState.unknown => AdapterStatus.unknown,
      };

  @override
  Future<void> turnOn() async {
    if (defaultTargetPlatform == TargetPlatform.android) {
      await FlutterBluePlus.turnOn();
    }
  }

  @override
  Stream<DiscoveredDevice> scan({
    List<String> withServices = const [],
    Duration timeout = const Duration(seconds: 10),
  }) {
    late StreamController<DiscoveredDevice> controller;
    StreamSubscription<List<ScanResult>>? results;
    StreamSubscription<bool>? scanning;

    Future<void> cleanUp() async {
      await results?.cancel();
      await scanning?.cancel();
      results = null;
      scanning = null;
    }

    controller = StreamController<DiscoveredDevice>(
      onListen: () async {
        results = FlutterBluePlus.onScanResults.listen(
          (list) {
            for (final r in list) {
              controller.add(_mapScanResult(r));
            }
          },
          onError: controller.addError,
        );
        try {
          await FlutterBluePlus.startScan(
            withServices: [for (final u in withServices) Guid(u)],
            timeout: timeout,
          );
        } catch (e, st) {
          controller.addError(BleException('Scan failed: $e'), st);
          await cleanUp();
          await controller.close();
          return;
        }
        // isScanning emits its current value first; close when it turns false.
        scanning = FlutterBluePlus.isScanning.where((on) => !on).listen((_) async {
          await cleanUp();
          await controller.close();
        });
      },
      onCancel: () async {
        await cleanUp();
        await FlutterBluePlus.stopScan();
      },
    );
    return controller.stream;
  }

  static DiscoveredDevice _mapScanResult(ScanResult r) {
    final adv = r.advertisementData;
    final name = adv.advName.isNotEmpty ? adv.advName : r.device.platformName;
    return DiscoveredDevice(
      id: r.device.remoteId.str,
      name: name,
      rssi: r.rssi,
      serviceUuids: [for (final g in adv.serviceUuids) g.str],
      manufacturerData: adv.manufacturerData,
      connectable: adv.connectable,
    );
  }

  @override
  Future<void> stopScan() => FlutterBluePlus.stopScan();

  @override
  Future<BleConnection> connect(
    String deviceId, {
    Duration timeout = const Duration(seconds: 15),
  }) async {
    final device = BluetoothDevice.fromId(deviceId);
    try {
      await device.connect(timeout: timeout, autoConnect: false);
    } on FlutterBluePlusException catch (e) {
      throw BleException('Could not connect: ${e.description ?? e.code}');
    } on TimeoutException {
      throw const BleException('Connection timed out');
    }
    return _FbpConnection(device);
  }
}

class _FbpConnection implements BleConnection {
  _FbpConnection(this._device);

  final BluetoothDevice _device;
  final Map<String, BluetoothCharacteristic> _characteristics = {};

  @override
  String get deviceId => _device.remoteId.str;

  @override
  Stream<ConnectionStatus> get status => _device.connectionState.map(
        (s) => s == BluetoothConnectionState.connected ? ConnectionStatus.connected : ConnectionStatus.disconnected,
      );

  @override
  int get mtu => _device.mtuNow;

  @override
  Future<int> requestMtu(int mtu) async {
    // iOS negotiates the MTU itself and does not allow requesting one.
    if (defaultTargetPlatform != TargetPlatform.android) return _device.mtuNow;
    return _device.requestMtu(mtu);
  }

  @override
  Future<List<GattService>> discoverServices() async {
    final services = await _device.discoverServices();
    _characteristics.clear();
    return [
      for (final s in services)
        GattService(
          uuid: s.serviceUuid.str,
          characteristics: [
            for (final c in s.characteristics) _register(s.serviceUuid.str, c),
          ],
        ),
    ];
  }

  GattCharacteristic _register(String serviceUuid, BluetoothCharacteristic c) {
    final p = c.properties;
    final mapped = GattCharacteristic(
      serviceUuid: serviceUuid,
      uuid: c.characteristicUuid.str,
      props: CharProps(
        read: p.read,
        write: p.write,
        writeWithoutResponse: p.writeWithoutResponse,
        notify: p.notify,
        indicate: p.indicate,
      ),
    );
    _characteristics[mapped.key] = c;
    return mapped;
  }

  BluetoothCharacteristic _find(GattCharacteristic c) {
    final found = _characteristics[c.key];
    if (found == null) {
      throw BleException('Unknown characteristic ${shortUuid(c.uuid)}; discover services first');
    }
    return found;
  }

  @override
  Future<List<int>> read(GattCharacteristic characteristic) => _guard(() => _find(characteristic).read());

  @override
  Future<void> write(
    GattCharacteristic characteristic,
    List<int> value, {
    bool withoutResponse = false,
  }) =>
      _guard(() => _find(characteristic).write(value, withoutResponse: withoutResponse));

  @override
  Stream<List<int>> subscribe(GattCharacteristic characteristic) {
    final c = _find(characteristic);
    late StreamController<List<int>> controller;
    StreamSubscription<List<int>>? values;
    controller = StreamController<List<int>>(
      onListen: () async {
        values = c.onValueReceived.listen(controller.add, onError: controller.addError);
        try {
          await c.setNotifyValue(true);
        } catch (e) {
          controller.addError(BleException('Could not subscribe: $e'));
        }
      },
      onCancel: () async {
        await values?.cancel();
        if (_device.isConnected) {
          try {
            await c.setNotifyValue(false);
          } catch (_) {
            // The device may have gone away meanwhile.
          }
        }
      },
    );
    return controller.stream;
  }

  @override
  Future<void> disconnect() => _device.disconnect();

  static Future<T> _guard<T>(Future<T> Function() action) async {
    try {
      return await action();
    } on FlutterBluePlusException catch (e) {
      throw BleException(e.description ?? 'Bluetooth error ${e.code}');
    }
  }
}
