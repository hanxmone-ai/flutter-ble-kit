/// Bluetooth UUID helpers.
///
/// Bluetooth SIG UUIDs are often written in their 16-bit short form ("180d").
/// Platforms report them differently (short or full 128-bit, upper or lower
/// case), so every comparison in this kit goes through [normalizeUuid].
library;

const String _baseSuffix = '-0000-1000-8000-00805f9b34fb';
final RegExp _short16 = RegExp(r'^[0-9a-f]{4}$');
final RegExp _short32 = RegExp(r'^[0-9a-f]{8}$');
final RegExp _full = RegExp(
  r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
);

/// The full, lower-case 128-bit form of [uuid].
///
/// Throws a [FormatException] for anything that is not a Bluetooth UUID.
String normalizeUuid(String uuid) {
  var u = uuid.trim().toLowerCase();
  if (u.startsWith('0x')) u = u.substring(2);
  if (_short16.hasMatch(u)) return '0000$u$_baseSuffix';
  if (_short32.hasMatch(u)) return '$u$_baseSuffix';
  if (_full.hasMatch(u)) return u;
  throw FormatException('Not a Bluetooth UUID', uuid);
}

/// The 16-bit form ("180d") for UUIDs on the Bluetooth base, otherwise the
/// full form.
String shortUuid(String uuid) {
  final n = normalizeUuid(uuid);
  if (n.startsWith('0000') && n.endsWith(_baseSuffix)) return n.substring(4, 8);
  return n;
}

/// Whether [a] and [b] are the same UUID, whatever form they are written in.
bool sameUuid(String a, String b) => normalizeUuid(a) == normalizeUuid(b);

/// UUIDs this kit has special handling for.
abstract final class KnownUuids {
  static const String genericAccess = '1800';
  static const String genericAttribute = '1801';
  static const String deviceInformation = '180a';
  static const String heartRate = '180d';
  static const String heartRateMeasurement = '2a37';
  static const String battery = '180f';
  static const String batteryLevel = '2a19';
  static const String manufacturerName = '2a29';
  static const String modelNumber = '2a24';

  /// Used by many low-cost Bluetooth receipt printers.
  static const String printerService = '18f0';
  static const String printerWrite = '2af1';

  /// Another common printer service (also seen on label printers).
  static const String printerServiceAlt = 'e7810a71-73ae-499d-8c15-faa9aef0c3f2';
}

const Map<String, String> _names = {
  '1800': 'Generic Access',
  '1801': 'Generic Attribute',
  '180a': 'Device Information',
  '180d': 'Heart Rate',
  '180f': 'Battery',
  '1810': 'Blood Pressure',
  '1816': 'Cycling Speed and Cadence',
  '181a': 'Environmental Sensing',
  '18f0': 'Receipt Printer',
  '2a00': 'Device Name',
  '2a01': 'Appearance',
  '2a19': 'Battery Level',
  '2a24': 'Model Number',
  '2a25': 'Serial Number',
  '2a26': 'Firmware Revision',
  '2a27': 'Hardware Revision',
  '2a29': 'Manufacturer Name',
  '2a37': 'Heart Rate Measurement',
  '2a38': 'Body Sensor Location',
  '2a39': 'Heart Rate Control Point',
  '2af1': 'Printer Data',
  'e7810a71-73ae-499d-8c15-faa9aef0c3f2': 'Receipt Printer',
};

/// A human-readable name for well-known UUIDs, or null.
String? uuidName(String uuid) {
  try {
    return _names[shortUuid(uuid)];
  } on FormatException {
    return null;
  }
}
