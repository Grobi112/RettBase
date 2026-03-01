import 'package:cloud_firestore/cloud_firestore.dart';

/// Mangel-Eintrag für Fahrzeugstatus (Übergabeprotokoll)
class FahrzeugstatusMangel {
  final String id;
  final String titel;
  final String? beschreibung;
  final bool? maengelmelderGemeldet;
  final String? createdBy;
  final String? createdByName;
  final DateTime? createdAt;

  FahrzeugstatusMangel({
    required this.id,
    required this.titel,
    this.beschreibung,
    this.maengelmelderGemeldet,
    this.createdBy,
    this.createdByName,
    this.createdAt,
  });

  factory FahrzeugstatusMangel.fromFirestore(String id, Map<String, dynamic> data) {
    Timestamp? ts = data['createdAt'] as Timestamp?;
    return FahrzeugstatusMangel(
      id: id,
      titel: data['titel']?.toString() ?? '',
      beschreibung: data['beschreibung']?.toString(),
      maengelmelderGemeldet: data.containsKey('maengelmelderGemeldet')
          ? (data['maengelmelderGemeldet'] == true)
          : null,
      createdBy: data['createdBy']?.toString(),
      createdByName: data['createdByName']?.toString(),
      createdAt: ts?.toDate(),
    );
  }

  Map<String, dynamic> toFirestore() => {
        'titel': titel,
        if (beschreibung != null && beschreibung!.isNotEmpty) 'beschreibung': beschreibung,
        'maengelmelderGemeldet': maengelmelderGemeldet ?? false,
        if (createdBy != null) 'createdBy': createdBy,
        if (createdByName != null) 'createdByName': createdByName,
        'createdAt': FieldValue.serverTimestamp(),
      };
}

/// Service für das Fahrzeugstatus-Modul (Übergabeprotokoll).
/// Mängel pro Fahrzeug: kunden/{companyId}/fahrzeugstatus/{fahrzeugId}/maengel/{mangelId}
class FahrzeugstatusService {
  final _db = FirebaseFirestore.instance;

  static String _normalize(String s) => s.trim().toLowerCase();

  /// Stream aller Mängel für ein Fahrzeug
  Stream<List<FahrzeugstatusMangel>> streamMaengel(String companyId, String fahrzeugId) {
    final cid = _normalize(companyId);
    final fid = fahrzeugId.trim();
    if (fid.isEmpty || fid == 'alle') {
      return Stream.value([]);
    }
    return _db
        .collection('kunden')
        .doc(cid)
        .collection('fahrzeugstatus')
        .doc(fid)
        .collection('maengel')
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snap) {
          final list = snap.docs
              .map((d) => FahrzeugstatusMangel.fromFirestore(d.id, d.data()))
              .toList();
          list.sort((a, b) {
            final ta = a.createdAt ?? DateTime(0);
            final tb = b.createdAt ?? DateTime(0);
            return tb.compareTo(ta);
          });
          return list;
        });
  }

  /// Neuen Mangel anlegen
  Future<String> createMangel(
    String companyId,
    String fahrzeugId,
    String titel, {
    String? beschreibung,
    bool maengelmelderGemeldet = false,
    String? createdBy,
    String? createdByName,
  }) async {
    final cid = _normalize(companyId);
    final fid = fahrzeugId.trim();
    if (fid.isEmpty || fid == 'alle') {
      throw ArgumentError('Ungültige Fahrzeug-ID');
    }
    final ref = await _db
        .collection('kunden')
        .doc(cid)
        .collection('fahrzeugstatus')
        .doc(fid)
        .collection('maengel')
        .add(FahrzeugstatusMangel(
          id: '',
          titel: titel.trim(),
          beschreibung: beschreibung?.trim().isNotEmpty == true ? beschreibung!.trim() : null,
          maengelmelderGemeldet: maengelmelderGemeldet,
          createdBy: createdBy,
          createdByName: createdByName,
          createdAt: DateTime.now(),
        ).toFirestore());
    return ref.id;
  }

  /// Mangel aktualisieren (Titel, Beschreibung, maengelmelderGemeldet)
  Future<void> updateMangel(
    String companyId,
    String fahrzeugId,
    String mangelId, {
    required String titel,
    String? beschreibung,
    bool maengelmelderGemeldet = false,
  }) async {
    final cid = _normalize(companyId);
    final fid = fahrzeugId.trim();
    if (fid.isEmpty || fid == 'alle' || mangelId.isEmpty) return;
    final updates = <String, dynamic>{
      'titel': titel.trim(),
      'maengelmelderGemeldet': maengelmelderGemeldet,
      'updatedAt': FieldValue.serverTimestamp(),
    };
    if (beschreibung == null || beschreibung.trim().isEmpty) {
      updates['beschreibung'] = FieldValue.delete();
    } else {
      updates['beschreibung'] = beschreibung.trim();
    }
    await _db
        .collection('kunden')
        .doc(cid)
        .collection('fahrzeugstatus')
        .doc(fid)
        .collection('maengel')
        .doc(mangelId)
        .update(updates);
  }

  /// Mangel löschen (wenn behoben)
  Future<void> deleteMangel(String companyId, String fahrzeugId, String mangelId) async {
    final cid = _normalize(companyId);
    final fid = fahrzeugId.trim();
    if (fid.isEmpty || fid == 'alle' || mangelId.isEmpty) return;
    await _db
        .collection('kunden')
        .doc(cid)
        .collection('fahrzeugstatus')
        .doc(fid)
        .collection('maengel')
        .doc(mangelId)
        .delete();
  }
}
