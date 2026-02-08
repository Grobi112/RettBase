import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import '../models/uebergriffsmeldung_model.dart';

/// Übergriffsmeldung – Firestore kunden/{companyId}/uebergriffsmeldungen
class UebergriffsmeldungService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirebaseStorage _storage = FirebaseStorage.instance;

  CollectionReference<Map<String, dynamic>> _col(String companyId) =>
      _db.collection('kunden').doc(companyId).collection('uebergriffsmeldungen');

  /// Übergriffsmeldung erstellen
  Future<String> create(String companyId, Uebergriffsmeldung m, String createdBy, String createdByName) async {
    final data = m.toFirestore();
    data['createdBy'] = createdBy;
    data['createdByName'] = createdByName;
    data['companyId'] = companyId;
    data['createdAt'] = FieldValue.serverTimestamp();
    final ref = await _col(companyId).add(data);
    return ref.id;
  }

  /// Alle Meldungen laden (neueste zuerst)
  Future<List<Uebergriffsmeldung>> loadAll(String companyId, {int limit = 200}) async {
    try {
      final snap = await _col(companyId)
          .orderBy('createdAt', descending: true)
          .limit(limit)
          .get();
      return snap.docs.map((d) => Uebergriffsmeldung.fromFirestore(d.id, d.data())).toList();
    } catch (_) {
      return [];
    }
  }

  /// Meldung aktualisieren
  Future<void> update(String companyId, Uebergriffsmeldung m) async {
    final data = m.toFirestore();
    data['updatedAt'] = FieldValue.serverTimestamp();
    await _col(companyId).doc(m.id).set(data, SetOptions(merge: true));
  }

  /// Meldung löschen
  Future<void> delete(String companyId, String id) async {
    await _col(companyId).doc(id).delete();
  }

  /// Dokument mit Unterschrift-URL aktualisieren
  Future<void> updateUnterschriftUrl(String companyId, String docId, String url) async {
    await _col(companyId).doc(docId).update({'unterschriftUrl': url});
  }

  /// Unterschrift hochladen
  Future<String> uploadUnterschrift(String companyId, String docId, Uint8List bytes) async {
    final path = 'kunden/$companyId/uebergriffsmeldung-attachments/$docId/unterschrift.png';
    final ref = _storage.ref(path);
    await ref.putData(bytes, SettableMetadata(contentType: 'image/png'));
    return ref.getDownloadURL();
  }
}
