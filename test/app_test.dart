import 'package:flutter_ble_kit/flutter_ble_kit.dart';
import 'package:flutter_ble_kit/src/ui/app.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('scan, open the printer and print a test receipt', (tester) async {
    final adapter = DemoBleAdapter(
      tick: const Duration(milliseconds: 200),
      scanInterval: const Duration(milliseconds: 100),
      connectDelay: const Duration(milliseconds: 50),
    );
    await tester.pumpWidget(BleKitApp(adapter: adapter));
    await tester.pump(const Duration(milliseconds: 250));

    expect(find.text('Pulse HR-200'), findsOneWidget);
    expect(find.text('Harborlane Printer 58'), findsOneWidget);
    expect(find.text('Unnamed device'), findsOneWidget);

    await tester.tap(find.text('Harborlane Printer 58'));
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(find.text('Receipt printer'), findsOneWidget);

    await tester.tap(find.text('Print test receipt'));
    for (var i = 0; i < 40; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(adapter.paper.value, isNotEmpty);
    expect(find.text('HARBORLANE CAFE'), findsOneWidget);

    // Leave the device page so timers and subscriptions are cleaned up.
    await tester.pageBack();
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('heart rate strap: overview card and GATT tab', (tester) async {
    final adapter = DemoBleAdapter(
      tick: const Duration(milliseconds: 200),
      scanInterval: const Duration(milliseconds: 100),
      connectDelay: const Duration(milliseconds: 50),
    );
    await tester.pumpWidget(BleKitApp(adapter: adapter));
    await tester.pump(const Duration(milliseconds: 250));
    await tester.tap(find.text('Pulse HR-200'));
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(find.text('Heart rate'), findsOneWidget);

    await tester.tap(find.text('Start live'));
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 200));
    }
    expect(find.text('bpm'), findsOneWidget);
    expect(find.text('--'), findsNothing);

    await tester.tap(find.text('GATT'));
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('Heart Rate Measurement'), findsOneWidget);
    expect(find.text('Battery Level'), findsOneWidget);

    await tester.pageBack();
    await tester.pump(const Duration(seconds: 1));
  });
}
