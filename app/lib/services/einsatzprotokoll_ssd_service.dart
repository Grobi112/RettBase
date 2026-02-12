import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';

/// Einsatzprotokoll SSD – Firestore kunden/{companyId}/einsatzprotokoll-ssd
class EinsatzprotokollSsdService {
  final _db = FirebaseFirestore.instance;
  final _storage = FirebaseStorage.instance;

  CollectionReference<Map<String, dynamic>> _col(String companyId) =>
      _db.collection('kunden').doc(companyId).collection('einsatzprotokoll-ssd');

  /// Nächste Einsatz-Nr. im Format YYYYNNNN (z.B. 20260001). Laufende Nr. beginnt am 1.1. um 00:00 Uhr neu.
  Future<String> getNextEinsatzNr(String companyId) async {
    final year = DateTime.now().year;
    final prefix = '$year';
    final snap = await _col(companyId).get();
    int maxNr = 0;
    for (final doc in snap.docs) {
      final nr = (doc.data()['protokollNr'] ?? '').toString().trim();
      if (nr.length >= 8 && nr.startsWith(prefix)) {
        final run = int.tryParse(nr.substring(4)) ?? 0;
        if (run > maxNr) maxNr = run;
      }
    }
    return '$prefix${(maxNr + 1).toString().padLeft(4, '0')}';
  }

  /// Protokoll löschen (inkl. Storage-Dateien)
  Future<void> delete(String companyId, String docId) async {
    final doc = _col(companyId).doc(docId);
    final data = (await doc.get()).data();
    if (data != null) {
      try {
        final ref = _storage.ref().child('kunden/$companyId/einsatzprotokoll-ssd/$docId');
        final list = await ref.listAll();
        for (final item in list.items) {
          await item.delete();
        }
      } catch (_) {}
    }
    await doc.delete();
  }

  /// Einsatz-Nr. eines Protokolls aktualisieren (nur Superadmin)
  Future<void> updateProtokollNr(String companyId, String docId, String protokollNr) async {
    await _col(companyId).doc(docId).update({'protokollNr': protokollNr.trim()});
  }

  /// Alle Protokolle streamen (neueste zuerst)
  Stream<List<Map<String, dynamic>>> streamProtokolle(String companyId) {
    return _col(companyId)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((s) => s.docs.map((d) => {'id': d.id, ...d.data()}).toList());
  }

  /// Protokoll erstellen
  Future<String> create(String companyId, Map<String, dynamic> data, String? creatorUid, String? creatorName) async {
    final clean = Map<String, dynamic>.from(data);
    clean['createdAt'] = FieldValue.serverTimestamp();
    clean['createdBy'] = creatorUid;
    clean['createdByName'] = creatorName;
    final ref = await _col(companyId).add(clean);
    return ref.id;
  }

  /// Körperdiagramm-Skizze hochladen
  Future<String?> uploadKoerperSkizze(String companyId, String docId, Uint8List bytes) async {
    if (bytes.isEmpty) return null;
    final path = 'kunden/$companyId/einsatzprotokoll-ssd/$docId/koerper-skizze.png';
    final ref = _storage.ref().child(path);
    await ref.putData(bytes, SettableMetadata(contentType: 'image/png'));
    return ref.getDownloadURL();
  }

  /// Skizzen-URL im Protokoll-Dokument speichern
  Future<void> updateKoerperSkizzeUrl(String companyId, String docId, String url) async {
    await _col(companyId).doc(docId).update({'koerperSkizzeUrl': url});
  }

  /// Unterschrift eines Ersthelfers hochladen (index: 1 oder 2)
  Future<String?> uploadUnterschrift(String companyId, String docId, Uint8List bytes, int index) async {
    if (bytes.isEmpty) return null;
    final path = 'kunden/$companyId/einsatzprotokoll-ssd/$docId/unterschrift-$index.png';
    final ref = _storage.ref().child(path);
    await ref.putData(bytes, SettableMetadata(contentType: 'image/png'));
    return ref.getDownloadURL();
  }

  /// Unterschrift-URL im Protokoll-Dokument speichern (index: 1 oder 2)
  Future<void> updateUnterschriftUrl(String companyId, String docId, String url, int index) async {
    await _col(companyId).doc(docId).update({'unterschriftUrl$index': url});
  }
}
