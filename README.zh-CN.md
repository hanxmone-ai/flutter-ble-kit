# BLE Kit for Flutter

[English](README.md)

Flutter 低功耗蓝牙（BLE）工具应用和可复用组件：扫描、连接、浏览 GATT 服务、实时传感器数据，以及通过蓝牙热敏打印机打印小票。

**[在线体验 →](https://hanxmone-ai.github.io/flutter-ble-kit/)**（浏览器没有通用的蓝牙接口，网页版使用和测试相同的模拟设备）

## 功能

- **扫描**：按信号强度排序，支持名称/地址筛选，显示广播的服务和厂商 ID，15 秒后自动停止以省电。
- **概览**：根据设备的服务自动显示面板——心率（实时曲线和 RR 间期）、温湿度、电量、小票打印。
- **GATT**：列出全部服务和特征值及其属性，可读、写（十六进制或文本，带/不带响应）、订阅通知。
- **日志**：带时间戳的读写、通知和错误记录。

打印用 [escpos_kit](https://github.com/hanxmone-ai/escpos-kit) 生成小票，自动找到打印机的写入特征值（优先常见的 `18F0/2AF1` 等通道），按 MTU 分块发送。模拟打印机会把收到的字节还原成小票预览。

## 架构

- 页面和控制器只依赖 `BleAdapter` 接口：Android/iOS 上用 [flutter_reactive_ble](https://pub.dev/packages/flutter_reactive_ble)（BSD-3 协议，可用于商业项目），其他平台和测试中用模拟设备 `DemoBleAdapter`。手机上也可以切换到"演示设备"。
- 协议解析是纯 Dart，按蓝牙 SIG 规范逐字节测试。
- 权限：Android 12+ 申请"附近的设备"（`BLUETOOTH_SCAN` 声明 `neverForLocation`、`BLUETOOTH_CONNECT`），Android 11 及以下按系统要求使用定位权限；iOS 使用 `NSBluetoothAlwaysUsageDescription`。

## 运行

```bash
flutter pub get
flutter run              # 手机：真实蓝牙
flutter run -d chrome    # 浏览器：模拟设备
flutter test
```

每次推送 CI 都会打出调试版 APK（Actions → 最新一次运行 → `ble-kit-debug-apk`）。

## 许可证

[MIT](LICENSE) © 2026 Yihan Qiu
