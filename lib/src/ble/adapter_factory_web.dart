import '../demo/demo_adapter.dart';
import 'ble_adapter.dart';

bool get hasRealBluetooth => false;

BleAdapter createAdapter({bool demo = false}) => DemoBleAdapter();
