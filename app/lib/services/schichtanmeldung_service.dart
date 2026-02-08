import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/fahrtenbuch_vorlage.dart';
import '../models/checklisten_vorlage.dart';
import 'fahrtenbuch_service.dart';

/// Modell: Bereitschafts-Typ
class BereitschaftsTyp {
  final String id;
  final String name;
  final String? beschreibung;

  BereitschaftsTyp({required this.id, required this.name, this.beschreibung});

  factory BereitschaftsTyp.fromFirestore(String id, Map<String, dynamic> data) {
    return BereitschaftsTyp(
      id: id,
      name: data['name']?.toString() ?? id,
      beschreibung: data['beschreibung']?.toString(),
    );
  }
}

/// Modell: Bereitschaft (Selbstanmeldung)
class Bereitschaft {
  final String id;
  final String mitarbeiterId;
  final String typId;
  final DateTime? createdAt;

  Bereitschaft({
    required this.id,
    required this.mitarbeiterId,
    required this.typId,
    this.createdAt,
  });

  factory Bereitschaft.fromFirestore(String id, Map<String, dynamic> data) {
    Timestamp? ts = data['createdAt'] as Timestamp?;
    return Bereitschaft(
      id: id,
      mitarbeiterId: data['mitarbeiterId']?.toString() ?? '',
      typId: data['typId']?.toString() ?? '',
      createdAt: ts?.toDate(),
    );
  }
}

/// Modell: Schichtplan-Mitarbeiter (für Zuordnung)
class SchichtplanMitarbeiter {
  final String id;
  final String? vorname;
  final String? nachname;
  final String? email;
  final List<String>? qualifikation;

  SchichtplanMitarbeiter({
    required this.id,
    this.vorname,
    this.nachname,
    this.email,
    this.qualifikation,
  });

  String get displayName => '${nachname ?? ''}, ${vorname ?? ''}'.trim();

  factory SchichtplanMitarbeiter.fromFirestore(String id, Map<String, dynamic> data) {
    final q = data['qualifikation'];
    List<String>? qual;
    if (q is List) qual = q.map((e) => e.toString()).toList();
    return SchichtplanMitarbeiter(
      id: id,
      vorname: data['vorname']?.toString(),
      nachname: data['nachname']?.toString(),
      email: data['email']?.toString(),
      qualifikation: qual,
    );
  }
}

/// Schichtanmeldung – Bereitschaften, Standorte, Typen
/// Nutzt schichtplanBereitschaften, schichtplanStandorte, schichtplanBereitschaftsTypen
class SchichtanmeldungService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  /// Standorte laden
  Future<List<Standort>> loadStandorte(String companyId) async {
    try {
      final snap = await _db
          .collection('kunden')
          .doc(companyId)
          .collection('schichtplanStandorte')
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

  /// Bereitschafts-Typen laden
  Future<List<BereitschaftsTyp>> loadBereitschaftsTypen(String companyId) async {
    try {
      final snap = await _db
          .collection('kunden')
          .doc(companyId)
          .collection('schichtplanBereitschaftsTypen')
          .orderBy('name')
          .get();
      return snap.docs
          .map((d) => BereitschaftsTyp.fromFirestore(d.id, d.data()))
          .toList();
    } catch (_) {
      return [];
    }
  }

  /// Schichtplan-Mitarbeiter laden (für Zuordnung zum eingeloggten User)
  Future<List<SchichtplanMitarbeiter>> loadSchichtplanMitarbeiter(String companyId) async {
    try {
      final snap = await _db
          .collection('kunden')
          .doc(companyId)
          .collection('schichtplanMitarbeiter')
          .orderBy('nachname')
          .get();
      return snap.docs
          .map((d) => SchichtplanMitarbeiter.fromFirestore(d.id, d.data()))
          .toList();
    } catch (_) {
      return [];
    }
  }

  /// Aktuellen User einem Schichtplan-Mitarbeiter zuordnen (per E-Mail)
  Future<SchichtplanMitarbeiter?> findMitarbeiterByEmail(
    String companyId,
    String email,
  ) async {
    if (email.isEmpty) return null;
    final list = await loadSchichtplanMitarbeiter(companyId);
    final normalized = email.trim().toLowerCase();
    for (final m in list) {
      if ((m.email ?? '').trim().toLowerCase() == normalized) return m;
    }
    return null;
  }

  /// Aktuellen User per Name in Schichtplan-Mitarbeiter finden (Fallback bei Übereinstimmung)
  Future<SchichtplanMitarbeiter?> findMitarbeiterByName(
    String companyId,
    String vorname,
    String nachname,
  ) async {
    final v = (vorname ?? '').trim().toLowerCase();
    final n = (nachname ?? '').trim().toLowerCase();
    if (v.isEmpty && n.isEmpty) return null;
    final list = await loadSchichtplanMitarbeiter(companyId);
    for (final m in list) {
      final mv = (m.vorname ?? '').trim().toLowerCase();
      final mn = (m.nachname ?? '').trim().toLowerCase();
      if (mv == v && mn == n) return m;
    }
    return null;
  }

  /// Aktuellen User per UID aus mitarbeiter-Collection finden, dann in Schichtplan-Mitarbeiter matchen
  Future<SchichtplanMitarbeiter?> findMitarbeiterByUid(
    String companyId,
    String uid,
  ) async {
    try {
      var docs = await _db
          .collection('kunden')
          .doc(companyId)
          .collection('mitarbeiter')
          .where('uid', isEqualTo: uid)
          .limit(1)
          .get()
          .then((s) => s.docs);
      if (docs.isEmpty) {
        final docById = await _db.doc('kunden/$companyId/mitarbeiter/$uid').get();
        if (docById.exists && docById.data() != null) {
          var m = await getSchichtplanMitarbeiterById(companyId, docById.id);
          if (m != null) return m;
          final d = docById.data()!;
          final email = d['email']?.toString() ?? '';
          final vorname = d['vorname']?.toString() ?? '';
          final nachname = d['nachname']?.toString() ?? '';
          m = await findMitarbeiterByEmail(companyId, email);
          if (m == null) m = await findMitarbeiterByName(companyId, vorname, nachname);
          return m;
        }
      }
      if (docs.isEmpty) return null;
      final doc = docs.first;
      final data = doc.data();
      final mitarbeiterDocId = doc.id;
      var m = await getSchichtplanMitarbeiterById(companyId, mitarbeiterDocId);
      if (m != null) return m;
      final email = data['email']?.toString() ?? '';
      final vorname = data['vorname']?.toString() ?? '';
      final nachname = data['nachname']?.toString() ?? '';
      m = await findMitarbeiterByEmail(companyId, email);
      if (m == null) m = await findMitarbeiterByName(companyId, vorname, nachname);
      return m;
    } catch (_) {
      return null;
    }
  }

  /// Schichtplan-Mitarbeiter direkt per Dokument-ID laden (Verknüpfung wenn gleiche ID wie mitarbeiter-Collection)
  Future<SchichtplanMitarbeiter?> getSchichtplanMitarbeiterById(String companyId, String id) async {
    if (id.isEmpty) return null;
    try {
      final snap = await _db
          .collection('kunden')
          .doc(companyId)
          .collection('schichtplanMitarbeiter')
          .doc(id)
          .get();
      if (!snap.exists) return null;
      return SchichtplanMitarbeiter.fromFirestore(snap.id, snap.data()!);
    } catch (_) {
      return null;
    }
  }

  /// Bereitschaften für ein Datum laden (dayId = DD.MM.YYYY)
  Future<List<Bereitschaft>> loadBereitschaften(
    String companyId,
    String dayId,
  ) async {
    try {
      final snap = await _db
          .collection('kunden')
          .doc(companyId)
          .collection('schichtplanBereitschaften')
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

  /// Bereitschaft anlegen (kompatibel mit Web-Schichtplan)
  Future<void> saveBereitschaft(
    String companyId,
    String dayId,
    String mitarbeiterId,
    String typId,
  ) async {
    final dayRef = _db
        .collection('kunden')
        .doc(companyId)
        .collection('schichtplanBereitschaften')
        .doc(dayId);
    final daySnap = await dayRef.get();
    if (!daySnap.exists) {
      await dayRef.set({
        'dayId': dayId,
        'createdAt': FieldValue.serverTimestamp(),
      });
    }
    final colRef = dayRef.collection('bereitschaften');
    await colRef.add({
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
        .collection('schichtplanBereitschaften')
        .doc(dayId)
        .collection('bereitschaften')
        .doc(bereitschaftId)
        .delete();
  }

  /// Schichten laden (schichtplanSchichten)
  Future<List<SchichtTyp>> loadSchichten(String companyId) async {
    try {
      final snap = await _db
          .collection('kunden')
          .doc(companyId)
          .collection('schichtplanSchichten')
          .orderBy('order')
          .get();
      final list = <SchichtTyp>[];
      for (final d in snap.docs) {
        final data = d.data();
        if (data['active'] == false) continue;
        list.add(SchichtTyp.fromFirestore(d.id, data));
      }
      return list;
    } catch (_) {
      try {
        final snap = await _db
            .collection('kunden')
            .doc(companyId)
            .collection('schichtplanSchichten')
            .get();
        return snap.docs
            .map((d) => SchichtTyp.fromFirestore(d.id, d.data()))
            .toList();
      } catch (_) {
        return [];
      }
    }
  }

  /// Fahrzeuge laden (für Dropdown, inkl. "Alle")
  Future<List<FahrzeugKurz>> loadFahrzeuge(String companyId) async {
    try {
      final normalizedId = companyId.trim().toLowerCase();
      var snap = await _db.collection('kunden').doc(normalizedId).collection('fahrzeuge').get();
      if (snap.docs.isEmpty && normalizedId != companyId) {
        snap = await _db.collection('kunden').doc(companyId).collection('fahrzeuge').get();
      }
      final list = <FahrzeugKurz>[
        const FahrzeugKurz(id: 'alle', displayName: 'Alle'),
      ];
      final items = <FahrzeugKurz>[];
      for (final d in snap.docs) {
        final data = d.data();
        if (data['aktiv'] == false) continue;
        final ruf = data['rufname']?.toString() ?? data['name']?.toString() ?? '';
        final wache = data['wache']?.toString();
        final kz = (data['kennzeichen'] ?? data['Kennzeichen'])?.toString().trim();
        items.add(FahrzeugKurz(id: d.id, displayName: ruf.isNotEmpty ? ruf : d.id, wache: wache, kennzeichen: kz?.isNotEmpty == true ? kz : null));
      }
      items.sort((a, b) => a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase()));
      return [...list, ...items];
    } catch (_) {
      return [const FahrzeugKurz(id: 'alle', displayName: 'Alle')];
    }
  }

  /// Schicht-Typ erstellen
  Future<String> createSchicht(String companyId, SchichtTyp s) async {
    final data = s.toFirestore();
    data['createdAt'] = FieldValue.serverTimestamp();
    final ref = await _db
        .collection('kunden')
        .doc(companyId)
        .collection('schichtplanSchichten')
        .add(data);
    return ref.id;
  }

  /// Schicht-Typ aktualisieren
  Future<void> updateSchicht(String companyId, String schichtId, SchichtTyp s) async {
    await _db
        .collection('kunden')
        .doc(companyId)
        .collection('schichtplanSchichten')
        .doc(schichtId)
        .update(s.toFirestore());
  }

  /// Schicht-Typ löschen (soft: active=false) oder hart löschen
  Future<void> deleteSchicht(String companyId, String schichtId, {bool hard = false}) async {
    if (hard) {
      await _db
          .collection('kunden')
          .doc(companyId)
          .collection('schichtplanSchichten')
          .doc(schichtId)
          .delete();
    } else {
      await _db
          .collection('kunden')
          .doc(companyId)
          .collection('schichtplanSchichten')
          .doc(schichtId)
          .update({'active': false, 'updatedAt': FieldValue.serverTimestamp()});
    }
  }

  /// Standort erstellen
  Future<String> createStandort(String companyId, String name, {int order = 0}) async {
    final ref = await _db
        .collection('kunden')
        .doc(companyId)
        .collection('schichtplanStandorte')
        .add({
      'name': name,
      'order': order,
      'active': true,
      'updatedAt': FieldValue.serverTimestamp(),
    });
    return ref.id;
  }

  /// Standort aktualisieren
  Future<void> updateStandort(String companyId, String standortId, String name, {int? order}) async {
    final data = <String, dynamic>{'name': name, 'updatedAt': FieldValue.serverTimestamp()};
    if (order != null) data['order'] = order;
    await _db
        .collection('kunden')
        .doc(companyId)
        .collection('schichtplanStandorte')
        .doc(standortId)
        .update(data);
  }

  /// Standort löschen
  Future<void> deleteStandort(String companyId, String standortId) async {
    await _db
        .collection('kunden')
        .doc(companyId)
        .collection('schichtplanStandorte')
        .doc(standortId)
        .delete();
  }

  /// Schichtanmeldung löschen
  Future<void> deleteSchichtanmeldung(String companyId, String anmeldungId) async {
    await _db
        .collection('kunden')
        .doc(companyId)
        .collection('schichtanmeldungen')
        .doc(anmeldungId)
        .delete();
  }

  /// Schichtanmeldung erfassen (vollständiges Formular)
  Future<void> saveSchichtanmeldung(
    String companyId,
    SchichtanmeldungEintrag e,
  ) async {
    await _db
        .collection('kunden')
        .doc(companyId)
        .collection('schichtanmeldungen')
        .add(e.toFirestore());
  }

  /// Alle Schichtanmeldungen für einen Datumsbereich laden (für Übersicht)
  Future<List<SchichtanmeldungEintrag>> loadSchichtanmeldungenForDateRange(
    String companyId,
    DateTime startDate,
    DateTime endDate,
  ) async {
    final dayIds = <String>[];
    var d = DateTime(startDate.year, startDate.month, startDate.day);
    final end = DateTime(endDate.year, endDate.month, endDate.day);
    while (!d.isAfter(end)) {
      dayIds.add('${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.${d.year}');
      d = d.add(const Duration(days: 1));
    }
    if (dayIds.isEmpty) return [];
    final results = <SchichtanmeldungEintrag>[];
    for (var i = 0; i < dayIds.length; i += 30) {
      final batch = dayIds.skip(i).take(30).toList();
      try {
        final snap = await _db
            .collection('kunden')
            .doc(companyId)
            .collection('schichtanmeldungen')
            .where('datum', whereIn: batch)
            .get();
        for (final doc in snap.docs) {
          results.add(SchichtanmeldungEintrag.fromFirestore(doc.id, doc.data()));
        }
      } catch (_) {}
    }
    return results;
  }

  /// Schichtanmeldungen für Mitarbeiter an Tagen laden
  Future<List<SchichtanmeldungEintrag>> loadSchichtanmeldungenForMitarbeiter(
    String companyId,
    String mitarbeiterId,
    List<String> dayIds,
  ) async {
    if (dayIds.isEmpty) return [];
    try {
      final snap = await _db
          .collection('kunden')
          .doc(companyId)
          .collection('schichtanmeldungen')
          .where('mitarbeiterId', isEqualTo: mitarbeiterId)
          .where('datum', whereIn: dayIds)
          .get();
      return snap.docs
          .map((d) => SchichtanmeldungEintrag.fromFirestore(d.id, d.data()))
          .toList();
    } catch (_) {
      return [];
    }
  }

  /// Prüft ob die aktuelle Zeit innerhalb der Schicht liegt (inkl. endetFolgetag)
  static bool _isZeitInSchicht(DateTime now, DateTime datumTag, SchichtTyp schicht) {
    final startStr = schicht.startTime;
    final endStr = schicht.endTime;
    if (startStr == null || endStr == null || startStr.isEmpty || endStr.isEmpty) return false;
    final sp = startStr.split(':');
    final ep = endStr.split(':');
    if (sp.length < 2 || ep.length < 2) return false;
    final startMin = (int.tryParse(sp[0]) ?? 0) * 60 + (int.tryParse(sp[1]) ?? 0);
    final endMin = (int.tryParse(ep[0]) ?? 0) * 60 + (int.tryParse(ep[1]) ?? 0);
    final nowMin = now.hour * 60 + now.minute;
    final tagStart = DateTime(datumTag.year, datumTag.month, datumTag.day);
    final tagEnd = tagStart.add(const Duration(days: 1));

    if (schicht.endetFolgetag) {
      final shiftStart = tagStart.add(Duration(minutes: startMin));
      final shiftEnd = tagEnd.add(Duration(minutes: endMin));
      return (now.isAfter(shiftStart) || now.isAtSameMomentAs(shiftStart)) && now.isBefore(shiftEnd);
    } else {
      final shiftStart = tagStart.add(Duration(minutes: startMin));
      final shiftEnd = tagStart.add(Duration(minutes: endMin));
      return (now.isAfter(shiftStart) || now.isAtSameMomentAs(shiftStart)) && now.isBefore(shiftEnd);
    }
  }

  /// FahrtenbuchVorlage aus Schichtanmeldung bauen (für Vorausfüllung bei aktivem Schicht-Einstieg)
  Future<FahrtenbuchVorlage?> buildFahrtenbuchVorlageFromAnmeldung(
    String companyId,
    SchichtanmeldungEintrag e,
    FahrtenbuchService fahrtenbuchService,
  ) async {
    if (e.datum.isEmpty) return null;
    final mitarbeiterList = await loadSchichtplanMitarbeiter(companyId);
    final mitarbeiterMap = {for (final m in mitarbeiterList) m.id: m};
    String mitarbeiterName(String id) => mitarbeiterMap[id]?.displayName ?? id;

    DateTime datumTag;
    try {
      final p = e.datum.split('.');
      if (p.length != 3) return null;
      datumTag = DateTime(int.parse(p[2]), int.parse(p[1]), int.parse(p[0]));
    } catch (_) {
      return null;
    }

    final alleFuerSchicht = await loadSchichtanmeldungenForDateRange(companyId, datumTag, datumTag);
    final gruppe = alleFuerSchicht
        .where((a) =>
            a.datum == e.datum &&
            a.wacheId == e.wacheId &&
            a.schichtId == e.schichtId &&
            a.fahrzeugId == e.fahrzeugId)
        .toList();
    final fahrer = gruppe.where((a) => a.rolle == 'fahrer').toList();
    final beifahrer = gruppe.where((a) => a.rolle != 'fahrer').toList();
    final nameFahrer = fahrer.isNotEmpty ? mitarbeiterName(fahrer.first.mitarbeiterId) : null;
    final nameBeifahrer = beifahrer.isNotEmpty ? mitarbeiterName(beifahrer.first.mitarbeiterId) : null;
    final fahrerNamen = fahrer.map((a) => mitarbeiterName(a.mitarbeiterId)).where((n) => n != '–' && n.isNotEmpty).toSet().toList();
    final beifahrerNamen = beifahrer.map((a) => mitarbeiterName(a.mitarbeiterId)).where((n) => n != '–' && n.isNotEmpty).toSet().toList();

    String rufname = e.fahrzeugId == 'alle' ? 'Alle' : '';
    String fahrzeugId = e.fahrzeugId;
    String? kennzeichen;
    int? kmAnfang;

    if (e.fahrzeugId != 'alle' && e.fahrzeugId.isNotEmpty) {
      final allFz = await loadFahrzeuge(companyId);
      final fahrzeugKurz = allFz.where((f) => f.id == e.fahrzeugId).firstOrNull;
      rufname = fahrzeugKurz?.displayName ?? e.fahrzeugId;
      kennzeichen = fahrzeugKurz?.kennzeichen;
      if (kennzeichen == null || kennzeichen!.isEmpty) {
        try {
          final fleetFz = await fahrtenbuchService.loadFahrzeuge(companyId);
          var ff = fleetFz.where((f) => f.id == e.fahrzeugId).firstOrNull;
          if (ff == null && rufname.isNotEmpty) {
            ff = fleetFz.where((f) => (f.rufname ?? f.id) == rufname).firstOrNull;
          }
          kennzeichen = ff?.kennzeichen;
        } catch (_) {}
      }
      kmAnfang = await fahrtenbuchService.getLetzterKmEnde(companyId, rufname);
    }

    return FahrtenbuchVorlage(
      fahrzeugId: fahrzeugId,
      fahrzeugRufname: rufname,
      kennzeichen: kennzeichen,
      nameFahrer: nameFahrer,
      nameBeifahrer: nameBeifahrer,
      kmAnfang: kmAnfang,
      datum: datumTag,
      fahrerOptionen: fahrerNamen,
      beifahrerOptionen: beifahrerNamen,
    );
  }

  /// ChecklistenVorlage aus Schichtanmeldung (Fahrer, Beifahrer, Kennzeichen, Standort, Wachbuch-Schicht)
  Future<ChecklistenVorlage?> buildChecklistenVorlageFromAnmeldung(
    String companyId,
    SchichtanmeldungEintrag e,
    FahrtenbuchService fahrtenbuchService,
  ) async {
    if (e.datum.isEmpty) return null;
    final mitarbeiterList = await loadSchichtplanMitarbeiter(companyId);
    final mitarbeiterMap = {for (final m in mitarbeiterList) m.id: m};
    String mitarbeiterName(String id) => mitarbeiterMap[id]?.displayName ?? id;

    final standorte = await loadStandorte(companyId);
    final schichten = await loadSchichten(companyId);
    final standortName = standorte.where((s) => s.id == e.wacheId).firstOrNull?.name ?? e.wacheId;
    final schicht = schichten.where((s) => s.id == e.schichtId).firstOrNull;
    final schichtName = schicht?.name ?? e.schichtId;

    final alleFuerSchicht = await loadSchichtanmeldungenForDateRange(companyId,
        DateTime(int.parse(e.datum.split('.').last), int.parse(e.datum.split('.')[1]), int.parse(e.datum.split('.')[0])),
        DateTime(int.parse(e.datum.split('.').last), int.parse(e.datum.split('.')[1]), int.parse(e.datum.split('.')[0])));
    final gruppe = alleFuerSchicht
        .where((a) => a.datum == e.datum && a.wacheId == e.wacheId && a.schichtId == e.schichtId && a.fahrzeugId == e.fahrzeugId)
        .toList();
    final fahrer = gruppe.where((a) => a.rolle == 'fahrer').toList();
    final beifahrer = gruppe.where((a) => a.rolle != 'fahrer').toList();
    final nameFahrer = fahrer.isNotEmpty ? mitarbeiterName(fahrer.first.mitarbeiterId) : null;
    final nameBeifahrer = beifahrer.isNotEmpty ? mitarbeiterName(beifahrer.first.mitarbeiterId) : null;
    final fahrerNamen = fahrer.map((a) => mitarbeiterName(a.mitarbeiterId)).where((n) => n != '–' && n.isNotEmpty).toSet().toList();
    final beifahrerNamen = beifahrer.map((a) => mitarbeiterName(a.mitarbeiterId)).where((n) => n != '–' && n.isNotEmpty).toSet().toList();

    String? kennzeichen;
    String? fahrzeugRufname;
    final kennzeichenOptionen = <String>[];
    if (e.fahrzeugId != 'alle' && e.fahrzeugId.isNotEmpty) {
      final allFz = await loadFahrzeuge(companyId);
      final fahrzeugKurz = allFz.where((f) => f.id == e.fahrzeugId).firstOrNull;
      fahrzeugRufname = fahrzeugKurz?.displayName ?? e.fahrzeugId;
      kennzeichen = fahrzeugKurz?.kennzeichen;
      if (kennzeichen == null || kennzeichen!.isEmpty) {
        try {
          final fleetFz = await fahrtenbuchService.loadFahrzeuge(companyId);
          final ff = fleetFz.where((f) => f.id == e.fahrzeugId).firstOrNull;
          kennzeichen = ff?.kennzeichen;
        } catch (_) {}
      }
      if (kennzeichen != null && kennzeichen.isNotEmpty) kennzeichenOptionen.add(kennzeichen);
      if (fahrzeugRufname != null && fahrzeugRufname!.isNotEmpty && !kennzeichenOptionen.contains(fahrzeugRufname)) {
        kennzeichenOptionen.add(fahrzeugRufname!);
      }
    }

    return ChecklistenVorlage(
      fahrer: nameFahrer,
      beifahrer: nameBeifahrer,
      kennzeichen: kennzeichen ?? fahrzeugRufname,
      fahrzeugRufname: fahrzeugRufname,
      fahrzeugId: e.fahrzeugId != 'alle' && e.fahrzeugId.isNotEmpty ? e.fahrzeugId : null,
      standort: standortName.isNotEmpty ? standortName : null,
      wachbuchSchicht: schichtName.isNotEmpty ? schichtName : null,
      fahrerOptionen: fahrerNamen,
      beifahrerOptionen: beifahrerNamen,
      kennzeichenOptionen: kennzeichenOptionen,
    );
  }

  /// Aktive Schichtanmeldung für Mitarbeiter ermitteln.
  /// User bleibt für die gesamte Schichtdauer aktiv (bis Endzeit), unabhängig von App-Logout.
  Future<SchichtanmeldungEintrag?> getAktiveSchichtanmeldung(
    String companyId,
    String mitarbeiterId, {
    DateTime? now,
  }) async {
    final n = now ?? DateTime.now();
    final todayStr = '${n.day.toString().padLeft(2, '0')}.${n.month.toString().padLeft(2, '0')}.${n.year}';
    final yesterday = n.subtract(const Duration(days: 1));
    final yesterdayStr = '${yesterday.day.toString().padLeft(2, '0')}.${yesterday.month.toString().padLeft(2, '0')}.${yesterday.year}';

    final anmeldungen = await loadSchichtanmeldungenForMitarbeiter(companyId, mitarbeiterId, [todayStr, yesterdayStr]);
    final schichten = await loadSchichten(companyId);
    final schichtenMap = {for (final s in schichten) s.id: s};

    for (final a in anmeldungen) {
      final schicht = schichtenMap[a.schichtId];
      if (schicht == null) continue;
      DateTime datumTag;
      try {
        final parts = a.datum.split('.');
        if (parts.length != 3) continue;
        datumTag = DateTime(int.parse(parts[2]), int.parse(parts[1]), int.parse(parts[0]));
      } catch (_) {
        continue;
      }
      if (_isZeitInSchicht(n, datumTag, schicht)) {
        return a;
      }
    }
    return null;
  }

}

/// Standort (Wache)
class Standort {
  final String id;
  final String name;
  final int order;

  Standort({required this.id, required this.name, this.order = 0});
}

/// Schicht-Typ aus schichtplanSchichten (mit standortId, Start-/Endzeit)
class SchichtTyp {
  final String id;
  final String name;
  final String? description;
  final String? standortId;
  final String? startTime; // HH:mm
  final String? endTime;   // HH:mm
  final bool endetFolgetag; // true wenn Endzeit <= Startzeit (z.B. 19:00-07:00, 19:00-19:00)
  final int order;
  final bool active;

  SchichtTyp({
    required this.id,
    required this.name,
    this.description,
    this.standortId,
    this.startTime,
    this.endTime,
    this.endetFolgetag = false,
    this.order = 0,
    this.active = true,
  });

  /// Prüft ob Endzeit auf Folgetag liegt (End <= Start, inkl. gleich)
  static bool computeEndetFolgetag(String? start, String? end) {
    if (start == null || end == null || start.isEmpty || end.isEmpty) return false;
    final sp = start.split(':');
    final ep = end.split(':');
    if (sp.length < 2 || ep.length < 2) return false;
    final sm = (int.tryParse(sp[0]) ?? 0) * 60 + (int.tryParse(sp[1]) ?? 0);
    final em = (int.tryParse(ep[0]) ?? 0) * 60 + (int.tryParse(ep[1]) ?? 0);
    return em <= sm;
  }

  factory SchichtTyp.fromFirestore(String id, Map<String, dynamic> data) {
    final startTime = data['startTime']?.toString();
    final endTime = data['endTime']?.toString();
    final endetFolgetag = data['endetFolgetag'] == true || computeEndetFolgetag(startTime, endTime);
    return SchichtTyp(
      id: id,
      name: data['name']?.toString() ?? id,
      description: data['description']?.toString(),
      standortId: data['standortId']?.toString(),
      startTime: startTime,
      endTime: endTime,
      endetFolgetag: endetFolgetag,
      order: (data['order'] as num?)?.toInt() ?? 0,
      active: data['active'] != false,
    );
  }

  Map<String, dynamic> toFirestore() => {
        'name': name,
        if (description != null) 'description': description,
        if (standortId != null) 'standortId': standortId,
        if (startTime != null) 'startTime': startTime,
        if (endTime != null) 'endTime': endTime,
        'endetFolgetag': endetFolgetag,
        'order': order,
        'active': active,
        'updatedAt': FieldValue.serverTimestamp(),
      };
}

/// Fahrzeug-Kurzinfo für Dropdown (mit wache für Standort-Filter)
class FahrzeugKurz {
  final String id;
  final String displayName;
  final String? wache; // Standort-ID oder -Name zur Zuordnung
  final String? kennzeichen;

  const FahrzeugKurz({required this.id, required this.displayName, this.wache, this.kennzeichen});
}

/// Erfasste Schichtanmeldung (vollständiges Formular)
class SchichtanmeldungEintrag {
  final String id;
  final String mitarbeiterId;
  final String wacheId;
  final String schichtId;
  final String fahrzeugId; // "alle" oder Fahrzeug-ID
  final String taetigkeit; // hauptamtlich, nebenamtlich, ...
  final int? bereitschaftszeitMin;
  final String rolle; // fahrer, beifahrer
  final String datum; // DD.MM.YYYY
  final String? bemerkung;
  final DateTime? createdAt;

  SchichtanmeldungEintrag({
    required this.id,
    required this.mitarbeiterId,
    required this.wacheId,
    required this.schichtId,
    required this.fahrzeugId,
    required this.taetigkeit,
    this.bereitschaftszeitMin,
    required this.rolle,
    required this.datum,
    this.bemerkung,
    this.createdAt,
  });

  Map<String, dynamic> toFirestore() => {
        'mitarbeiterId': mitarbeiterId,
        'wacheId': wacheId,
        'schichtId': schichtId,
        'fahrzeugId': fahrzeugId,
        'taetigkeit': taetigkeit,
        if (bereitschaftszeitMin != null) 'bereitschaftszeitMin': bereitschaftszeitMin,
        'rolle': rolle,
        'datum': datum,
        if (bemerkung != null && bemerkung!.isNotEmpty) 'bemerkung': bemerkung,
        'createdAt': FieldValue.serverTimestamp(),
      };

  factory SchichtanmeldungEintrag.fromFirestore(String id, Map<String, dynamic> data) {
    Timestamp? ts = data['createdAt'] as Timestamp?;
    return SchichtanmeldungEintrag(
      id: id,
      mitarbeiterId: data['mitarbeiterId']?.toString() ?? '',
      wacheId: data['wacheId']?.toString() ?? '',
      schichtId: data['schichtId']?.toString() ?? '',
      fahrzeugId: data['fahrzeugId']?.toString() ?? 'alle',
      taetigkeit: data['taetigkeit']?.toString() ?? 'hauptamtlich',
      bereitschaftszeitMin: (data['bereitschaftszeitMin'] as num?)?.toInt(),
      rolle: data['rolle']?.toString() ?? 'fahrer',
      datum: data['datum']?.toString() ?? '',
      bemerkung: data['bemerkung']?.toString(),
      createdAt: ts?.toDate(),
    );
  }
}
