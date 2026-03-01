import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/fahrtenbuch_v2_model.dart';
import '../models/fleet_model.dart';
import 'checklisten_service.dart';
import 'fahrtenbuch_service.dart';

/// Ein Fahrtenbuch V2 in der Übersicht (Fahrzeug mit Einträgen)
class FahrtenbuchV2UebersichtItem {
  final String kennzeichen;
  final String fahrzeugkennung;
  final int anzahl;
  final String displayLabel;

  FahrtenbuchV2UebersichtItem({
    required this.kennzeichen,
    required this.fahrzeugkennung,
    required this.anzahl,
    required this.displayLabel,
  });

  String get vehicleKey => kennzeichen.isNotEmpty ? kennzeichen : fahrzeugkennung;
}

/// Fahrtenbuch V2 – Firestore: kunden/{companyId}/fahrtenbuchEintraegeV2
class FahrtenbuchV2Service {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final _fahrtenbuchService = FahrtenbuchService();
  final _checklistenService = ChecklistenService();

  CollectionReference<Map<String, dynamic>> _eintraege(String companyId) =>
      _db
          .collection('kunden')
          .doc(companyId.trim().toLowerCase())
          .collection('fahrtenbuchEintraegeV2');

  Stream<List<FahrtenbuchV2Eintrag>> streamEintraege(String companyId) {
    return _eintraege(companyId)
        .orderBy('datum', descending: true)
        .snapshots()
        .map((s) => s.docs.map((d) => FahrtenbuchV2Eintrag.fromFirestore(d.id, d.data())).toList());
  }

  Stream<List<FahrtenbuchV2Eintrag>> streamEintraegeVonBis(
    String companyId, {
    required DateTime von,
    required DateTime bis,
  }) {
    return _eintraege(companyId)
        .where('datum', isGreaterThanOrEqualTo: Timestamp.fromDate(DateTime(von.year, von.month, von.day)))
        .where('datum', isLessThanOrEqualTo: Timestamp.fromDate(DateTime(bis.year, bis.month, bis.day, 23, 59, 59)))
        .orderBy('datum', descending: true)
        .snapshots()
        .map((s) => s.docs.map((d) => FahrtenbuchV2Eintrag.fromFirestore(d.id, d.data())).toList());
  }

  /// Letzten KM-Stand (Fahrtende) eines Fahrzeugs – für Vorausfüllung bei neuem Eintrag
  /// Berücksichtigt: V2-Einträge, V1-Einträge (inkl. manuelle KM-Korrektur aus Checkliste), Checkliste-Ausfüllungen
  Future<int?> getLetzterKmEnde(String companyId, String? kennzeichenOderRufname) async {
    if (kennzeichenOderRufname == null || kennzeichenOderRufname.trim().isEmpty) return null;
    final key = kennzeichenOderRufname.trim();

    ({int km, DateTime datum})? best;

    // 1. V2-Einträge
    try {
      final snap = await _eintraege(companyId)
          .orderBy('datum', descending: true)
          .limit(100)
          .get();
      for (final doc in snap.docs) {
        final d = doc.data();
        final kz = (d['kennzeichen'] ?? '').toString().trim();
        final fk = (d['fahrzeugkennung'] ?? '').toString().trim();
        if (kz == key || fk == key) {
          final kmE = d['kmEnde'];
          if (kmE != null) {
            final km = (kmE is num) ? kmE.toInt() : int.tryParse(kmE.toString());
            if (km != null) {
              final datum = d['datum'];
              DateTime? dt;
              if (datum is Timestamp) dt = datum.toDate();
              if (datum is DateTime) dt = datum;
              if (dt != null && (best == null || dt.isAfter(best!.datum))) {
                best = (km: km, datum: dt);
              }
              break;
            }
          }
        }
      }
    } catch (_) {}

    // 2. V1-Einträge (inkl. manuelle KM-Korrektur aus Checkliste)
    final v1 = await _fahrtenbuchService.getLetzterKmEndeByKennzeichenOderRufnameMitDatum(
      companyId,
      key,
      fahrzeugRufnameAlternativ: key,
    );
    if (v1 != null && (best == null || v1.datum.isAfter(best!.datum))) {
      best = (km: v1.km, datum: v1.datum);
    }

    // 3. Checkliste-Ausfüllungen (KM-Stand aus Checkliste)
    final checkliste = await _checklistenService.getLetzterKmStandFuerFahrzeug(companyId, key);
    if (checkliste != null && (best == null || checkliste.datum.isAfter(best!.datum))) {
      best = (km: checkliste.km, datum: checkliste.datum);
    }

    return best?.km;
  }

  /// Letzter KM-Stand nur aus Fahrtenbuch (V1 + V2), ohne Checkliste – z.B. für Checkliste-Vorausfüllung
  Future<int?> getLetzterKmEndeNurFahrtenbuch(
    String companyId, {
    String? kennzeichenOderRufname,
    String? fahrzeugRufnameAlternativ,
    String? fahrzeugId,
  }) async {
    final keys = <String>{
      if (kennzeichenOderRufname != null && kennzeichenOderRufname.trim().isNotEmpty) kennzeichenOderRufname.trim(),
      if (fahrzeugRufnameAlternativ != null && fahrzeugRufnameAlternativ.trim().isNotEmpty) fahrzeugRufnameAlternativ.trim(),
      if (fahrzeugId != null && fahrzeugId.trim().isNotEmpty) fahrzeugId.trim(),
    };
    if (keys.isEmpty) return null;

    ({int km, DateTime datum})? best;

    // 1. V2-Einträge
    try {
      final snap = await _eintraege(companyId)
          .orderBy('datum', descending: true)
          .limit(100)
          .get();
      for (final doc in snap.docs) {
        final d = doc.data();
        final kz = (d['kennzeichen'] ?? '').toString().trim();
        final fk = (d['fahrzeugkennung'] ?? '').toString().trim();
        if (!keys.contains(kz) && !keys.contains(fk)) continue;
        final kmE = d['kmEnde'];
        if (kmE != null) {
          final km = (kmE is num) ? kmE.toInt() : int.tryParse(kmE.toString());
          if (km != null) {
            final datum = d['datum'];
            DateTime? dt;
            if (datum is Timestamp) dt = datum.toDate();
            if (datum is DateTime) dt = datum;
            if (dt != null && (best == null || dt.isAfter(best!.datum))) {
              best = (km: km, datum: dt);
            }
            break;
          }
        }
      }
    } catch (_) {}

    // 2. V1-Einträge (ohne manuelle KM-Korrektur – die stammen aus der Checkliste, nicht aus dem Fahrtenbuch)
    final v1 = await _fahrtenbuchService.getLetzterKmEndeByKennzeichenOderRufnameMitDatum(
      companyId,
      kennzeichenOderRufname,
      fahrzeugRufnameAlternativ: fahrzeugRufnameAlternativ,
      fahrzeugId: fahrzeugId,
      ohneManuelleKmKorrektur: true,
    );
    if (v1 != null && (best == null || v1.datum.isAfter(best!.datum))) {
      best = (km: v1.km, datum: v1.datum);
    }

    return best?.km;
  }

  Future<String> createEintrag(String companyId, FahrtenbuchV2Eintrag e, String uid) async {
    final data = e.toFirestore();
    data['createdAt'] = FieldValue.serverTimestamp();
    data['createdBy'] = uid;
    final ref = await _eintraege(companyId).add(data);
    return ref.id;
  }

  Future<void> updateEintrag(String companyId, String eintragId, FahrtenbuchV2Eintrag e) async {
    final data = e.toFirestore();
    await _eintraege(companyId).doc(eintragId).update(data);
  }

  Future<void> deleteEintrag(String companyId, String eintragId) async {
    await _eintraege(companyId).doc(eintragId).delete();
  }

  Future<List<Fahrzeug>> loadFahrzeuge(String companyId) async {
    return _fahrtenbuchService.loadFahrzeuge(companyId);
  }

  /// Übersicht: Fahrzeuge mit Einträgen (aus Flotte + V2-Einträgen)
  Future<List<FahrtenbuchV2UebersichtItem>> loadFahrtenbuecherUebersicht(String companyId) async {
    final fahrzeuge = await loadFahrzeuge(companyId);
    final snap = await _eintraege(companyId).orderBy('datum', descending: true).get();
    final byKey = <String, FahrtenbuchV2UebersichtItem>{};
    for (final doc in snap.docs) {
      final d = doc.data();
      final kz = (d['kennzeichen'] ?? '').toString().trim();
      final fk = (d['fahrzeugkennung'] ?? '').toString().trim();
      final key = kz.isNotEmpty ? kz : (fk.isNotEmpty ? fk : 'Unbekannt');
      final label = kz.isNotEmpty ? kz : (fk.isNotEmpty ? fk : 'Unbekannt');
      if (byKey.containsKey(key)) {
        byKey[key] = FahrtenbuchV2UebersichtItem(
          kennzeichen: kz,
          fahrzeugkennung: fk,
          anzahl: byKey[key]!.anzahl + 1,
          displayLabel: label,
        );
      } else {
        byKey[key] = FahrtenbuchV2UebersichtItem(
          kennzeichen: kz,
          fahrzeugkennung: fk,
          anzahl: 1,
          displayLabel: label,
        );
      }
    }

    final fleetKeys = <String>{};
    final items = fahrzeuge.map((f) {
      final kz = (f.kennzeichen ?? '').trim();
      final ruf = (f.rufname ?? f.id ?? '').trim();
      final key = kz.isNotEmpty ? kz : (ruf.isNotEmpty ? ruf : f.id);
      final label = kz.isNotEmpty ? kz : (ruf.isNotEmpty ? ruf : f.id);
      if (kz.isNotEmpty) fleetKeys.add(kz);
      if (ruf.isNotEmpty) fleetKeys.add(ruf);
      final anzahl = byKey[key]?.anzahl ?? 0;
      return FahrtenbuchV2UebersichtItem(
        kennzeichen: kz,
        fahrzeugkennung: ruf,
        anzahl: anzahl,
        displayLabel: label,
      );
    }).toList();

    for (final u in byKey.values) {
      final key = u.vehicleKey;
      if (!fleetKeys.contains(key) && !fleetKeys.contains(u.kennzeichen) && !fleetKeys.contains(u.fahrzeugkennung)) {
        items.add(u);
      }
    }

    items.sort((a, b) {
      final ak = a.kennzeichen.isNotEmpty ? a.kennzeichen : a.fahrzeugkennung;
      final bk = b.kennzeichen.isNotEmpty ? b.kennzeichen : b.fahrzeugkennung;
      return ak.toLowerCase().compareTo(bk.toLowerCase());
    });
    return items;
  }

  /// Einträge für ein Fahrzeug streamen
  Stream<List<FahrtenbuchV2Eintrag>> streamEintraegeFuerFahrzeug(
    String companyId,
    String kennzeichenOderRufname,
  ) {
    if (kennzeichenOderRufname.trim().isEmpty) return Stream.value([]);
    final key = kennzeichenOderRufname.trim();
    return streamEintraege(companyId).map((list) {
      return list.where((e) {
        final kz = (e.kennzeichen ?? '').trim();
        final fk = (e.fahrzeugkennung ?? '').trim();
        return kz == key || fk == key;
      }).toList();
    });
  }
}
