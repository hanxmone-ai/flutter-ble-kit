import 'dart:typed_data';

import 'uuids.dart';

/// Whether Bluetooth can be used right now.
enum BleState {
  unknown,
  ready,
  poweredOff,
  unauthorized,
  locationServicesDisabled,
  unsupported,
}

/// Connection progress of one device.
enum BleConnectionState { connecting, connected, disconnecting, disconnected }

/// A device seen while scanning.
class ScannedDevice {
  const ScannedDevice({
    required this.id,
    required this.name,
    required this.rssi,
    this.serviceUuids = const [],
    this.manufacturerData,
    this.connectable = true,
  });

  /// MAC address on Android, a random UUID on iOS.
  final String id;

  /// Advertised name; empty when the device does not send one.
  final String name;

  /// Signal strength in dBm, roughly -30 (very close) to -100 (barely heard).
  final int rssi;

  /// Advertised service UUIDs, normalised to 128-bit form.
  final List<String> serviceUuids;

  /// Manufacturer-specific advertising data; the first two bytes are the
  /// company identifier (little endian).
  final Uint8List? manufacturerData;

  final bool connectable;

  String get displayName => name.isEmpty ? 'Unnamed device' : name;

  /// Bluetooth SIG company identifier from [manufacturerData], if present.
  int? get companyId {
    final data = manufacturerData;
    if (data == null || data.length < 2) return null;
    return data[0] | data[1] << 8;
  }

  ScannedDevice copyWith({int? rssi, String? name}) => ScannedDevice(
        id: id,
        name: name ?? this.name,
        rssi: rssi ?? this.rssi,
        serviceUuids: serviceUuids,
        manufacturerData: manufacturerData,
        connectable: connectable,
      );
}

/// What a characteristic supports.
class CharProps {
  const CharProps({
    this.read = false,
    this.write = false,
    this.writeWithoutResponse = false,
    this.notify = false,
    this.indicate = false,
  });

  final bool read;
  final bool write;
  final bool writeWithoutResponse;
  final bool notify;
  final bool indicate;

  bool get canWrite => write || writeWithoutResponse;
  bool get canSubscribe => notify || indicate;

  List<String> get labels => [
        if (read) 'read',
        if (write) 'write',
        if (writeWithoutResponse) 'write no resp',
        if (notify) 'notify',
        if (indicate) 'indicate',
      ];
}

/// A GATT characteristic, identified by its service and its own UUID.
class GattCharacteristic {
  GattCharacteristic({
    required String serviceUuid,
    required String uuid,
    required this.props,
  })  : serviceUuid = normalizeUuid(serviceUuid),
        uuid = normalizeUuid(uuid);

  final String serviceUuid;
  final String uuid;
  final CharProps props;

  String get name => uuidName(uuid) ?? shortUuid(uuid);

  bool matches(String service, String characteristic) =>
      sameUuid(service, serviceUuid) && sameUuid(characteristic, uuid);

  @override
  bool operator ==(Object other) =>
      other is GattCharacteristic &&
      other.serviceUuid == serviceUuid &&
      other.uuid == uuid;

  @override
  int get hashCode => Object.hash(serviceUuid, uuid);
}

/// A GATT service and its characteristics.
class GattService {
  GattService({required String uuid, required this.characteristics})
      : uuid = normalizeUuid(uuid);

  final String uuid;
  final List<GattCharacteristic> characteristics;

  String get name => uuidName(uuid) ?? shortUuid(uuid);
}

/// The Bluetooth operations the app needs, so screens and services can run
/// against a real radio or against simulated devices.
abstract class BleAdapter {
  /// Short label shown in the UI, such as "Bluetooth" or "Demo devices".
  String get label;

  Stream<BleState> get state;

  /// Asks for the runtime permissions scanning and connecting need.
  /// Returns false when the user refused.
  Future<bool> requestPermissions() async => true;

  /// Devices as they are seen; the same device is reported repeatedly with
  /// fresh RSSI values. Cancel the subscription to stop scanning.
  Stream<ScannedDevice> scan({List<String> services = const []});

  /// Connects and reports progress. Cancel the subscription to disconnect.
  Stream<BleConnectionState> connect(String deviceId);

  Future<List<GattService>> discoverServices(String deviceId);

  Future<List<int>> read(String deviceId, GattCharacteristic characteristic);

  Future<void> write(
    String deviceId,
    GattCharacteristic characteristic,
    List<int> value, {
    bool withResponse = true,
  });

  Stream<List<int>> subscribe(String deviceId, GattCharacteristic characteristic);

  /// Negotiates the ATT MTU; returns the value actually agreed.
  Future<int> requestMtu(String deviceId, int mtu);
}
