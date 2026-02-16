import 'dart:async';
import 'dart:html' as html;

/// Startet den Service-Worker-Update-Check (nur Web).
/// Prüft periodisch auf neue Versionen und lädt die Seite neu, wenn ein Update verfügbar ist.
void initServiceWorkerUpdateListener() {
  if (html.window.navigator.serviceWorker == null) return;

  html.window.navigator.serviceWorker!.ready.then((registration) {
    html.window.navigator.serviceWorker!.addEventListener('controllerchange', (_) {
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

    // Sofort prüfen
    registration.update();

    // Beim Fokus zurück zur App (Tab-Wechsel) erneut prüfen
    html.window.onFocus.listen((_) => registration.update());

    // Alle 5 Minuten prüfen
    Timer.periodic(const Duration(minutes: 5), (_) => registration.update());
  });
}
