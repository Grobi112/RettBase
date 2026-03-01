import 'dart:convert';
import 'dart:html' as html;
import 'dart:js_interop';

import 'package:web/web.dart' as web;

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

/// Web: Einmalige Versionsprüfung (vor Dashboard-Load).
/// Keine periodische Prüfung mehr – stört den Ablauf innerhalb der Session.
/// Reload nur wenn Server > Client – verhindert Endlosschleife durch Cache-Unterschiede.
Future<void> runWebVersionCheckOnce(void Function() onUpdateAvailable) async {
  final host = html.window.location.hostname;
  if (host == 'localhost' || host == '127.0.0.0' || host == '127.0.0.1') return;

  final baseUrl = AppConfig.androidUpdateCheckUrl;
  if (baseUrl == null || baseUrl.isEmpty) return;

  const reloadCooldownMs = 120000;  // 2 Min – nach Reload nicht erneut prüfen

  try {
    final lastReload = html.window.sessionStorage['rettbase_version_reload'];
    if (lastReload != null) {
      final t = int.tryParse(lastReload) ?? 0;
      if (DateTime.now().millisecondsSinceEpoch - t < reloadCooldownMs) return;
    }

    // Cache-Bypass: fetch mit cache:'no-store' umgeht SW- und HTTP-Cache (PWA-Handy)
    final url = '$baseUrl?t=${DateTime.now().millisecondsSinceEpoch}';
    final res = await web.window
        .fetch(url.toJS, web.RequestInit(cache: 'no-store'))
        .toDart
        .timeout(const Duration(seconds: 10));
    if (res.status != 200) return;
    final raw = (await res.text().toDart.timeout(const Duration(seconds: 10))).toDart.trim();
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

    if (serverVer.isEmpty || clientVer.isEmpty) return;
    if (!_isVersionNewer(serverVer, clientVer)) return;

    html.window.sessionStorage['rettbase_version_reload'] =
        '${DateTime.now().millisecondsSinceEpoch}';
    onUpdateAvailable();
  } catch (_) {}
}

/// Web: Version von Server holen und Meta-Tag aktualisieren – kein Reload.
/// Wird beim Dashboard-Laden aufgerufen, Nutzer bleibt angemeldet.
Future<void> updateWebVersionFromServer() async {
  final host = html.window.location.hostname;
  if (host == 'localhost' || host == '127.0.0.0' || host == '127.0.0.1') return;

  final baseUrl = AppConfig.androidUpdateCheckUrl;
  if (baseUrl == null || baseUrl.isEmpty) return;

  try {
    // Cache-Bypass: fetch mit cache:'no-store' umgeht SW- und HTTP-Cache (PWA-Handy)
    final url = '$baseUrl?t=${DateTime.now().millisecondsSinceEpoch}';
    final res = await web.window
        .fetch(url.toJS, web.RequestInit(cache: 'no-store'))
        .toDart
        .timeout(const Duration(seconds: 10));
    if (res.status != 200) return;
    final raw = (await res.text().toDart.timeout(const Duration(seconds: 10))).toDart.trim();
    if (raw.isEmpty || !raw.startsWith('{')) return;
    Map<String, dynamic>? data;
    try {
      data = jsonDecode(raw) as Map<String, dynamic>?;
    } catch (_) {
      return;
    }
    if (data == null) return;
    final serverVer = ((data['version'] as String?) ?? '').trim();
    if (serverVer.isEmpty) return;

    var meta = html.document.querySelector('meta[name="rettbase-version"]');
    if (meta == null) {
      meta = html.document.createElement('meta');
      meta.setAttribute('name', 'rettbase-version');
      html.document.head?.append(meta);
    }
    meta.setAttribute('content', serverVer);
  } catch (_) {}
}
