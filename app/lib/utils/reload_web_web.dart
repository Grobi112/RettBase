import 'dart:html' as html;

/// Lädt die Seite neu und umgeht den Cache, damit index.html mit aktualisierter
/// Version geladen wird (verhindert erneutes Anzeigen des Update-Banners).
void reload() {
  final uri = html.window.location;
  final base = '${uri.protocol}//${uri.host}${uri.pathname}';
  final separator = (uri.search == null || uri.search!.isEmpty) ? '?' : '&';
  html.window.location.href = '$base${separator}_=${DateTime.now().millisecondsSinceEpoch}';
}
