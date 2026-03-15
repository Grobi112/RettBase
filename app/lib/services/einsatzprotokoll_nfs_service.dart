import 'package:cloud_firestore/cloud_firestore.dart';

/// Einsatzprotokoll NFS (Notfallseelsorge) – Firestore kunden/{companyId}/einsatzprotokoll-nfs
class EinsatzprotokollNfsService {
  final _db = FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> _col(String companyId) =>
      _db.collection('kunden').doc(companyId).collection('einsatzprotokoll-nfs');

  DocumentReference<Map<String, dynamic>> _counterDoc(String companyId, int year) =>
      _db.collection('kunden').doc(companyId).collection('einsatzprotokoll-nfs-zähler').doc(year.toString());

  /// Vorschau der nächsten laufenden Nr. (ohne Zähler zu erhöhen). Für Anzeige im Formular.
  Future<String> getNextLaufendeInterneNrPreview(String companyId) async {
    final year = DateTime.now().year;
    final ref = _counterDoc(companyId, year);
    final snap = await ref.get();
    final next = (snap.data()?['lastNumber'] as int? ?? 0) + 1;
    return '$year${next.toString().padLeft(4, '0')}';
  }

  /// Nächste laufende interne Nummer für das aktuelle Jahr (Format: YYYYNNNN, z.B. 20260001).
  /// Wird nur beim Speichern aufgerufen – erhöht den Zähler.
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
  /// [laufendeNrOverride]: Wenn gesetzt (z.B. "20260001-1" bei mehreren Kräften), wird diese Nr. verwendet
  /// und der Zähler nicht erhöht. Sonst wird die nächste fortlaufende Nr. vergeben.
  Future<({String id, String laufendeInterneNr})> create(
    String companyId,
    Map<String, dynamic> data, {
    String? creatorUid,
    String? creatorName,
    String? laufendeNrOverride,
  }) async {
    final laufendeNr = laufendeNrOverride?.trim().isNotEmpty == true
        ? laufendeNrOverride!.trim()
        : await getNextLaufendeInterneNr(companyId);
    final clean = Map<String, dynamic>.from(data);
    clean['laufendeInterneNr'] = laufendeNr;
    clean['createdAt'] = FieldValue.serverTimestamp();
    clean['createdBy'] = creatorUid;
    clean['createdByName'] = creatorName;
    final ref = await _col(companyId).add(clean);
    return (id: ref.id, laufendeInterneNr: laufendeNr);
  }

  /// Protokoll löschen. Wenn laufendeInterneNr die letzte vergebene Nr. ist, wird sie wieder freigegeben.
  /// Bei Format mit Suffix (z.B. 20260001-1) wird der Zähler nicht angepasst.
  Future<void> delete(String companyId, String docId, {String? laufendeInterneNr}) async {
    await _col(companyId).doc(docId).delete();
    if (laufendeInterneNr != null && laufendeInterneNr.length >= 8 && !laufendeInterneNr.contains('-')) {
      await _releaseLaufendeNrIfLast(companyId, laufendeInterneNr);
    }
  }

  /// Wenn die gelöschte Nr. die letzte vergebene war, Zähler zurücksetzen (Nr. wiederverwendbar).
  Future<void> _releaseLaufendeNrIfLast(String companyId, String laufendeInterneNr) async {
    final yearStr = laufendeInterneNr.substring(0, 4);
    final numStr = laufendeInterneNr.substring(4);
    final year = int.tryParse(yearStr);
    final num = int.tryParse(numStr);
    if (year == null || num == null) return;
    await _db.runTransaction((tx) async {
      final ref = _counterDoc(companyId, year);
      final snap = await tx.get(ref);
      final last = snap.data()?['lastNumber'] as int? ?? 0;
      if (last == num && num > 0) {
        tx.set(ref, {'lastNumber': num - 1});
      }
    });
  }

  /// Alle Protokolle streamen (neueste zuerst)
  Stream<List<Map<String, dynamic>>> streamProtokolle(String companyId) {
    return _col(companyId)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((s) => s.docs.map((d) => {'id': d.id, ...d.data()}).toList());
  }
}
