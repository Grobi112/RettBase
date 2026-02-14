/// Web: Badge setzen – direkt via Navigator.setAppBadge (PWA-Icon).
/// Zusätzlich postMessage an Service Worker (firebase-messaging-sw) falls dieser aktiv ist.
import 'package:flutter/foundation.dart';
import 'dart:html' as html;

int _lastUnreadCount = 0;
bool _visibilitySetup = false;

void updateBadgeWeb(int unreadCount) {
  _lastUnreadCount = unreadCount;
  if (!_visibilitySetup) {
    _visibilitySetup = true;
    setupVisibilityBadgeNotify();
  }
  _setBadgeDirect(unreadCount);
  _setBadgeViaServiceWorker(unreadCount, showNotification: false);
}

void setupVisibilityBadgeNotify() {
  try {
    html.document.addEventListener('visibilitychange', (_) {
      if (html.document.visibilityState == 'hidden' && _lastUnreadCount > 0) {
        _setBadgeViaServiceWorker(_lastUnreadCount, showNotification: true);
      } else if (html.document.visibilityState == 'visible') {
        // Bei Rückkehr: Badge erneut setzen (hilft z.B. Safari iOS)
        _setBadgeDirect(_lastUnreadCount);
      }
    });
    // pageshow: Badge nach Wiederherstellen des Tabs/Reload aktualisieren
    html.window.addEventListener('pageshow', (_) {
      _setBadgeDirect(_lastUnreadCount);
    });
  } catch (_) {}
}

/// Manueller Test: setzt Badge auf 5. Zum Prüfen ob die API auf dem Gerät funktioniert.
/// Rückgabe: true wenn API vorhanden und aufgerufen, sonst false.
bool testBadgeApi() {
  try {
    final nav = html.window.navigator as dynamic;
    if (!_hasBadgeApi(nav, 'setAppBadge')) return false;
    final p = nav.setAppBadge(5);
    if (p != null) _catchPromise(p);
    return true;
  } catch (_) {
    return false;
  }
}

void _setBadgeDirect(int unreadCount) {
  try {
    final nav = html.window.navigator as dynamic;
    if (unreadCount <= 0) {
      if (_hasBadgeApi(nav, 'clearAppBadge')) {
        final p = nav.clearAppBadge();
        if (p != null) _catchPromise(p);
        if (kDebugMode) debugPrint('RettBase Badge: clearAppBadge');
      }
    } else {
      if (_hasBadgeApi(nav, 'setAppBadge')) {
        final n = unreadCount > 99 ? 99 : unreadCount;
        final p = nav.setAppBadge(n);
        if (p != null) _catchPromise(p);
        if (kDebugMode) debugPrint('RettBase Badge: setAppBadge($n)');
      }
    }
  } catch (e) {
    if (kDebugMode) debugPrint('RettBase Badge: Fehler: $e');
  }
}

bool _hasBadgeApi(dynamic nav, String name) {
  try {
    return nav != null && nav[name] != null;
  } catch (_) {
    return false;
  }
}

void _catchPromise(dynamic p) {
  try {
    if (p == null) return;
    if (p is Future) {
      p.catchError((_) {});
    } else {
      final catchFn = (p as dynamic)['catch'];
      if (catchFn != null) catchFn((_) {});
    }
  } catch (_) {}
}

void _setBadgeViaServiceWorker(int unreadCount, {bool showNotification = false}) {
  try {
    final sw = html.window.navigator.serviceWorker;
    if (sw == null) return;
    final msg = unreadCount <= 0
        ? {'action': 'clearChatNotification'}
        : {
            'action': 'setBadge',
            'count': unreadCount > 99 ? 99 : unreadCount,
            'showNotification': showNotification,
          };
    // Sofort postMessage wenn Controller da – bei visibilitychange wird die Seite sonst evtl. suspendiert
    final controller = sw.controller;
    if (controller != null) {
      controller.postMessage(msg);
    } else {
      sw.ready.then((reg) => reg.active?.postMessage(msg));
    }
  } catch (_) {}
}

