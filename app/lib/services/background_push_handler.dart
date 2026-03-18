import 'dart:io';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart' show kDebugMode, kIsWeb;
import 'package:flutter_app_badger/flutter_app_badger.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// Zeigt eine lokale Benachrichtigung mit Badge und Ton, wenn ein Chat-Push im Hintergrund ankommt.
/// Das System-Badge aus dem APNs-Payload erscheint oft erst nach App-Start – diese lokale
/// Benachrichtigung stellt sicher, dass Badge + Ton sofort sichtbar/hörbar sind.
const _channelId = 'chat_messages';
const _channelName = 'Chat-Nachrichten';
const _alarmChannelId = 'alarm_messages';
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
    await androidPlugin?.createNotificationChannel(
      const AndroidNotificationChannel(
        _alarmChannelId,
        _alarmChannelName,
        description: 'Alarmierungen für Einsätze (Einsatzverwaltung)',
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
