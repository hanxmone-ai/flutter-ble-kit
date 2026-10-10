import 'models.dart';

/// Everything the app needs from a Bluetooth stack.
///
/// The app talks only to this interface. `FlutterBluePlusAdapter` implements it
/// on real hardware and `DemoAdapter` simulates devices, so all logic above it
/// can be tested without a phone.
abstract class BleAdapter {
  /// The radio's state; emits the current state first.
  Stream<AdapterStatus> get status;

  /// Asks the user to turn Bluetooth on (Android only; elsewhere a no-op).
  Future<void> turnOn();

  /// Scans for [timeout] and emits every advertisement seen. The stream closes
  /// when the scan ends. Pass [withServices] to only see matching devices.
  Stream<DiscoveredDevice> scan({
    List<String> withServices = const [],
    Duration timeout = const Duration(seconds: 10),
  });

  /// Ends a running scan early.
  Future<void> stopScan();

  /// Connects to the device with [deviceId].
  Future<BleConnection> connect(
    String deviceId, {
    Duration timeout = const Duration(seconds: 15),
  });
}

/// An open connection to one peripheral.
abstract class BleConnection {
  String get deviceId;

  /// Connection state changes, starting with the current state.
  Stream<ConnectionStatus> get status;

  /// The negotiated ATT MTU. A single write can carry `mtu - 3` bytes.
  int get mtu;

  /// Asks for a larger MTU (Android; iOS negotiates by itself) and returns the
  /// MTU in effect afterwards.
  Future<int> requestMtu(int mtu);

  Future<List<GattService>> discoverServices();

  Future<List<int>> read(GattCharacteristic characteristic);

  Future<void> write(
    GattCharacteristic characteristic,
    List<int> value, {
    bool withoutResponse = false,
  });

  /// Turns on notifications or indications and emits each value received.
  /// Cancelling the subscription turns them off again.
  Stream<List<int>> subscribe(GattCharacteristic characteristic);

  Future<void> disconnect();
}
