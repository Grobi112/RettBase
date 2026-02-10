import 'package:cloud_firestore/cloud_firestore.dart';

/// Service für Modulverwaltung – settings/modules/items, kunden/{id}/modules.
class ModulverwaltungService {
  final _db = FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> get _items =>
      _db.collection('settings').doc('modules').collection('items');

  /// Lädt alle Modul-Definitionen
  Future<Map<String, Map<String, dynamic>>> getAllModules() async {
    try {
      final snap = await _items.orderBy('order').get();
      return {for (final d in snap.docs) d.id: d.data()..['id'] = d.id};
    } catch (_) {
      return {};
    }
  }

  /// Lädt ein einzelnes Modul
  Future<Map<String, dynamic>?> getModule(String moduleId) async {
    final snap = await _items.doc(moduleId).get();
    if (!snap.exists) return null;
    return snap.data()!..['id'] = snap.id;
  }

  /// Speichert ein Modul (Create oder Update)
  Future<String> saveModule(Map<String, dynamic> data) async {
    final id = (data['id'] as String?) ?? _idFromLabel((data['label'] ?? '').toString());
    await _db.collection('settings').doc('modules').set({'_exists': true}, SetOptions(merge: true));

    final toSave = <String, dynamic>{
      'label': data['label'] ?? id,
      'url': data['url'] ?? '',
      'icon': data['icon'] ?? 'default',
      'roles': data['roles'] is List ? (data['roles'] as List).map((e) => e.toString()).toList() : ['user'],
      'free': data['free'] != false,
      'order': (data['order'] as num?)?.toInt() ?? 999,
      'active': data['active'] != false,
      'updatedAt': FieldValue.serverTimestamp(),
    };

    final ref = _items.doc(id);
    final exists = (await ref.get()).exists;
    if (!exists) toSave['createdAt'] = FieldValue.serverTimestamp();
    await ref.set(toSave, SetOptions(merge: true));
    return id;
  }

  /// Löscht ein Modul
  Future<void> deleteModule(String moduleId) async {
    if (['home', 'admin', 'kundenverwaltung'].contains(moduleId)) {
      throw Exception('System-Module können nicht gelöscht werden.');
    }
    await _items.doc(moduleId).delete();
  }

  /// Schaltet Modul für Firma frei/gesperrt
  Future<void> setCompanyModule(String companyId, String moduleId, bool enabled) async {
    await _db
        .collection('kunden')
        .doc(companyId)
        .collection('modules')
        .doc(moduleId)
        .set({'enabled': enabled});
  }

  /// Schaltet alle Module für Admin frei
  Future<void> enableAllForAdmin(Map<String, Map<String, dynamic>> modules) async {
    final batch = _db.batch();
    for (final id in modules.keys) {
      final ref = _db.collection('kunden').doc('admin').collection('modules').doc(id);
      batch.set(ref, {'enabled': true});
    }
    await batch.commit();
  }

  static String _idFromLabel(String label) =>
      label.toLowerCase().trim().replaceAll(RegExp(r'\s+'), '-').replaceAll(RegExp(r'[^a-z0-9-]'), '');
}
