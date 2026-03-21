import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../generated/alarm_tones.dart' as alarm_tones;

/// Service für Toneinstellungen (Alarm-Push).
/// Chat-Push bleibt immer Systemton.
/// "system" = Geräte-Standardton; sonst benutzerdefinierter Ton.
/// Liste aus lib/generated/alarm_tones.dart (auto-generiert aus voices/*.mp3).
class ToneSettingsService {
  /// Systemton – Gerätestandard für Benachrichtigungen.
  static const String kSystemToneId = 'system';

  /// Verfügbare Alarm-Töne (generiert aus voices/*.mp3).
  static List<({String id, String assetPath, String label})> get kAlarmToneOptions =>
      alarm_tones.kAlarmToneOptions;

  /// Mapping: Ton-ID → Android res/raw Ressourcenname (lowercase, ohne Sonderzeichen).
  static String? toAndroidRawName(String id) {
    if (id == kSystemToneId) return null;
    var t = id.trim();
    if (t.isEmpty) return null;
    final lower = t.toLowerCase();
    if (lower.endsWith('.mp3')) {
      t = t.substring(0, t.length - 4);
    }
    final out = t.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '_').replaceAll(RegExp(r'^_+|_+$'), '');
    return out.isEmpty ? null : out;
  }

  /// Mapping: Ton-ID → iOS Sound-Dateiname im Bundle (.wav, da iOS kein MP3 unterstützt).
  static String? toIosSoundName(String id) {
    if (id == kSystemToneId) return null;
    if (id.endsWith('.mp3')) return id.replaceFirst(RegExp(r'\.mp3$'), '.wav');
    return id;
  }

  static const _keyAlarmTone = 'rettbase_alarm_tone';

  /// Gibt die gewählte Alarm-Ton-ID zurück (Default: Systemton).
  Future<String> getAlarmToneId() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_keyAlarmTone);
    if (saved != null && kAlarmToneOptions.any((o) => o.id == saved)) {
      return saved;
    }
    return kSystemToneId;
  }

  /// Speichert die gewählte Alarm-Ton-ID (lokal + optional Firestore).
  Future<void> setAlarmToneId(String id) async {
    if (!kAlarmToneOptions.any((o) => o.id == id)) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyAlarmTone, id);
  }

  /// Synchronisiert die gewählte Alarm-Ton-ID nach Firestore (für Server-Push).
  /// Muss aufgerufen werden, wenn Nutzer eingeloggt ist.
  Future<void> syncAlarmToneToFirestore(String companyId, String uid) async {
    try {
      final id = await getAlarmToneId();
      final payload = {'alarmToneId': id};
      final fs = FirebaseFirestore.instance;
      await fs
          .collection('kunden')
          .doc(companyId)
          .collection('users')
          .doc(uid)
          .set(payload, SetOptions(merge: true));
      // Spiegel für Cloud Function: getFcmToken fällt sonst auf fcmTokens zurück ohne alarmToneId.
      await fs.collection('fcmTokens').doc(uid).set(payload, SetOptions(merge: true));
    } catch (_) {}
  }

  /// Asset-Pfad für die gewählte Alarm-Ton-ID (leer bei Systemton).
  Future<String> getAlarmToneAssetPath() async {
    final id = await getAlarmToneId();
    if (id == kSystemToneId) return '';
    for (final o in kAlarmToneOptions) {
      if (o.id == id && o.assetPath.isNotEmpty) return o.assetPath;
    }
    return '';
  }

  /// Ob ein benutzerdefinierter Ton (nicht System) gewählt ist.
  Future<bool> hasCustomAlarmTone() async {
    final id = await getAlarmToneId();
    return id != kSystemToneId && id.isNotEmpty;
  }
}
