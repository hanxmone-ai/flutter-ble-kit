import 'package:ble_kit/core/chunked_writer.dart';
import 'package:ble_kit/core/hex.dart';
import 'package:ble_kit/core/models.dart';
import 'package:ble_kit/core/parsers.dart';
import 'package:ble_kit/core/scan_list.dart';
import 'package:ble_kit/core/uuids.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('UUIDs', () {
    test('expands 16-bit UUIDs onto the Bluetooth base', () {
      expect(normalizeUuid('180D'), '0000180d-0000-1000-8000-00805f9b34fb');
      expect(normalizeUuid('0x2a37'), '00002a37-0000-1000-8000-00805f9b34fb');
    });
    test('keeps 128-bit UUIDs, lower-cased', () {
      expect(
        normalizeUuid('6E400001-B5A3-F393-E0A9-E50E24DCCA9E'),
        '6e400001-b5a3-f393-e0a9-e50e24dcca9e',
      );
    });
    test('short form and comparison', () {
      expect(shortUuid('0000180d-0000-1000-8000-00805f9b34fb'), '180d');
      expect(sameUuid('180d', '0000180D-0000-1000-8000-00805F9B34FB'), isTrue);
      expect(sameUuid('180d', '180f'), isFalse);
    });
    test('names', () {
      expect(uuidName('2a37'), 'Heart Rate Measurement');
      expect(uuidName('not a uuid'), isNull);
    });
    test('rejects garbage', () {
      expect(() => normalizeUuid('xyz'), throwsFormatException);
    });
  });

  group('hex', () {
    test('formats', () => expect(toHex([0, 10, 255]), '00 0a ff'));
    test('parses common spellings', () {
      expect(parseHex('0a 1b ff'), [0x0a, 0x1b, 0xff]);
      expect(parseHex('0x0A,0x1B'), [0x0a, 0x1b]);
      expect(parseHex('0a1bff'), [0x0a, 0x1b, 0xff]);
      expect(parseHex('0A:1B'), [0x0a, 0x1b]);
    });
    test('rejects odd lengths and non-hex', () {
      expect(() => parseHex('abc'), throwsFormatException);
      expect(() => parseHex('zz'), throwsFormatException);
    });
    test('shows printable bytes as text', () {
      expect(asciiOrNull('hi'.codeUnits), 'hi');
      expect(asciiOrNull([0, 1]), isNull);
    });
  });

  group('heart rate', () {
    test('8-bit value without extras', () {
      final hr = parseHeartRate([0x00, 72]);
      expect(hr.bpm, 72);
      expect(hr.contactDetected, isNull);
      expect(hr.rrIntervalsMs, isEmpty);
    });
    test('16-bit value', () => expect(parseHeartRate([0x01, 0x2C, 0x01]).bpm, 300));
    test('sensor contact', () {
      expect(parseHeartRate([0x06, 60]).contactDetected, isTrue);
      expect(parseHeartRate([0x04, 60]).contactDetected, isFalse);
    });
    test('energy expended and RR intervals', () {
      // flags: energy + RR; bpm 64; energy 0x0102; RR 1024/1024 s and 512/1024 s.
      final hr = parseHeartRate([0x18, 64, 0x02, 0x01, 0x00, 0x04, 0x00, 0x02]);
      expect(hr.energyExpended, 0x0102);
      expect(hr.rrIntervalsMs, [1000, 500]);
    });
    test('truncated data is an error', () {
      expect(() => parseHeartRate([]), throwsFormatException);
      expect(() => parseHeartRate([0x01, 0x2C]), throwsFormatException);
    });
    test('battery and strings', () {
      expect(parseBatteryLevel([87]), 87);
      expect(() => parseBatteryLevel([101]), throwsFormatException);
      expect(parseUtf8String([0x48, 0x69, 0, 0]), 'Hi');
    });
  });

  group('ScanList', () {
    DiscoveredDevice d(String id, int rssi, {String name = 'x'}) =>
        DiscoveredDevice(id: id, name: name, rssi: rssi);

    test('one entry per device, strongest first', () {
      final list = ScanList()
        ..add(d('a', -80))
        ..add(d('b', -50))
        ..add(d('a', -80));
      expect(list.length, 2);
      expect(list.devices().map((e) => e.id), ['b', 'a']);
    });
    test('smooths RSSI', () {
      final list = ScanList()
        ..add(d('a', -80))
        ..add(d('a', -40));
      expect(list['a']!.rssi, -68); // -80 * 0.7 + -40 * 0.3
    });
    test('keeps a name once seen', () {
      final list = ScanList()
        ..add(d('a', -60, name: 'Band'))
        ..add(d('a', -60, name: ''));
      expect(list['a']!.name, 'Band');
    });
    test('filters', () {
      final list = ScanList()
        ..add(d('a', -60, name: 'Pulse Band'))
        ..add(d('b', -95, name: 'Far'))
        ..add(d('c', -60, name: ''));
      expect(list.devices(const ScanFilter(namedOnly: true)).map((e) => e.id), ['a', 'b']);
      expect(list.devices(const ScanFilter(minRssi: -90)).map((e) => e.id), ['a', 'c']);
      expect(list.devices(const ScanFilter(query: 'pulse')).map((e) => e.id), ['a']);
    });
    test('forgets stale devices', () {
      var now = DateTime(2026);
      final list = ScanList(clock: () => now)..add(d('a', -60));
      now = now.add(const Duration(seconds: 20));
      list.add(d('b', -60));
      expect(list.prune(), isTrue);
      expect(list.devices().map((e) => e.id), ['b']);
    });
    test('signal bars', () {
      expect(d('a', -50).signalBars, 4);
      expect(d('a', -70).signalBars, 2);
      expect(d('a', -99).signalBars, 0);
    });
  });

  group('ChunkedWriter', () {
    test('chunk size follows the MTU', () {
      expect(ChunkedWriter.chunkSizeForMtu(23), 20);
      expect(ChunkedWriter.chunkSizeForMtu(185), 182);
      expect(ChunkedWriter.chunkSizeForMtu(517), 512);
      expect(ChunkedWriter.chunkSizeForMtu(185, max: 100), 100);
    });
    test('splits, reports progress and pauses between chunks only', () async {
      final chunks = <List<int>>[];
      final progress = <int>[];
      var pauses = 0;
      final writer = ChunkedWriter(
        write: (c) async => chunks.add(c),
        chunkSize: 4,
        pause: const Duration(milliseconds: 5),
        sleep: (_) async => pauses++,
      );
      await writer.writeAll(List.generate(10, (i) => i), onProgress: (sent, _) => progress.add(sent));
      expect(chunks, [
        [0, 1, 2, 3],
        [4, 5, 6, 7],
        [8, 9],
      ]);
      expect(progress, [4, 8, 10]);
      expect(pauses, 2);
    });
  });
}
