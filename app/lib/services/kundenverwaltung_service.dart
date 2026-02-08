import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/kunde_model.dart';

/// Service für Kundenverwaltung – lädt und verwaltet Kunden (Firmen) aus Firestore.
/// Nur für Superadmin-Rolle.
class KundenverwaltungService {
  final _db = FirebaseFirestore.instance;

  /// Lädt alle Kunden (Firmen) aus kunden-Collection, sortiert nach Name.
  Future<List<Kunde>> loadKunden() async {
    final snap = await _db
        .collection('kunden')
        .orderBy('name')
        .get();

    return snap.docs
        .map((d) => Kunde.fromFirestore(d.id, d.data()))
        .toList();
  }

  /// Ermittelt die Anzahl der Benutzer einer Firma.
  Future<int> getUserCount(String companyId) async {
    final snap = await _db
        .collection('kunden')
        .doc(companyId)
        .collection('users')
        .get();
    return snap.docs.length;
  }

  /// Aktualisiert Kundendaten.
  Future<void> updateKunde(Kunde kunde, Map<String, dynamic> updates) async {
    await _db.collection('kunden').doc(kunde.id).update(updates);
  }

  /// Löscht einen Kunden (Hinweis: Subcollections bleiben erhalten).
  Future<void> deleteKunde(String companyId) async {
    await _db.collection('kunden').doc(companyId).delete();
  }

  /// Lädt die freigeschalteten Module für eine Firma.
  Future<Map<String, bool>> getCompanyModules(String companyId) async {
    try {
      final snap = await _db
          .collection('kunden')
          .doc(companyId)
          .collection('modules')
          .get();
      return {for (final d in snap.docs) d.id: d.data()['enabled'] == true};
    } catch (_) {
      return {};
    }
  }

  /// Speichert die Modul-Freischaltungen für eine Firma.
  Future<void> setCompanyModules(String companyId, Map<String, bool> modules) async {
    final batch = _db.batch();
    for (final entry in modules.entries) {
      final ref = _db
          .collection('kunden')
          .doc(companyId)
          .collection('modules')
          .doc(entry.key);
      batch.set(ref, {'enabled': entry.value});
    }
    await batch.commit();
  }

  /// Lädt alle Modul-Definitionen aus settings/modules/items.
  Future<Map<String, Map<String, dynamic>>> getAllModuleDefs() async {
    try {
      final snap = await _db
          .collection('settings')
          .doc('modules')
          .collection('items')
          .orderBy('order')
          .get();
      return {for (final d in snap.docs) d.id: d.data()};
    } catch (_) {
      return {};
    }
  }
}
