import 'dart:html' as html;

/// Lädt die Seite neu und umgeht den Cache. Deregistriert zuvor den Service Worker,
/// damit der Reload index.html frisch vom Server holt (ohne Query-Parameter).
/// Kurze Verzögerung nach unregister für mobile Browser (PWA).
void reload() {
  void doReload() {
    // Cache-Bypass für PWA: URL mit Timestamp erzwingt frischen Abruf
    final uri = html.window.location;
    final base = '${uri.origin}${uri.pathname}';
    final search = uri.search ?? '';
    final sep = search.isEmpty ? '?' : '&';
    html.window.location.replace('$base$search$sep' '_nocache=${DateTime.now().millisecondsSinceEpoch}');
  }

  if (html.window.navigator.serviceWorker != null) {
    html.window.navigator.serviceWorker!.ready.then((_) {
      return html.window.navigator.serviceWorker!.getRegistrations();
    }).then((regs) {
      return Future.wait(regs.map((r) => r.unregister()));
    }).then((_) {
      // Kurze Verzögerung: mobile Browser brauchen Zeit, bis unregister wirkt
      return Future.delayed(const Duration(milliseconds: 150));
    }).then((_) {
      doReload();
    }).catchError((_) {
      doReload();
    });
  } else {
    doReload();
  }
}
