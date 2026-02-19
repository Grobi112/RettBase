import 'dart:async';
import 'dart:convert';
import 'dart:html' as html;

import '../app_config.dart';

/// Liest die in index.html eingetragene Client-Version (meta rettbase-version).
String _getClientVersion() {
  final meta = html.document.querySelector('meta[name="rettbase-version"]');
  return (meta?.getAttribute('content') ?? '').trim();
}

/// Web: Prüft periodisch version.json; bei neuer Version wird die Seite automatisch neu geladen.
/// Vergleicht die in index.html eingebettete Version mit der Server-Version.
void initWebVersionCheck(void Function() onUpdateAvailable) {
  // Lokale Entwicklung (localhost): CORS verhindert Abruf von app.rettbase.de – überspringen
  final host = html.window.location.hostname;
  if (host == 'localhost' || host == '127.0.0.0' || host == '127.0.0.1') return;

  final baseUrl = AppConfig.androidUpdateCheckUrl;
  if (baseUrl == null || baseUrl.isEmpty) return;

  const checkInterval = Duration(minutes: 5);

  Future<void> check() async {
    try {
      // Cache-Busting: verhindert gecachte version.json
      final url = '$baseUrl?t=${DateTime.now().millisecondsSinceEpoch}';
      final res = await html.HttpRequest.request(url, method: 'GET')
          .timeout(const Duration(seconds: 10));
      if (res.status != 200) return;
      final data = jsonDecode(res.responseText ?? '{}') as Map<String, dynamic>?;
      if (data == null) return;
      final v = (data['version'] as String?) ?? '';
      final serverVer = v.trim();

      final clientVer = _getClientVersion();
      if (serverVer.isNotEmpty && clientVer.isNotEmpty && serverVer != clientVer) {
        onUpdateAvailable();
      }
    } catch (_) {}
  }

  // Erster Check nach 10 Sek (früher als 30)
  Future.delayed(const Duration(seconds: 10), check);
  // Bei Tab-Fokus erneut prüfen
  html.window.onFocus.listen((_) => check());
  // Alle 5 Minuten
  Timer.periodic(checkInterval, (_) => check());
}
