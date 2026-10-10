// Picks the real Bluetooth adapter where dart:io exists (Android, iOS) and the
// simulated one elsewhere (the web demo).
export 'adapter_factory_web.dart' if (dart.library.io) 'adapter_factory_io.dart';
