import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';
import '../models/kunde_model.dart';

/// Service für Kundenverwaltung – lädt und verwaltet Kunden (Firmen) aus Firestore.
/// Nur für Superadmin-Rolle.
/// Auf Web: Cloud Function loadKunden (umgeht Auth/Regel-Probleme).
class KundenverwaltungService {
  final _db = FirebaseFirestore.instance;
  final _functions = FirebaseFunctions.instanceFor(region: 'europe-west1');

  /// Lädt alle Kunden (Firmen) aus kunden-Collection.
  /// Web: Cloud Function (umgeht permission-denied). Mobile: direkter Firestore-Zugriff.
  /// Projekt: rett-fe0fa, Collection: kunden.
  Future<List<Kunde>> loadKunden() async {
    if (kIsWeb) {
      try {
        debugPrint('Kundenverwaltung: Lade über Cloud Function (Projekt: rett-fe0fa, Collection: kunden)');
        final res = await _functions.httpsCallable('loadKunden').call<Map<String, dynamic>>();
        final data = res.data;
        if (data == null) {
          debugPrint('Kundenverwaltung: Cloud Function lieferte kein data');
          return _loadKundenDirect();
        }
        final kundenList = data['kunden'] as List<dynamic>? ?? [];
        debugPrint('Kundenverwaltung: Cloud Function lieferte ${kundenList.length} Kunden');
        final result = kundenList.map((m) {
          final map = Map<String, dynamic>.from(m as Map);
          final id = map.remove('id') as String? ?? '';
          return Kunde.fromFirestore(id, map);
        }).toList();
        return result;
      } catch (e, st) {
        debugPrint('Kundenverwaltung: Cloud Function Fehler: $e');
        debugPrint('Kundenverwaltung: Stack: $st');
        try {
          return await _loadKundenDirect();
        } catch (e2) {
          debugPrint('Kundenverwaltung: Fallback Firestore ebenfalls fehlgeschlagen: $e2');
          rethrow;
        }
      }
    }
    return _loadKundenDirect();
  }

  Future<List<Kunde>> _loadKundenDirect() async {
    final snap = await _db.collection('kunden').get();
    final list = snap.docs
        .map((d) => Kunde.fromFirestore(d.id, d.data()))
        .toList();
    list.sort((a, b) => (a.name).toLowerCase().compareTo((b.name).toLowerCase()));
    return list;
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

  /// Lädt den Bereich eines Kunden (für Menü-Zuordnung).
  /// Sucht kunden/{companyId}, bei leerem bereich zusätzlich per kundenId/subdomain (Umbenennung).
  Future<String?> getCompanyBereich(String companyId) async {
    final cid = companyId.trim().toLowerCase();
    if (cid.isEmpty) return null;
    try {
      final doc = await _db.collection('kunden').doc(cid).get();
      var b = doc.data()?['bereich']?.toString();
      if (b != null && b.isNotEmpty) return b;
      // Auch bei existierendem Doc: Fallback wenn bereich fehlt (z.B. kkg-luenen leer, keg-luenen hat bereich)
      var q = await _db.collection('kunden').where('kundenId', isEqualTo: cid).limit(5).get();
      if (q.docs.isEmpty) {
        q = await _db.collection('kunden').where('subdomain', isEqualTo: cid).limit(5).get();
      }
      for (final d in q.docs) {
        final br = d.data()['bereich']?.toString();
        if (br != null && br.isNotEmpty) return br;
      }
    } catch (_) {}
    return null;
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
