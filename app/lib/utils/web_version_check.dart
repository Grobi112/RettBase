/// Web-Versionsprüfung: nur auf Web aktiv.
import 'web_version_check_stub.dart'
    if (dart.library.html) 'web_version_check_web.dart' as impl;

void initWebVersionCheck(void Function() onUpdateAvailable) =>
    impl.initWebVersionCheck(onUpdateAvailable);
