import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';
import 'package:permission_handler/permission_handler.dart';

import 'ble_adapter.dart';
import 'uuids.dart';

/// [BleAdapter] backed by flutter_reactive_ble (BSD-3-Clause, Android and iOS).
class ReactiveBleAdapter extends BleAdapter {
  ReactiveBleAdapter([FlutterReactiveBle? ble]) : _ble = ble ?? FlutterReactiveBle();

  final FlutterReactiveBle _ble;

  @override
  String get label => 'Bluetooth';

  @override
  Stream<BleState> get state => _ble.statusStream.map(_mapStatus);

  static BleState _mapStatus(BleStatus status) => switch (status) {
        BleStatus.ready => BleState.ready,
        BleStatus.poweredOff => BleState.poweredOff,
        BleStatus.unauthorized => BleState.unauthorized,
        BleStatus.locationServicesDisabled => BleState.locationServicesDisabled,
        BleStatus.unsupported => BleState.unsupported,
        BleStatus.unknown => BleState.unknown,
      };

  @override
  Future<bool> requestPermissions() async {
    if (!Platform.isAndroid) return true; // iOS asks on first use via Info.plist
    final results = await [
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      Permission.locationWhenInUse, // needed for scanning on Android 11 and older
    ].request();
    final scan = results[Permission.bluetoothScan];
    final connect = results[Permission.bluetoothConnect];
    final location = results[Permission.locationWhenInUse];
    // On Android 12+ the Bluetooth permissions are what matter; on older
    // versions they are granted automatically and location is required.
    final bluetoothOk = (scan?.isGranted ?? true) && (connect?.isGranted ?? true);
    return bluetoothOk || (location?.isGranted ?? false);
  }

  @override
  Stream<ScannedDevice> scan({List<String> services = const []}) => _ble
      .scanForDevices(
        withServices: [for (final s in services) Uuid.parse(normalizeUuid(s))],
        scanMode: ScanMode.lowLatency,
      )
      .map(
        (d) => ScannedDevice(
          id: d.id,
          name: d.name,
          rssi: d.rssi,
          serviceUuids: [for (final u in d.serviceUuids) normalizeUuid(u.toString())],
          manufacturerData: d.manufacturerData.isEmpty ? null : d.manufacturerData,
          connectable: d.connectable != Connectable.unavailable,
        ),
      );

  @override
  Stream<BleConnectionState> connect(String deviceId) => _ble
      .connectToDevice(id: deviceId, connectionTimeout: const Duration(seconds: 10))
      .map((update) {
    final failure = update.failure;
    if (failure != null && update.connectionState == DeviceConnectionState.disconnected) {
      throw StateError('Connection failed: ${failure.message}');
    }
    return switch (update.connectionState) {
      DeviceConnectionState.connecting => BleConnectionState.connecting,
      DeviceConnectionState.connected => BleConnectionState.connected,
      DeviceConnectionState.disconnecting => BleConnectionState.disconnecting,
      DeviceConnectionState.disconnected => BleConnectionState.disconnected,
    };
  });

  @override
  Future<List<GattService>> discoverServices(String deviceId) async {
    await _ble.discoverAllServices(deviceId);
    final services = await _ble.getDiscoveredServices(deviceId);
    return [
      for (final s in services)
        GattService(
          uuid: s.id.toString(),
          characteristics: [
            for (final c in s.characteristics)
              GattCharacteristic(
                serviceUuid: s.id.toString(),
                uuid: c.id.toString(),
                props: CharProps(
                  read: c.isReadable,
                  write: c.isWritableWithResponse,
                  writeWithoutResponse: c.isWritableWithoutResponse,
                  notify: c.isNotifiable,
                  indicate: c.isIndicatable,
                ),
              ),
          ],
        ),
    ];
  }

  QualifiedCharacteristic _qualified(String deviceId, GattCharacteristic c) =>
      QualifiedCharacteristic(
        deviceId: deviceId,
        serviceId: Uuid.parse(c.serviceUuid),
        characteristicId: Uuid.parse(c.uuid),
      );

  @override
  Future<List<int>> read(String deviceId, GattCharacteristic characteristic) =>
      _ble.readCharacteristic(_qualified(deviceId, characteristic));

  @override
  Future<void> write(
    String deviceId,
    GattCharacteristic characteristic,
    List<int> value, {
    bool withResponse = true,
  }) {
    final target = _qualified(deviceId, characteristic);
    return withResponse
        ? _ble.writeCharacteristicWithResponse(target, value: value)
        : _ble.writeCharacteristicWithoutResponse(target, value: value);
  }

  @override
  Stream<List<int>> subscribe(String deviceId, GattCharacteristic characteristic) =>
      _ble.subscribeToCharacteristic(_qualified(deviceId, characteristic));

  @override
  Future<int> requestMtu(String deviceId, int mtu) =>
      _ble.requestMtu(deviceId: deviceId, mtu: mtu);
}
