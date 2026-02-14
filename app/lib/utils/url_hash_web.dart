/// Web: Liest und bereinigt URL-Hash (z.B. für Notification-Klick: #chat/companyId/chatId).
import 'dart:html' as html;

String? getInitialHash() {
  final h = html.window.location.hash;
  return h.isEmpty ? null : h;
}

/// Entfernt den Hash aus der URL (nach Verarbeitung).
void clearHash() {
  final loc = html.window.location;
  final path = loc.pathname ?? '';
  final search = loc.search ?? '';
  html.window.history.replaceState(null, '', path + search);
}
