import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/kunde_model.dart';

/// Service für Menüverwaltung – pro Bereich (Rettungsdienst, Notfallseelsorge, …)
/// Firestore: settings/menus/{bereich}
///
/// Struktur: Jedes Item kann sein:
/// - type: 'heading' – Oberbegriff mit children (max 2 Unterpunkte)
/// - type: 'module' | 'custom' – eigenständiger Menüpunkt
class MenueverwaltungService {
  final _db = FirebaseFirestore.instance;

  DocumentReference<Map<String, dynamic>> _menuRef(String bereich) =>
      _db.collection('settings').doc('menus').collection('items').doc(bereich);

  static const int _maxChildrenPerHeading = 6;

  /// Lädt die Menüstruktur für einen Bereich.
  /// [forceServerRead]: wenn true, liest direkt vom Server (um Cache nach Speichern zu umgehen).
  Future<List<Map<String, dynamic>>> loadMenuStructure(String bereich, {bool forceServerRead = false}) async {
    if (bereich.isEmpty) return [];
    final options = forceServerRead ? const GetOptions(source: Source.server) : null;
    final snap = options != null
        ? await _menuRef(bereich).get(options)
        : await _menuRef(bereich).get();
    if (!snap.exists) return [];
    final items = snap.data()?['items'];
    if (items is List) {
      return items.map((e) => _normalizeItem(e as Map)).toList();
    }
    return [];
  }

  /// Lädt Menüstruktur aus altem globalMenu (Abwärtskompatibilität/Migration).
  /// [forceServerRead]: wenn true, liest direkt vom Server.
  Future<List<Map<String, dynamic>>> loadLegacyGlobalMenu({bool forceServerRead = false}) async {
    final options = forceServerRead ? const GetOptions(source: Source.server) : null;
    final snap = options != null
        ? await _db.collection('settings').doc('globalMenu').get(options)
        : await _db.collection('settings').doc('globalMenu').get();
    if (!snap.exists) return [];
    final items = snap.data()?['items'];
    if (items is List) {
      return items.map((e) => _normalizeItem(e as Map)).toList();
    }
    return [];
  }

  /// Normalisiert ein Item (z.B. nach Laden aus Firestore)
  Map<String, dynamic> _normalizeItem(Map e) {
    final item = Map<String, dynamic>.from(e);
    final type = (item['type'] ?? 'module').toString();
    if (type == 'heading') {
      final childrenRaw = item['children'];
      List<Map<String, dynamic>> children = [];
      if (childrenRaw is List) {
        for (final c in childrenRaw) {
          if (c is Map) children.add(Map<String, dynamic>.from(c));
          if (children.length >= _maxChildrenPerHeading) break;
        }
      }
      item['children'] = children;
    } else {
      item['children'] = null; // oder weglassen
    }
    return item;
  }

  /// Speichert die Menüstruktur für einen Bereich
  Future<void> saveMenuStructure(String bereich, List<Map<String, dynamic>> items) async {
    if (bereich.isEmpty) return;
    final normalized = items.map(_normalizeItem).toList();
    for (var i = 0; i < normalized.length; i++) {
      normalized[i]['order'] = i;
    }
    await _menuRef(bereich).set({
      'items': normalized,
      'bereich': bereich,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  /// Extrahiert alle Modul-IDs aus der Menüstruktur (Reihenfolge: zuerst Top-Level, dann Kinder)
  static List<String> extractModuleIdsFromMenu(List<Map<String, dynamic>> items) {
    final ids = <String>[];
    for (final item in items) {
      final type = (item['type'] ?? '').toString();
      if (type == 'heading') {
        final children = item['children'];
        if (children is List) {
          for (final c in children) {
            if (c is Map && (c['type'] ?? '') == 'module') {
              final id = c['id']?.toString();
              if (id != null && id.isNotEmpty) ids.add(id);
            }
          }
        }
      } else if (type == 'module') {
        final id = item['id']?.toString();
        if (id != null && id.isNotEmpty) ids.add(id);
      }
      // type 'custom' wird übersprungen (kein App-Modul)
    }
    return ids;
  }

  /// Max. Unterpunkte pro Oberbegriff
  static int get maxChildrenPerHeading => _maxChildrenPerHeading;
}
