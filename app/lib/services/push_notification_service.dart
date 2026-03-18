import 'dart:async';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_app_badger/flutter_app_badger.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:just_audio/just_audio.dart';
import 'package:flutter_volume_controller/flutter_volume_controller.dart';
import 'package:app/app_config.dart';
import 'package:app/services/alarm_quittierung_service.dart';
import 'package:app/services/tone_settings_service.dart';
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
  static String? _initialAlarmCompanyId;
  static String? _initialAlarmEinsatzId;
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

  /// Setzt Alarm-Kontext aus URL-Hash (Web: nach Klick auf Alarm-Push).
  /// Format: #einsatz/companyId/einsatzId
  static void setInitialAlarmFromHash(String? hash) {
    if (hash == null || !hash.startsWith('#einsatz/')) return;
    final rest = hash.substring(9).split('/');
    if (rest.length >= 2) {
      _initialAlarmCompanyId = rest[0].trim().isEmpty ? null : rest[0].trim();
      _initialAlarmEinsatzId = rest[1].trim().isEmpty ? null : rest[1].trim();
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

  /// Ob ein Alarm-Popup beim App-Öffnen ansteht (Nutzer hat über Benachrichtigung geöffnet).
  /// Wird nicht konsumiert – nur zur Prüfung, ob wir den Alarmton unterdrücken sollen.
  static bool get hasPendingInitialAlarm =>
      _initialAlarmCompanyId != null && _initialAlarmEinsatzId != null;

  /// Alarm-Kontext aus Push (wenn App durch Alarm-Benachrichtigung geöffnet wurde).
  static (String companyId, String einsatzId)? get initialAlarmFromNotification {
    if (_initialAlarmCompanyId != null && _initialAlarmEinsatzId != null) {
      final c = _initialAlarmCompanyId!;
      final e = _initialAlarmEinsatzId!;
      _initialAlarmCompanyId = null;
      _initialAlarmEinsatzId = null;
      return (c, e);
    }
    return null;
  }

  static Future<void>? _initFuture;

  /// Initialisierung: Berechtigungen, Handler, Token-Refresh.
  /// Vor saveToken [ensureInitialized] abwarten, damit Permission-Dialog beantwortet ist.
  static Future<void> initialize() async {
    _initFuture ??= _initializeImpl();
    await _initFuture;
  }

  static Future<void> _initializeImpl() async {
    final service = PushNotificationService();
    await service._requestPermissions();
    if (!kIsWeb) {
      await FirebaseMessaging.instance.setForegroundNotificationPresentationOptions(
        alert: true,
        badge: true,
        sound: true,
      );
    }
    FirebaseMessaging.onMessage.listen(service._onForegroundMessage);
    FirebaseMessaging.onMessageOpenedApp.listen(service._onBackgroundOpenedApp);
    final initial = await FirebaseMessaging.instance.getInitialMessage();
    if (initial != null) _handleMessageData(initial.data);
    if (!kIsWeb && !_tokenRefreshListenerActive) {
      _tokenRefreshListenerActive = true;
      FirebaseMessaging.instance.onTokenRefresh.listen((token) {
        if (_lastCompanyId != null && _lastUid != null && token.isNotEmpty) {
          PushNotificationService()._saveTokenToFirestore(_lastCompanyId!, _lastUid!, token);
        }
      });
    }
  }

  /// Wartet auf Initialisierung (Permission). Vor saveToken aufrufen.
  static Future<void> ensureInitialized() => initialize();

  Future<void> _requestPermissions() async {
    if (kIsWeb) return;
    final settings = await _messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );
    debugPrint('RettBase Push: permission ${settings.authorizationStatus} (authorized=${settings.authorizationStatus == AuthorizationStatus.authorized})');
  }

  void _onForegroundMessage(RemoteMessage message) {
    debugPrint('RettBase Push: foreground ${message.data}');
    final data = message.data ?? const {};
    final type = data['type'] as String?;
    if (type == 'chat') {
      final badgeStr = data['totalUnread'] ?? data['badge'];
      if (badgeStr != null && badgeStr.toString().isNotEmpty) {
        final badge = int.tryParse(badgeStr.toString());
        if (badge != null && badge >= 0) {
          updateBadge(badge);
        }
      }
    } else if (type == 'alarm' && !kIsWeb) {
      // Kein Alarmton, wenn Nutzer App über Benachrichtigung geöffnet hat – Popup kommt
      if (!hasPendingInitialAlarm) {
        unawaited(_maybePlayAlarmTone(data));
      }
    }
  }

  /// Spielt den Alarm-Ton nur, wenn der Einsatz noch nicht quittiert wurde.
  Future<void> _maybePlayAlarmTone(Map<String, dynamic> data) async {
    final companyId = data['companyId'] as String? ?? '';
    final einsatzId = data['einsatzId'] as String? ?? '';
    final quittiert = await AlarmQuittierungService().isQuittiert(companyId, einsatzId);
    if (quittiert) return;
    await _playAlarmTone();
  }

  static AudioPlayer? _alarmPlayer;
  static double? _volumeBeforeAlarm;

  /// Ob der Alarm-Ton gerade abgespielt wird (Foreground-Push).
  static bool get isAlarmTonePlaying => _alarmPlayer != null;

  /// Stoppt den laufenden Alarm-Ton (z.B. nach Quittierung oder Schließen des Popups).
  static Future<void> stopAlarmTone() async {
    final p = _alarmPlayer;
    if (p != null) {
      _alarmPlayer = null;
      try {
        await p.stop();
      } catch (_) {}
      await p.dispose();
    }
    // Lautstärke wiederherstellen
    if (!kIsWeb && _volumeBeforeAlarm != null) {
      try {
        await FlutterVolumeController.setVolume(_volumeBeforeAlarm!);
      } catch (_) {}
      _volumeBeforeAlarm = null;
    }
  }

  /// Spielt den in den Toneinstellungen gewählten Alarm-Ton (Foreground).
  /// Einmal abspielen, kein Loop. Setzt die Gerätelautstärke auf Maximum (nur bei Alarmierung).
  /// Bei "Systemton" wird nichts abgespielt – die OS-Benachrichtigung nutzt den Gerätestandard.
  Future<void> _playAlarmTone() async {
    final assetPath = await ToneSettingsService().getAlarmToneAssetPath();
    if (assetPath.isEmpty) return; // Systemton – kein Custom-Asset
    await stopAlarmTone();
    // Gerätelautstärke auf Maximum setzen (nur bei Alarmierung)
    if (!kIsWeb) {
      try {
        _volumeBeforeAlarm = await FlutterVolumeController.getVolume();
        await FlutterVolumeController.setVolume(1.0);
      } catch (e) {
        debugPrint('RettBase Push: Lautstärke setzen fehlgeschlagen: $e');
      }
    }
    final player = AudioPlayer();
    _alarmPlayer = player;
    try {
      await player.setAsset(assetPath);
      await player.setVolume(1.0);
      await player.play();
    } catch (e) {
      debugPrint('RettBase Push: Alarm-Ton abspielen fehlgeschlagen: $e');
      _alarmPlayer = null;
      await player.dispose();
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
    } else if (type == 'alarm') {
      _initialAlarmCompanyId = data['companyId'] as String?;
      _initialAlarmEinsatzId = data['einsatzId'] as String?;
    }
  }

  /// Erneutes Speichern des Tokens (z.B. bei App-Resume), wenn companyId/uid bekannt.
  static Future<void> retrySaveTokenIfNeeded() async {
    if (kIsWeb) return;
    final c = _lastCompanyId;
    final u = _lastUid;
    if (c != null && u != null && c.isNotEmpty && u.isNotEmpty) {
      unawaited(PushNotificationService().saveToken(c, u));
    }
  }

  /// FCM-Token für Native (iOS/Android). Auf iOS: APNs-Token muss zuerst verfügbar sein.
  Future<String?> _getFcmTokenForNative() async {
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.iOS) {
      var apnsToken = await _messaging.getAPNSToken();
      if (apnsToken == null || apnsToken.isEmpty) {
        debugPrint('RettBase Push: APNs-Token noch nicht da – warte 3s, dann Retry');
        await Future.delayed(const Duration(seconds: 3));
        apnsToken = await _messaging.getAPNSToken();
      }
      if (apnsToken == null || apnsToken.isEmpty) {
        debugPrint('RettBase Push: APNs-Token nach Retry weiterhin null – echtes Gerät nötig (kein Simulator)');
        return null;
      }
      debugPrint('RettBase Push: APNs-Token vorhanden, hole FCM-Token');
    }
    var token = await _messaging.getToken();
    if (token == null || token.isEmpty) {
      debugPrint('RettBase Push: getToken null – Retry in 3s');
      await Future.delayed(const Duration(seconds: 3));
      token = await _messaging.getToken();
    }
    return token;
  }

  /// FCM-Token in Firestore speichern (nach Login). Wird bei jedem Dashboard-Load aufgerufen.
  Future<void> saveToken(String companyId, String uid) async {
    _lastCompanyId = companyId;
    _lastUid = uid;
    if (kIsWeb) {
      if (AppConfig.fcmWebVapidKey == null || AppConfig.fcmWebVapidKey!.isEmpty) {
        return;
      }
      // Nur Token holen wenn Berechtigung bereits erteilt – sonst kein getToken (vermeidet Dialog beim Start)
      if (getNotificationPermissionStatusWeb() != 'granted') return;
      try {
        await perm_impl.ensureServiceWorkerRegisteredWeb();
        final token = await _messaging.getToken(vapidKey: AppConfig.fcmWebVapidKey);
        if (token == null || token.isEmpty) return;
        await _saveTokenToFirestore(companyId, uid, token);
      } catch (e) {
        // permission-blocked ist erwartbar (Nutzer hat abgelehnt) – nicht als Fehler loggen
        final msg = e.toString();
        if (!msg.contains('permission-blocked') && !msg.contains('permission_blocked')) {
          debugPrint('RettBase Push Web: token speichern fehlgeschlagen: $e');
        }
      }
      return;
    }
    try {
      await ensureInitialized();
      var token = await _getFcmTokenForNative();
      if (token == null || token.isEmpty) {
        debugPrint('RettBase Push: getToken nach Retries weiterhin null – prüfe Einstellungen → Benachrichtigungen');
        return;
      }
      await _saveTokenToFirestore(companyId, uid, token);
      debugPrint('RettBase Push: Token gespeichert für uid=$uid');
    } catch (e) {
      final msg = e.toString();
      if (!msg.contains('permission-blocked') && !msg.contains('permission_blocked')) {
        debugPrint('RettBase Push: token speichern fehlgeschlagen: $e');
      }
    }
  }

  Future<void> _saveTokenToFirestore(String companyId, String uid, String token) async {
    try {
      debugPrint('RettBase Push: schreibe Token nach Firestore (companyId=$companyId, uid=$uid)');
      final data = {
        'fcmToken': token,
        'fcmTokenUpdatedAt': FieldValue.serverTimestamp(),
      };
      await _db.collection('kunden').doc(companyId).collection('users').doc(uid).set(data, SetOptions(merge: true));
      await _db.collection('fcmTokens').doc(uid).set(data, SetOptions(merge: true));
      unawaited(ToneSettingsService().syncAlarmToneToFirestore(companyId, uid));
      debugPrint('RettBase Push: Firestore-Schreiben erfolgreich');
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
