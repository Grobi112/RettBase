import 'package:cloud_firestore/cloud_firestore.dart';

/// Einsatzprotokoll NFS (Notfallseelsorge) – Firestore kunden/{companyId}/einsatzprotokoll-nfs
class EinsatzprotokollNfsService {
  final _db = FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> _col(String companyId) =>
      _db.collection('kunden').doc(companyId).collection('einsatzprotokoll-nfs');

  DocumentReference<Map<String, dynamic>> _counterDoc(String companyId, int year) =>
      _db.collection('kunden').doc(companyId).collection('einsatzprotokoll-nfs-zähler').doc(year.toString());

  /// Nächste laufende interne Nummer für das aktuelle Jahr (Format: YYYYNNNN, z.B. 20260001).
  /// Reserviert die Nummer (erhöht Zähler). Muss beim Speichern mit übergeben werden.
  Future<String> getNextLaufendeInterneNr(String companyId) async {
    final year = DateTime.now().year;
    return _db.runTransaction<String>((tx) async {
      final ref = _counterDoc(companyId, year);
      final snap = await tx.get(ref);
      final next = (snap.data()?['lastNumber'] as int? ?? 0) + 1;
      tx.set(ref, {'lastNumber': next});
      return '$year${next.toString().padLeft(4, '0')}';
    });
  }

  /// Protokoll erstellen. Gibt (docId, laufendeInterneNr) zurück.
  /// Wenn data['laufendeInterneNr'] gesetzt ist, wird diese verwendet (bereits beim Formular-Load reserviert).
  Future<({String id, String laufendeInterneNr})> create(
    String companyId,
    Map<String, dynamic> data, {
    String? creatorUid,
    String? creatorName,
  }) async {
    final laufendeNr = (data['laufendeInterneNr']?.toString().trim().isNotEmpty == true)
        ? data['laufendeInterneNr']!.toString().trim()
        : await getNextLaufendeInterneNr(companyId);
    final clean = Map<String, dynamic>.from(data);
    clean['laufendeInterneNr'] = laufendeNr;
    clean['createdAt'] = FieldValue.serverTimestamp();
    clean['createdBy'] = creatorUid;
    clean['createdByName'] = creatorName;
    final ref = await _col(companyId).add(clean);
    return (id: ref.id, laufendeInterneNr: laufendeNr);
  }

  /// Protokoll löschen
  Future<void> delete(String companyId, String docId) async {
    await _col(companyId).doc(docId).delete();
  }

  /// Alle Protokolle streamen (neueste zuerst)
  Stream<List<Map<String, dynamic>>> streamProtokolle(String companyId) {
    return _col(companyId)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((s) => s.docs.map((d) => {'id': d.id, ...d.data()}).toList());
  }
}
