/// Bluetooth UUID helpers and names for common services and characteristics.
library;

const String _baseSuffix = '-0000-1000-8000-00805f9b34fb';

/// Normalises a UUID to lower-case 128-bit form.
///
/// Accepts 16-bit (`180d`), 32-bit (`0000180d`) and 128-bit forms, with or
/// without dashes and braces.
String normalizeUuid(String uuid) {
  final hex = uuid.replaceAll(RegExp(r'[{}\-\s]'), '').toLowerCase();
  if (!RegExp(r'^[0-9a-f]+$').hasMatch(hex)) {
    throw FormatException('Not a UUID', uuid);
  }
  switch (hex.length) {
    case 4:
      return '0000$hex$_baseSuffix';
    case 8:
      return '$hex$_baseSuffix';
    case 32:
      return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
          '${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
    default:
      throw FormatException('A UUID has 4, 8 or 32 hex digits', uuid);
  }
}

/// The short form (`180D`) of a UUID built on the Bluetooth base UUID, or
/// the full lower-case form for vendor UUIDs.
String shortUuid(String uuid) {
  final full = normalizeUuid(uuid);
  if (full.endsWith(_baseSuffix) && full.startsWith('0000')) {
    return full.substring(4, 8).toUpperCase();
  }
  return full;
}

/// Whether two UUIDs are the same, whatever form they are written in.
bool sameUuid(String a, String b) => normalizeUuid(a) == normalizeUuid(b);

/// Human-readable name of a well-known service or characteristic, or null.
String? uuidName(String uuid) => _names[shortUuid(uuid)];

/// Assigned numbers used by this app.
abstract final class Gatt {
  static const String heartRateService = '180D';
  static const String heartRateMeasurement = '2A37';
  static const String batteryService = '180F';
  static const String batteryLevel = '2A19';
  static const String deviceInformation = '180A';
  static const String manufacturerName = '2A29';
  static const String modelNumber = '2A24';
  static const String firmwareRevision = '2A26';
  static const String environmentalSensing = '181A';
  static const String temperature = '2A6E';
  static const String humidity = '2A6F';
}

const Map<String, String> _names = {
  '1800': 'Generic Access',
  '1801': 'Generic Attribute',
  '180A': 'Device Information',
  '180D': 'Heart Rate',
  '180F': 'Battery',
  '181A': 'Environmental Sensing',
  '18F0': 'Printer (serial)',
  '2A00': 'Device Name',
  '2A01': 'Appearance',
  '2A19': 'Battery Level',
  '2A24': 'Model Number',
  '2A26': 'Firmware Revision',
  '2A29': 'Manufacturer Name',
  '2A37': 'Heart Rate Measurement',
  '2A38': 'Body Sensor Location',
  '2A39': 'Heart Rate Control Point',
  '2A6E': 'Temperature',
  '2A6F': 'Humidity',
  '2AF0': 'Printer notify',
  '2AF1': 'Printer write',
  'e7810a71-73ae-499d-8c15-faa9aef0c3f2': 'Printer (vendor)',
  'bef8d6c9-9c21-4c9e-b632-bd58c1009f9f': 'Printer write (vendor)',
  '49535343-fe7d-4ae5-8fa9-9fafd205e455': 'Transparent UART',
  '49535343-8841-43f4-a8d4-ecbe34729bb3': 'UART write',
  '49535343-1e4d-4bd9-ba61-23c647249616': 'UART notify',
};
