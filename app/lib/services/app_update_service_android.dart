import 'dart:io' show Platform;

import 'app_update_types.dart';

/// Android: Direkte APK-Updates wurden entfernt – Updates laufen über den Play Store.
bool get canCheckAppUpdate => false;

Future<AppUpdateResult> checkForAppUpdate() async {
  if (!Platform.isAndroid) return AppUpdateResult.upToDate;
  return AppUpdateResult.upToDate;
}

void setAppUpdateNavigatorContext(BuildContext? context) {}
void setAppUpdateNavigatorKey(GlobalKey<NavigatorState>? key) {}

/// Öffentlich: Manueller Update-Check aus Einstellungen. Muss mit [context] aufgerufen werden.
Future<AppUpdateResult> checkForAppUpdateWithContext(BuildContext context) async {
  if (!Platform.isAndroid) return AppUpdateResult.upToDate;
  return checkForAppUpdate();
}

/// APK-Download wurde entfernt – Updates über Play Store.
Future<void> openApkDownloadUrl() async {}
