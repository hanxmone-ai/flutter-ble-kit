# BLE Kit

[![Flutter CI](https://github.com/hanxmone-ai/flutter-ble-kit/actions/workflows/ci.yml/badge.svg)](https://github.com/hanxmone-ai/flutter-ble-kit/actions/workflows/ci.yml)

A Flutter app and toolkit for Bluetooth Low Energy devices: scan, connect, browse GATT services,
read / write / subscribe, show live heart rate, and print receipts to BLE thermal printers.

It is built the way I build hardware apps for clients: the Bluetooth plugin sits behind one small
interface, so everything above it (connection handling, parsing, chunked printing, the UI) runs and is
tested without a phone. A **demo mode** simulates a heart-rate band, a receipt printer and a UART dev
board, so the whole app can be tried on an emulator, in CI or in a review.

[中文说明](#中文说明)

## Features

- **Scanning** with de-duplication, smoothed RSSI (no jumping list), signal bars, name/id search and a
  "named only" filter. Scanning stops before connecting, which Android needs for reliable connections.
- **Connections that recover.** `DeviceSession` negotiates the MTU, discovers services and, when the link
  drops, reconnects with exponential backoff before giving up.
- **GATT browser.** Every service and characteristic with its properties; read, write (text or hex) and
  toggle notifications, with a timestamped log of everything sent and received.
- **Heart rate.** A full parser for the Heart Rate Measurement characteristic (8/16-bit values, sensor
  contact, energy expended, RR intervals) plus battery level and device information.
- **Receipt printing.** Finds the printer's data characteristic, builds the receipt with
  [escpos_kit](https://github.com/hanxmone-ai/escpos-kit) (Chinese GBK text, aligned columns, QR code) and
  sends it in MTU-sized chunks with write-without-response and a short pause, which keeps cheap printers
  from dropping data.
- **Virtual printer.** In demo mode the printer decodes the ESC/POS bytes back into a receipt you can
  look at, so printing is testable end to end.

## Architecture

```
lib/
├── core/                      pure Dart, no Flutter imports: all of it is unit tested
│   ├── adapter.dart           BleAdapter / BleConnection: the only Bluetooth API the app uses
│   ├── session.dart           connect → MTU → discover, reconnect with backoff
│   ├── scan_list.dart         merging, smoothing, filtering advertisements
│   ├── chunked_writer.dart    MTU-sized writes with pacing and progress
│   ├── printer.dart           finds the printer characteristic, prints escpos_kit receipts
│   ├── parsers.dart           Heart Rate Measurement, Battery Level, strings
│   ├── virtual_printer.dart   ESC/POS bytes → printed lines
│   └── demo_adapter.dart      simulated devices for demo mode and tests
├── ble/
│   └── flutter_blue_plus_adapter.dart   the real hardware, via flutter_blue_plus
├── app/                       ChangeNotifier controllers for the two screens
└── ui/                        Material 3 screens and widgets
```

Swapping flutter_blue_plus for another plugin (or a platform channel) means rewriting one file.

## Run it

```bash
flutter pub get
flutter run            # on a phone for real Bluetooth; anywhere else it starts in demo mode
flutter test
```

On a phone, the **Demo** switch in the app bar flips between real devices and the simulated ones.

The `android/` and `ios/` folders come from `flutter create` plus `tool/patch_platforms.py`, which adds the
Bluetooth permissions (Android 12+ `BLUETOOTH_SCAN` with `neverForLocation`, `BLUETOOTH_CONNECT`, legacy
permissions capped at API 30) and the iOS `NSBluetoothAlwaysUsageDescription`. CI generates them if they
are missing and builds a debug APK on every push; download it from the run's artifacts.

## Tests

- `test/core_test.dart`: UUIDs, hex, heart-rate parsing, scan list, chunked writes.
- `test/device_test.dart`: scanning, connecting, reconnecting after a dropped link, giving up, GATT
  read/write/notify, MTU limits, and printing a receipt that is decoded and checked line by line.
- `test/widget_test.dart`: the app in demo mode: scan, open the heart-rate band and see live bpm, print
  the sample receipt and open the printout.

## License

[MIT](LICENSE) © 2026 Yihan Qiu

---

## 中文说明

Flutter 蓝牙 BLE 工具包和示例应用：扫描、连接、浏览 GATT 服务、读写与订阅通知、实时心率，以及通过 BLE 热敏打印机打印小票。

- 蓝牙插件只藏在一个接口后面，连接管理、数据解析、分包打印、界面都能脱离手机运行和测试。
- **演示模式**模拟了心率手环、小票打印机和串口开发板，模拟器、CI 和评审时都能完整体验。
- `DeviceSession` 负责协商 MTU、发现服务，断线后按指数退避自动重连。
- 打印用 [escpos_kit](https://github.com/hanxmone-ai/escpos-kit) 生成小票（GBK 中文、列对齐、二维码），按 MTU 分包、无响应写入并留间隔，避免低价打印机丢数据。
- 演示模式下的虚拟打印机会把 ESC/POS 字节还原成小票画面，打印流程可以端到端测试。

运行：`flutter pub get` → `flutter run`（真机使用真实蓝牙，其他平台自动进入演示模式）→ `flutter test`。
