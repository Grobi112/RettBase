import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';

/// Einsatzprotokoll SSD – Firestore kunden/{companyId}/einsatzprotokoll-ssd
class EinsatzprotokollSsdService {
  final _db = FirebaseFirestore.instance;
  final _storage = FirebaseStorage.instance;

  CollectionReference<Map<String, dynamic>> _col(String companyId) =>
      _db.collection('kunden').doc(companyId).collection('einsatzprotokoll-ssd');

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
}
