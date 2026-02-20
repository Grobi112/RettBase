import 'dart:html' as html;

/// Lädt die Seite neu und umgeht den Cache. Deregistriert zuvor den Service Worker,
/// damit der Reload index.html frisch vom Server holt (ohne Query-Parameter).
void reload() {
  if (html.window.navigator.serviceWorker != null) {
    html.window.navigator.serviceWorker!.ready.then((_) {
      return html.window.navigator.serviceWorker!.getRegistrations();
    }).then((regs) {
      return Future.wait(regs.map((r) => r.unregister()));
    }).then((_) {
      html.window.location.reload();
    }).catchError((_) {
      html.window.location.reload();
    });
  } else {
    html.window.location.reload();
  }
}
