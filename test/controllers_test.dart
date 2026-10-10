import 'package:flutter_ble_kit/flutter_ble_kit.dart';
import 'package:flutter_test/flutter_test.dart';

DemoBleAdapter fastAdapter() => DemoBleAdapter(
      tick: const Duration(milliseconds: 10),
      scanInterval: const Duration(milliseconds: 5),
      connectDelay: const Duration(milliseconds: 3),
    );

Future<void> waitFor(bool Function() condition, {Duration timeout = const Duration(seconds: 3)}) async {
  final end = DateTime.now().add(timeout);
  while (!condition()) {
    if (DateTime.now().isAfter(end)) fail('condition not met within $timeout');
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
}

ScannedDevice demoDevice(String id) => ScannedDevice(id: id, name: id, rssi: -60);

void main() {
  group('ScannerController', () {
    test('finds the demo devices, strongest first, and stops', () async {
      final scanner = ScannerController(fastAdapter());
      await scanner.start();
      await waitFor(() => scanner.totalSeen == 4);
      final rssi = [for (final d in scanner.devices) d.rssi];
      expect(rssi, [...rssi]..sort((a, b) => b.compareTo(a)));
      await scanner.stop();
      expect(scanner.scanning, isFalse);
      scanner.dispose();
    });

    test('filters by name and hides unnamed devices', () async {
      final scanner = ScannerController(fastAdapter());
      await scanner.start();
      await waitFor(() => scanner.totalSeen == 4);
      scanner.setNamedOnly(true);
      expect(scanner.devices.length, 3);
      scanner.setQuery('printer');
      expect(scanner.devices.single.name, 'Harborlane Printer 58');
      scanner.setQuery('de:m0:00:00:00:03');
      expect(scanner.devices.single.name, 'Climate Tag');
      scanner.dispose();
    });

    test('stops by itself after the scan duration', () async {
      final scanner = ScannerController(fastAdapter(), scanDuration: const Duration(milliseconds: 30));
      await scanner.start();
      await waitFor(() => !scanner.scanning);
      scanner.dispose();
    });
  });

  group('DeviceController', () {
    test('connects, negotiates MTU, discovers services and reads the battery', () async {
      final device = DeviceController(fastAdapter(), demoDevice(DemoBleAdapter.heartRateId));
      await device.connect();
      await waitFor(() => device.battery != null);
      expect(device.isConnected, isTrue);
      expect(device.mtu, 185);
      expect(device.services.map((s) => s.name), containsAll(['Heart Rate', 'Battery', 'Device Information']));
      expect(device.battery, inInclusiveRange(1, 100));
      device.dispose();
    });

    test('heart rate notifications fill the history', () async {
      final device = DeviceController(fastAdapter(), demoDevice(DemoBleAdapter.heartRateId));
      await device.connect();
      await waitFor(() => device.services.isNotEmpty);
      final hr = device.find(Gatt.heartRateService, Gatt.heartRateMeasurement)!;
      await device.toggleNotifications(hr);
      await waitFor(() => device.heartRateHistory.length >= 3);
      expect(device.heartRate!.bpm, inInclusiveRange(55, 90));
      expect(device.heartRate!.rrIntervalsMs, isNotEmpty);
      await device.toggleNotifications(hr);
      expect(device.isSubscribed(hr), isFalse);
      device.dispose();
    });

    test('reads text characteristics', () async {
      final device = DeviceController(fastAdapter(), demoDevice(DemoBleAdapter.climateId));
      await device.connect();
      await waitFor(() => device.services.isNotEmpty);
      final model = device.find(Gatt.deviceInformation, Gatt.modelNumber)!;
      await device.read(model);
      expect(asPrintableText(device.values[model]!), 'CT-1');
      final temp = device.find(Gatt.environmentalSensing, Gatt.temperature)!;
      await device.read(temp);
      expect(device.temperature, closeTo(22.4, 1.0));
      device.dispose();
    });

    test('prints the sample receipt on the simulated printer', () async {
      final adapter = fastAdapter();
      final device = DeviceController(adapter, demoDevice(DemoBleAdapter.printerId));
      await device.connect();
      await waitFor(() => device.services.isNotEmpty);
      expect(device.printerCharacteristic, isNotNull);
      final receipt = sampleReceipt();
      await device.printReceipt(receipt);
      expect(adapter.paper.value, receipt.bytes);
      final text = previewEscPos(adapter.paper.value).whereType<PreviewText>().map((t) => t.text);
      expect(text, contains('HARBORLANE CAFE'));
      device.dispose();
    });

    test('reports devices that refuse connections', () async {
      final device = DeviceController(fastAdapter(), demoDevice(DemoBleAdapter.beaconId));
      await device.connect();
      expect(device.error, contains('does not accept connections'));
      expect(device.isConnected, isFalse);
      device.dispose();
    });

    test('disconnect stops notifications', () async {
      final device = DeviceController(fastAdapter(), demoDevice(DemoBleAdapter.climateId));
      await device.connect();
      await waitFor(() => device.services.isNotEmpty);
      final temp = device.find(Gatt.environmentalSensing, Gatt.temperature)!;
      await device.toggleNotifications(temp);
      await device.disconnect();
      expect(device.isSubscribed(temp), isFalse);
      expect(device.connection, BleConnectionState.disconnected);
      device.dispose();
    });
  });
}
