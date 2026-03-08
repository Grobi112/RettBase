import 'dart:convert';
import 'dart:typed_data';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:hive_flutter/hive_flutter.dart';

/// Eintrag in der Offline-Nachrichten-Queue.
class PendingChatMessage {
  final String id;
  final String companyId;
  final String chatId;
  final String text;
  final List<Uint8List>? imageBytes;
  final List<String>? imageNames;
  final List<Uint8List>? audioBytes;
  final List<String>? audioNames;
  final DateTime createdAt;

  PendingChatMessage({
    required this.id,
    required this.companyId,
    required this.chatId,
    required this.text,
    this.imageBytes,
    this.imageNames,
    this.audioBytes,
    this.audioNames,
    required this.createdAt,
  });

  bool get hasAudio => audioBytes != null && audioBytes!.isNotEmpty;

  Map<String, dynamic> toJson() => {
        'id': id,
        'companyId': companyId,
        'chatId': chatId,
        'text': text,
        'imageBytes': imageBytes?.map((b) => base64Encode(b)).toList(),
        'imageNames': imageNames,
        'audioBytes': audioBytes?.map((b) => base64Encode(b)).toList(),
        'audioNames': audioNames,
        'createdAt': createdAt.millisecondsSinceEpoch,
      };

  static PendingChatMessage fromJson(Map<String, dynamic> m) {
    final ib = m['imageBytes'] as List?;
    final ab = m['audioBytes'] as List?;
    return PendingChatMessage(
      id: m['id'] as String,
      companyId: m['companyId'] as String,
      chatId: m['chatId'] as String,
      text: m['text'] as String,
      imageBytes: ib?.map((e) => Uint8List.fromList(base64Decode(e as String))).toList(),
      imageNames: (m['imageNames'] as List?)?.cast<String>(),
      audioBytes: ab?.map((e) => Uint8List.fromList(base64Decode(e as String))).toList(),
      audioNames: (m['audioNames'] as List?)?.cast<String>(),
      createdAt: DateTime.fromMillisecondsSinceEpoch(m['createdAt'] as int),
    );
  }
}

/// Offline-Queue für Chat-Nachrichten. Speichert lokal, sendet bei Netzverbindung.
class ChatOfflineQueue {
  static const _boxName = 'chat_pending_messages';
  static bool _initialized = false;

  static Future<void> init() async {
    if (_initialized) return;
    await Hive.initFlutter();
    if (!Hive.isBoxOpen(_boxName)) {
      await Hive.openBox<String>(_boxName);
    }
    _initialized = true;
  }

  static Box<String> get _box => Hive.box<String>(_boxName);

  /// Fügt eine Nachricht zur Queue hinzu (wenn offline).
  static Future<String> enqueue(PendingChatMessage msg) async {
    await init();
    await _box.put(msg.id, jsonEncode(msg.toJson()));
    return msg.id;
  }

  /// Entfernt eine Nachricht aus der Queue (nach erfolgreichem Senden).
  static Future<void> remove(String id) async {
    if (!_initialized) return;
    await _box.delete(id);
  }

  /// Liefert alle ausstehenden Nachrichten, sortiert nach Zeit.
  static Future<List<PendingChatMessage>> getAll() async {
    await init();
    final list = _box.values
        .map((s) => PendingChatMessage.fromJson(Map<String, dynamic>.from(jsonDecode(s) as Map)))
        .toList();
    list.sort((a, b) => a.createdAt.compareTo(b.createdAt));
    return list;
  }

  /// Prüft ob Netz verfügbar ist (WiFi, Mobil, Ethernet, VPN, other).
  static Future<bool> get isOnline async {
    final results = await Connectivity().checkConnectivity();
    return results.any((r) =>
        r != ConnectivityResult.none && r != ConnectivityResult.bluetooth);
  }

  /// Stream für Änderungen der Netzverbindung.
  static Stream<List<ConnectivityResult>> get onConnectivityChanged =>
      Connectivity().onConnectivityChanged;
}
