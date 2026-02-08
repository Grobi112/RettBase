import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/checkliste_model.dart';

/// Service für Checklisten (Qualitätsmanagement)
class ChecklistenService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> _checklisten(String companyId) =>
      _db.collection('kunden').doc(companyId).collection('checklisten');

  Stream<List<Checkliste>> streamChecklisten(String companyId) {
    return _checklisten(companyId)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((s) => s.docs.map((d) => Checkliste.fromFirestore(d.id, d.data())).toList());
  }

  Future<List<Checkliste>> loadChecklisten(String companyId) async {
    final snap = await _checklisten(companyId).orderBy('createdAt', descending: true).get();
    return snap.docs.map((d) => Checkliste.fromFirestore(d.id, d.data())).toList();
  }

  Future<String> createCheckliste(String companyId, Checkliste c, String uid) async {
    final data = c.toFirestore();
    data['createdAt'] = FieldValue.serverTimestamp();
    data['createdBy'] = uid;
    final ref = await _checklisten(companyId).add(data);
    return ref.id;
  }

  Future<void> updateCheckliste(String companyId, String id, Checkliste c) async {
    await _checklisten(companyId).doc(id).update(c.toFirestore());
  }

  Future<void> deleteCheckliste(String companyId, String id) async {
    await _checklisten(companyId).doc(id).delete();
  }

  CollectionReference<Map<String, dynamic>> _ausfuellungen(String companyId) =>
      _db.collection('kunden').doc(companyId).collection('checklistenAusfuellungen');

  Stream<List<ChecklisteAusfuellung>> streamAusfuellungen(String companyId) {
    return _ausfuellungen(companyId)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((s) => s.docs.map((d) => ChecklisteAusfuellung.fromFirestore(d.id, d.data())).toList());
  }

  Future<void> deleteAusfuellung(String companyId, String id) async {
    await _ausfuellungen(companyId).doc(id).delete();
  }

  Future<String> saveAusfuellung(String companyId, ChecklisteAusfuellung a, String uid, String? userName) async {
    final data = a.toFirestore();
    data['createdAt'] = FieldValue.serverTimestamp();
    data['createdBy'] = uid;
    data['createdByName'] = userName;
    final ref = await _ausfuellungen(companyId).add(data);
    return ref.id;
  }
}
