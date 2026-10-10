import 'package:escpos_kit/escpos_kit.dart';

import 'adapter.dart';
import 'chunked_writer.dart';
import 'models.dart';
import 'uuids.dart';

/// Prints ESC/POS data to a Bluetooth LE receipt printer.
class BlePrinter {
  BlePrinter(
    this.connection,
    this.characteristic, {
    this.pause = const Duration(milliseconds: 20),
    Future<void> Function(Duration)? sleep,
  }) : _sleep = sleep;

  final BleConnection connection;
  final GattCharacteristic characteristic;

  /// Wait between chunks so the printer's buffer keeps up.
  final Duration pause;
  final Future<void> Function(Duration)? _sleep;

  /// The characteristic to send print data to, or null if none looks right.
  ///
  /// Prefers the printer services that most low-cost BLE printers use, then
  /// any writable characteristic outside the standard GAP/GATT services.
  static GattCharacteristic? findDataCharacteristic(List<GattService> services) {
    for (final service in [KnownUuids.printerService, KnownUuids.printerServiceAlt]) {
      for (final s in services.where((s) => sameUuid(s.uuid, service))) {
        for (final c in s.characteristics) {
          if (c.props.canWrite) return c;
        }
      }
    }
    for (final s in services.where((s) => !s.isStandard)) {
      for (final c in s.characteristics) {
        if (c.props.canWrite) return c;
      }
    }
    return null;
  }

  /// Whether [services] look like a receipt printer.
  static bool looksLikePrinter(List<GattService> services) => services.any(
        (s) =>
            sameUuid(s.uuid, KnownUuids.printerService) ||
            sameUuid(s.uuid, KnownUuids.printerServiceAlt),
      );

  /// Sends raw bytes. Uses write-without-response when the printer supports
  /// it, which is several times faster.
  Future<void> printBytes(List<int> bytes, {void Function(int sent, int total)? onProgress}) {
    final withoutResponse = characteristic.props.writeWithoutResponse;
    final writer = ChunkedWriter(
      write: (chunk) => connection.write(characteristic, chunk, withoutResponse: withoutResponse),
      chunkSize: ChunkedWriter.chunkSizeForMtu(connection.mtu, max: 180),
      pause: pause,
      sleep: _sleep,
    );
    return writer.writeAll(bytes, onProgress: onProgress);
  }

  Future<void> printReceipt(Receipt receipt, {void Function(int sent, int total)? onProgress}) =>
      printBytes(receipt.bytes, onProgress: onProgress);
}

/// The receipt the demo app prints.
Receipt sampleReceipt({DateTime? now, Paper paper = Paper.mm58}) {
  final t = now ?? DateTime.now();
  String two(int n) => n.toString().padLeft(2, '0');
  final stamp = '${t.year}-${two(t.month)}-${two(t.day)} ${two(t.hour)}:${two(t.minute)}';
  return Receipt(paper: paper)
    ..text('HARBORLANE CAFE', align: PosAlign.center, bold: true, size: TextSize.large)
    ..text('港湾咖啡 · BLE Kit demo', align: PosAlign.center)
    ..text(stamp, align: PosAlign.center)
    ..divider()
    ..row(['Flat white', '4.50'])
    ..row(['Banana bread with walnuts', '3.20'])
    ..row(['拿铁 Latte', '5.00'])
    ..divider()
    ..row(['TOTAL', '12.70'], bold: true)
    ..feed()
    ..qr('https://github.com/hanxmone-ai/flutter-ble-kit', moduleSize: 5)
    ..text('Printed over Bluetooth LE', align: PosAlign.center)
    ..cut();
}
