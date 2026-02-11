import 'package:cloud_firestore/cloud_firestore.dart';

/// Einstellungen für das Informationssystem
/// Firestore: kunden/{companyId}/settings/informationssystem
class InformationssystemService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  static const List<String> defaultContainerTypeIds = ['informationen', 'verkehrslage'];
  static const Map<String, String> defaultContainerLabels = {
    'informationen': 'Informationen',
    'verkehrslage': 'Verkehrslage',
  };

  /// Legacy: für Abwärtskompatibilität (informationssystem_screen nutzt ggf. noch loadContainerOrder)
  static List<String> get containerTypes => defaultContainerTypeIds;
  static Map<String, String> get containerLabels => defaultContainerLabels;

  DocumentReference<Map<String, dynamic>> _settingsRef(String companyId) =>
      _db.collection('kunden').doc(companyId).collection('settings').doc('informationssystem');

  /// Container-Typen laden (id + label), benutzerdefinierte + Standard
  Future<Map<String, String>> loadContainerTypeLabels(String companyId) async {
    try {
      final snap = await _settingsRef(companyId).get();
      final data = snap.data();
      final list = data?['containerTypes'] as List?;
      if (list != null && list.isNotEmpty) {
        final map = <String, String>{};
        for (final e in list) {
          if (e is Map) {
            final id = e['id']?.toString();
            final label = e['label']?.toString();
            if (id != null && id.isNotEmpty) {
              map[id] = label ?? id;
            }
          }
        }
        if (map.isNotEmpty) return map;
      }
    } catch (_) {}
    return Map.from(defaultContainerLabels);
  }

  /// Container-Reihenfolge für Tabs laden (Reihenfolge der Typen)
  Future<List<String>> loadContainerTypeOrder(String companyId) async {
    try {
      final snap = await _settingsRef(companyId).get();
      final data = snap.data();
      final list = data?['containerTypeOrder'] as List?;
      if (list != null && list.isNotEmpty) {
        final ids = list.map((e) => e.toString()).where((s) => s.isNotEmpty).toList();
        if (ids.isNotEmpty) return ids;
      }
    } catch (_) {}
    return List.from(defaultContainerTypeIds);
  }

  /// Container-Reihenfolge laden (2 Slots für Hauptseite)
  Future<List<String?>> loadContainerOrder(String companyId) async {
    try {
      final snap = await _settingsRef(companyId).get();
      final data = snap.data();
      final list = data?['containerSlots'] as List?;
      if (list != null && list.length >= 2) {
        return [list[0]?.toString(), list[1]?.toString()];
      }
    } catch (_) {}
    return ['informationen', 'verkehrslage'];
  }

  /// Kategorien laden (Reihenfolge wie gespeichert, von oben nach unten)
  Future<List<String>> loadKategorien(String companyId) async {
    try {
      final snap = await _settingsRef(companyId).get();
      final data = snap.data();
      final list = data?['kategorien'] as List?;
      if (list != null) {
        return list.map((e) => e.toString()).where((s) => s.isNotEmpty).toList();
      }
    } catch (_) {}
    return [];
  }

  /// Container-Typen und Kategorien speichern
  Future<void> saveContainerTypesAndKategorien(
    String companyId, {
    required List<MapEntry<String, String>> containerTypes,
    required List<String> kategorien,
  }) async {
    final typesList = containerTypes.map((e) => {'id': e.key, 'label': e.value}).toList();
    final orderList = containerTypes.map((e) => e.key).toList();
    await _settingsRef(companyId).set({
      'containerTypes': typesList,
      'containerTypeOrder': orderList,
      'kategorien': kategorien,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  /// Einstellungen speichern (inkl. Slots für Hauptseite)
  Future<void> saveAll(
    String companyId, {
    required List<String?> containerSlots,
    required List<String> kategorien,
    List<MapEntry<String, String>>? containerTypes,
    List<String>? containerTypeOrder,
  }) async {
    final payload = <String, dynamic>{
      'containerSlots': containerSlots,
      'kategorien': kategorien,
      'updatedAt': FieldValue.serverTimestamp(),
    };
    if (containerTypes != null) {
      payload['containerTypes'] = containerTypes.map((e) => {'id': e.key, 'label': e.value}).toList();
    }
    if (containerTypeOrder != null) {
      payload['containerTypeOrder'] = containerTypeOrder;
    }
    await _settingsRef(companyId).set(payload, SetOptions(merge: true));
  }
}
