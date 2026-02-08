import 'device_utils_stub.dart'
    if (dart.library.io) 'device_utils_io.dart' as _impl;

/// Prüft, ob die App im Simulator (iOS) bzw. Emulator (Android) läuft.
/// Im Simulator/Emulator ist keine Touch-Unterschrift möglich.
Future<bool> isSimulatorOrEmulator() => _impl.isSimulatorOrEmulator();
