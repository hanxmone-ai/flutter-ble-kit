/// Parsers for standard GATT characteristics.
library;

import 'dart:convert';

/// One Heart Rate Measurement (characteristic 0x2A37).
class HeartRate {
  const HeartRate({
    required this.bpm,
    this.contactDetected,
    this.energyExpended,
    this.rrIntervalsMs = const [],
  });

  final int bpm;

  /// Whether the sensor touches skin; null when the sensor does not say.
  final bool? contactDetected;

  /// Kilojoules since the last reset, when reported.
  final int? energyExpended;

  /// Time between beats in milliseconds, when reported.
  final List<int> rrIntervalsMs;

  @override
  String toString() => 'HeartRate($bpm bpm)';
}

/// Parses a Heart Rate Measurement as defined in the Bluetooth Heart Rate
/// Service specification.
///
/// Flags (first byte): bit 0 = 16-bit heart rate, bits 1-2 = sensor contact,
/// bit 3 = energy expended present, bit 4 = RR intervals present.
HeartRate parseHeartRate(List<int> data) {
  if (data.isEmpty) throw const FormatException('Empty heart rate measurement');
  final flags = data[0];
  var i = 1;

  int need(int bytes) {
    if (i + bytes > data.length) {
      throw FormatException('Heart rate measurement too short', data, i);
    }
    final start = i;
    i += bytes;
    return start;
  }

  final int bpm;
  if (flags & 0x01 == 0) {
    bpm = data[need(1)];
  } else {
    final at = need(2);
    bpm = data[at] | data[at + 1] << 8;
  }

  final bool? contact = flags & 0x04 != 0 ? flags & 0x02 != 0 : null;

  int? energy;
  if (flags & 0x08 != 0) {
    final at = need(2);
    energy = data[at] | data[at + 1] << 8;
  }

  final rr = <int>[];
  if (flags & 0x10 != 0) {
    while (i + 1 < data.length) {
      final at = need(2);
      final raw = data[at] | data[at + 1] << 8; // units of 1/1024 s
      rr.add((raw * 1000 / 1024).round());
    }
  }

  return HeartRate(
    bpm: bpm,
    contactDetected: contact,
    energyExpended: energy,
    rrIntervalsMs: rr,
  );
}

/// Parses a Battery Level (characteristic 0x2A19): one byte, 0 to 100 percent.
int parseBatteryLevel(List<int> data) {
  if (data.isEmpty) throw const FormatException('Empty battery level');
  final level = data.first;
  if (level > 100) throw FormatException('Battery level above 100', data);
  return level;
}

/// Parses a UTF-8 string characteristic such as Manufacturer Name (0x2A29),
/// dropping trailing NUL bytes that some devices send.
String parseUtf8String(List<int> data) {
  var end = data.length;
  while (end > 0 && data[end - 1] == 0) {
    end--;
  }
  return utf8.decode(data.sublist(0, end), allowMalformed: true);
}
