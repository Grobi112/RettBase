import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

/// Speichert quittierte Alarm-Einsätze (Einsatzdetails-Tap).
/// Verhindert erneutes Abspielen des Alarmtons und erneutes Anzeigen des Popups.
class AlarmQuittierungService {
  static const _key = 'rettbase_quittierte_einsaetze';
  static const _maxEntries = 100;

  String _keyFor(String companyId, String einsatzId) =>
      '$companyId:$einsatzId';

  Future<Set<String>> _loadKeys() async {
    final prefs = await SharedPreferences.getInstance();
    final json = prefs.getString(_key);
    if (json == null || json.isEmpty) return {};
    try {
      final list = jsonDecode(json) as List<dynamic>?;
      return (list ?? []).map((e) => e.toString()).where((s) => s.isNotEmpty).toSet();
    } catch (_) {
      return {};
    }
  }

  Future<void> _saveKeys(Set<String> keys) async {
    final prefs = await SharedPreferences.getInstance();
    final list = keys.toList();
    if (list.length > _maxEntries) {
      list.removeRange(0, list.length - _maxEntries);
    }
    await prefs.setString(_key, jsonEncode(list));
  }

  /// Prüft, ob der Einsatz bereits quittiert wurde.
  Future<bool> isQuittiert(String companyId, String einsatzId) async {
    if (companyId.isEmpty || einsatzId.isEmpty) return false;
    final keys = await _loadKeys();
    return keys.contains(_keyFor(companyId, einsatzId));
  }

  /// Markiert den Einsatz als quittiert (nach Klick auf Einsatzdetails).
  Future<void> markQuittiert(String companyId, String einsatzId) async {
    if (companyId.isEmpty || einsatzId.isEmpty) return;
    final keys = await _loadKeys();
    keys.add(_keyFor(companyId, einsatzId));
    await _saveKeys(keys);
  }
}
