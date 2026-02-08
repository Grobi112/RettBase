import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';

Future<bool> isSimulatorOrEmulator() async {
  try {
    final deviceInfo = DeviceInfoPlugin();
    if (Platform.isIOS) {
      final ios = await deviceInfo.iosInfo;
      return !ios.isPhysicalDevice;
    }
    if (Platform.isAndroid) {
      final android = await deviceInfo.androidInfo;
      return !android.isPhysicalDevice;
    }
  } catch (_) {}
  return false;
}
