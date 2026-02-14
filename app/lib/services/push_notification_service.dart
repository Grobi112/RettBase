import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_app_badger/flutter_app_badger.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:app/app_config.dart';
import 'package:app/services/push_badge_stub.dart'
    if (dart.library.html) 'package:app/services/push_badge_web.dart' as badge_impl;
import 'package:app/services/push_permission_stub.dart'
    if (dart.library.html) 'package:app/services/push_permission_web.dart' as perm_impl;

/// Push-Benachrichtigungen und App-Icon-Badge für Chat.
/// FCM-Token wird in Firestore gespeichert; Cloud Function sendet Push bei neuer Nachricht.
class PushNotificationService {
  final _db = FirebaseFirestore.instance;
  final _messaging = FirebaseMessaging.instance;

  static String? _initialMessageChatId;
  static String? _initialMessageCompanyId;
  static String? _lastCompanyId;
  static String? _lastUid;
  static bool _tokenRefreshListenerActive = false;

  /// Setzt Chat-Kontext aus URL-Hash (Web: nach Klick auf Push-Notification).
  /// Format: #chat/companyId/chatId
  static void setInitialChatFromHash(String? hash) {
    if (hash == null || !hash.startsWith('#chat/')) return;
    final rest = hash.substring(6).split('/');
    if (rest.length >= 2) {
      _initialMessageCompanyId = rest[0].trim().isEmpty ? null : rest[0].trim();
      _initialMessageChatId = rest[1].trim().isEmpty ? null : rest[1].trim();
    }
  }

  /// Chat-Kontext aus Push (wenn App durch Benachrichtigung geöffnet wurde).
  static (String companyId, String chatId)? get initialChatFromNotification {
    if (_initialMessageCompanyId != null && _initialMessageChatId != null) {
      final c = _initialMessageCompanyId!;
      final ch = _initialMessageChatId!;
      _initialMessageCompanyId = null;
      _initialMessageChatId = null;
      return (c, ch);
    }
    return null;
  }

  /// Initialisierung: Berechtigungen, Handler, Token-Refresh.
  static Future<void> initialize() async {
    final service = PushNotificationService();
    await service._requestPermissions();
    FirebaseMessaging.onMessage.listen(service._onForegroundMessage);
    FirebaseMessaging.onMessageOpenedApp.listen(service._onBackgroundOpenedApp);
    final initial = await FirebaseMessaging.instance.getInitialMessage();
    if (initial != null) {
      _handleMessageData(initial.data);
    }
    if (!kIsWeb && !_tokenRefreshListenerActive) {
      _tokenRefreshListenerActive = true;
      FirebaseMessaging.instance.onTokenRefresh.listen((token) {
        if (_lastCompanyId != null && _lastUid != null && token.isNotEmpty) {
          PushNotificationService()._saveTokenToFirestore(_lastCompanyId!, _lastUid!, token);
        }
      });
    }
  }

  Future<void> _requestPermissions() async {
    if (kIsWeb) return;
    final settings = await _messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );
    debugPrint('RettBase Push: permission ${settings.authorizationStatus}');
  }

  void _onForegroundMessage(RemoteMessage message) {
    debugPrint('RettBase Push: foreground ${message.data}');
    if (kIsWeb && message.data != null) {
      final badgeStr = message.data!['badge'] as String?;
      if (badgeStr != null && badgeStr.isNotEmpty) {
        final badge = int.tryParse(badgeStr);
        if (badge != null && badge > 0) {
          updateBadge(badge);
        }
      }
    }
  }

  void _onBackgroundOpenedApp(RemoteMessage message) {
    debugPrint('RettBase Push: opened from background ${message.data}');
    _handleMessageData(message.data);
  }

  static void _handleMessageData(Map<String, dynamic>? data) {
    if (data == null) return;
    final type = data['type'] as String?;
    if (type == 'chat') {
      _initialMessageCompanyId = data['companyId'] as String?;
      _initialMessageChatId = data['chatId'] as String?;
    }
  }

  /// FCM-Token in Firestore speichern (nach Login). Wird bei jedem Dashboard-Load aufgerufen.
  Future<void> saveToken(String companyId, String uid) async {
    _lastCompanyId = companyId;
    _lastUid = uid;
    if (kIsWeb) {
      try {
        if (AppConfig.fcmWebVapidKey == null || AppConfig.fcmWebVapidKey!.isEmpty) {
          debugPrint('RettBase Push Web: VAPID-Key fehlt – Token wird nicht abgerufen');
          return;
        }
        await perm_impl.ensureServiceWorkerRegisteredWeb();
        final token = await _messaging.getToken(vapidKey: AppConfig.fcmWebVapidKey);
        if (token == null || token.isEmpty) {
          debugPrint('RettBase Push Web: getToken lieferte null – Berechtigung prüfen');
          return;
        }
        await _saveTokenToFirestore(companyId, uid, token);
        debugPrint('RettBase Push Web: Token erfolgreich gespeichert für $companyId / $uid');
      } catch (e) {
        debugPrint('RettBase Push Web: token speichern fehlgeschlagen: $e');
      }
      return;
    }
    try {
      final token = await _messaging.getToken();
      if (token == null || token.isEmpty) {
        debugPrint('RettBase Push: getToken lieferte null – Berechtigung prüfen');
        return;
      }
      await _saveTokenToFirestore(companyId, uid, token);
    } catch (e) {
      debugPrint('RettBase Push: token speichern fehlgeschlagen: $e');
    }
  }

  Future<void> _saveTokenToFirestore(String companyId, String uid, String token) async {
    try {
      final data = {
        'fcmToken': token,
        'fcmTokenUpdatedAt': FieldValue.serverTimestamp(),
      };
      await _db.collection('kunden').doc(companyId).collection('users').doc(uid).set(data, SetOptions(merge: true));
      await _db.collection('fcmTokens').doc(uid).set(data, SetOptions(merge: true));
      debugPrint('RettBase Push: token gespeichert für $companyId / $uid (global)');
    } catch (e) {
      debugPrint('RettBase Push: Firestore-Schreiben fehlgeschlagen: $e');
    }
  }

  /// Web: Startet Permission-Anfrage – muss synchron im Tap-Handler aufgerufen werden
  /// (vor Navigator.pop oder await), sonst blockiert der mobile Browser den Dialog.
  static Future<String>? startNotificationPermissionRequestForWeb() {
    if (!kIsWeb) return null;
    return perm_impl.requestNotificationPermissionWeb();
  }

  /// Web: Berechtigung per Benutzer-Tap anfordern (mobil erforderlich).
  /// [permissionFuture] muss von startNotificationPermissionRequestForWeb() kommen,
  /// synchron im Tap-Handler aufgerufen – sonst zeigt der mobile Browser keinen Dialog.
  /// Gibt (erfolg, nachReloadVersuchen) zurück.
  static Future<(bool success, bool needsReload)> requestPermissionAndSaveTokenForWeb(
    String companyId,
    String uid, {
    Future<String>? permissionFuture,
  }) async {
    if (!kIsWeb) return (false, false);
    try {
      final perm = permissionFuture != null
          ? await permissionFuture
          : await perm_impl.requestNotificationPermissionWeb();
      if (perm != 'granted') return (false, false);
      try {
        await PushNotificationService().saveToken(companyId, uid);
        return (true, false);
      } catch (e) {
        debugPrint('RettBase Push Web: getToken fehlgeschlagen (evtl. Seite neu laden): $e');
        return (false, true);
      }
    } catch (e) {
      debugPrint('RettBase Push Web: Permission-Anfrage fehlgeschlagen: $e');
      return (false, false);
    }
  }

  /// Web: Aktuellen Berechtigungsstatus prüfen (z. B. um Button anzuzeigen).
  static String getNotificationPermissionStatusWeb() {
    if (!kIsWeb) return 'granted';
    return perm_impl.getNotificationPermissionWeb();
  }

  /// Prüft ob FCM-Token in Firestore gespeichert ist (via Cloud Function).
  static Future<bool> checkFcmTokenInFirestore(String companyId) async {
    try {
      final res = await FirebaseFunctions.instanceFor(region: 'europe-west1')
          .httpsCallable('getFcmTokenStatus')
          .call<Map<String, dynamic>>({'companyId': companyId});
      return res.data['hasToken'] == true;
    } catch (_) {
      return false;
    }
  }

  /// App-Icon-Badge setzen (iOS/Android: flutter_app_badger; Web: Badging API).
  static Future<void> updateBadge(int unreadCount) async {
    if (kIsWeb) {
      _updateBadgeWeb(unreadCount);
      return;
    }
    try {
      if (unreadCount <= 0) {
        await FlutterAppBadger.removeBadge();
      } else {
        await FlutterAppBadger.updateBadgeCount(unreadCount > 99 ? 99 : unreadCount);
      }
    } catch (e) {
      debugPrint('RettBase Push: badge update fehlgeschlagen: $e');
    }
  }

  static void _updateBadgeWeb(int unreadCount) {
    badge_impl.updateBadgeWeb(unreadCount);
  }

  /// Web: Test ob Badge-API verfügbar ist. Setzt Badge auf 5 – App minimieren und Icon prüfen.
  static bool testBadgeApiWeb() => kIsWeb && badge_impl.testBadgeApi();
}
