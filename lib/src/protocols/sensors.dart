/// Parsers for the standard Bluetooth SIG characteristics this app displays.
library;

/// Heart Rate Measurement (0x2A37).
class HeartRateMeasurement {
  const HeartRateMeasurement({
    required this.bpm,
    this.sensorContact,
    this.energyExpended,
    this.rrIntervalsMs = const [],
  });

  /// Parses the characteristic value as defined by the Heart Rate Service.
  ///
  /// Flags (first byte): bit 0 = 16-bit heart rate, bits 1-2 = sensor contact
  /// status, bit 3 = energy expended present, bit 4 = RR intervals present.
  factory HeartRateMeasurement.parse(List<int> data) {
    if (data.length < 2) throw const FormatException('Heart rate value too short');
    final flags = data[0];
    int i;
    final int bpm;
    if (flags & 0x01 != 0) {
      if (data.length < 3) throw const FormatException('Missing 16-bit heart rate');
      bpm = data[1] | data[2] << 8;
      i = 3;
    } else {
      bpm = data[1];
      i = 2;
    }
    final contactSupported = flags & 0x04 != 0;
    final contact = contactSupported ? flags & 0x02 != 0 : null;
    int? energy;
    if (flags & 0x08 != 0) {
      if (data.length < i + 2) throw const FormatException('Missing energy expended');
      energy = data[i] | data[i + 1] << 8;
      i += 2;
    }
    final rr = <double>[];
    if (flags & 0x10 != 0) {
      for (; i + 1 < data.length; i += 2) {
        // RR intervals are in units of 1/1024 second.
        rr.add((data[i] | data[i + 1] << 8) * 1000 / 1024);
      }
    }
    return HeartRateMeasurement(
      bpm: bpm,
      sensorContact: contact,
      energyExpended: energy,
      rrIntervalsMs: rr,
    );
  }

  final int bpm;

  /// Null when the sensor cannot tell whether it touches the skin.
  final bool? sensorContact;

  /// Kilojoules since the last reset, if the sensor reports it.
  final int? energyExpended;

  /// Time between beats in milliseconds.
  final List<double> rrIntervalsMs;

  /// Encodes a measurement with an 8-bit rate, contact detected and RR
  /// intervals; used by the demo devices.
  static List<int> encode(int bpm, {List<int> rrRaw = const []}) => [
        0x06 | (rrRaw.isEmpty ? 0 : 0x10),
        bpm & 0xFF,
        for (final r in rrRaw) ...[r & 0xFF, r >> 8 & 0xFF],
      ];
}

/// Battery Level (0x2A19): one byte, 0-100 %.
int parseBatteryLevel(List<int> data) {
  if (data.isEmpty) throw const FormatException('Empty battery level');
  return data[0].clamp(0, 100);
}

/// Temperature (0x2A6E): signed 16-bit little endian, in 0.01 °C.
double parseTemperature(List<int> data) {
  if (data.length < 2) throw const FormatException('Temperature value too short');
  final raw = data[0] | data[1] << 8;
  final signed = raw >= 0x8000 ? raw - 0x10000 : raw;
  return signed / 100;
}

/// Encodes a temperature in °C as 0x2A6E bytes.
List<int> encodeTemperature(double celsius) {
  final raw = (celsius * 100).round() & 0xFFFF;
  return [raw & 0xFF, raw >> 8];
}

/// Humidity (0x2A6F): unsigned 16-bit little endian, in 0.01 %.
double parseHumidity(List<int> data) {
  if (data.length < 2) throw const FormatException('Humidity value too short');
  return (data[0] | data[1] << 8) / 100;
}
