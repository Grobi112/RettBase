import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/fahrtenbuch_vorlage.dart';
import '../models/fahrtenbuch_v2_vorlage.dart';
import '../models/checklisten_vorlage.dart';
import 'fahrtenbuch_service.dart';
import 'fahrtenbuch_v2_service.dart';

/// Modell: Bereitschafts-Typ
class BereitschaftsTyp {
  final String id;
  final String name;
  final String? beschreibung;
  /// Farbe als Int (0xFFRRGGBB), null = Standard-Farbe
  final int? color;

  BereitschaftsTyp({required this.id, required this.name, this.beschreibung, this.color});

  factory BereitschaftsTyp.fromFirestore(String id, Map<String, dynamic> data) {
    int? color;
    final c = data['color'];
    if (c is int) color = c;
    if (c is num) color = c.toInt();
    return BereitschaftsTyp(
      id: id,
      name: data['name']?.toString() ?? id,
      beschreibung: data['beschreibung']?.toString(),
      color: color,
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
/// NFS: erweiterte Felder (Personalnummer, Adresse, Ort, Telefon)
class SchichtplanMitarbeiter {
  final String id;
  final String? vorname;
  final String? nachname;
  final String? email;
  final List<String>? qualifikation;
  final String? personalnummer;
  final String? strasse;
  final String? hausnummer;
  final String? plz;
  final String? ort;
  final String? telefonnummer;
  final String? role;

  SchichtplanMitarbeiter({
    required this.id,
    this.vorname,
    this.nachname,
    this.email,
    this.qualifikation,
    this.personalnummer,
    this.strasse,
    this.hausnummer,
    this.plz,
    this.ort,
    this.telefonnummer,
    this.role,
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
      personalnummer: data['personalnummer']?.toString(),
      strasse: data['strasse']?.toString(),
      hausnummer: data['hausnummer']?.toString(),
      plz: data['plz']?.toString(),
      ort: data['ort']?.toString(),
      telefonnummer: data['telefonnummer']?.toString(),
      role: data['role']?.toString(),
    );
  }
}

/// Schichtanmeldung – Bereitschaften, Standorte, Typen
/// Nutzt schichtplanBereitschaften, schichtplanStandorte, schichtplanBereitschaftsTypen
/// Wichtig: companyId wird stets normalisiert (trim, toLowerCase) – keine Daten anderer Kunden.
class SchichtanmeldungService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  static String _cid(String companyId) => companyId.trim().toLowerCase();

  /// Standorte laden – ausschließlich aus kunden/{companyId}/schichtplanStandorte
  Future<List<Standort>> loadStandorte(String companyId) async {
    try {
      final cid = _cid(companyId);
      final snap = await _db
          .collection('kunden')
          .doc(cid)
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

  /// Bereitschafts-Typen laden – ausschließlich aus kunden/{companyId}/schichtplanBereitschaftsTypen
  Future<List<BereitschaftsTyp>> loadBereitschaftsTypen(String companyId) async {
    try {
      final cid = _cid(companyId);
      final snap = await _db
          .collection('kunden')
          .doc(cid)
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

  /// Bereitschafts-Typ anlegen (schichtplanBereitschaftsTypen)
  Future<String> createBereitschaftsTyp(
    String companyId,
    String name, {
    String? beschreibung,
    int? color,
  }) async {
    final cid = _cid(companyId);
    final ref = await _db
        .collection('kunden')
        .doc(cid)
        .collection('schichtplanBereitschaftsTypen')
        .add({
      'name': name,
      if (beschreibung != null && beschreibung.isNotEmpty) 'beschreibung': beschreibung,
      if (color != null) 'color': color,
      'updatedAt': FieldValue.serverTimestamp(),
    });
    return ref.id;
  }

  /// Bereitschafts-Typ löschen
  Future<void> deleteBereitschaftsTyp(String companyId, String typId) async {
    final cid = _cid(companyId);
    await _db
        .collection('kunden')
        .doc(cid)
        .collection('schichtplanBereitschaftsTypen')
        .doc(typId)
        .delete();
  }

  /// Bereitschafts-Typ aktualisieren
  Future<void> updateBereitschaftsTyp(
    String companyId,
    String typId, {
    String? name,
    String? beschreibung,
    int? color,
  }) async {
    final cid = _cid(companyId);
    final data = <String, dynamic>{'updatedAt': FieldValue.serverTimestamp()};
    if (name != null) data['name'] = name;
    if (beschreibung != null) data['beschreibung'] = beschreibung;
    if (color != null) data['color'] = color;
    await _db
        .collection('kunden')
        .doc(cid)
        .collection('schichtplanBereitschaftsTypen')
        .doc(typId)
        .update(data);
  }

  /// NFS-BereitschaftsTypen nach schichtplanBereitschaftsTypen synchronisieren
  /// Kopiert alle Einträge aus schichtplanNfsBereitschaftsTypen
  Future<int> syncBereitschaftsTypenFromNfs(String companyId) async {
    final cid = _cid(companyId);
    final nfsSnap = await _db
        .collection('kunden')
        .doc(cid)
        .collection('schichtplanNfsBereitschaftsTypen')
        .get();
    if (nfsSnap.docs.isEmpty) return 0;
    final existing = await _db
        .collection('kunden')
        .doc(cid)
        .collection('schichtplanBereitschaftsTypen')
        .get();
    final existingNames = existing.docs
        .map((d) => (d.data()['name'] ?? '').toString().trim().toLowerCase())
        .where((n) => n.isNotEmpty)
        .toSet();
    var count = 0;
    for (final d in nfsSnap.docs) {
      final data = d.data();
      final name = (data['name'] ?? '').toString().trim();
      if (name.isEmpty) continue;
      if (existingNames.contains(name.toLowerCase())) continue;
      await _db
          .collection('kunden')
          .doc(cid)
          .collection('schichtplanBereitschaftsTypen')
          .add({
        'name': name,
        if (data['beschreibung'] != null) 'beschreibung': data['beschreibung'],
        if (data['color'] != null) 'color': data['color'],
        'updatedAt': FieldValue.serverTimestamp(),
      });
      existingNames.add(name.toLowerCase());
      count++;
    }
    return count;
  }

  /// Schichtplan-Mitarbeiter laden (für Zuordnung zum eingeloggten User)
  /// Merge: schichtplanMitarbeiter + mitarbeiter (Mitgliederverwaltung), damit alle Nutzer zugreifen können
  Future<List<SchichtplanMitarbeiter>> loadSchichtplanMitarbeiter(String companyId) async {
    try {
      final cid = _cid(companyId);
      final snap = await _db
          .collection('kunden')
          .doc(cid)
          .collection('schichtplanMitarbeiter')
          .orderBy('nachname')
          .get();
      final list = snap.docs
          .map((d) => SchichtplanMitarbeiter.fromFirestore(d.id, d.data()))
          .toList();
      final existingIds = list.map((m) => m.id).toSet();
      // Fallback: mitarbeiter aus Mitgliederverwaltung ergänzen (nicht in schichtplanMitarbeiter)
      try {
        final mitSnap = await _db
            .collection('kunden')
            .doc(cid)
            .collection('mitarbeiter')
            .get();
        for (final d in mitSnap.docs) {
          final data = d.data();
          if (data['active'] == false) continue;
          if (existingIds.contains(d.id)) continue;
          list.add(_mitarbeiterDocToSchichtplanMitarbeiter(d.id, data));
          existingIds.add(d.id);
        }
        list.sort((a, b) => (a.nachname ?? '').toLowerCase().compareTo((b.nachname ?? '').toLowerCase()));
      } catch (_) {}
      return list;
    } catch (_) {
      return [];
    }
  }

  /// Mitarbeiter-Doc aus mitarbeiter-Collection zu SchichtplanMitarbeiter konvertieren
  SchichtplanMitarbeiter _mitarbeiterDocToSchichtplanMitarbeiter(String id, Map<String, dynamic> data) {
    final q = data['qualifikation'];
    List<String>? qual;
    if (q is List) qual = q.map((e) => e.toString()).toList();
    return SchichtplanMitarbeiter(
      id: id,
      vorname: data['vorname']?.toString(),
      nachname: data['nachname']?.toString(),
      email: (data['email'] ?? data['pseudoEmail'])?.toString(),
      qualifikation: qual,
      personalnummer: data['personalnummer']?.toString(),
      strasse: data['strasse']?.toString(),
      hausnummer: data['hausnummer']?.toString(),
      plz: data['plz']?.toString(),
      ort: data['ort']?.toString(),
      telefonnummer: (data['telefonnummer'] ?? data['telefon'])?.toString(),
      role: data['role']?.toString(),
    );
  }

  /// Aktuellen User einem Schichtplan-Mitarbeiter zuordnen (per E-Mail)
  /// Fallback: Wenn nicht in schichtplanMitarbeiter, Suche in mitarbeiter-Collection
  Future<SchichtplanMitarbeiter?> findMitarbeiterByEmail(
    String companyId,
    String email,
  ) async {
    if (email.isEmpty) return null;
    final normalized = email.trim().toLowerCase();
    for (final m in await loadSchichtplanMitarbeiter(companyId)) {
      if ((m.email ?? '').trim().toLowerCase() == normalized) return m;
    }
    // Fallback: in mitarbeiter-Collection suchen (E-Mail oder Pseudo-E-Mail)
    try {
      final cid = _cid(companyId);
      var snap = await _db
          .collection('kunden')
          .doc(cid)
          .collection('mitarbeiter')
          .where('email', isEqualTo: normalized)
          .limit(1)
          .get();
      if (snap.docs.isEmpty) {
        snap = await _db
            .collection('kunden')
            .doc(cid)
            .collection('mitarbeiter')
            .where('pseudoEmail', isEqualTo: normalized)
            .limit(1)
            .get();
      }
      if (snap.docs.isNotEmpty) {
        final d = snap.docs.first;
        return _mitarbeiterDocToSchichtplanMitarbeiter(d.id, d.data());
      }
    } catch (_) {}
    return null;
  }

  /// Aktuellen User per Name in Schichtplan-Mitarbeiter finden (Fallback bei Übereinstimmung)
  /// Nutzt loadSchichtplanMitarbeiter (enthält bereits mitarbeiter-Merge)
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
  /// Fallback: Wenn nicht in schichtplanMitarbeiter, Mitarbeiter-Doc direkt als SchichtplanMitarbeiter verwenden
  Future<SchichtplanMitarbeiter?> findMitarbeiterByUid(
    String companyId,
    String uid,
  ) async {
    try {
      final normalizedId = companyId.trim().toLowerCase();
      var docs = await _db
          .collection('kunden')
          .doc(normalizedId)
          .collection('mitarbeiter')
          .where('uid', isEqualTo: uid)
          .limit(1)
          .get()
          .then((s) => s.docs);
      if (docs.isEmpty) {
        final docById = await _db.doc('kunden/$normalizedId/mitarbeiter/$uid').get();
        if (docById.exists && docById.data() != null) {
          final data = docById.data()!;
          final mitarbeiterDocId = docById.id;
          var m = await getSchichtplanMitarbeiterById(companyId, mitarbeiterDocId);
          if (m != null) return m;
          final email = data['email']?.toString() ?? data['pseudoEmail']?.toString() ?? '';
          final vorname = data['vorname']?.toString() ?? '';
          final nachname = data['nachname']?.toString() ?? '';
          m = await findMitarbeiterByEmail(companyId, email);
          if (m == null) m = await findMitarbeiterByName(companyId, vorname, nachname);
          if (m != null) return m;
          return _mitarbeiterDocToSchichtplanMitarbeiter(mitarbeiterDocId, data);
        }
      }
      if (docs.isEmpty && normalizedId != companyId.trim()) {
        docs = await _db
            .collection('kunden')
            .doc(companyId.trim())
            .collection('mitarbeiter')
            .where('uid', isEqualTo: uid)
            .limit(1)
            .get()
            .then((s) => s.docs);
      }
      if (docs.isEmpty) return null;
      final doc = docs.first;
      final data = doc.data();
      final mitarbeiterDocId = doc.id;
      var m = await getSchichtplanMitarbeiterById(companyId, mitarbeiterDocId);
      if (m != null) return m;
      final email = data['email']?.toString() ?? data['pseudoEmail']?.toString() ?? '';
      final vorname = data['vorname']?.toString() ?? '';
      final nachname = data['nachname']?.toString() ?? '';
      m = await findMitarbeiterByEmail(companyId, email);
      if (m == null) m = await findMitarbeiterByName(companyId, vorname, nachname);
      if (m != null) return m;
      // Fallback: Mitarbeiter aus mitarbeiter-Collection direkt verwenden (ohne schichtplanMitarbeiter-Eintrag)
      return _mitarbeiterDocToSchichtplanMitarbeiter(mitarbeiterDocId, data);
    } catch (_) {
      return null;
    }
  }

  /// Schichtplan-Mitarbeiter direkt per Dokument-ID laden (Verknüpfung wenn gleiche ID wie mitarbeiter-Collection)
  /// Fallback: Wenn nicht in schichtplanMitarbeiter, in mitarbeiter-Collection suchen
  Future<SchichtplanMitarbeiter?> getSchichtplanMitarbeiterById(String companyId, String id) async {
    if (id.isEmpty) return null;
    try {
      final normalizedId = companyId.trim().toLowerCase();
      var snap = await _db
          .collection('kunden')
          .doc(normalizedId)
          .collection('schichtplanMitarbeiter')
          .doc(id)
          .get();
      if (snap.exists && snap.data() != null) {
        return SchichtplanMitarbeiter.fromFirestore(snap.id, snap.data()!);
      }
      // Fallback: in mitarbeiter-Collection
      snap = await _db
          .collection('kunden')
          .doc(normalizedId)
          .collection('mitarbeiter')
          .doc(id)
          .get();
      if (snap.exists && snap.data() != null) {
        final data = snap.data()!;
        if (data['active'] == false) return null;
        return _mitarbeiterDocToSchichtplanMitarbeiter(snap.id, data);
      }
    } catch (_) {}
    return null;
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

  /// Schichten laden – ausschließlich aus kunden/{companyId}/schichtplanSchichten
  Future<List<SchichtTyp>> loadSchichten(String companyId) async {
    try {
      final cid = _cid(companyId);
      final snap = await _db
          .collection('kunden')
          .doc(cid)
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
      return [];
    }
  }

  /// Fahrzeuge laden (für Dropdown, inkl. "Alle")
  Future<List<FahrzeugKurz>> loadFahrzeuge(String companyId) async {
    try {
      final cid = _cid(companyId);
      final snap = await _db.collection('kunden').doc(cid).collection('fahrzeuge').get();
      final list = <FahrzeugKurz>[
        const FahrzeugKurz(id: 'alle', displayName: 'Alle'),
      ];
      final items = <FahrzeugKurz>[];
      for (final d in snap.docs) {
        final data = d.data();
        if (data['aktiv'] == false) continue;
        final ruf = data['rufname']?.toString() ?? data['name']?.toString() ?? '';
        final wache = data['wache']?.toString();
        final kz = (data['kennzeichen'] ?? data['Kennzeichen'] ?? data['nummernschild'])?.toString().trim();
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
    final cid = _cid(companyId);
    final data = s.toFirestore();
    data['createdAt'] = FieldValue.serverTimestamp();
    final ref = await _db
        .collection('kunden')
        .doc(cid)
        .collection('schichtplanSchichten')
        .add(data);
    return ref.id;
  }

  /// Schicht-Typ aktualisieren
  Future<void> updateSchicht(String companyId, String schichtId, SchichtTyp s) async {
    final cid = _cid(companyId);
    await _db
        .collection('kunden')
        .doc(cid)
        .collection('schichtplanSchichten')
        .doc(schichtId)
        .update(s.toFirestore());
  }

  /// Schicht-Typ löschen (soft: active=false) oder hart löschen
  Future<void> deleteSchicht(String companyId, String schichtId, {bool hard = false}) async {
    final cid = _cid(companyId);
    if (hard) {
      await _db
          .collection('kunden')
          .doc(cid)
          .collection('schichtplanSchichten')
          .doc(schichtId)
          .delete();
    } else {
      await _db
          .collection('kunden')
          .doc(cid)
          .collection('schichtplanSchichten')
          .doc(schichtId)
          .update({'active': false, 'updatedAt': FieldValue.serverTimestamp()});
    }
  }

  /// Standort erstellen
  Future<String> createStandort(String companyId, String name, {int order = 0}) async {
    final cid = _cid(companyId);
    final ref = await _db
        .collection('kunden')
        .doc(cid)
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
    final cid = _cid(companyId);
    final data = <String, dynamic>{'name': name, 'updatedAt': FieldValue.serverTimestamp()};
    if (order != null) data['order'] = order;
    await _db
        .collection('kunden')
        .doc(cid)
        .collection('schichtplanStandorte')
        .doc(standortId)
        .update(data);
  }

  /// Standort löschen
  Future<void> deleteStandort(String companyId, String standortId) async {
    final cid = _cid(companyId);
    await _db
        .collection('kunden')
        .doc(cid)
        .collection('schichtplanStandorte')
        .doc(standortId)
        .delete();
  }

  /// Schichtanmeldung löschen
  Future<void> deleteSchichtanmeldung(String companyId, String anmeldungId) async {
    final cid = _cid(companyId);
    await _db
        .collection('kunden')
        .doc(cid)
        .collection('schichtanmeldungen')
        .doc(anmeldungId)
        .delete();
  }

  /// Schichtanmeldung erfassen (vollständiges Formular)
  Future<void> saveSchichtanmeldung(
    String companyId,
    SchichtanmeldungEintrag e,
  ) async {
    final cid = _cid(companyId);
    await _db
        .collection('kunden')
        .doc(cid)
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
    final cid = _cid(companyId);
    final results = <SchichtanmeldungEintrag>[];
    for (var i = 0; i < dayIds.length; i += 30) {
      final batch = dayIds.skip(i).take(30).toList();
      try {
        final snap = await _db
            .collection('kunden')
            .doc(cid)
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
      final cid = _cid(companyId);
      final snap = await _db
          .collection('kunden')
          .doc(cid)
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

  /// FahrtenbuchV2Vorlage aus Schichtanmeldung (für Vorausfüllung bei aktivem Schicht-Einstieg)
  Future<FahrtenbuchV2Vorlage?> buildFahrtenbuchV2VorlageFromAnmeldung(
    String companyId,
    SchichtanmeldungEintrag e,
    FahrtenbuchService fahrtenbuchService,
    FahrtenbuchV2Service fahrtenbuchV2Service,
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
    // Fahrer + Beifahrer für Dropdown (beide auf Schicht angemeldet)
    final fahrerNamen = fahrer.map((a) => mitarbeiterName(a.mitarbeiterId)).where((n) => n != '–' && n.isNotEmpty).toSet().toList();
    final beifahrerNamen = beifahrer.map((a) => mitarbeiterName(a.mitarbeiterId)).where((n) => n != '–' && n.isNotEmpty).toSet().toList();
    for (final n in beifahrerNamen) {
      if (!fahrerNamen.contains(n)) fahrerNamen.add(n);
    }

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
      kmAnfang = await fahrtenbuchV2Service.getLetzterKmEnde(companyId, rufname.isNotEmpty ? rufname : kennzeichen);
    }

    return FahrtenbuchV2Vorlage(
      fahrzeugId: fahrzeugId,
      fahrzeugRufname: rufname,
      kennzeichen: kennzeichen,
      nameFahrer: nameFahrer,
      kmAnfang: kmAnfang,
      datum: datumTag,
      fahrerOptionen: fahrerNamen,
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
  final String? typId; // BereitschaftsTyp-ID (schichtplanBereitschaftsTypen)
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
    this.typId,
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
      typId: data['typId']?.toString(),
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
        if (typId != null && typId!.isNotEmpty) 'typId': typId,
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
