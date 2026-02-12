import 'dart:async';
import 'dart:html' as html;

/// Startet den Service-Worker-Update-Check (nur Web).
/// Prüft periodisch auf neue Versionen und lädt die Seite neu, wenn ein Update verfügbar ist.
void initServiceWorkerUpdateListener() {
  if (html.window.navigator.serviceWorker == null) return;

  html.window.navigator.serviceWorker!.ready.then((registration) {
    // Bei controllerchange: Neue SW aktiv → Seite neu laden für frische App
    html.window.navigator.serviceWorker!.addEventListener('controllerchange', (_) {
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
