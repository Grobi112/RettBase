/// App-Update-Check: nur auf Android aktiv (APK-Direktverteilung).
import 'package:flutter/material.dart';

import 'app_update_types.dart';
export 'app_update_types.dart';
import 'app_update_service_stub.dart'
    if (dart.library.io) 'app_update_service_android.dart' as app_update;

bool get canCheckAppUpdate => app_update.canCheckAppUpdate;
Future<AppUpdateResult> checkForAppUpdate() => app_update.checkForAppUpdate();
Future<void> openApkDownloadUrl() => app_update.openApkDownloadUrl();
void setAppUpdateNavigatorContext(BuildContext? context) =>
    app_update.setAppUpdateNavigatorContext(context);
void setAppUpdateNavigatorKey(GlobalKey<NavigatorState>? key) =>
    app_update.setAppUpdateNavigatorKey(key);
Future<void> checkForAppUpdateWithContext(BuildContext context) =>
    app_update.checkForAppUpdateWithContext(context);
