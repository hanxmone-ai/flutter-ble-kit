# BLE Kit for Flutter

[![Flutter CI](https://github.com/hanxmone-ai/flutter-ble-kit/actions/workflows/ci.yml/badge.svg)](https://github.com/hanxmone-ai/flutter-ble-kit/actions/workflows/ci.yml)

A Flutter app and a set of reusable pieces for working with Bluetooth Low Energy devices: scan, connect, browse GATT
services, show live sensor data, and print receipts on Bluetooth thermal printers.

**[Try the web demo →](https://hanxmone-ai.github.io/flutter-ble-kit/)** (runs with simulated devices; browsers have
no general BLE access, so the demo swaps in the same simulated adapter the tests use).

[中文说明](README.zh-CN.md)

## What it does

| Screen | |
|---|---|
| **Scanner** | Live list sorted by signal strength, name/address filter, advertised services and manufacturer IDs, auto-stop after 15 s to save battery. |
| **Overview** | Dashboards picked from the services a device has: heart rate with a live chart and RR intervals, temperature and humidity, battery, and a receipt-printer card. |
| **GATT** | Every service and characteristic with its properties; read, write (hex or text, with or without response) and subscribe. |
| **Log** | Timestamped reads, writes, notifications and errors with hex and text values. |

Printing builds the receipt with [escpos_kit](https://github.com/hanxmone-ai/escpos-kit), finds the printer's write
characteristic (known channels such as `18F0/2AF1` first, then any vendor characteristic that accepts writes), and sends
it in MTU-sized chunks. The simulated printer turns the bytes it receives back into a paper preview.

## How it is built

```
lib/src/
  ble/        BleAdapter interface, flutter_reactive_ble implementation, UUID helpers
  demo/       DemoBleAdapter: heart rate strap, receipt printer, climate sensor, beacon
  protocols/  Heart Rate Measurement, temperature, humidity, battery, hex
  printing/   BlePrinter (chunked writes), printer discovery, ESC/POS → preview
  state/      ScannerController, DeviceController (ChangeNotifier, no state package)
  ui/         Screens and widgets
```

- **One interface, two radios.** Screens and controllers talk to `BleAdapter`. On Android and iOS it is backed by
  [flutter_reactive_ble](https://pub.dev/packages/flutter_reactive_ble) (BSD-3-Clause, so it can ship in commercial
  apps); everywhere else, and in tests, by `DemoBleAdapter`. A "Demo devices" switch on the scanner screen lets you try
  the app on a phone with no hardware around.
- **Protocols are plain Dart** with byte-level tests against the Bluetooth SIG specs.
- **Permissions:** Android 12+ asks for "Nearby devices" (`BLUETOOTH_SCAN` with `neverForLocation`,
  `BLUETOOTH_CONNECT`); Android 11 and older fall back to location, as the platform requires. iOS uses
  `NSBluetoothAlwaysUsageDescription`.

## Run it

```bash
flutter pub get
flutter run                  # on a phone: real Bluetooth
flutter run -d chrome        # in a browser: simulated devices
flutter test
```

A debug APK is built by CI on every push (Actions → latest run → `ble-kit-debug-apk`).

## Reuse in your app

```dart
import 'package:flutter_ble_kit/flutter_ble_kit.dart';

final device = DeviceController(adapter, scannedDevice);
await device.connect();                // MTU negotiation and service discovery included
await device.printReceipt(myReceipt);  // any escpos_kit Receipt
```

## License

[MIT](LICENSE) © 2026 Yihan Qiu. DejaVu Sans Mono is bundled under its own license (`assets/fonts`).
