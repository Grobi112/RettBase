import 'dart:io';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart' show kDebugMode, kIsWeb;
import 'package:flutter/services.dart';
import 'package:flutter_app_badger/flutter_app_badger.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'tone_settings_service.dart';

/// Zeigt eine lokale Benachrichtigung mit Badge und Ton, wenn ein Chat-Push im Hintergrund ankommt.
/// Das System-Badge aus dem APNs-Payload erscheint oft erst nach App-Start – diese lokale
/// Benachrichtigung stellt sicher, dass Badge + Ton sofort sichtbar/hörbar sind.
const _channelId = 'chat_messages';
const _channelName = 'Chat-Nachrichten';
// v2: alarm_messages_v2 mit System-Alarmton + USAGE_ALARM (alarm_messages war ohne Sound angelegt).
const _alarmChannelId = 'alarm_messages_v2';
const _alarmChannelName = 'Alarmierungen';

final FlutterLocalNotificationsPlugin _plugin = FlutterLocalNotificationsPlugin();

/// Initialisiert flutter_local_notifications im Background-Isolate.
/// Muss vor dem ersten show() aufgerufen werden.
Future<void> initBackgroundNotifications() async {
  if (kIsWeb) return;
  const android = AndroidInitializationSettings('@mipmap/ic_launcher');
  const darwin = DarwinInitializationSettings(
    requestAlertPermission: false,
    requestBadgePermission: false,
  );
  const initSettings = InitializationSettings(
    android: android,
    iOS: darwin,
  );
  await _plugin.initialize(
    initSettings,
    onDidReceiveNotificationResponse: (_) {},
  );
  if (Platform.isAndroid) {
    final androidPlugin = _plugin
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    await androidPlugin?.createNotificationChannel(
      const AndroidNotificationChannel(
        _channelId,
        _channelName,
        description: 'Benachrichtigungen für neue Chat-Nachrichten',
        importance: Importance.max,
        playSound: true,
        enableVibration: true,
      ),
    );
    // Kanal-Erstellung hier ist Fallback – Haupterstellung in NotificationChannelSetup.kt (RettBaseApplication).
    // flutter_local_notifications kann keinen Sound-URI setzen; NotificationChannelSetup.kt setzt System-Alarm-URI.
    await androidPlugin?.createNotificationChannel(
      const AndroidNotificationChannel(
        _alarmChannelId,
        _alarmChannelName,
        description: 'Alarmierungen für Einsätze',
        importance: Importance.max,
        playSound: true,
        enableVibration: true,
        audioAttributesUsage: AudioAttributesUsage.alarm,
      ),
    );
  }
}

/// Zeigt eine lokale Benachrichtigung für eine Chat-Nachricht.
/// Wird aus dem FCM-Background-Handler aufgerufen.
Future<void> showChatNotificationFromBackground(RemoteMessage message) async {
  if (kIsWeb) return;
  final data = message.data;
  if (data == null || (data['type'] as String? ?? '') != 'chat') return;

  final title = message.notification?.title ?? data['title'] as String? ?? 'Neue Chat-Nachricht';
  final body = message.notification?.body ?? data['body'] as String? ?? 'Du hast eine neue Nachricht';
  final totalUnread = int.tryParse((data['totalUnread'] ?? data['badge'] ?? '1').toString()) ?? 1;
  final companyId = data['companyId'] as String? ?? '';
  final chatId = data['chatId'] as String? ?? '';

  final id = (companyId + chatId).hashCode.abs() % 2147483647;

  const androidDetails = AndroidNotificationDetails(
    _channelId,
    _channelName,
    channelDescription: 'Benachrichtigungen für neue Chat-Nachrichten',
    importance: Importance.max,
    priority: Priority.max,
    playSound: true,
    enableVibration: true,
  );
  final darwinDetails = DarwinNotificationDetails(
    presentAlert: true,
    presentBadge: true,
    presentSound: true,
    badgeNumber: totalUnread,
  );
  final details = NotificationDetails(
    android: androidDetails,
    iOS: darwinDetails,
  );

  try {
    // Badge SOFORT setzen – nicht auf Dashboard warten
    final badgeCount = totalUnread > 99 ? 99 : totalUnread;
    await FlutterAppBadger.updateBadgeCount(badgeCount);
    await _plugin.show(id, title, body, details);
    if (kDebugMode) {
      // ignore: avoid_print
      print('RettBase Push: Badge=$badgeCount gesetzt, Benachrichtigung angezeigt');
    }
  } catch (e) {
    if (kDebugMode) {
      // ignore: avoid_print
      print('RettBase Push: lokale Benachrichtigung fehlgeschlagen: $e');
    }
  }
}

/// Android: FCM-Alarm als **Data-Message** (ohne Root-notification), damit dieser Handler läuft
/// und eine sichtbare lokale Notification mit dem richtigen Kanal/Ton erscheint.
/// iOS bleibt bei APNs (Critical Alert) – hier kein zweites Banner.
Future<void> showAlarmNotificationFromBackground(RemoteMessage message) async {
  if (kIsWeb || !Platform.isAndroid) return;
  final data = message.data;
  if (data.isEmpty || (data['type'] as String? ?? '') != 'alarm') return;

  final titleRaw = (data['title'] as String? ?? '').trim();
  final bodyRaw = (data['body'] as String? ?? '').trim();
  final title = titleRaw.isNotEmpty
      ? titleRaw
      : (message.notification?.title ?? 'Alarmierung');
  final body = bodyRaw.isNotEmpty
      ? bodyRaw
      : (message.notification?.body ?? 'Neuer Einsatz');
  // Kanal lokal aus SharedPreferences bestimmen – zuverlässiger als Firestore-Roundtrip der
  // Firebase Function (alarmToneId kann in Firestore veraltet/"system" sein).
  // SharedPreferences ist im Background-Isolate nach Firebase.initializeApp() verfügbar.
  String channelId;
  try {
    final toneId = await ToneSettingsService().getAlarmToneId();
    final raw = ToneSettingsService.toAndroidRawName(toneId);
    channelId = raw != null ? 'rett_alarm_w5_$raw' : _alarmChannelId;
  } catch (_) {
    // Fallback: Kanal aus FCM-Daten (von Firebase Function)
    channelId = (data['alarmChannelId'] as String? ?? '').trim();
    if (channelId.isEmpty || channelId == 'alarm_messages' ||
        !RegExp(r'^[a-zA-Z0-9_.-]+$').hasMatch(channelId)) {
      channelId = _alarmChannelId;
    }
  }

  final companyId = data['companyId'] as String? ?? '';
  final einsatzId = data['einsatzId'] as String? ?? '';
  final id = ('alarm$companyId$einsatzId').hashCode.abs() % 2147483647;

  final androidDetails = AndroidNotificationDetails(
    channelId,
    _alarmChannelName,
    channelDescription: 'Einsatzalarm',
    importance: Importance.max,
    priority: Priority.max,
    playSound: true,
    enableVibration: true,
    category: AndroidNotificationCategory.alarm,
    audioAttributesUsage: AudioAttributesUsage.alarm,
    number: 1,
    visibility: NotificationVisibility.public,
  );
  const darwinDetails = DarwinNotificationDetails();
  final details = NotificationDetails(
    android: androidDetails,
    iOS: darwinDetails,
  );

  final payload = '$companyId|$einsatzId';
  try {
    await _plugin.show(id, title, body, details, payload: payload);

    // Full-Screen Alarm-Activity für kritische Einsätze (zeigt sich auf Lock Screen)
    if (Platform.isAndroid) {
      try {
        const alarmChannel = MethodChannel('com.mikefullbeck.rettbase/alarm');
        await alarmChannel.invokeMethod('showAlarmFullScreen', {
          'title': title,
          'message': body,
          'notificationId': id,
        });
        if (kDebugMode) {
          // ignore: avoid_print
          print('RettBase Push: AlarmActivity gestartet (Full-Screen)');
        }
      } catch (e) {
        if (kDebugMode) {
          // ignore: avoid_print
          print('RettBase Push: AlarmActivity-Fehler: $e');
        }
      }
    }

    if (kDebugMode) {
      // ignore: avoid_print
      print('RettBase Push: Alarm-Notification Android channel=$channelId');
    }
  } catch (e) {
    if (kDebugMode) {
      // ignore: avoid_print
      print('RettBase Push: Alarm lokale Notification fehlgeschlagen: $e');
    }
    // Fallback: Standard-Alarmkanal (existiert immer in NotificationChannelSetup)
    try {
      const fallback = AndroidNotificationDetails(
        _alarmChannelId,
        _alarmChannelName,
        channelDescription: 'Einsatzalarm (Fallback)',
        importance: Importance.max,
        priority: Priority.max,
        playSound: true,
        enableVibration: true,
        category: AndroidNotificationCategory.alarm,
        audioAttributesUsage: AudioAttributesUsage.alarm,
        number: 1,
        visibility: NotificationVisibility.public,
      );
      await _plugin.show(
        id,
        title,
        body,
        const NotificationDetails(android: fallback, iOS: darwinDetails),
        payload: payload,
      );
    } catch (_) {}
  }
}

/// Initialisiert flutter_local_notifications im Main-Isolate (Tap-Handler + Cold-Start).
/// Muss in main() aufgerufen werden – zusätzlich zu [initBackgroundNotifications] im Background-Isolate.
/// [onTap] erhält den Payload "companyId|einsatzId" wenn der Nutzer die Alarm-Notification tippt.
Future<void> initMainNotifications(void Function(String payload) onTap) async {
  if (kIsWeb) return;
  const android = AndroidInitializationSettings('@mipmap/ic_launcher');
  const darwin = DarwinInitializationSettings(
    requestAlertPermission: false,
    requestBadgePermission: false,
  );
  await _plugin.initialize(
    const InitializationSettings(android: android, iOS: darwin),
    onDidReceiveNotificationResponse: (details) {
      final payload = details.payload ?? '';
      if (payload.isNotEmpty) onTap(payload);
    },
  );
  // Cold-Start: App wurde durch Tippen auf die Notification gestartet
  try {
    final launch = await _plugin.getNotificationAppLaunchDetails();
    if (launch?.didNotificationLaunchApp == true) {
      final payload = launch?.notificationResponse?.payload ?? '';
      if (payload.isNotEmpty) onTap(payload);
    }
  } catch (_) {}
}
