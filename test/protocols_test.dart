import 'package:flutter_ble_kit/flutter_ble_kit.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('heart rate measurement', () {
    test('8-bit value without extras', () {
      final m = HeartRateMeasurement.parse([0x00, 72]);
      expect(m.bpm, 72);
      expect(m.sensorContact, isNull);
      expect(m.energyExpended, isNull);
      expect(m.rrIntervalsMs, isEmpty);
    });

    test('16-bit value', () {
      expect(HeartRateMeasurement.parse([0x01, 0x2C, 0x01]).bpm, 300);
    });

    test('sensor contact supported and detected / not detected', () {
      expect(HeartRateMeasurement.parse([0x06, 60]).sensorContact, isTrue);
      expect(HeartRateMeasurement.parse([0x04, 60]).sensorContact, isFalse);
    });

    test('energy expended and RR intervals', () {
      // flags: energy (0x08) + RR (0x10); 80 bpm; 500 kJ; RR 1024 and 512 (1/1024 s).
      final m = HeartRateMeasurement.parse([0x18, 80, 0xF4, 0x01, 0x00, 0x04, 0x00, 0x02]);
      expect(m.bpm, 80);
      expect(m.energyExpended, 500);
      expect(m.rrIntervalsMs, [1000.0, 500.0]);
    });

    test('encode and parse round trip', () {
      final m = HeartRateMeasurement.parse(HeartRateMeasurement.encode(75, rrRaw: [819]));
      expect(m.bpm, 75);
      expect(m.sensorContact, isTrue);
      expect(m.rrIntervalsMs.single, closeTo(799.8, 0.1));
    });

    test('rejects short data', () {
      expect(() => HeartRateMeasurement.parse([0x00]), throwsFormatException);
      expect(() => HeartRateMeasurement.parse([0x01, 0x10]), throwsFormatException);
    });
  });

  group('environmental sensing', () {
    test('temperature is signed hundredths of a degree', () {
      expect(parseTemperature([0x60, 0x09]), 24.0); // 2400
      expect(parseTemperature([0x0C, 0xFE]), -5.0); // -500
      expect(parseTemperature(encodeTemperature(-12.34)), closeTo(-12.34, 0.001));
    });

    test('humidity is unsigned hundredths of a percent', () {
      expect(parseHumidity([0x10, 0x27]), 100.0); // 10000
    });

    test('battery level is clamped to 0-100', () {
      expect(parseBatteryLevel([87]), 87);
      expect(parseBatteryLevel([250]), 100);
    });
  });

  group('hex', () {
    test('formats bytes', () => expect(toHex([0x01, 0xAB, 0xFF]), '01 AB FF'));

    test('parses common spellings', () {
      expect(parseHex('01 ab ff'), [0x01, 0xAB, 0xFF]);
      expect(parseHex('01ABFF'), [0x01, 0xAB, 0xFF]);
      expect(parseHex('0x01, 0xAB'), [0x01, 0xAB]);
      expect(parseHex('  '), isEmpty);
    });

    test('rejects odd digits and non-hex', () {
      expect(() => parseHex('ABC'), throwsFormatException);
      expect(() => parseHex('zz'), throwsFormatException);
    });

    test('printable text', () {
      expect(asPrintableText('HR-200'.codeUnits), 'HR-200');
      expect(asPrintableText([0x00, 0x41]), isNull);
    });
  });

  group('uuids', () {
    test('normalises 16, 32 and 128-bit forms', () {
      const full = '0000180d-0000-1000-8000-00805f9b34fb';
      expect(normalizeUuid('180D'), full);
      expect(normalizeUuid('0000180d'), full);
      expect(normalizeUuid('{0000180D-0000-1000-8000-00805F9B34FB}'), full);
      expect(normalizeUuid('0000180d00001000800000805f9b34fb'), full);
    });

    test('short form only for the Bluetooth base UUID', () {
      expect(shortUuid('0000180d-0000-1000-8000-00805f9b34fb'), '180D');
      expect(shortUuid('E7810A71-73AE-499D-8C15-FAA9AEF0C3F2'), 'e7810a71-73ae-499d-8c15-faa9aef0c3f2');
    });

    test('names', () {
      expect(uuidName('2a37'), 'Heart Rate Measurement');
      expect(uuidName('1234'), isNull);
    });

    test('rejects garbage', () => expect(() => normalizeUuid('12345'), throwsFormatException));
  });
}
