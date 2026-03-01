import 'dart:html' as html;

/// Service-Worker-Controller-Wechsel: Reload nur wenn neuer SW aktiv wird (z.B. nach Tab-Schließen).
/// Keine Update-Prüfung während der Session – Updates erfolgen über „Dashboard laden“.
void initServiceWorkerUpdateListener() {
  if (html.window.navigator.serviceWorker == null) return;

  html.window.navigator.serviceWorker!.ready.then((registration) {
    registration.addEventListener('controllerchange', (_) {
      final key = 'rettbase_sw_reload';
      final last = html.window.sessionStorage[key];
      final now = DateTime.now().millisecondsSinceEpoch;
      if (last != null) {
        final t = int.tryParse(last) ?? 0;
        if (now - t < 30000) return;
      }
      html.window.sessionStorage[key] = '$now';
      html.window.location.reload();
    });
  });
}
