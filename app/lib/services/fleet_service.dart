import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import '../models/fleet_model.dart';

/// Flottenmanagement – Fahrzeuge, Beauftragte, Termine
/// Firestore: kunden/{companyId}/fahrzeuge
class FleetService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirebaseStorage _storage = FirebaseStorage.instance;

  CollectionReference<Map<String, dynamic>> _fahrzeuge(String companyId) =>
      _db.collection('kunden').doc(companyId).collection('fahrzeuge');

  CollectionReference<Map<String, dynamic>> _termine(String companyId) =>
      _db.collection('kunden').doc(companyId).collection('fahrzeugTermine');

  CollectionReference<Map<String, dynamic>> _maengel(String companyId, [String col = 'fahrzeugMaengel']) =>
      _db.collection('kunden').doc(companyId).collection(col);

  /// Alle Fahrzeuge streamen
  Stream<List<Fahrzeug>> streamFahrzeuge(String companyId) {
    return _fahrzeuge(companyId)
        .orderBy('rufname')
        .snapshots()
        .map((s) => s.docs.map((d) => Fahrzeug.fromFirestore(d.id, d.data())).toList());
  }

  /// Fahrzeug laden
  Future<Fahrzeug?> getFahrzeug(String companyId, String fahrzeugId) async {
    final doc = await _fahrzeuge(companyId).doc(fahrzeugId).get();
    if (!doc.exists || doc.data() == null) return null;
    return Fahrzeug.fromFirestore(doc.id, doc.data()!);
  }

  /// Fahrzeug erstellen
  Future<void> createFahrzeug(String companyId, Fahrzeug f) async {
    final data = f.toFirestore();
    data['createdAt'] = FieldValue.serverTimestamp();
    await _fahrzeuge(companyId).add(data);
  }

  /// Fahrzeug aktualisieren
  Future<void> updateFahrzeug(String companyId, Fahrzeug f) async {
    final data = f.toFirestore();
    await _fahrzeuge(companyId).doc(f.id).update(data);
  }

  /// Fahrzeug löschen
  Future<void> deleteFahrzeug(String companyId, String fahrzeugId) async {
    await _fahrzeuge(companyId).doc(fahrzeugId).delete();
  }

  /// Mitarbeiter für Fahrzeugbeauftragte laden (aktive Mitarbeiter)
  Future<List<Fahrzeugbeauftragter>> loadMitarbeiter(String companyId) async {
    final snap = await _db
        .collection('kunden')
        .doc(companyId)
        .collection('mitarbeiter')
        .where('active', isNotEqualTo: false)
        .get();

    final list = <Fahrzeugbeauftragter>[];
    for (final d in snap.docs) {
      final data = d.data();
      if (data['active'] == false) continue;
      final uid = data['uid']?.toString() ?? d.id;
      final vorname = data['vorname']?.toString() ?? '';
      final nachname = data['nachname']?.toString() ?? '';
      final name = [vorname, nachname].where((e) => e.isNotEmpty).join(' ').trim();
      list.add(Fahrzeugbeauftragter(uid: uid, name: name.isNotEmpty ? name : (data['name']?.toString() ?? uid)));
    }
    list.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return list;
  }

  /// Termine streamen (alle oder nach Fahrzeug)
  Stream<List<FahrzeugTermin>> streamTermine(String companyId, {String? fahrzeugId}) {
    var q = _termine(companyId).orderBy('datum', descending: false);
    if (fahrzeugId != null && fahrzeugId.isNotEmpty) {
      q = _termine(companyId).where('fahrzeugId', isEqualTo: fahrzeugId).orderBy('datum', descending: false);
    }
    return q.snapshots().map((s) {
      return s.docs.map((d) => FahrzeugTermin.fromFirestore(d.id, d.data())).toList();
    });
  }

  /// Termin erstellen
  Future<void> createTermin(String companyId, FahrzeugTermin t) async {
    await _termine(companyId).add(t.toFirestore());
  }

  /// Termin löschen
  Future<void> deleteTermin(String companyId, String terminId) async {
    await _termine(companyId).doc(terminId).delete();
  }

  /// Mängel streamen (neueste zuerst)
  /// Nutzt Collection "maengel" – gleicher Name wie in der Webseite (kunden/{id}/maengel)
  Stream<List<FahrzeugMangel>> streamMaengel(String companyId) {
    return _maengel(companyId, 'maengel')
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((s) => s.docs.map((d) => FahrzeugMangel.fromFirestore(d.id, d.data())).toList());
  }

  /// Mangel erstellen (für Mängelmelder). Gibt die neue Dokument-ID zurück.
  Future<String> createMangel(String companyId, FahrzeugMangel m) async {
    final data = m.toFirestore();
    data['createdAt'] = FieldValue.serverTimestamp();
    final ref = await _maengel(companyId, 'maengel').add(data);
    return ref.id;
  }

  /// Mangel-Bilder in Firebase Storage hochladen (wie Chat/E-Mail)
  /// Pfad: kunden/{companyId}/maengel-attachments/{mangelId}/{ts}_{i}_{name}
  Future<List<String>> uploadMangelBilder(String companyId, String mangelId, List<Uint8List> imageBytes, List<String> imageNames) async {
    if (imageBytes.isEmpty) return [];
    final urls = <String>[];
    final ts = DateTime.now().millisecondsSinceEpoch;
    for (var i = 0; i < imageBytes.length; i++) {
      final name = (i < imageNames.length ? imageNames[i] : 'image_$i.jpg')
          .replaceAll(RegExp(r'[^a-zA-Z0-9.-]'), '_');
      final path = 'kunden/$companyId/maengel-attachments/$mangelId/${ts}_${i}_$name';
      final ref = _storage.ref(path);
      await ref.putData(imageBytes[i], SettableMetadata(contentType: 'image/jpeg'));
      final url = await ref.getDownloadURL();
      urls.add(url);
    }
    return urls;
  }

  /// Mangel aktualisieren (Status, Priorität, Bilder, etc.)
  Future<void> updateMangel(String companyId, FahrzeugMangel m) async {
    final data = <String, dynamic>{
      if (m.mangelTyp != null) 'mangelTyp': m.mangelTyp,
      'fahrzeugId': m.fahrzeugId,
      'fahrzeugRufname': m.fahrzeugRufname,
      'kennzeichen': m.kennzeichen,
      'betreff': m.betreff,
      'beschreibung': m.beschreibung,
      'kategorie': m.kategorie,
      'melderName': m.melderName,
      'melderUid': m.melderUid,
      'status': m.status,
      'prioritaet': m.prioritaet,
      'datum': m.datum != null ? Timestamp.fromDate(m.datum!) : null,
      'kilometerstand': m.kilometerstand,
      'bilder': m.bilder,
      'updatedAt': FieldValue.serverTimestamp(),
    };
    await _maengel(companyId, 'maengel').doc(m.id).update(data);
  }

  /// Mangel löschen
  Future<void> deleteMangel(String companyId, String mangelId) async {
    await _maengel(companyId, 'maengel').doc(mangelId).delete();
  }

  /// Mangel-Status aktualisieren
  Future<void> updateMangelStatus(String companyId, String mangelId, String status) async {
    await _maengel(companyId, 'maengel').doc(mangelId).update({
      'status': status,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  /// Einstellungen laden
  Future<FleetSettings> loadSettings(String companyId) async {
    final doc = await _db.collection('kunden').doc(companyId).collection('settings').doc('fleetManagement').get();
    if (!doc.exists || doc.data() == null) return FleetSettings();
    return FleetSettings.fromFirestore(doc.data());
  }

  /// Einstellungen speichern
  Future<void> saveSettings(String companyId, FleetSettings s) async {
    await _db.collection('kunden').doc(companyId).collection('settings').doc('fleetManagement').set(s.toFirestore());
  }

  /// Standorte aus Schichtplan laden (für Wache-Dropdown)
  Future<List<Standort>> loadStandorte(String companyId) async {
    try {
      final snap = await _db.collection('kunden').doc(companyId).collection('schichtplanStandorte').get();
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
}

/// Standort aus Schichtplan (Wache)
class Standort {
  final String id;
  final String name;
  final int order;

  Standort({required this.id, required this.name, this.order = 0});
}
