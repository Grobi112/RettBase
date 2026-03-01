/// Web-Versionsprüfung: nur auf Web aktiv.
import 'web_version_check_stub.dart'
    if (dart.library.html) 'web_version_check_web.dart' as impl;

Future<void> runWebVersionCheckOnce(void Function() onUpdateAvailable) =>
    impl.runWebVersionCheckOnce(onUpdateAvailable);

/// Version von Server holen und Meta-Tag aktualisieren – kein Reload (beim Dashboard-Laden).
Future<void> updateWebVersionFromServer() => impl.updateWebVersionFromServer();
