import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/information_model.dart';

/// CRUD für Information-Einträge.
/// Firestore: kunden/{companyId}/informationen
///
/// **Firmenweit:** Pro Firma eine Sammlung, keine Bereichs-Trennung.
class InformationenService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  static String _normalizeCompanyId(String companyId) =>
      companyId.trim().toLowerCase();

  Future<List<Information>> loadInformationen(String companyId, {int limit = 50}) async {
    try {
      final cid = _normalizeCompanyId(companyId);
      final snap = await _db
          .collection('kunden')
          .doc(cid)
          .collection('informationen')
          .orderBy('createdAt', descending: true)
          .limit(limit)
          .get();

      final items = snap.docs.map((d) => Information.fromFirestore(d.id, d.data())).toList();
      final expired = items.where((i) => i.isExpired).toList();
      if (expired.isNotEmpty) {
        for (final i in expired) {
          try {
            await deleteInformation(cid, i.id);
          } catch (_) {}
        }
      }
      return items.where((i) => !i.isExpired).toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> saveInformation(String companyId, Information info) async {
    final cid = _normalizeCompanyId(companyId);
    final col = _db.collection('kunden').doc(cid).collection('informationen');
    if (info.id.isEmpty) {
      final ref = col.doc();
      await ref.set(info.toMap());
    } else {
      await col.doc(info.id).set(info.toMap(), SetOptions(merge: true));
    }
  }

  Future<void> deleteInformation(String companyId, String id) async {
    final cid = _normalizeCompanyId(companyId);
    await _db.collection('kunden').doc(cid).collection('informationen').doc(id).delete();
  }
}
