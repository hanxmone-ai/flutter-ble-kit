import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/foundation.dart';

import '../ble/ble_adapter.dart';
import '../ble/uuids.dart';
import '../protocols/sensors.dart';

/// Simulated peripherals, so the app can be explored (and tested, and run in
/// a browser) without Bluetooth hardware.
///
/// - **Pulse HR-200**: heart rate strap; notifies Heart Rate Measurement with
///   RR intervals, readable battery and device information.
/// - **Harborlane Printer 58**: receipt printer on the common 0x18F0/0x2AF1
///   channel; everything written to it ends up in [paper].
/// - **Climate Tag**: environmental sensor with temperature and humidity.
/// - An iBeacon-style advertiser that cannot be connected to.
class DemoBleAdapter extends BleAdapter {
  DemoBleAdapter({
    this.tick = const Duration(seconds: 1),
    this.scanInterval = const Duration(milliseconds: 400),
    this.connectDelay = const Duration(milliseconds: 600),
    int seed = 7,
  }) : _random = math.Random(seed);

  /// How often sensors notify.
  final Duration tick;

  /// How often each device is re-reported while scanning.
  final Duration scanInterval;

  /// Time from "connecting" to "connected".
  final Duration connectDelay;

  final math.Random _random;

  static const String heartRateId = 'DE:M0:00:00:00:01';
  static const String printerId = 'DE:M0:00:00:00:02';
  static const String climateId = 'DE:M0:00:00:00:03';
  static const String beaconId = 'DE:M0:00:00:00:04';

  /// Bytes received by the simulated printer since the last [clearPaper].
  final ValueNotifier<List<int>> paper = ValueNotifier(const []);

  void clearPaper() => paper.value = const [];

  final Set<String> _connected = {};
  int _battery = 87;

  @override
  String get label => 'Demo devices';

  @override
  Stream<BleState> get state => Stream.value(BleState.ready);

  static final List<ScannedDevice> _devices = [
    ScannedDevice(
      id: heartRateId,
      name: 'Pulse HR-200',
      rssi: -58,
      serviceUuids: [normalizeUuid(Gatt.heartRateService)],
    ),
    ScannedDevice(
      id: printerId,
      name: 'Harborlane Printer 58',
      rssi: -66,
      serviceUuids: [normalizeUuid('18F0')],
    ),
    ScannedDevice(
      id: climateId,
      name: 'Climate Tag',
      rssi: -74,
      serviceUuids: [normalizeUuid(Gatt.environmentalSensing)],
    ),
    ScannedDevice(
      id: beaconId,
      name: '',
      rssi: -89,
      connectable: false,
      // Apple company ID (0x004C), iBeacon type 0x02, length 0x15.
      manufacturerData: Uint8List.fromList([0x4C, 0x00, 0x02, 0x15, 0xE2, 0xC5, 0x6D, 0xB5]),
    ),
  ];

  @override
  Stream<ScannedDevice> scan({List<String> services = const []}) {
    final wanted = services.map(normalizeUuid).toSet();
    final matching = _devices
        .where((d) => wanted.isEmpty || d.serviceUuids.any(wanted.contains))
        .toList();
    Timer? timer;
    late final StreamController<ScannedDevice> controller;
    void emit() {
      for (final d in matching) {
        controller.add(d.copyWith(rssi: d.rssi + _random.nextInt(9) - 4));
      }
    }

    controller = StreamController<ScannedDevice>(
      onListen: () {
        emit();
        timer = Timer.periodic(scanInterval, (_) => emit());
      },
      onCancel: () => timer?.cancel(),
    );
    return controller.stream;
  }

  @override
  Stream<BleConnectionState> connect(String deviceId) {
    Timer? timer;
    late final StreamController<BleConnectionState> controller;
    controller = StreamController<BleConnectionState>(
      onListen: () {
        controller.add(BleConnectionState.connecting);
        timer = Timer(connectDelay, () {
          final device = _devices.where((d) => d.id == deviceId).firstOrNull;
          if (device == null || !device.connectable) {
            controller.addError(StateError('This device does not accept connections'));
            controller.add(BleConnectionState.disconnected);
            return;
          }
          _connected.add(deviceId);
          controller.add(BleConnectionState.connected);
        });
      },
      onCancel: () {
        timer?.cancel();
        _connected.remove(deviceId);
      },
    );
    return controller.stream;
  }

  void _requireConnection(String deviceId) {
    if (!_connected.contains(deviceId)) {
      throw StateError('Not connected to $deviceId');
    }
  }

  @override
  Future<List<GattService>> discoverServices(String deviceId) async {
    _requireConnection(deviceId);
    await Future<void>.delayed(Duration(milliseconds: connectDelay.inMilliseconds ~/ 3));
    return _services(deviceId);
  }

  static List<GattService> _services(String deviceId) {
    GattService info() => GattService(
          uuid: Gatt.deviceInformation,
          characteristics: [
            for (final c in [Gatt.manufacturerName, Gatt.modelNumber, Gatt.firmwareRevision])
              GattCharacteristic(
                serviceUuid: Gatt.deviceInformation,
                uuid: c,
                props: const CharProps(read: true),
              ),
          ],
        );
    final battery = GattService(
      uuid: Gatt.batteryService,
      characteristics: [
        GattCharacteristic(
          serviceUuid: Gatt.batteryService,
          uuid: Gatt.batteryLevel,
          props: const CharProps(read: true, notify: true),
        ),
      ],
    );
    return switch (deviceId) {
      heartRateId => [
          GattService(
            uuid: Gatt.heartRateService,
            characteristics: [
              GattCharacteristic(
                serviceUuid: Gatt.heartRateService,
                uuid: Gatt.heartRateMeasurement,
                props: const CharProps(notify: true),
              ),
              GattCharacteristic(
                serviceUuid: Gatt.heartRateService,
                uuid: '2A38',
                props: const CharProps(read: true),
              ),
            ],
          ),
          battery,
          info(),
        ],
      printerId => [
          GattService(
            uuid: '18F0',
            characteristics: [
              GattCharacteristic(
                serviceUuid: '18F0',
                uuid: '2AF1',
                props: const CharProps(write: true, writeWithoutResponse: true),
              ),
              GattCharacteristic(
                serviceUuid: '18F0',
                uuid: '2AF0',
                props: const CharProps(notify: true),
              ),
            ],
          ),
          info(),
        ],
      climateId => [
          GattService(
            uuid: Gatt.environmentalSensing,
            characteristics: [
              for (final c in [Gatt.temperature, Gatt.humidity])
                GattCharacteristic(
                  serviceUuid: Gatt.environmentalSensing,
                  uuid: c,
                  props: const CharProps(read: true, notify: true),
                ),
            ],
          ),
          battery,
          info(),
        ],
      _ => const [],
    };
  }

  int _t = 0;

  List<int> _value(String deviceId, GattCharacteristic c) {
    final id = shortUuid(c.uuid);
    _t++;
    return switch (id) {
      '2A37' => _heartRate(),
      '2A38' => const [1], // chest
      '2A19' => [_battery],
      '2A29' => 'Harborlane Labs'.codeUnits,
      '2A24' => (deviceId == heartRateId ? 'HR-200' : deviceId == printerId ? 'HP-58BT' : 'CT-1').codeUnits,
      '2A26' => '1.4.2'.codeUnits,
      '2A6E' => encodeTemperature(22.4 + 0.6 * math.sin(_t / 20) + (_random.nextDouble() - 0.5) * 0.1),
      '2A6F' => () {
          final raw = ((46 + 3 * math.sin(_t / 30)) * 100).round();
          return [raw & 0xFF, raw >> 8];
        }(),
      '2AF0' => const [0x00], // printer status: ready
      _ => const [],
    };
  }

  List<int> _heartRate() {
    final bpm = (72 + 10 * math.sin(_t / 8) + _random.nextInt(5) - 2).round();
    final rrMs = 60000 / bpm;
    return HeartRateMeasurement.encode(bpm, rrRaw: [(rrMs * 1024 / 1000).round()]);
  }

  @override
  Future<List<int>> read(String deviceId, GattCharacteristic characteristic) async {
    _requireConnection(deviceId);
    if (!characteristic.props.read) {
      throw StateError('${characteristic.name} is not readable');
    }
    await Future<void>.delayed(const Duration(milliseconds: 60));
    return _value(deviceId, characteristic);
  }

  @override
  Future<void> write(
    String deviceId,
    GattCharacteristic characteristic,
    List<int> value, {
    bool withResponse = true,
  }) async {
    _requireConnection(deviceId);
    if (!characteristic.props.canWrite) {
      throw StateError('${characteristic.name} is not writable');
    }
    if (deviceId == printerId && sameUuid(characteristic.uuid, '2AF1')) {
      paper.value = [...paper.value, ...value];
    }
    if (withResponse) await Future<void>.delayed(const Duration(milliseconds: 5));
  }

  @override
  Stream<List<int>> subscribe(String deviceId, GattCharacteristic characteristic) {
    _requireConnection(deviceId);
    if (!characteristic.props.canSubscribe) {
      throw StateError('${characteristic.name} does not notify');
    }
    Timer? timer;
    late final StreamController<List<int>> controller;
    controller = StreamController<List<int>>(
      onListen: () {
        timer = Timer.periodic(tick, (_) {
          if (!_connected.contains(deviceId)) {
            controller.close();
            timer?.cancel();
            return;
          }
          if (sameUuid(characteristic.uuid, Gatt.batteryLevel) && _t % 30 == 0 && _battery > 5) {
            _battery--;
          }
          controller.add(_value(deviceId, characteristic));
        });
      },
      onCancel: () => timer?.cancel(),
    );
    return controller.stream;
  }

  @override
  Future<int> requestMtu(String deviceId, int mtu) async {
    _requireConnection(deviceId);
    return mtu.clamp(23, 185);
  }
}
