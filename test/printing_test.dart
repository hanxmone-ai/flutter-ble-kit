import 'package:escpos_kit/escpos_kit.dart';
import 'package:flutter_ble_kit/flutter_ble_kit.dart';
import 'package:flutter_test/flutter_test.dart';

/// Records writes instead of sending them.
class RecordingAdapter extends DemoBleAdapter {
  RecordingAdapter() : super(connectDelay: Duration.zero);

  final List<(List<int>, bool)> writes = [];

  @override
  Future<void> write(
    String deviceId,
    GattCharacteristic characteristic,
    List<int> value, {
    bool withResponse = true,
  }) async {
    writes.add((List.of(value), withResponse));
  }
}

GattCharacteristic char(String service, String uuid, CharProps props) =>
    GattCharacteristic(serviceUuid: service, uuid: uuid, props: props);

void main() {
  group('findPrinterCharacteristic', () {
    test('prefers a known printer channel', () {
      final services = [
        GattService(uuid: 'ffe0', characteristics: [char('ffe0', 'ffe1', const CharProps(writeWithoutResponse: true))]),
        GattService(uuid: '18f0', characteristics: [char('18f0', '2af1', const CharProps(write: true))]),
      ];
      expect(shortUuid(findPrinterCharacteristic(services)!.uuid), '2AF1');
    });

    test('falls back to a vendor characteristic that accepts writes', () {
      final services = [
        GattService(uuid: '1800', characteristics: [char('1800', '2a00', const CharProps(write: true))]),
        GattService(uuid: 'ffe0', characteristics: [char('ffe0', 'ffe1', const CharProps(write: true))]),
      ];
      expect(shortUuid(findPrinterCharacteristic(services)!.uuid), 'FFE1');
    });

    test('returns null when nothing is writable', () {
      final services = [
        GattService(uuid: '180f', characteristics: [char('180f', '2a19', const CharProps(read: true))]),
      ];
      expect(findPrinterCharacteristic(services), isNull);
    });
  });

  group('BlePrinter', () {
    test('splits data into MTU-sized writes that add up to the receipt', () async {
      final adapter = RecordingAdapter();
      final target = char('18f0', '2af1', const CharProps(write: true, writeWithoutResponse: true));
      final printer = BlePrinter(adapter, 'x', target, mtu: 23, pauseBetweenChunks: Duration.zero);
      final receipt = sampleReceipt(now: DateTime(2026, 10, 10, 9, 30));
      final progress = <double>[];

      await printer.print(receipt, onProgress: progress.add);

      expect(adapter.writes.every((w) => w.$1.length <= 20), isTrue);
      expect([for (final w in adapter.writes) ...w.$1], receipt.bytes);
      expect(adapter.writes.every((w) => w.$2 == false), isTrue, reason: 'write without response when supported');
      expect(progress.last, 1.0);
    });

    test('larger MTU means fewer writes', () async {
      final adapter = RecordingAdapter();
      final target = char('18f0', '2af1', const CharProps(write: true));
      final bytes = List.filled(1000, 0x41);
      await BlePrinter(adapter, 'x', target, mtu: 185).send(bytes);
      expect(adapter.writes.length, (1000 / 182).ceil());
      expect(adapter.writes.first.$2, isTrue, reason: 'only write-with-response is available');
    });
  });

  group('ESC/POS preview', () {
    test('reconstructs text, styles, QR code and cut', () {
      final receipt = Receipt()
        ..text('HARBORLANE', align: PosAlign.center, bold: true, size: TextSize.large)
        ..text('港湾咖啡')
        ..row(['Latte', '4.50'])
        ..qr('https://example.com/r/1')
        ..barcode('A-1')
        ..cut();
      final items = previewEscPos(receipt.bytes);

      final title = items[0] as PreviewText;
      expect(title.text, 'HARBORLANE');
      expect(title.align, PosAlign.center);
      expect(title.bold, isTrue);
      expect(title.widthScale, 2);
      expect(title.heightScale, 2);

      final chinese = items[1] as PreviewText;
      expect(chinese.text, '港湾咖啡');
      expect(chinese.bold, isFalse);
      expect(chinese.align, PosAlign.left);

      expect((items[2] as PreviewText).text, 'Latte${' ' * 23}4.50');

      final qr = items.whereType<PreviewQr>().single;
      expect(qr.data, 'https://example.com/r/1');
      expect(qr.align, PosAlign.center);

      expect(items.whereType<PreviewBarcode>().single.data, 'A-1');
      expect(items.last, isA<PreviewCut>());
    });

    test('raster images keep their size and pixels', () {
      final image = RasterImage.fromLuminance([0, 255, 255, 0], 2, 2);
      final items = previewEscPos((Receipt()..image(image)).bytes);
      final preview = items.whereType<PreviewImage>().single;
      expect(preview.width, 8);
      expect(preview.height, 2);
      expect(preview.isBlack(0, 0), isTrue);
      expect(preview.isBlack(1, 0), isFalse);
      expect(preview.isBlack(1, 1), isTrue);
    });

    test('feed lines become empty lines and unknown commands are skipped', () {
      final items = previewEscPos([0x1B, 0x40, 0x41, 0x0A, 0x1B, 0x64, 2, 0x1B, 0x99, 0x42, 0x0A]);
      expect([for (final i in items) (i as PreviewText).text], ['A', '', '', 'B']);
    });
  });
}
