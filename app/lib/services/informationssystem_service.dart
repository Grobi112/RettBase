import 'package:cloud_firestore/cloud_firestore.dart';

/// Einstellungen für das Informationssystem.
/// Firestore: kunden/{companyId}/settings/informationssystem
///
/// **Firmenweit:** Pro Firma (companyId = Firestore docId) eine Konfiguration.
/// Kein Bereich in der Pfadstruktur – alle Bereiche einer Firma nutzen dieselben Container-Typen, Slots und Informationen.
class InformationssystemService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  static String _normalizeCompanyId(String companyId) =>
      companyId.trim().toLowerCase();

  static const List<String> defaultContainerTypeIds = ['informationen', 'verkehrslage'];
  static const Map<String, String> defaultContainerLabels = {
    'informationen': 'Informationen',
    'verkehrslage': 'Verkehrslage',
  };

  /// Max. Container-Slots auf der Hauptseite
  static const int maxContainerSlots = 6;

  /// Legacy: für Abwärtskompatibilität (informationssystem_screen nutzt ggf. noch loadContainerOrder)
  static List<String> get containerTypes => defaultContainerTypeIds;
  static Map<String, String> get containerLabels => defaultContainerLabels;

  DocumentReference<Map<String, dynamic>> _settingsRef(String companyId) =>
      _db.collection('kunden').doc(_normalizeCompanyId(companyId)).collection('settings').doc('informationssystem');

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

  /// Container-Reihenfolge laden (bis zu 6 Slots für Hauptseite)
  Future<List<String?>> loadContainerOrder(String companyId) async {
    try {
      final snap = await _settingsRef(companyId).get();
      final data = snap.data();
      final list = data?['containerSlots'] as List?;
      if (list != null && list.isNotEmpty) {
        final slots = <String?>[];
        for (var i = 0; i < maxContainerSlots && i < list.length; i++) {
          final v = list[i]?.toString().trim();
          slots.add((v != null && v.isNotEmpty && v != 'null') ? v : null);
        }
        while (slots.length < maxContainerSlots) {
          slots.add(null);
        }
        return slots.take(maxContainerSlots).toList();
      }
    } catch (_) {}
    // Neue Kunden: leere Slots – keine vorgefüllten Container
    return List.filled(maxContainerSlots, null);
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

  /// Container-Typen und Kategorien speichern.
  /// [containerSlotsOverride]: Optional – explizite Slots für Hauptseite (bis zu 6 Positionen).
  /// Ohne Override: bestehende Slots werden synchronisiert (ungültige entfernt, leere gefüllt).
  Future<void> saveContainerTypesAndKategorien(
    String companyId, {
    required List<MapEntry<String, String>> containerTypes,
    required List<String> kategorien,
    List<String?>? containerSlotsOverride,
  }) async {
    final typesList = containerTypes.map((e) => {'id': e.key, 'label': e.value}).toList();
    final orderList = containerTypes.map((e) => e.key).toList();
    final validIds = orderList.toSet();

    // containerSlots für HomeScreen
    List<String?> containerSlots;
    if (containerSlotsOverride != null && containerSlotsOverride.isNotEmpty) {
      final usedIds = <String>{};
      containerSlots = containerSlotsOverride.take(maxContainerSlots).map((s) {
        final v = s?.trim();
        if (v == null || v.isEmpty) return null;
        if (!validIds.contains(v) || usedIds.contains(v)) return null;
        usedIds.add(v);
        return v;
      }).toList();
      while (containerSlots.length < maxContainerSlots) {
        containerSlots.add(null);
      }
    } else {
      containerSlots = await loadContainerOrder(companyId);
      final usedIds = <String>{};
      containerSlots = containerSlots.asMap().entries.map((e) {
        final slot = e.value;
        if (slot == null || slot.isEmpty) return null;
        if (!validIds.contains(slot)) return null; // gelöschter Typ → Slot leeren
        if (usedIds.contains(slot)) return null;  // doppelten Typ vermeiden
        usedIds.add(slot);
        return slot;
      }).toList();
      // Keine automatische Befüllung: Nur explizit gewählte Slots bleiben.
      while (containerSlots.length < maxContainerSlots) {
        containerSlots.add(null);
      }
      containerSlots = containerSlots.take(maxContainerSlots).toList();
    }

    await _settingsRef(companyId).set({
      'containerTypes': typesList,
      'containerTypeOrder': orderList,
      'containerSlots': containerSlots,
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
