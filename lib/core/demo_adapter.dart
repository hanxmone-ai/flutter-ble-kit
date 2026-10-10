import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'adapter.dart';
import 'models.dart';
import 'uuids.dart';
import 'virtual_printer.dart';

/// A simulated peripheral for [DemoAdapter].
class DemoPeripheral {
  DemoPeripheral({
    required this.advert,
    this.services = const [],
    Map<String, List<int>>? values,
    this.notifications,
    this.onWrite,
    this.connectDelay = const Duration(milliseconds: 350),
    this.maxMtu = 185,
  }) : values = values ?? {};

  final DiscoveredDevice advert;
  final List<GattService> services;

  /// Readable values keyed by [GattCharacteristic.key].
  final Map<String, List<int>> values;

  /// Values the peripheral pushes for a characteristic, or null.
  final Stream<List<int>>? Function(GattCharacteristic characteristic)? notifications;

  /// Called for every write.
  final void Function(GattCharacteristic characteristic, List<int> value)? onWrite;

  final Duration connectDelay;
  final int maxMtu;

  /// Every write received, in order.
  final List<List<int>> writes = [];

  /// When true, connecting fails (for testing error paths).
  bool failConnect = false;

  String get id => advert.id;
}

/// A [BleAdapter] that simulates peripherals, for demos and tests.
class DemoAdapter implements BleAdapter {
  DemoAdapter(
    this.peripherals, {
    this.advertiseEvery = const Duration(milliseconds: 400),
    Random? random,
  }) : _random = random ?? Random();

  final List<DemoPeripheral> peripherals;
  final Duration advertiseEvery;
  final Random _random;

  final StreamController<AdapterStatus> _statusChanges = StreamController.broadcast();
  AdapterStatus _status = AdapterStatus.on;
  StreamController<DiscoveredDevice>? _scan;
  Timer? _scanTimer;
  Timer? _scanTimeout;
  final Map<String, DemoConnection> _connections = {};

  @override
  Stream<AdapterStatus> get status async* {
    yield _status;
    yield* _statusChanges.stream;
  }

  /// Simulates the user switching Bluetooth on or off.
  void setStatus(AdapterStatus status) {
    _status = status;
    _statusChanges.add(status);
    if (status != AdapterStatus.on) {
      _stopScan();
      for (final c in _connections.values.toList()) {
        c.drop();
      }
    }
  }

  @override
  Future<void> turnOn() async => setStatus(AdapterStatus.on);

  @override
  Stream<DiscoveredDevice> scan({
    List<String> withServices = const [],
    Duration timeout = const Duration(seconds: 10),
  }) {
    _stopScan();
    final controller = StreamController<DiscoveredDevice>();
    _scan = controller;

    void advertise() {
      for (final p in peripherals) {
        if (withServices.isNotEmpty && !withServices.any(p.advert.advertises)) continue;
        final jitter = _random.nextInt(7) - 3;
        controller.add(p.advert.copyWith(rssi: p.advert.rssi + jitter));
      }
    }

    controller.onListen = () {
      if (_status != AdapterStatus.on) {
        controller.addError(const BleException('Bluetooth is off'));
        _stopScan();
        return;
      }
      advertise();
      _scanTimer = Timer.periodic(advertiseEvery, (_) => advertise());
      _scanTimeout = Timer(timeout, _stopScan);
    };
    controller.onCancel = _stopScan;
    return controller.stream;
  }

  @override
  Future<void> stopScan() async => _stopScan();

  void _stopScan() {
    _scanTimer?.cancel();
    _scanTimeout?.cancel();
    _scanTimer = null;
    _scanTimeout = null;
    final controller = _scan;
    _scan = null;
    if (controller != null && !controller.isClosed) controller.close();
  }

  @override
  Future<BleConnection> connect(
    String deviceId, {
    Duration timeout = const Duration(seconds: 15),
  }) async {
    final peripheral = peripherals.where((p) => p.id == deviceId).firstOrNull;
    if (peripheral == null) throw BleException('No device $deviceId');
    if (!peripheral.advert.connectable) throw BleException('$deviceId does not accept connections');
    if (_status != AdapterStatus.on) throw const BleException('Bluetooth is off');
    await Future<void>.delayed(peripheral.connectDelay);
    if (peripheral.failConnect) throw BleException('Could not connect to $deviceId');
    _connections[deviceId]?.drop();
    final connection = DemoConnection._(this, peripheral);
    _connections[deviceId] = connection;
    return connection;
  }

  /// Simulates the link dropping (device out of range, rebooted...).
  void dropConnection(String deviceId) => _connections[deviceId]?.drop();

  /// Whether a device currently has an open connection.
  bool isConnected(String deviceId) => _connections.containsKey(deviceId);
}

class DemoConnection implements BleConnection {
  DemoConnection._(this._adapter, this._peripheral);

  final DemoAdapter _adapter;
  final DemoPeripheral _peripheral;
  final StreamController<ConnectionStatus> _statusChanges = StreamController.broadcast();
  final List<StreamSubscription<List<int>>> _subscriptions = [];
  ConnectionStatus _status = ConnectionStatus.connected;
  int _mtu = 23;

  @override
  String get deviceId => _peripheral.id;

  @override
  Stream<ConnectionStatus> get status async* {
    yield _status;
    yield* _statusChanges.stream;
  }

  @override
  int get mtu => _mtu;

  @override
  Future<int> requestMtu(int mtu) async {
    _check();
    _mtu = min(mtu, _peripheral.maxMtu);
    return _mtu;
  }

  @override
  Future<List<GattService>> discoverServices() async {
    _check();
    return _peripheral.services;
  }

  @override
  Future<List<int>> read(GattCharacteristic characteristic) async {
    _check();
    if (!characteristic.props.read) throw BleException('${characteristic.displayName} is not readable');
    final value = _peripheral.values[characteristic.key];
    if (value == null) throw BleException('No value for ${characteristic.displayName}');
    return List.of(value);
  }

  @override
  Future<void> write(
    GattCharacteristic characteristic,
    List<int> value, {
    bool withoutResponse = false,
  }) async {
    _check();
    final allowed = withoutResponse ? characteristic.props.writeWithoutResponse : characteristic.props.write;
    if (!allowed) throw BleException('${characteristic.displayName} does not accept this kind of write');
    if (value.length > _mtu - 3) {
      throw BleException('Write of ${value.length} bytes exceeds MTU $_mtu');
    }
    _peripheral.writes.add(List.of(value));
    _peripheral.onWrite?.call(characteristic, value);
  }

  @override
  Stream<List<int>> subscribe(GattCharacteristic characteristic) {
    final source = characteristic.props.canSubscribe ? _peripheral.notifications?.call(characteristic) : null;
    if (source == null) {
      return Stream.error(BleException('${characteristic.displayName} does not notify'));
    }
    late StreamController<List<int>> controller;
    StreamSubscription<List<int>>? sub;
    controller = StreamController<List<int>>(
      onListen: () {
        sub = source.listen(controller.add, onError: controller.addError);
        _subscriptions.add(sub!);
      },
      onCancel: () {
        final s = sub;
        if (s != null) {
          _subscriptions.remove(s);
          s.cancel();
        }
      },
    );
    return controller.stream;
  }

  @override
  Future<void> disconnect() async {
    if (_status == ConnectionStatus.disconnected) return;
    _close();
  }

  /// Ends the connection as if the radio link was lost.
  void drop() => _close();

  void _close() {
    for (final s in _subscriptions) {
      s.cancel();
    }
    _subscriptions.clear();
    _status = ConnectionStatus.disconnected;
    _statusChanges.add(ConnectionStatus.disconnected);
    if (_adapter._connections[deviceId] == this) _adapter._connections.remove(deviceId);
  }

  void _check() {
    if (_status != ConnectionStatus.connected) throw const BleException('Not connected');
  }
}

/// The devices the demo mode shows, plus the virtual printer they print to.
class DemoDevices {
  DemoDevices({Random? random, Duration connectDelay = const Duration(milliseconds: 350)}) {
    final rnd = random ?? Random();
    adapter = DemoAdapter(
      [
        _heartRateBand(rnd, connectDelay),
        _printer(connectDelay),
        _uartBoard(connectDelay),
        DemoPeripheral(
          advert: const DiscoveredDevice(
            id: 'D4:2F:91:0C:77:3A',
            name: '',
            rssi: -88,
            manufacturerData: {
              0x004C: [0x02, 0x15, 0xE2, 0xC5, 0x6D, 0xB5],
            },
            connectable: false,
          ),
        ),
      ],
      random: rnd,
    );
  }

  late final DemoAdapter adapter;

  /// Receives everything sent to the demo printer.
  final VirtualPrinter printer = VirtualPrinter();

  static const String heartRateId = 'C8:1E:A4:52:90:11';
  static const String printerId = '66:22:B3:0F:4D:A8';
  static const String uartId = 'F1:03:7C:2E:5B:94';

  static const String uartService = '6e400001-b5a3-f393-e0a9-e50e24dcca9e';
  static const String uartRx = '6e400002-b5a3-f393-e0a9-e50e24dcca9e';
  static const String uartTx = '6e400003-b5a3-f393-e0a9-e50e24dcca9e';

  static GattCharacteristic _char(String service, String uuid, CharProps props) =>
      GattCharacteristic(serviceUuid: service, uuid: uuid, props: props);

  static GattService _deviceInfo(String maker, String model) => GattService(
        uuid: KnownUuids.deviceInformation,
        characteristics: [
          _char(KnownUuids.deviceInformation, KnownUuids.manufacturerName, const CharProps(read: true)),
          _char(KnownUuids.deviceInformation, KnownUuids.modelNumber, const CharProps(read: true)),
        ],
      );

  static Map<String, List<int>> _deviceInfoValues(String maker, String model) => {
        _char(KnownUuids.deviceInformation, KnownUuids.manufacturerName, const CharProps()).key: utf8.encode(maker),
        _char(KnownUuids.deviceInformation, KnownUuids.modelNumber, const CharProps()).key: utf8.encode(model),
      };

  DemoPeripheral _heartRateBand(Random rnd, Duration connectDelay) {
    final measurement = _char(KnownUuids.heartRate, KnownUuids.heartRateMeasurement, const CharProps(notify: true));
    final location = _char(KnownUuids.heartRate, '2a38', const CharProps(read: true));
    final battery = _char(KnownUuids.battery, KnownUuids.batteryLevel, const CharProps(read: true, notify: true));
    var bpm = 72;
    var level = 87;
    return DemoPeripheral(
      advert: const DiscoveredDevice(
        id: heartRateId,
        name: 'Pulse Band 7',
        rssi: -58,
        serviceUuids: [KnownUuids.heartRate, KnownUuids.battery],
      ),
      connectDelay: connectDelay,
      services: [
        GattService(uuid: KnownUuids.heartRate, characteristics: [measurement, location]),
        GattService(uuid: KnownUuids.battery, characteristics: [battery]),
        _deviceInfo('Harborlane Labs', 'PB-7'),
      ],
      values: {
        location.key: [1], // chest
        battery.key: [level],
        ..._deviceInfoValues('Harborlane Labs', 'PB-7'),
      },
      notifications: (c) {
        if (c.key == measurement.key) {
          return Stream.periodic(const Duration(seconds: 1), (_) {
            bpm = (bpm + rnd.nextInt(7) - 3).clamp(58, 112);
            final rr = (60000 / bpm * 1024 / 1000).round();
            // Flags: contact supported + detected, RR intervals present.
            return [0x16, bpm, rr & 0xFF, rr >> 8];
          });
        }
        if (c.key == battery.key) {
          return Stream.periodic(const Duration(seconds: 20), (_) => [level = max(level - 1, 5)]);
        }
        return null;
      },
    );
  }

  DemoPeripheral _printer(Duration connectDelay) {
    final data = _char(
      KnownUuids.printerService,
      KnownUuids.printerWrite,
      const CharProps(write: true, writeWithoutResponse: true),
    );
    return DemoPeripheral(
      advert: const DiscoveredDevice(
        id: printerId,
        name: 'MPT-58 Printer',
        rssi: -64,
        serviceUuids: [KnownUuids.printerService],
      ),
      connectDelay: connectDelay,
      services: [
        GattService(uuid: KnownUuids.printerService, characteristics: [data]),
        _deviceInfo('Harborlane Labs', 'MPT-58'),
      ],
      values: _deviceInfoValues('Harborlane Labs', 'MPT-58'),
      onWrite: (c, value) {
        if (c.key == data.key) printer.feed(value);
      },
    );
  }

  DemoPeripheral _uartBoard(Duration connectDelay) {
    final rx = _char(uartService, uartRx, const CharProps(write: true, writeWithoutResponse: true));
    final tx = _char(uartService, uartTx, const CharProps(notify: true));
    final replies = StreamController<List<int>>.broadcast();
    return DemoPeripheral(
      advert: const DiscoveredDevice(
        id: uartId,
        name: 'Dev Board UART',
        rssi: -71,
        serviceUuids: [uartService],
      ),
      connectDelay: connectDelay,
      services: [
        GattService(uuid: uartService, characteristics: [rx, tx]),
      ],
      notifications: (c) => c.key == tx.key ? replies.stream : null,
      onWrite: (c, value) {
        if (c.key != rx.key) return;
        // Echoes what it receives, like the classic UART sample firmware.
        final text = utf8.decode(value, allowMalformed: true).trim();
        scheduleMicrotask(() => replies.add(utf8.encode('echo: $text')));
      },
    );
  }
}
