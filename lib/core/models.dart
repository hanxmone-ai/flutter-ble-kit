import 'uuids.dart';

/// State of the phone's Bluetooth radio.
enum AdapterStatus { unknown, unavailable, unauthorized, off, on }

/// State of a connection to one peripheral.
enum ConnectionStatus { connecting, connected, disconnecting, disconnected }

/// One advertisement seen while scanning.
class DiscoveredDevice {
  const DiscoveredDevice({
    required this.id,
    required this.name,
    required this.rssi,
    this.serviceUuids = const [],
    this.manufacturerData = const {},
    this.connectable = true,
  });

  /// Platform id: a MAC address on Android, a UUID on iOS and macOS.
  final String id;

  /// Advertised name; empty when the device does not send one.
  final String name;

  /// Signal strength in dBm, usually between -100 (far) and -30 (very close).
  final int rssi;

  final List<String> serviceUuids;

  /// Manufacturer-specific data keyed by company id.
  final Map<int, List<int>> manufacturerData;

  final bool connectable;

  String get displayName => name.isEmpty ? 'Unnamed device' : name;

  /// Whether the advertisement lists [uuid] among its services.
  bool advertises(String uuid) => serviceUuids.any((s) => sameUuid(s, uuid));

  /// Signal strength as 0 to 4 bars.
  int get signalBars {
    if (rssi >= -55) return 4;
    if (rssi >= -67) return 3;
    if (rssi >= -78) return 2;
    if (rssi >= -90) return 1;
    return 0;
  }

  DiscoveredDevice copyWith({int? rssi, String? name}) => DiscoveredDevice(
        id: id,
        name: name ?? this.name,
        rssi: rssi ?? this.rssi,
        serviceUuids: serviceUuids,
        manufacturerData: manufacturerData,
        connectable: connectable,
      );

  @override
  String toString() => 'DiscoveredDevice($id, "$name", $rssi dBm)';
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

  /// Short labels such as "read, notify", for display.
  List<String> get labels => [
        if (read) 'read',
        if (write) 'write',
        if (writeWithoutResponse) 'write no response',
        if (notify) 'notify',
        if (indicate) 'indicate',
      ];
}

class GattCharacteristic {
  const GattCharacteristic({
    required this.serviceUuid,
    required this.uuid,
    required this.props,
  });

  final String serviceUuid;
  final String uuid;
  final CharProps props;

  /// A key that identifies this characteristic within one device.
  String get key => '${normalizeUuid(serviceUuid)}/${normalizeUuid(uuid)}';

  String get displayName => uuidName(uuid) ?? shortUuid(uuid);

  bool matches(String service, String characteristic) =>
      sameUuid(serviceUuid, service) && sameUuid(uuid, characteristic);

  @override
  String toString() => 'GattCharacteristic(${shortUuid(serviceUuid)}/${shortUuid(uuid)})';
}

class GattService {
  const GattService({required this.uuid, required this.characteristics});

  final String uuid;
  final List<GattCharacteristic> characteristics;

  String get displayName => uuidName(uuid) ?? shortUuid(uuid);

  bool get isStandard {
    final s = shortUuid(uuid);
    return s == KnownUuids.genericAccess || s == KnownUuids.genericAttribute;
  }
}

/// A Bluetooth operation failed.
class BleException implements Exception {
  const BleException(this.message);

  final String message;

  @override
  String toString() => 'BleException: $message';
}

/// Finds a characteristic in [services], or null.
GattCharacteristic? findCharacteristic(
  List<GattService> services,
  String service,
  String characteristic,
) {
  for (final s in services) {
    for (final c in s.characteristics) {
      if (c.matches(service, characteristic)) return c;
    }
  }
  return null;
}
