import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/fahrtenbuch_model.dart';
import '../models/fleet_model.dart';

/// Ein Fahrtenbuch in der Übersicht (Fahrzeug mit Einträgen)
class FahrtenbuchUebersichtItem {
  final String kennzeichen;
  final String fahrzeugkennung;
  final int anzahl;
  final String displayLabel;
  /// true = letzter Eintrag ist manuelle KM-Korrektur (Fahrt nicht eingetragen)
  final bool hasManuelleKmKorrektur;

  FahrtenbuchUebersichtItem({
    required this.kennzeichen,
    required this.fahrzeugkennung,
    required this.anzahl,
    required this.displayLabel,
    this.hasManuelleKmKorrektur = false,
  });

  String get vehicleKey => kennzeichen.isNotEmpty ? kennzeichen : fahrzeugkennung;
}

/// Fahrtenbuch – digitales Fahrtenbuch
/// Firestore: kunden/{companyId}/fahrtenbuchEintraege
class FahrtenbuchService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> _eintraege(String companyId) =>
      _db.collection('kunden').doc(companyId).collection('fahrtenbuchEintraege');

  /// Alle Einträge streamen, sortiert nach Datum absteigend
  Stream<List<FahrtenbuchEintrag>> streamEintraege(String companyId) {
    return _eintraege(companyId)
        .orderBy('datum', descending: true)
        .snapshots()
        .map((s) => s.docs.map((d) => FahrtenbuchEintrag.fromFirestore(d.id, d.data())).toList());
  }

  /// Einträge nach Datumsbereich filtern
  Stream<List<FahrtenbuchEintrag>> streamEintraegeVonBis(
    String companyId, {
    required DateTime von,
    required DateTime bis,
  }) {
    return _eintraege(companyId)
        .where('datum', isGreaterThanOrEqualTo: Timestamp.fromDate(DateTime(von.year, von.month, von.day)))
        .where('datum', isLessThanOrEqualTo: Timestamp.fromDate(DateTime(bis.year, bis.month, bis.day, 23, 59, 59)))
        .orderBy('datum', descending: true)
        .snapshots()
        .map((s) => s.docs.map((d) => FahrtenbuchEintrag.fromFirestore(d.id, d.data())).toList());
  }

  /// Letzten Km-Stand eines Fahrzeugs laden (kmEnde der letzten Fahrt)
  /// fahrzeugId oder fahrzeugkennung wird verwendet
  Future<int?> getLetzterKmEnde(String companyId, String? fahrzeugkennung) async {
    if (fahrzeugkennung == null || fahrzeugkennung.trim().isEmpty) return null;
    final snap = await _eintraege(companyId)
        .where('fahrzeugkennung', isEqualTo: fahrzeugkennung.trim())
        .orderBy('datum', descending: true)
        .limit(1)
        .get();
    if (snap.docs.isEmpty) return null;
    final d = snap.docs.first.data();
    final kmE = d['kmEnde'];
    if (kmE == null) return null;
    return (kmE is num) ? kmE.toInt() : int.tryParse(kmE.toString());
  }

  /// Letzten End-Km eines Fahrzeugs nach Kennzeichen, fahrzeugkennung oder fahrzeugId
  /// Lädt Einträge und filtert in-memory (vermeidet Firestore-Index-Probleme)
  Future<int?> getLetzterKmEndeByKennzeichenOderRufname(
    String companyId,
    String? kennzeichenOderRufname, {
    String? fahrzeugRufnameAlternativ,
    String? fahrzeugId,
  }) async {
    final keys = <String>{
      if (kennzeichenOderRufname != null && kennzeichenOderRufname.trim().isNotEmpty) kennzeichenOderRufname.trim(),
      if (fahrzeugRufnameAlternativ != null && fahrzeugRufnameAlternativ.trim().isNotEmpty) fahrzeugRufnameAlternativ.trim(),
      if (fahrzeugId != null && fahrzeugId.trim().isNotEmpty) fahrzeugId.trim(),
    };
    if (keys.isEmpty) return null;

    int? _parseKm(Map<String, dynamic> d) {
      final kmE = d['kmEnde'] ?? d['km_ende'] ?? d['KmEnde'] ?? d['endKm'];
      if (kmE == null) return null;
      return (kmE is num) ? kmE.toInt() : int.tryParse(kmE.toString());
    }

    for (final cid in [companyId.trim().toLowerCase(), companyId]) {
      if (cid.isEmpty) continue;
      try {
        final snap = await _eintraege(cid)
            .orderBy('datum', descending: true)
            .limit(300)
            .get();
        int? bestKm;
        DateTime? bestDatum;
        for (final doc in snap.docs) {
          final d = doc.data();
          final kz = (d['kennzeichen'] ?? '').toString().trim();
          final fk = (d['fahrzeugkennung'] ?? '').toString().trim();
          final fid = (d['fahrzeugId'] ?? '').toString().trim();
          if (!keys.contains(kz) && !keys.contains(fk) && !keys.contains(fid)) continue;
          final km = _parseKm(d);
          if (km == null) continue;
          final datum = d['datum'];
          DateTime? dt;
          if (datum is Timestamp) dt = datum.toDate();
          if (datum is DateTime) dt = datum;
          if (dt != null && (bestDatum == null || dt.isAfter(bestDatum))) {
            bestKm = km;
            bestDatum = dt;
          }
        }
        if (bestKm != null) return bestKm;
      } catch (_) {}
    }
    return null;
  }

  /// Manuelle KM-Korrektur aus Checkliste speichern (z.B. wenn Fahrt nicht eingetragen wurde)
  /// Wird als Fahrtenbucheintrag gespeichert mit "Fehlender Fahrtenbucheintrag. Hier fehlen X km"
  Future<String> createManuelleKmKorrektur(
    String companyId, {
    required String? kennzeichen,
    required String? fahrzeugkennung,
    required int kmEnde,
    required int? kmAnfang,
    required String uid,
    String? userName,
  }) async {
    var kz = kennzeichen?.trim();
    var fk = fahrzeugkennung?.trim();
    if ((kz == null || kz.isEmpty) && (fk == null || fk.isEmpty)) {
      throw ArgumentError('Kennzeichen oder Fahrzeugkennung erforderlich');
    }
    if ((fk == null || fk.isEmpty) && (kz != null && kz.isNotEmpty)) fk = kz;
    if ((kz == null || kz.isEmpty) && (fk != null && fk.isNotEmpty)) kz = fk;

    final diff = kmAnfang != null ? kmEnde - kmAnfang : null;
    final diffText = diff != null ? 'Fehlender Fahrtenbucheintrag. Hier fehlen $diff km' : 'Fehlender Fahrtenbucheintrag (KM-Korrektur aus Checkliste)';

    final now = DateTime.now();
    final e = FahrtenbuchEintrag(
      id: '',
      fahrzeugkennung: fk?.isNotEmpty == true ? fk : null,
      kennzeichen: kz?.isNotEmpty == true ? kz : null,
      nameFahrer: userName,
      datum: now,
      einsatzart: 'Fehlender Fahrtenbucheintrag',
      einsatzort: diffText,
      kmAnfang: kmAnfang,
      kmEnde: kmEnde,
      gesamtKm: kmAnfang != null ? kmEnde - kmAnfang : null,
      manuellKmKorrektur: true,
      createdBy: uid,
    );
    final cid = companyId.trim().toLowerCase();
    try {
      return await createEintrag(cid, e, uid);
    } catch (_) {
      if (cid != companyId) return await createEintrag(companyId, e, uid);
      rethrow;
    }
  }

  /// Prüft ob der letzte Eintrag für ein Fahrzeug eine manuelle KM-Korrektur ist (Vermerk nötig)
  Future<bool> hatManuelleKmKorrekturAlsLetzten(
    String companyId,
    String kennzeichenOderRufname,
  ) async {
    if (kennzeichenOderRufname.trim().isEmpty) return false;
    final key = kennzeichenOderRufname.trim();
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
          return d['manuellKmKorrektur'] == true;
        }
      }
    } catch (_) {}
    return false;
  }

  /// Eintrag erstellen
  /// Bei echtem Fahrt-Eintrag (nicht KM-Korrektur) werden obsolete KM-Korrekturen
  /// für dasselbe Fahrzeug und denselben Tag automatisch gelöscht.
  Future<String> createEintrag(String companyId, FahrtenbuchEintrag e, String uid) async {
    final data = e.toFirestore();
    data['createdAt'] = FieldValue.serverTimestamp();
    data['createdBy'] = uid;
    final ref = await _eintraege(companyId).add(data);
    if (!e.manuellKmKorrektur && e.datum != null) {
      _removeObsoleteKmKorrekturen(companyId, e);
    }
    return ref.id;
  }

  /// Löscht KM-Korrektur-Einträge („Fehlender Fahrtenbucheintrag“), sobald die
  /// echte Fahrt für dasselbe Fahrzeug am selben Tag nachgetragen wurde.
  /// Nutzt Flotten-Daten, um Kennzeichen und Rufname als dasselbe Fahrzeug zu erkennen.
  Future<void> _removeObsoleteKmKorrekturen(String companyId, FahrtenbuchEintrag realEntry) async {
    var keys = <String>{
      if (realEntry.kennzeichen != null && realEntry.kennzeichen!.trim().isNotEmpty) realEntry.kennzeichen!.trim(),
      if (realEntry.fahrzeugkennung != null && realEntry.fahrzeugkennung!.trim().isNotEmpty) realEntry.fahrzeugkennung!.trim(),
    };
    if (keys.isEmpty) return;
    try {
      final fahrzeuge = await loadFahrzeuge(companyId);
      for (final f in fahrzeuge) {
        final kz = (f.kennzeichen ?? '').trim();
        final ruf = (f.rufname ?? '').trim();
        if (kz.isEmpty && ruf.isEmpty) continue;
        final fahrzeugKeys = {if (kz.isNotEmpty) kz, if (ruf.isNotEmpty) ruf, f.id};
        if (keys.any((k) => fahrzeugKeys.contains(k))) {
          keys = keys.union(fahrzeugKeys);
          break;
        }
      }
    } catch (_) {}
    final datum = realEntry.datum!;
    final tagStart = DateTime(datum.year, datum.month, datum.day);
    final tagEnd = DateTime(datum.year, datum.month, datum.day, 23, 59, 59);
    try {
      final snap = await _eintraege(companyId).orderBy('datum', descending: true).limit(300).get();
      for (final doc in snap.docs) {
        final d = doc.data();
        if (d['manuellKmKorrektur'] != true) continue;
        final docDatum = d['datum'];
        DateTime? docDt;
        if (docDatum is Timestamp) docDt = docDatum.toDate();
        if (docDatum is DateTime) docDt = docDatum;
        if (docDt == null || docDt.isBefore(tagStart) || docDt.isAfter(tagEnd)) continue;
        final kz = (d['kennzeichen'] ?? '').toString().trim();
        final fk = (d['fahrzeugkennung'] ?? '').toString().trim();
        final fid = (d['fahrzeugId'] ?? '').toString().trim();
        if (!keys.contains(kz) && !keys.contains(fk) && !keys.contains(fid)) continue;
        await _eintraege(companyId).doc(doc.id).delete();
      }
    } catch (_) {}
  }

  /// Eintrag aktualisieren
  Future<void> updateEintrag(String companyId, String eintragId, FahrtenbuchEintrag e) async {
    await _eintraege(companyId).doc(eintragId).update(e.toFirestore());
  }

  /// Eintrag löschen
  Future<void> deleteEintrag(String companyId, String eintragId) async {
    await _eintraege(companyId).doc(eintragId).delete();
  }

  /// Bereinigt obsolete KM-Korrekturen: Löscht „Fehlender Fahrtenbucheintrag“-Einträge,
  /// für die am selben Tag bereits eine echte Fahrt für dasselbe Fahrzeug existiert.
  /// Kann beim Aktualisieren der Übersicht aufgerufen werden.
  Future<void> cleanupObsoleteKmKorrekturen(String companyId) async {
    try {
      final snap = await _eintraege(companyId).orderBy('datum', descending: true).limit(400).get();
      final docs = snap.docs;
      final fahrzeuge = await loadFahrzeuge(companyId);
      final vehicleKeysByFahrzeug = <String, Set<String>>{};
      for (final f in fahrzeuge) {
        final kz = (f.kennzeichen ?? '').trim();
        final ruf = (f.rufname ?? '').trim();
        final ids = <String>{if (kz.isNotEmpty) kz, if (ruf.isNotEmpty) ruf, f.id};
        for (final id in ids) {
          if (id.isNotEmpty) vehicleKeysByFahrzeug[id] = ids;
        }
      }
      Set<String> _keysFor(Map<String, dynamic> d) {
        final kz = (d['kennzeichen'] ?? '').toString().trim();
        final fk = (d['fahrzeugkennung'] ?? '').toString().trim();
        final fid = (d['fahrzeugId'] ?? '').toString().trim();
        return vehicleKeysByFahrzeug[kz] ?? vehicleKeysByFahrzeug[fk] ?? vehicleKeysByFahrzeug[fid] ?? {if (kz.isNotEmpty) kz, if (fk.isNotEmpty) fk, if (fid.isNotEmpty) fid};
      }
      final daysWithRealEntries = <String>{};
      for (final doc in docs) {
        final d = doc.data();
        if (d['manuellKmKorrektur'] == true) continue;
        final docDatum = d['datum'];
        DateTime? docDt;
        if (docDatum is Timestamp) docDt = docDatum.toDate();
        if (docDatum is DateTime) docDt = docDatum;
        if (docDt == null) continue;
        final dayKey = '${docDt.year}-${docDt.month}-${docDt.day}';
        for (final k in _keysFor(d)) {
          if (k.isNotEmpty) daysWithRealEntries.add('$dayKey::$k');
        }
      }
      for (final doc in docs) {
        final d = doc.data();
        if (d['manuellKmKorrektur'] != true) continue;
        final docDatum = d['datum'];
        DateTime? docDt;
        if (docDatum is Timestamp) docDt = docDatum.toDate();
        if (docDatum is DateTime) docDt = docDatum;
        if (docDt == null) continue;
        final dayKey = '${docDt.year}-${docDt.month}-${docDt.day}';
        final keys = _keysFor(d);
        final hasRealEntry = keys.any((k) => k.isNotEmpty && daysWithRealEntries.contains('$dayKey::$k'));
        if (hasRealEntry) await _eintraege(companyId).doc(doc.id).delete();
      }
    } catch (_) {}
  }

  /// Fahrzeuge aus Flottenmanagement als Fahrtenbuch-Übersicht (nach Kennzeichen)
  /// Zeigt alle Flotten-Fahrzeuge; beim Klick die Fahrten dieses Fahrzeugs
  Future<List<FahrtenbuchUebersichtItem>> loadFahrtenbuecherAusFlotte(String companyId) async {
    final fahrzeuge = await loadFahrzeuge(companyId);
    final uebersicht = await loadFahrtenbuecherUebersicht(companyId);
    final anzahlByKey = <String, int>{};
    final korrekturByKey = <String, bool>{};
    for (final u in uebersicht) {
      anzahlByKey[u.vehicleKey] = u.anzahl;
      if (u.kennzeichen.isNotEmpty) anzahlByKey[u.kennzeichen] = u.anzahl;
      if (u.fahrzeugkennung.isNotEmpty) anzahlByKey[u.fahrzeugkennung] = u.anzahl;
      korrekturByKey[u.vehicleKey] = u.hasManuelleKmKorrektur;
      if (u.kennzeichen.isNotEmpty) korrekturByKey[u.kennzeichen] = u.hasManuelleKmKorrektur;
      if (u.fahrzeugkennung.isNotEmpty) korrekturByKey[u.fahrzeugkennung] = u.hasManuelleKmKorrektur;
    }

    final fleetKeys = <String>{};
    final items = fahrzeuge.map((f) {
      final kz = (f.kennzeichen ?? '').trim();
      final ruf = (f.rufname ?? f.id ?? '').trim();
      final key = kz.isNotEmpty ? kz : (ruf.isNotEmpty ? ruf : f.id);
      final label = kz.isNotEmpty ? kz : (ruf.isNotEmpty ? ruf : f.id);
      fleetKeys.add(key);
      if (kz.isNotEmpty) fleetKeys.add(kz);
      if (ruf.isNotEmpty) fleetKeys.add(ruf);
      final anzahl = anzahlByKey[key] ?? anzahlByKey[kz] ?? anzahlByKey[ruf] ?? 0;
      final hasKorrektur = korrekturByKey[key] ?? korrekturByKey[kz] ?? korrekturByKey[ruf] ?? false;
      return FahrtenbuchUebersichtItem(
        kennzeichen: kz,
        fahrzeugkennung: ruf,
        anzahl: anzahl,
        displayLabel: label,
        hasManuelleKmKorrektur: hasKorrektur,
      );
    }).toList();

    for (final u in uebersicht) {
      final key = u.vehicleKey;
      if (!fleetKeys.contains(key) && !fleetKeys.contains(u.kennzeichen) && !fleetKeys.contains(u.fahrzeugkennung)) {
        items.add(FahrtenbuchUebersichtItem(
          kennzeichen: u.kennzeichen,
          fahrzeugkennung: u.fahrzeugkennung,
          anzahl: u.anzahl,
          displayLabel: u.displayLabel,
          hasManuelleKmKorrektur: u.hasManuelleKmKorrektur,
        ));
      }
    }

    items.sort((a, b) {
      final ak = a.kennzeichen.isNotEmpty ? a.kennzeichen : a.fahrzeugkennung;
      final bk = b.kennzeichen.isNotEmpty ? b.kennzeichen : b.fahrzeugkennung;
      return ak.toLowerCase().compareTo(bk.toLowerCase());
    });
    return items;
  }

  /// Übersicht der Fahrtenbücher: Fahrzeuge (Kennzeichen) mit Einträgen
  /// Kennzeichen ist ausschlaggebend; bei leerem Kennzeichen wird fahrzeugkennung verwendet
  Future<List<FahrtenbuchUebersichtItem>> loadFahrtenbuecherUebersicht(String companyId) async {
    final snap = await _eintraege(companyId).orderBy('datum', descending: true).get();
    final byKey = <String, FahrtenbuchUebersichtItem>{};
    for (final doc in snap.docs) {
      final d = doc.data();
      final kz = (d['kennzeichen'] ?? '').toString().trim();
      final fk = (d['fahrzeugkennung'] ?? '').toString().trim();
      final key = kz.isNotEmpty ? kz : (fk.isNotEmpty ? fk : 'Unbekannt');
      final label = kz.isNotEmpty ? kz : (fk.isNotEmpty ? fk : 'Unbekannt');
      final isKorrektur = d['manuellKmKorrektur'] == true;
      if (byKey.containsKey(key)) {
        byKey[key] = FahrtenbuchUebersichtItem(
          kennzeichen: kz,
          fahrzeugkennung: fk,
          anzahl: byKey[key]!.anzahl + 1,
          displayLabel: label,
          hasManuelleKmKorrektur: byKey[key]!.hasManuelleKmKorrektur,
        );
      } else {
        byKey[key] = FahrtenbuchUebersichtItem(
          kennzeichen: kz,
          fahrzeugkennung: fk,
          anzahl: 1,
          displayLabel: label,
          hasManuelleKmKorrektur: isKorrektur,
        );
      }
    }
    final list = byKey.values.toList();
    list.sort((a, b) => (b.kennzeichen.isNotEmpty ? b.kennzeichen : b.fahrzeugkennung)
        .toLowerCase()
        .compareTo((a.kennzeichen.isNotEmpty ? a.kennzeichen : a.fahrzeugkennung).toLowerCase()));
    return list;
  }

  /// Einträge für ein bestimmtes Fahrzeug streamen (Kennzeichen oder fahrzeugkennung)
  Stream<List<FahrtenbuchEintrag>> streamEintraegeFuerFahrzeug(
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

  /// Aktive Fahrzeuge laden (für Dropdown)
  /// Lädt ohne aktiv-Filter (Filter in Code), damit auch Unternehmen mit abweichender Struktur funktionieren
  Future<List<Fahrzeug>> loadFahrzeuge(String companyId) async {
    try {
      final normalizedId = companyId.trim().toLowerCase();
      var snap = await _db
          .collection('kunden')
          .doc(normalizedId)
          .collection('fahrzeuge')
          .get();
      if (snap.docs.isEmpty && normalizedId != companyId) {
        snap = await _db
            .collection('kunden')
            .doc(companyId)
            .collection('fahrzeuge')
            .get();
      }
      final list = snap.docs
          .map((d) => Fahrzeug.fromFirestore(d.id, d.data()))
          .where((f) => f.aktiv != false)
          .toList();
      list.sort((a, b) => ((a.rufname ?? a.id) ?? '').toLowerCase().compareTo(((b.rufname ?? b.id) ?? '').toLowerCase()));
      return list;
    } catch (_) {
      return [];
    }
  }
}
