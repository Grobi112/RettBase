import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/schnittstellenmeldung_model.dart';

/// Service für Schnittstellenmeldungen
/// Firestore: kunden/{companyId}/schnittstellenmeldungen
class SchnittstellenmeldungService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> _collection(String companyId) =>
      _db.collection('kunden').doc(companyId).collection('schnittstellenmeldungen');

  /// Schnittstellenmeldung erstellen
  Future<String> create(String companyId, Schnittstellenmeldung m, String createdBy, String createdByName) async {
    final ref = _collection(companyId).doc();
    final data = m.toFirestore();
    data['createdBy'] = createdBy;
    data['createdByName'] = createdByName;
    data['companyId'] = companyId;
    data['createdAt'] = FieldValue.serverTimestamp();
    await ref.set(data);
    return ref.id;
  }

  /// Schnittstellenmeldung aktualisieren
  Future<void> update(String companyId, Schnittstellenmeldung m) async {
    final ref = _collection(companyId).doc(m.id);
    final data = Map<String, dynamic>.from(m.toFirestore());
    data['updatedAt'] = FieldValue.serverTimestamp();
    await ref.set(data, SetOptions(merge: true));
  }

  /// Schnittstellenmeldung löschen
  Future<void> delete(String companyId, String id) async {
    await _collection(companyId).doc(id).delete();
  }

  /// Alle Meldungen laden (neueste zuerst)
  Future<List<Schnittstellenmeldung>> loadAll(String companyId, {int limit = 200}) async {
    try {
      final snap = await _collection(companyId)
          .orderBy('createdAt', descending: true)
          .limit(limit)
          .get();
      return snap.docs.map((d) => Schnittstellenmeldung.fromFirestore(d.id, d.data())).toList();
    } catch (_) {
      return [];
    }
  }
}
