/// Web: Prüft und fordert Benachrichtigungs-Berechtigung per Browser-API.
/// Muss als Reaktion auf Benutzer-Tap aufgerufen werden (z. B. Button-Klick) –
/// sonst zeigen mobile Browser keinen Dialog.
import 'dart:html' as html;

/// Registriert den Firebase-Messaging-Service-Worker vor getToken.
/// Ohne aktiven SW schlägt getToken auf mobilen Browsern oft fehl.
Future<void> ensureServiceWorkerRegisteredWeb() async {
  final sw = html.window.navigator.serviceWorker;
  if (sw == null) return;
  try {
    final reg = await sw.ready;
    if (reg.active != null) return;
  } catch (_) {}
  try {
    await sw.register(
      '/firebase-messaging-sw.js',
      { 'scope': '/' },
    );
    await sw.ready;
  } catch (_) {}
}

String getNotificationPermissionWeb() {
  try {
    return html.Notification.permission ?? 'denied';
  } catch (_) {
    return 'denied';
  }
}

Future<String> requestNotificationPermissionWeb() async {
  try {
    return await html.Notification.requestPermission();
  } catch (_) {
    return 'denied';
  }
}
