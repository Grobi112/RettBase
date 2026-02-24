import 'package:cloud_firestore/cloud_firestore.dart';

/// Einsatzprotokoll NFS (Notfallseelsorge) – Firestore kunden/{companyId}/einsatzprotokoll-nfs
class EinsatzprotokollNfsService {
  final _db = FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> _col(String companyId) =>
      _db.collection('kunden').doc(companyId).collection('einsatzprotokoll-nfs');

  /// Protokoll erstellen
  Future<String> create(
    String companyId,
    Map<String, dynamic> data, {
    String? creatorUid,
    String? creatorName,
  }) async {
    final clean = Map<String, dynamic>.from(data);
    clean['createdAt'] = FieldValue.serverTimestamp();
    clean['createdBy'] = creatorUid;
    clean['createdByName'] = creatorName;
    final ref = await _col(companyId).add(clean);
    return ref.id;
  }

  /// Alle Protokolle streamen (neueste zuerst)
  Stream<List<Map<String, dynamic>>> streamProtokolle(String companyId) {
    return _col(companyId)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((s) => s.docs.map((d) => {'id': d.id, ...d.data()}).toList());
  }
}
