/// Stub: Kein App-Update-Check (Web, iOS).
import 'app_update_types.dart';

bool get canCheckAppUpdate => false;
Future<AppUpdateResult> checkForAppUpdate() async =>
    AppUpdateResult.upToDate;
Future<void> openApkDownloadUrl() async {}
void setAppUpdateNavigatorContext(dynamic context) {}
void setAppUpdateNavigatorKey(dynamic key) {}
Future<AppUpdateResult> checkForAppUpdateWithContext(dynamic context) async =>
    AppUpdateResult.upToDate;
