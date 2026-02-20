/// Web-Versionsprüfung: nur auf Web aktiv (einmalig vor Dashboard-Load).
import 'web_version_check_stub.dart'
    if (dart.library.html) 'web_version_check_web.dart' as impl;

Future<void> runWebVersionCheckOnce(void Function() onUpdateAvailable) =>
    impl.runWebVersionCheckOnce(onUpdateAvailable);
