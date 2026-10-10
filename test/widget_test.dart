import 'dart:math';

import 'package:ble_kit/app.dart';
import 'package:ble_kit/core/demo_adapter.dart';
import 'package:ble_kit/ui/widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> pumpFor(WidgetTester tester, Duration total, {Duration step = const Duration(milliseconds: 100)}) async {
  var elapsed = Duration.zero;
  while (elapsed < total) {
    await tester.pump(step);
    elapsed += step;
  }
}

void main() {
  late DemoDevices demo;

  setUp(() => demo = DemoDevices(random: Random(3), connectDelay: Duration.zero));

  Future<void> scan(WidgetTester tester) async {
    await tester.pumpWidget(BleKitApp(demo: demo, startInDemo: true));
    expect(find.text('Tap Scan to find Bluetooth LE devices nearby.'), findsOneWidget);
    await tester.tap(find.text('Scan'));
    await pumpFor(tester, const Duration(milliseconds: 600));
  }

  testWidgets('scanning lists the simulated devices', (tester) async {
    await scan(tester);
    expect(find.text('Pulse Band 7'), findsOneWidget);
    expect(find.text('MPT-58 Printer'), findsOneWidget);
    expect(find.text('Dev Board UART'), findsOneWidget);
    expect(find.text('Not connectable'), findsOneWidget);

    await tester.tap(find.text('Stop'));
    await pumpFor(tester, const Duration(milliseconds: 200));
    expect(find.text('Scan'), findsOneWidget);
  });

  testWidgets('heart-rate band shows live bpm', (tester) async {
    await scan(tester);
    await tester.tap(find.text('Pulse Band 7'));
    await pumpFor(tester, const Duration(milliseconds: 2500));

    expect(find.text('Connected'), findsOneWidget);
    final bpm = tester.widget<Text>(find.byKey(const Key('bpm')));
    expect(bpm.textSpan!.toPlainText(), matches(RegExp(r'^\d+  bpm$')));
    expect(find.text('Harborlane Labs'), findsOneWidget);

    await tester.pageBack();
    await pumpFor(tester, const Duration(milliseconds: 500));
  });

  testWidgets('printer prints the sample receipt', (tester) async {
    await scan(tester);
    await tester.tap(find.text('MPT-58 Printer'));
    await pumpFor(tester, const Duration(milliseconds: 500));

    await tester.tap(find.text('Print sample receipt'));
    await pumpFor(tester, const Duration(seconds: 1));
    expect(demo.printer.textLines, contains('HARBORLANE CAFE'));

    await tester.tap(find.text('View printout'));
    await pumpFor(tester, const Duration(milliseconds: 600));
    expect(find.byType(ReceiptView), findsOneWidget);
    expect(find.text('港湾咖啡 · BLE Kit demo'), findsOneWidget);
  });
}
