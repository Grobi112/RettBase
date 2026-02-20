import 'dart:async';
import 'dart:convert';
import 'dart:html' as html;

import '../app_config.dart';

/// Liest die in index.html eingetragene Client-Version (meta rettbase-version).
String _getClientVersion() {
  final meta = html.document.querySelector('meta[name="rettbase-version"]');
  return (meta?.getAttribute('content') ?? '').trim();
}

/// Vergleicht Versions-Strings (z.B. "1.0.8" vs "1.0.7"). Rückgabe: true wenn a > b.
bool _isVersionNewer(String a, String b) {
  final aa = a.split('.').map((s) => int.tryParse(s.trim()) ?? 0).toList();
  final bb = b.split('.').map((s) => int.tryParse(s.trim()) ?? 0).toList();
  for (var i = 0; i < aa.length || i < bb.length; i++) {
    final va = i < aa.length ? aa[i] : 0;
    final vb = i < bb.length ? bb[i] : 0;
    if (va > vb) return true;
    if (va < vb) return false;
  }
  return false;
}

/// Web: Prüft periodisch version.json; nur bei echt neuer Server-Version wird neu geladen.
/// Reload nur wenn Server > Client – verhindert Endlosschleife durch Cache-Unterschiede.
void initWebVersionCheck(void Function() onUpdateAvailable) {
  final host = html.window.location.hostname;
  if (host == 'localhost' || host == '127.0.0.0' || host == '127.0.0.1') return;

  final baseUrl = AppConfig.androidUpdateCheckUrl;
  if (baseUrl == null || baseUrl.isEmpty) return;

  const checkInterval = Duration(minutes: 5);
  const reloadCooldownMs = 120000;  // 2 Min – nach Reload nicht erneut prüfen

  Future<void> check() async {
    try {
      // Cooldown: Kein Reload, wenn wir kürzlich schon einen ausgelöst haben (z.B. Tab-Wechsel während Reload)
      final lastReload = html.window.sessionStorage['rettbase_version_reload'];
      if (lastReload != null) {
        final t = int.tryParse(lastReload) ?? 0;
        if (DateTime.now().millisecondsSinceEpoch - t < reloadCooldownMs) return;
      }

      final url = '$baseUrl?t=${DateTime.now().millisecondsSinceEpoch}';
      final res = await html.HttpRequest.request(url, method: 'GET')
          .timeout(const Duration(seconds: 10));
      if (res.status != 200) return;
      final raw = (res.responseText ?? '').trim();
      if (raw.isEmpty || !raw.startsWith('{')) return;
      Map<String, dynamic>? data;
      try {
        data = jsonDecode(raw) as Map<String, dynamic>?;
      } catch (_) {
        return;
      }
      if (data == null) return;
      final serverVer = ((data['version'] as String?) ?? '').trim();
      final clientVer = _getClientVersion();

      // Nur neu laden, wenn Server-Version echt neuer ist (nicht bei Cache-Abweichung)
      if (serverVer.isEmpty || clientVer.isEmpty) return;
      if (!_isVersionNewer(serverVer, clientVer)) return;

      html.window.sessionStorage['rettbase_version_reload'] = '${DateTime.now().millisecondsSinceEpoch}';
      onUpdateAvailable();
    } catch (_) {}
  }

  Future.delayed(const Duration(seconds: 10), check);
  html.window.onFocus.listen((_) => check());
  Timer.periodic(checkInterval, (_) => check());
}
