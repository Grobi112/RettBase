/// Stub: Auf Native hat Push-Berechtigung eigene APIs (z. B. requestPermission via Firebase Messaging).
Future<void> ensureServiceWorkerRegisteredWeb() async {}

String getNotificationPermissionWeb() => 'granted';

Future<String> requestNotificationPermissionWeb() async => 'granted';
