import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Service für Toneinstellungen (Alarm-Push).
/// Chat-Push bleibt immer Systemton.
/// "system" = Geräte-Standardton; sonst benutzerdefinierter Ton.
class ToneSettingsService {
  /// Systemton – Gerätestandard für Benachrichtigungen.
  static const String kSystemToneId = 'system';

  /// Verfügbare Alarm-Töne. Erste Option = Systemton (kein Asset).
  /// Alle Töne: voices/ als Quelle, 1:1 Dateiname, mp3-Format.
  static const List<({String id, String assetPath, String label})> kAlarmToneOptions = [
    (id: 'system', assetPath: '', label: 'Systemton (Gerätestandard)'),
    (id: 'EFDN-Gong.mp3', assetPath: 'voices/EFDN-Gong.mp3', label: 'EFDN-Gong'),
    (id: 'Ton1.mp3', assetPath: 'voices/Ton1.mp3', label: 'Ton 1'),
    (id: 'Ton2.mp3', assetPath: 'voices/Ton2.mp3', label: 'Ton 2'),
    (id: 'Ton3.mp3', assetPath: 'voices/Ton3.mp3', label: 'Ton 3'),
    (id: 'Ton4.mp3', assetPath: 'voices/Ton4.mp3', label: 'Ton 4'),
  ];

  /// Mapping: Ton-ID → Android res/raw Ressourcenname (lowercase, ohne Sonderzeichen).
  static String? toAndroidRawName(String id) {
    if (id == kSystemToneId) return null;
    switch (id) {
      case 'EFDN-Gong.mp3': return 'efdn_gong';
      case 'Ton1.mp3': return 'ton1';
      case 'Ton2.mp3': return 'ton2';
      case 'Ton3.mp3': return 'ton3';
      case 'Ton4.mp3': return 'ton4';
      default: return null;
    }
  }

  /// Mapping: Ton-ID → iOS Sound-Dateiname im Bundle.
  static String? toIosSoundName(String id) {
    if (id == kSystemToneId) return null;
    return id; // z.B. Melder1.wav
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
      await FirebaseFirestore.instance
          .collection('kunden')
          .doc(companyId)
          .collection('users')
          .doc(uid)
          .set({'alarmToneId': id}, SetOptions(merge: true));
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
