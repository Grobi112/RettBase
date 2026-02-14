import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/mitarbeiter_model.dart';
import 'mitarbeiter_service.dart';
import 'schichtanmeldung_service.dart';

/// Schichtplan NFS (Notfallseelsorge) – eigenes Modul mit separaten Firestore-Collections.
/// Pfade: schichtplanNfsStandorte, schichtplanNfsBereitschaftsTypen,
/// Mitarbeiter aus Mitgliederverwaltung (kunden/{companyId}/mitarbeiter)
/// schichtplanNfsBereitschaften/{dayId}/bereitschaften
SchichtplanMitarbeiter _mitarbeiterToSchichtplanMitarbeiter(Mitarbeiter m) {
  return SchichtplanMitarbeiter(
    id: m.id,
    vorname: m.vorname,
    nachname: m.nachname,
    email: m.email ?? m.pseudoEmail,
    qualifikation: m.qualifikation,
    personalnummer: m.personalnummer,
    strasse: m.strasse,
    hausnummer: m.hausnummer,
    plz: m.plz,
    ort: m.ort,
    telefonnummer: m.handynummer ?? m.telefon,
    role: m.role,
  );
}

class SchichtplanNfsService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final MitarbeiterService _mitarbeiterService = MitarbeiterService();

  /// Standorte laden (schichtplanNfsStandorte)
  Future<List<Standort>> loadStandorte(String companyId) async {
    try {
      final snap = await _db
          .collection('kunden')
          .doc(companyId)
          .collection('schichtplanNfsStandorte')
          .orderBy('order')
          .get();
      final list = <Standort>[];
      for (final d in snap.docs) {
        final data = d.data();
        if (data['active'] == false) continue;
        list.add(Standort(
          id: d.id,
          name: data['name']?.toString() ?? d.id,
          order: (data['order'] as num?)?.toInt() ?? 0,
        ));
      }
      list.sort((a, b) => a.order.compareTo(b.order));
      return list;
    } catch (_) {
      return [];
    }
  }

  /// Bereitschafts-Typen laden (schichtplanNfsBereitschaftsTypen)
  Future<List<BereitschaftsTyp>> loadBereitschaftsTypen(String companyId) async {
    try {
      final snap = await _db
          .collection('kunden')
          .doc(companyId)
          .collection('schichtplanNfsBereitschaftsTypen')
          .orderBy('name')
          .get();
      return snap.docs
          .map((d) => BereitschaftsTyp.fromFirestore(d.id, d.data()))
          .toList();
    } catch (_) {
      return [];
    }
  }

  /// Mitarbeiter laden aus Mitgliederverwaltung (kunden/{companyId}/mitarbeiter)
  Future<List<SchichtplanMitarbeiter>> loadMitarbeiter(String companyId) async {
    try {
      final list = await _mitarbeiterService.loadMitarbeiter(companyId);
      return list
          .where((m) => m.active)
          .map(_mitarbeiterToSchichtplanMitarbeiter)
          .toList();
    } catch (_) {
      return [];
    }
  }

  /// User einem NFS-Mitarbeiter zuordnen (E-Mail oder UID aus mitarbeiter)
  Future<SchichtplanMitarbeiter?> findMitarbeiterByEmail(
    String companyId,
    String email,
  ) async {
    if (email.isEmpty) return null;
    final list = await loadMitarbeiter(companyId);
    final normalized = email.trim().toLowerCase();
    for (final m in list) {
      if ((m.email ?? '').trim().toLowerCase() == normalized) return m;
    }
    return null;
  }

  Future<SchichtplanMitarbeiter?> findMitarbeiterByUid(
    String companyId,
    String uid,
  ) async {
    try {
      final docById = await _db.doc('kunden/$companyId/mitarbeiter/$uid').get();
      if (docById.exists && docById.data() != null) {
        var m = await _getMitarbeiterById(companyId, docById.id);
        if (m != null) return m;
        final d = docById.data()!;
        final email = d['email']?.toString() ?? '';
        final vorname = d['vorname']?.toString() ?? '';
        final nachname = d['nachname']?.toString() ?? '';
        m = await findMitarbeiterByEmail(companyId, email);
        if (m == null) m = await _findMitarbeiterByName(companyId, vorname, nachname);
        return m;
      }
      final docs = await _db
          .collection('kunden')
          .doc(companyId)
          .collection('mitarbeiter')
          .where('uid', isEqualTo: uid)
          .limit(1)
          .get();
      if (docs.docs.isEmpty) return null;
      final doc = docs.docs.first;
      final data = doc.data();
      var m = await _getMitarbeiterById(companyId, doc.id);
      if (m != null) return m;
      final email = data['email']?.toString() ?? '';
      final vorname = data['vorname']?.toString() ?? '';
      final nachname = data['nachname']?.toString() ?? '';
      m = await findMitarbeiterByEmail(companyId, email);
      if (m == null) m = await _findMitarbeiterByName(companyId, vorname, nachname);
      return m;
    } catch (_) {
      return null;
    }
  }

  Future<SchichtplanMitarbeiter?> _findMitarbeiterByName(
    String companyId,
    String vorname,
    String nachname,
  ) async {
    final v = (vorname).trim().toLowerCase();
    final n = (nachname).trim().toLowerCase();
    if (v.isEmpty && n.isEmpty) return null;
    final list = await loadMitarbeiter(companyId);
    for (final m in list) {
      final mv = (m.vorname ?? '').trim().toLowerCase();
      final mn = (m.nachname ?? '').trim().toLowerCase();
      if (mv == v && mn == n) return m;
    }
    return null;
  }

  Future<SchichtplanMitarbeiter?> _getMitarbeiterById(String companyId, String id) async {
    if (id.isEmpty) return null;
    try {
      final list = await _mitarbeiterService.loadMitarbeiter(companyId);
      final m = list.where((x) => x.id == id && x.active).firstOrNull;
      return m != null ? _mitarbeiterToSchichtplanMitarbeiter(m) : null;
    } catch (_) {
      return null;
    }
  }

  /// Bereitschaften für ein Datum laden
  Future<List<Bereitschaft>> loadBereitschaften(
    String companyId,
    String dayId,
  ) async {
    try {
      final snap = await _db
          .collection('kunden')
          .doc(companyId)
          .collection('schichtplanNfsBereitschaften')
          .doc(dayId)
          .collection('bereitschaften')
          .get();
      return snap.docs
          .map((d) => Bereitschaft.fromFirestore(d.id, d.data()))
          .toList();
    } catch (_) {
      return [];
    }
  }

  /// Bereitschaft anlegen
  Future<void> saveBereitschaft(
    String companyId,
    String dayId,
    String mitarbeiterId,
    String typId,
  ) async {
    final dayRef = _db
        .collection('kunden')
        .doc(companyId)
        .collection('schichtplanNfsBereitschaften')
        .doc(dayId);
    final daySnap = await dayRef.get();
    if (!daySnap.exists) {
      await dayRef.set({
        'dayId': dayId,
        'createdAt': FieldValue.serverTimestamp(),
      });
    }
    await dayRef.collection('bereitschaften').add({
      'mitarbeiterId': mitarbeiterId,
      'typId': typId,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  /// Bereitschaft löschen
  Future<void> deleteBereitschaft(
    String companyId,
    String dayId,
    String bereitschaftId,
  ) async {
    await _db
        .collection('kunden')
        .doc(companyId)
        .collection('schichtplanNfsBereitschaften')
        .doc(dayId)
        .collection('bereitschaften')
        .doc(bereitschaftId)
        .delete();
  }

  /// Bereitschafts-Typ anlegen
  Future<String> createBereitschaftsTyp(
    String companyId,
    String name, [
    String? beschreibung,
    int? color,
  ]) async {
    final ref = await _db
        .collection('kunden')
        .doc(companyId)
        .collection('schichtplanNfsBereitschaftsTypen')
        .add({
      'name': name.trim(),
      if (beschreibung != null && beschreibung.isNotEmpty) 'beschreibung': beschreibung.trim(),
      if (color != null) 'color': color,
      'createdAt': FieldValue.serverTimestamp(),
    });
    return ref.id;
  }

  /// Bereitschafts-Typ aktualisieren (Name, Beschreibung, Farbe)
  Future<void> updateBereitschaftsTyp(
    String companyId,
    String typId, {
    String? name,
    String? beschreibung,
    int? color,
  }) async {
    final data = <String, dynamic>{
      'updatedAt': FieldValue.serverTimestamp(),
    };
    if (name != null) data['name'] = name.trim();
    if (beschreibung != null) {
      data['beschreibung'] = beschreibung.trim().isEmpty ? FieldValue.delete() : beschreibung.trim();
    }
    if (color != null) data['color'] = color;
    await _db
        .collection('kunden')
        .doc(companyId)
        .collection('schichtplanNfsBereitschaftsTypen')
        .doc(typId)
        .update(data);
  }

  /// Mitarbeiter anlegen (schichtplanNfsMitarbeiter)
  Future<String> createMitarbeiter(
    String companyId, {
    String? personalnummer,
    required String email,
    required String vorname,
    required String nachname,
    String? strasse,
    String? hausnummer,
    String? plz,
    String? ort,
    String? telefonnummer,
    String? role,
  }) async {
    final ref = await _db
        .collection('kunden')
        .doc(companyId)
        .collection('schichtplanNfsMitarbeiter')
        .add({
      if (personalnummer != null && personalnummer.trim().isNotEmpty) 'personalnummer': personalnummer.trim(),
      'email': email.trim(),
      'vorname': vorname.trim(),
      'nachname': nachname.trim(),
      if (strasse != null && strasse.trim().isNotEmpty) 'strasse': strasse.trim(),
      if (hausnummer != null && hausnummer.trim().isNotEmpty) 'hausnummer': hausnummer.trim(),
      if (plz != null && plz.trim().isNotEmpty) 'plz': plz.trim(),
      if (ort != null && ort.trim().isNotEmpty) 'ort': ort.trim(),
      if (telefonnummer != null && telefonnummer.trim().isNotEmpty) 'telefonnummer': telefonnummer.trim(),
      if (role != null && role.trim().isNotEmpty) 'role': role.trim(),
      'createdAt': FieldValue.serverTimestamp(),
    });
    return ref.id;
  }

  /// Mitarbeiter aktualisieren (schichtplanNfsMitarbeiter)
  Future<void> updateMitarbeiter(
    String companyId,
    String mitarbeiterId, {
    String? personalnummer,
    String? email,
    String? vorname,
    String? nachname,
    String? strasse,
    String? hausnummer,
    String? plz,
    String? ort,
    String? telefonnummer,
    String? role,
  }) async {
    final data = <String, dynamic>{
      'updatedAt': FieldValue.serverTimestamp(),
    };
    if (personalnummer != null) data['personalnummer'] = personalnummer.trim().isEmpty ? FieldValue.delete() : personalnummer.trim();
    if (email != null) data['email'] = email.trim();
    if (vorname != null) data['vorname'] = vorname.trim();
    if (nachname != null) data['nachname'] = nachname.trim();
    if (strasse != null) data['strasse'] = strasse.trim().isEmpty ? FieldValue.delete() : strasse.trim();
    if (hausnummer != null) data['hausnummer'] = hausnummer.trim().isEmpty ? FieldValue.delete() : hausnummer.trim();
    if (plz != null) data['plz'] = plz.trim().isEmpty ? FieldValue.delete() : plz.trim();
    if (ort != null) data['ort'] = ort.trim().isEmpty ? FieldValue.delete() : ort.trim();
    if (telefonnummer != null) data['telefonnummer'] = telefonnummer.trim().isEmpty ? FieldValue.delete() : telefonnummer.trim();
    if (role != null) data['role'] = role.trim().isEmpty ? FieldValue.delete() : role.trim();
    await _db
        .collection('kunden')
        .doc(companyId)
        .collection('schichtplanNfsMitarbeiter')
        .doc(mitarbeiterId)
        .update(data);
  }

  // ---- Stundenplan (stundenweise Einträge) ----

  /// Tage im Monat, die mindestens einen Eintrag haben
  Future<Set<String>> loadTageMitEintraegen(
    String companyId,
    int month,
    int year,
  ) async {
    final daysInMonth = DateTime(year, month + 1, 0).day;
    final result = <String>{};
    for (var day = 1; day <= daysInMonth; day++) {
      final dayId =
          '${day.toString().padLeft(2, '0')}.${month.toString().padLeft(2, '0')}.$year';
      final e = await loadStundenplanEintraege(companyId, dayId);
      if (e.isNotEmpty && e.values.any((v) => v.trim().isNotEmpty)) {
        result.add(dayId);
      }
    }
    return result;
  }

  /// Tag-Status für Farbe: 'red' = offene Schichten, 'green' = alle mit S1 belegt, 'neutral' = sonst
  Future<Map<String, String>> loadTageStatusForMonth(
    String companyId,
    int month,
    int year,
  ) async {
    final typen = await loadBereitschaftsTypen(companyId);
    final s1Typ = typen
        .where((t) => t.name.trim().toLowerCase() == 's1')
        .firstOrNull;
    final s1TypId = s1Typ?.id;
    final daysInMonth = DateTime(year, month + 1, 0).day;
    final result = <String, String>{};
    for (var day = 1; day <= daysInMonth; day++) {
      final dayId =
          '${day.toString().padLeft(2, '0')}.${month.toString().padLeft(2, '0')}.$year';
      final e = await loadStundenplanEintraege(companyId, dayId);
      final belegt = <int>{};
      final typenProStunde = <int, Set<String>>{};
      for (var h = 0; h < 24; h++) typenProStunde[h] = {};
      for (final entry in e.entries) {
        if (entry.value.trim().isEmpty) continue;
        final parts = entry.key.split('_');
        if (parts.length != 2) continue;
        final h = int.tryParse(parts[1]);
        if (h == null || h < 0 || h >= 24) continue;
        belegt.add(h);
        typenProStunde[h]!.add(entry.value.trim());
      }
      final freieStunden = [for (var h = 0; h < 24; h++) if (!belegt.contains(h)) h];
      if (freieStunden.isNotEmpty) {
        result[dayId] = 'red';
      } else if (s1TypId != null &&
          typenProStunde.values.every((t) => t.length == 1 && t.contains(s1TypId))) {
        result[dayId] = 'green';
      } else {
        result[dayId] = 'neutral';
      }
    }
    return result;
  }

  /// Einträge für einen Tag: Map mit Key "mitarbeiterId_stunde" -> typId
  Future<Map<String, String>> loadStundenplanEintraege(
    String companyId,
    String dayId,
  ) async {
    try {
      final snap = await _db
          .collection('kunden')
          .doc(companyId)
          .collection('schichtplanNfsStundenplan')
          .doc(dayId)
          .get();
      final eintraege = snap.data()?['eintraege'];
      if (eintraege is Map) {
        return eintraege.map((k, v) => MapEntry(k.toString(), (v ?? '').toString()));
      }
    } catch (_) {}
    return {};
  }

  /// Einträge eines Mitarbeiters für bestimmte Stunden löschen (ein Schreibvorgang)
  Future<void> deleteStundenplanEintraegeForMitarbeiterStunden(
    String companyId,
    String dayId,
    String mitarbeiterId,
    int startStunde,
    int endStunde,
  ) async {
    final ref = _db
        .collection('kunden')
        .doc(companyId)
        .collection('schichtplanNfsStundenplan')
        .doc(dayId);
    final snap = await ref.get();
    final eintraege = snap.data()?['eintraege'];
    if (eintraege == null || eintraege is! Map) return;
    final e = Map<String, dynamic>.from(eintraege);
    for (var h = startStunde; h < endStunde; h++) {
      e.remove('${mitarbeiterId}_$h');
    }
    await ref.set({
      'dayId': dayId,
      'eintraege': e,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  /// Alle Einträge eines Mitarbeiters für einen Tag löschen
  Future<void> deleteStundenplanEintraegeForMitarbeiter(
    String companyId,
    String dayId,
    String mitarbeiterId,
  ) async {
    final ref = _db
        .collection('kunden')
        .doc(companyId)
        .collection('schichtplanNfsStundenplan')
        .doc(dayId);
    final snap = await ref.get();
    final eintraege = snap.data()?['eintraege'];
    if (eintraege == null || eintraege is! Map) return;
    final e = Map<String, dynamic>.from(eintraege);
    final prefix = '${mitarbeiterId}_';
    e.removeWhere((k, _) => k.startsWith(prefix));
    await ref.set({
      'dayId': dayId,
      'eintraege': e,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  /// Eintrag setzen oder löschen (typId leer = entfernen)
  Future<void> saveStundenplanEintrag(
    String companyId,
    String dayId,
    String mitarbeiterId,
    int stunde,
    String typId,
  ) async {
    final ref = _db
        .collection('kunden')
        .doc(companyId)
        .collection('schichtplanNfsStundenplan')
        .doc(dayId);
    final key = '${mitarbeiterId}_$stunde';
    final snap = await ref.get();
    final existing = snap.data()?['eintraege'] ?? {};
    final e = Map<String, dynamic>.from(existing);
    if (typId.trim().isEmpty) {
      e.remove(key);
    } else {
      e[key] = typId.trim();
    }
    await ref.set({
      'dayId': dayId,
      'eintraege': e,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  /// Meldung speichern (von "Bereitschaftszeit angeben")
  Future<String> saveMeldung(
    String companyId, {
    required String mitarbeiterId,
    required String vorname,
    required String nachname,
    required String? ort,
    required DateTime datumVon,
    required DateTime datumBis,
    required int uhrzeitVon,
    required int uhrzeitBis,
    required String typId,
  }) async {
    final ref = await _db
        .collection('kunden')
        .doc(companyId)
        .collection('schichtplanNfsMeldungen')
        .add({
      'mitarbeiterId': mitarbeiterId,
      'vorname': vorname.trim(),
      'nachname': nachname.trim(),
      'ort': ort?.trim().isEmpty == true ? null : (ort?.trim()),
      'datumVon': Timestamp.fromDate(datumVon),
      'datumBis': Timestamp.fromDate(datumBis),
      'uhrzeitVon': uhrzeitVon,
      'uhrzeitBis': uhrzeitBis,
      'typId': typId.trim(),
      'status': 'pending',
      'createdAt': FieldValue.serverTimestamp(),
    });
    return ref.id;
  }

  /// Pending-Meldungen laden (status == 'pending')
  Future<List<NfsMeldung>> loadMeldungen(String companyId) async {
    try {
      final snap = await _db
          .collection('kunden')
          .doc(companyId)
          .collection('schichtplanNfsMeldungen')
          .where('status', isEqualTo: 'pending')
          .get();
      final data = snap.docs.map((d) => (d: d, m: NfsMeldung.fromFirestore(d.id, d.data()))).toList();
      data.sort((a, b) {
        final tsA = a.d.data()['createdAt'] as Timestamp?;
        final tsB = b.d.data()['createdAt'] as Timestamp?;
        if (tsA == null && tsB == null) return 0;
        if (tsA == null) return 1;
        if (tsB == null) return -1;
        return tsB.compareTo(tsA);
      });
      return data.map((e) => e.m).toList();
    } catch (e) {
      // Index-Fehler oder Berechtigungen – Fehler weiterwerfen für Anzeige
      rethrow;
    }
  }

  /// Meldung als angenommen markieren und in Kalender eintragen
  Future<void> acceptMeldung(
    String companyId,
    NfsMeldung meldung,
  ) async {
    var d = DateTime(
      meldung.datumVon.year,
      meldung.datumVon.month,
      meldung.datumVon.day,
    );
    final end = DateTime(
      meldung.datumBis.year,
      meldung.datumBis.month,
      meldung.datumBis.day,
    );
    while (!d.isAfter(end)) {
      final dayId =
          '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.${d.year}';
      for (var h = meldung.uhrzeitVon; h < meldung.uhrzeitBis; h++) {
        await saveStundenplanEintrag(
          companyId,
          dayId,
          meldung.mitarbeiterId,
          h,
          meldung.typId,
        );
      }
      d = d.add(const Duration(days: 1));
    }
    await _db
        .collection('kunden')
        .doc(companyId)
        .collection('schichtplanNfsMeldungen')
        .doc(meldung.id)
        .update({
      'status': 'accepted',
      'acceptedAt': FieldValue.serverTimestamp(),
    });
  }

  /// Meldung ablehnen
  Future<void> rejectMeldung(
    String companyId,
    String meldungId,
  ) async {
    await _db
        .collection('kunden')
        .doc(companyId)
        .collection('schichtplanNfsMeldungen')
        .doc(meldungId)
        .update({
      'status': 'rejected',
      'rejectedAt': FieldValue.serverTimestamp(),
    });
  }

  /// Mitarbeiter mit Standort laden aus Mitgliederverwaltung (Ort = ort aus Adresse)
  Future<List<NfsMitarbeiterRow>> loadMitarbeiterMitStandort(String companyId) async {
    try {
      final ma = await loadMitarbeiter(companyId);
      return ma
          .map((m) => NfsMitarbeiterRow(
                mitarbeiter: m,
                standortName: m.ort?.trim().isNotEmpty == true ? m.ort : null,
              ))
          .toList();
    } catch (_) {
      return [];
    }
  }
}

/// Mitarbeiter mit Standort für Grid-Anzeige
class NfsMitarbeiterRow {
  final SchichtplanMitarbeiter mitarbeiter;
  final String? standortName;

  NfsMitarbeiterRow({required this.mitarbeiter, this.standortName});
}

/// Meldung von "Bereitschaftszeit angeben" (pending, bis angenommen/abgelehnt)
class NfsMeldung {
  final String id;
  final String mitarbeiterId;
  final String vorname;
  final String nachname;
  final String? ort;
  final DateTime datumVon;
  final DateTime datumBis;
  final int uhrzeitVon;
  final int uhrzeitBis;
  final String typId;
  final String status;

  NfsMeldung({
    required this.id,
    required this.mitarbeiterId,
    required this.vorname,
    required this.nachname,
    this.ort,
    required this.datumVon,
    required this.datumBis,
    required this.uhrzeitVon,
    required this.uhrzeitBis,
    required this.typId,
    required this.status,
  });

  factory NfsMeldung.fromFirestore(String id, Map<String, dynamic> data) {
    Timestamp? tv = data['datumVon'] as Timestamp?;
    Timestamp? tb = data['datumBis'] as Timestamp?;
    return NfsMeldung(
      id: id,
      mitarbeiterId: data['mitarbeiterId']?.toString() ?? '',
      vorname: data['vorname']?.toString() ?? '',
      nachname: data['nachname']?.toString() ?? '',
      ort: data['ort']?.toString(),
      datumVon: tv?.toDate() ?? DateTime.now(),
      datumBis: tb?.toDate() ?? DateTime.now(),
      uhrzeitVon: (data['uhrzeitVon'] as num?)?.toInt() ?? 0,
      uhrzeitBis: (data['uhrzeitBis'] as num?)?.toInt() ?? 24,
      typId: data['typId']?.toString() ?? '',
      status: data['status']?.toString() ?? 'pending',
    );
  }

  String get displayName => '$vorname $nachname'.trim();
  String get wohnort => ort?.trim().isEmpty == true ? '–' : (ort ?? '–');
}
