import 'dart:math';

import 'package:ble_kit/core/demo_adapter.dart';
import 'package:ble_kit/core/models.dart';
import 'package:ble_kit/core/printer.dart';
import 'package:ble_kit/core/session.dart';
import 'package:ble_kit/core/uuids.dart';
import 'package:ble_kit/core/virtual_printer.dart';
import 'package:escpos_kit/escpos_kit.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late DemoDevices demo;

  setUp(() => demo = DemoDevices(random: Random(1), connectDelay: Duration.zero));

  DeviceSession sessionFor(String id) =>
      DeviceSession(demo.adapter, id, sleep: (_) async {}, maxRetries: 2);

  group('demo adapter', () {
    test('scan finds every simulated device', () async {
      final seen = await demo.adapter.scan(timeout: const Duration(milliseconds: 50)).toList();
      final ids = seen.map((d) => d.id).toSet();
      expect(ids, containsAll([DemoDevices.heartRateId, DemoDevices.printerId, DemoDevices.uartId]));
    });

    test('scan can filter by service', () async {
      final seen = await demo.adapter
          .scan(withServices: [KnownUuids.heartRate], timeout: const Duration(milliseconds: 50))
          .toList();
      expect(seen.map((d) => d.id).toSet(), {DemoDevices.heartRateId});
    });

    test('scan fails when Bluetooth is off', () async {
      demo.adapter.setStatus(AdapterStatus.off);
      expect(demo.adapter.scan().toList(), throwsA(isA<BleException>()));
    });
  });

  group('session', () {
    test('connects, negotiates the MTU and discovers services', () async {
      final session = sessionFor(DemoDevices.heartRateId);
      await session.open();
      expect(session.state, SessionState.ready);
      expect(session.connection!.mtu, 185);
      expect(session.services.map((s) => shortUuid(s.uuid)), ['180d', '180f', '180a']);
      await session.close();
      expect(demo.adapter.isConnected(DemoDevices.heartRateId), isFalse);
    });

    test('reconnects after the link drops', () async {
      final session = sessionFor(DemoDevices.heartRateId);
      await session.open();
      final states = <SessionState>[];
      session.states.listen(states.add);
      final readyAgain = session.states.firstWhere((s) => s == SessionState.ready);
      demo.adapter.dropConnection(DemoDevices.heartRateId);
      await readyAgain.timeout(const Duration(seconds: 2));
      expect(states, [SessionState.reconnecting, SessionState.ready]);
      await session.close();
    });

    test('gives up after maxRetries', () async {
      final session = sessionFor(DemoDevices.heartRateId);
      await session.open();
      demo.adapter.peripherals.firstWhere((p) => p.id == DemoDevices.heartRateId).failConnect = true;
      final failed = session.states.firstWhere((s) => s == SessionState.failed);
      demo.adapter.dropConnection(DemoDevices.heartRateId);
      await failed.timeout(const Duration(seconds: 2));
      expect(session.lastError, isA<BleException>());
      await session.close();
    });

    test('a first connection failure is reported', () async {
      demo.adapter.peripherals.firstWhere((p) => p.id == DemoDevices.printerId).failConnect = true;
      final session = sessionFor(DemoDevices.printerId);
      await expectLater(session.open(), throwsA(isA<BleException>()));
      expect(session.state, SessionState.failed);
    });
  });

  group('GATT', () {
    test('reads, notifies and writes', () async {
      final session = sessionFor(DemoDevices.uartId);
      await session.open();
      final conn = session.connection!;
      final rx = findCharacteristic(session.services, DemoDevices.uartService, DemoDevices.uartRx)!;
      final tx = findCharacteristic(session.services, DemoDevices.uartService, DemoDevices.uartTx)!;
      final reply = conn.subscribe(tx).first;
      await conn.write(rx, 'ping'.codeUnits);
      expect(String.fromCharCodes(await reply), 'echo: ping');
      await session.close();
    });

    test('writes larger than the MTU are refused', () async {
      final session = sessionFor(DemoDevices.uartId);
      await session.open();
      final rx = findCharacteristic(session.services, DemoDevices.uartService, DemoDevices.uartRx)!;
      expect(session.connection!.write(rx, List.filled(200, 0)), throwsA(isA<BleException>()));
      await session.close();
    });
  });

  group('printing', () {
    test('finds the printer characteristic', () async {
      final session = sessionFor(DemoDevices.printerId);
      await session.open();
      expect(BlePrinter.looksLikePrinter(session.services), isTrue);
      final c = BlePrinter.findDataCharacteristic(session.services)!;
      expect(shortUuid(c.uuid), '2af1');
      await session.close();
    });

    test('prints a receipt in MTU-sized chunks and it reads back correctly', () async {
      final session = sessionFor(DemoDevices.printerId);
      await session.open();
      final c = BlePrinter.findDataCharacteristic(session.services)!;
      final receipt = sampleReceipt(now: DateTime(2026, 10, 10, 9, 30));
      await BlePrinter(session.connection!, c, sleep: (_) async {}).printReceipt(receipt);

      final peripheral = demo.adapter.peripherals.firstWhere((p) => p.id == DemoDevices.printerId);
      expect(peripheral.writes.every((w) => w.length <= 180), isTrue);
      expect(peripheral.writes.expand((w) => w).toList(), receipt.bytes);

      final text = demo.printer.textLines;
      expect(text, contains('HARBORLANE CAFE'));
      expect(text, contains('港湾咖啡 · BLE Kit demo'));
      expect(text, contains('2026-10-10 09:30'));
      expect(text, contains('TOTAL${' ' * 22}12.70'));
      expect(demo.printer.lines.any((l) => l.kind == PrintedKind.qr), isTrue);
      expect(demo.printer.lines.last.kind, PrintedKind.cut);
      await session.close();
    });
  });

  group('virtual printer', () {
    test('handles bytes split anywhere', () {
      final bytes = (Receipt(encoding: PrinterEncoding.gbk)
            ..text('中文 OK', bold: true, align: PosAlign.right)
            ..barcode('A1'))
          .bytes;
      final printer = VirtualPrinter();
      for (final b in bytes) {
        printer.feed([b]);
      }
      expect(printer.lines.first.text, '中文 OK');
      expect(printer.lines.first.bold, isTrue);
      expect(printer.lines.first.align, PosAlign.right);
      expect(printer.lines.last.kind, PrintedKind.barcode);
      expect(printer.lines.last.text, 'A1');
    });

    test('reads double-size text', () {
      final printer = VirtualPrinter()
        ..feed((Receipt(encoding: PrinterEncoding.ascii)..text('BIG', size: TextSize.large)).bytes);
      expect(printer.lines.single.widthScale, 2);
      expect(printer.lines.single.heightScale, 2);
    });
  });
}
