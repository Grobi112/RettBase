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

  /// Protokoll löschen. Anschließend wird der Zähler anhand der noch vorhandenen
  /// Protokolle neu berechnet, sodass auch nach Löschungen in beliebiger Reihenfolge
  /// die nächste freie Nr. korrekt vergeben wird.
  /// Bei Format mit Suffix (z.B. 20260001-1) wird der Zähler nicht angepasst.
  /// Wenn [laufendeInterneNr] nicht übergeben wird, wird sie aus dem Dokument gelesen (Robustheit).
  Future<void> delete(String companyId, String docId, {String? laufendeInterneNr}) async {
    var nr = laufendeInterneNr?.trim();
    if (nr == null || nr.isEmpty) {
      final doc = await _col(companyId).doc(docId).get();
      nr = doc.data()?['laufendeInterneNr']?.toString().trim();
    }
    await _col(companyId).doc(docId).delete();
    if (nr != null && nr.isNotEmpty && nr.length >= 8 && !nr.contains('-')) {
      final year = int.tryParse(nr.substring(0, 4));
      if (year != null) await _recalculateCounterForYear(companyId, year);
    }
  }

  /// Zähler für ein Jahr anhand der noch vorhandenen Protokolle neu berechnen.
  /// Setzt lastNumber auf die höchste noch vorhandene laufendeInterneNr dieses Jahres.
  /// Sind keine Protokolle mehr vorhanden, wird lastNumber auf 0 gesetzt.
  Future<void> _recalculateCounterForYear(String companyId, int year) async {
    final yearStr = year.toString();
    final snap = await _col(companyId).get();
    int maxNum = 0;
    for (final doc in snap.docs) {
      final nr = doc.data()['laufendeInterneNr']?.toString().trim() ?? '';
      if (nr.length >= 8 && nr.startsWith(yearStr) && !nr.contains('-')) {
        final num = int.tryParse(nr.substring(4));
        if (num != null && num > maxNum) maxNum = num;
      }
    }
    await _counterDoc(companyId, year).set({'lastNumber': maxNum});
  }

  /// Zähler manuell setzen (nur Superadmin).
  /// [lastNumber] = 0 → nächste vergebene Nummer wird YYYY0001 (z.B. 20260001).
  Future<void> setCounter(String companyId, int year, int lastNumber) async {
    await _counterDoc(companyId, year).set({'lastNumber': lastNumber});
  }

  /// Alle Protokolle streamen (neueste zuerst)
  Stream<List<Map<String, dynamic>>> streamProtokolle(String companyId) {
    return _col(companyId)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((s) => s.docs.map((d) => {'id': d.id, ...d.data()}).toList());
  }
}
