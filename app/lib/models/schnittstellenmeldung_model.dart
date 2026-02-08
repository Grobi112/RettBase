import 'package:cloud_firestore/cloud_firestore.dart';

/// Schnittstellenmeldung – Meldung eines Schnittstellen-Vorkommnisses
/// Firestore: kunden/{companyId}/schnittstellenmeldungen/{docId}
class Schnittstellenmeldung {
  final String id;
  final DateTime? datum;
  final String? uhrzeit; // z.B. "14:30"
  final String? einsatznummer;
  final String? leitstelle;
  final String? fbNummer;
  final String? schnPersonal;
  final String? rtwMzf;
  final String? nef;
  final String? besatzung;
  final String? arzt;
  final String vorkommnis;
  final String? companyId;
  final String? createdBy;
  final String? createdByName;
  final DateTime? createdAt;

  Schnittstellenmeldung({
    required this.id,
    this.datum,
    this.uhrzeit,
    this.einsatznummer,
    this.leitstelle,
    this.fbNummer,
    this.schnPersonal,
    this.rtwMzf,
    this.nef,
    this.besatzung,
    this.arzt,
    required this.vorkommnis,
    this.companyId,
    this.createdBy,
    this.createdByName,
    this.createdAt,
  });

  factory Schnittstellenmeldung.fromFirestore(String id, Map<String, dynamic> d) {
    DateTime? datum;
    final dv = d['datum'] ?? d['date'];
    if (dv is Timestamp) datum = dv.toDate();
    else if (dv is DateTime) datum = dv;
    else if (dv is String) datum = DateTime.tryParse(dv);

    DateTime? createdAt;
    final cv = d['createdAt'] ?? d['created'];
    if (cv is Timestamp) createdAt = cv.toDate();
    else if (cv is DateTime) createdAt = cv;
    else if (cv is String) createdAt = DateTime.tryParse(cv);

    return Schnittstellenmeldung(
      id: id,
      datum: datum,
      uhrzeit: d['uhrzeit']?.toString() ?? d['time']?.toString(),
      einsatznummer: d['einsatznummer']?.toString(),
      leitstelle: d['leitstelle']?.toString(),
      fbNummer: d['fbNummer']?.toString() ?? d['fb_nummer']?.toString(),
      schnPersonal: d['schnPersonal']?.toString() ?? d['schn_personal']?.toString(),
      rtwMzf: d['rtwMzf']?.toString() ?? d['rtw_mzf']?.toString(),
      nef: d['nef']?.toString(),
      besatzung: d['besatzung']?.toString(),
      arzt: d['arzt']?.toString(),
      vorkommnis: d['vorkommnis']?.toString() ?? d['beschreibung']?.toString() ?? '',
      companyId: d['companyId']?.toString(),
      createdBy: d['createdBy']?.toString(),
      createdByName: d['createdByName']?.toString(),
      createdAt: createdAt,
    );
  }

  Map<String, dynamic> toFirestore() => {
        'datum': datum != null ? Timestamp.fromDate(datum!) : null,
        'uhrzeit': uhrzeit,
        'einsatznummer': einsatznummer,
        'leitstelle': leitstelle,
        'fbNummer': fbNummer,
        'schnPersonal': schnPersonal,
        'rtwMzf': rtwMzf,
        'nef': nef,
        'besatzung': besatzung,
        'arzt': arzt,
        'vorkommnis': vorkommnis,
        'companyId': companyId,
        'createdBy': createdBy,
        'createdByName': createdByName,
        'createdAt': createdAt != null ? Timestamp.fromDate(createdAt!) : FieldValue.serverTimestamp(),
      };
}
