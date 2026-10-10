import 'dart:async';
import 'dart:typed_data';

import 'package:escpos_kit/escpos_kit.dart';

import '../ble/ble_adapter.dart';
import '../ble/uuids.dart';

/// Service and characteristic pairs used by common Bluetooth receipt printers,
/// in order of preference.
const List<(String service, String characteristic)> knownPrinterChannels = [
  ('18F0', '2AF1'), // most low-cost 58/80 mm printers
  ('e7810a71-73ae-499d-8c15-faa9aef0c3f2', 'bef8d6c9-9c21-4c9e-b632-bd58c1009f9f'),
  ('49535343-fe7d-4ae5-8fa9-9fafd205e455', '49535343-8841-43f4-a8d4-ecbe34729bb3'),
  ('0000ff00-0000-1000-8000-00805f9b34fb', '0000ff02-0000-1000-8000-00805f9b34fb'),
];

/// Picks the characteristic to send print data to: a known printer channel if
/// there is one, otherwise the first characteristic that accepts writes
/// without response, otherwise any writable one.
GattCharacteristic? findPrinterCharacteristic(List<GattService> services) {
  final all = [for (final s in services) ...s.characteristics];
  for (final (service, characteristic) in knownPrinterChannels) {
    for (final c in all) {
      if (c.matches(service, characteristic) && c.props.canWrite) return c;
    }
  }
  // Skip standard services such as Generic Access, where writes mean
  // something else.
  const standard = {'1800', '1801', '180A', '180D', '180F', '181A'};
  final candidates = [for (final c in all) if (!standard.contains(shortUuid(c.serviceUuid))) c];
  for (final c in candidates) {
    if (c.props.writeWithoutResponse) return c;
  }
  for (final c in candidates) {
    if (c.props.write) return c;
  }
  return null;
}

/// Sends ESC/POS data to a Bluetooth LE printer in MTU-sized writes.
class BlePrinter {
  BlePrinter(
    this.adapter,
    this.deviceId,
    this.characteristic, {
    this.mtu = 23,
    this.pauseBetweenChunks = const Duration(milliseconds: 15),
  });

  final BleAdapter adapter;
  final String deviceId;
  final GattCharacteristic characteristic;

  /// Negotiated ATT MTU. Each write carries at most `mtu - 3` bytes.
  final int mtu;

  /// Gives printers with small buffers time to keep up when writing without
  /// response.
  final Duration pauseBetweenChunks;

  int get chunkSize => (mtu - 3).clamp(20, 509);

  /// Sends [bytes]; [onProgress] gets the fraction sent after each write.
  Future<void> send(List<int> bytes, {void Function(double progress)? onProgress}) async {
    final data = Uint8List.fromList(bytes);
    final withResponse = !characteristic.props.writeWithoutResponse;
    for (var start = 0; start < data.length; start += chunkSize) {
      final end = start + chunkSize < data.length ? start + chunkSize : data.length;
      await adapter.write(
        deviceId,
        characteristic,
        Uint8List.sublistView(data, start, end),
        withResponse: withResponse,
      );
      onProgress?.call(end / data.length);
      if (!withResponse && end < data.length && pauseBetweenChunks > Duration.zero) {
        await Future<void>.delayed(pauseBetweenChunks);
      }
    }
  }

  Future<void> print(Receipt receipt, {void Function(double progress)? onProgress}) =>
      send(receipt.bytes, onProgress: onProgress);
}

/// The receipt the app prints as a test page.
Receipt sampleReceipt({Paper paper = Paper.mm58, DateTime? now}) {
  final time = now ?? DateTime.now();
  String two(int n) => n.toString().padLeft(2, '0');
  final stamp = '${time.year}-${two(time.month)}-${two(time.day)} ${two(time.hour)}:${two(time.minute)}';
  return Receipt(paper: paper)
    ..text('HARBORLANE CAFE', align: PosAlign.center, bold: true, size: TextSize.large)
    ..text('港湾咖啡 · Order #1042', align: PosAlign.center)
    ..text(stamp, align: PosAlign.center)
    ..divider()
    ..row(['Flat white 澳白', '4.50'])
    ..row(['Banana bread with walnuts', '3.20'])
    ..row(['Sparkling water', '1.80'])
    ..divider()
    ..row(['TOTAL', '9.50'], bold: true)
    ..feed()
    ..qr('https://example.com/r/1042', moduleSize: 5)
    ..text('Printed over Bluetooth LE', align: PosAlign.center)
    ..cut();
}
