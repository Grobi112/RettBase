import 'package:cloud_firestore/cloud_firestore.dart';

/// Fahrtenbuch V2 – Eintrag mit erweiterten Feldern
/// Firestore: kunden/{companyId}/fahrtenbuchEintraegeV2
class FahrtenbuchV2Eintrag {
  final String id;
  final DateTime? datum;
  final String? fahrzeitVon;
  final String? fahrzeitBis;
  final String? fahrtVon;
  final String? ziel;
  final String? grundDerFahrt;
  final int? kmAnfang;
  final int? kmEnde;
  final int? kmDienstlich;
  final int? kmWohnortArbeit;
  final int? kmPrivat;
  final String? nameFahrer;
  final num? kostenBetrag;
  final String? kostenArt;
  final String? fahrzeugkennung;
  final String? kennzeichen;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final String? createdBy;

  FahrtenbuchV2Eintrag({
    required this.id,
    this.datum,
    this.fahrzeitVon,
    this.fahrzeitBis,
    this.fahrtVon,
    this.ziel,
    this.grundDerFahrt,
    this.kmAnfang,
    this.kmEnde,
    this.kmDienstlich,
    this.kmWohnortArbeit,
    this.kmPrivat,
    this.nameFahrer,
    this.kostenBetrag,
    this.kostenArt,
    this.fahrzeugkennung,
    this.kennzeichen,
    this.createdAt,
    this.updatedAt,
    this.createdBy,
  });

  factory FahrtenbuchV2Eintrag.fromFirestore(String id, Map<String, dynamic> d) {
    DateTime? datum;
    final dVal = d['datum'];
    if (dVal is Timestamp) datum = dVal.toDate();
    if (dVal is DateTime) datum = dVal;

    DateTime? createdAt;
    final ca = d['createdAt'];
    if (ca is Timestamp) createdAt = ca.toDate();
    if (ca is DateTime) createdAt = ca;

    DateTime? updatedAt;
    final ua = d['updatedAt'];
    if (ua is Timestamp) updatedAt = ua.toDate();
    if (ua is DateTime) updatedAt = ua;

    int? parseInt(dynamic v) {
      if (v == null) return null;
      return (v is num) ? v.toInt() : int.tryParse(v.toString());
    }

    num? kostenBetrag;
    final kb = d['kostenBetrag'];
    if (kb != null) kostenBetrag = (kb is num) ? kb : num.tryParse(kb.toString());

    return FahrtenbuchV2Eintrag(
      id: id,
      datum: datum,
      fahrzeitVon: d['fahrzeitVon']?.toString(),
      fahrzeitBis: d['fahrzeitBis']?.toString(),
      fahrtVon: d['fahrtVon']?.toString(),
      ziel: d['ziel']?.toString(),
      grundDerFahrt: d['grundDerFahrt']?.toString(),
      kmAnfang: parseInt(d['kmAnfang']),
      kmEnde: parseInt(d['kmEnde']),
      kmDienstlich: parseInt(d['kmDienstlich']),
      kmWohnortArbeit: parseInt(d['kmWohnortArbeit']),
      kmPrivat: parseInt(d['kmPrivat']),
      nameFahrer: d['nameFahrer']?.toString(),
      kostenBetrag: kostenBetrag,
      kostenArt: d['kostenArt']?.toString(),
      fahrzeugkennung: d['fahrzeugkennung']?.toString(),
      kennzeichen: d['kennzeichen']?.toString(),
      createdAt: createdAt,
      updatedAt: updatedAt,
      createdBy: d['createdBy']?.toString(),
    );
  }

  Map<String, dynamic> toFirestore() {
    final map = <String, dynamic>{
      'datum': datum != null ? Timestamp.fromDate(datum!) : null,
      'fahrzeitVon': fahrzeitVon,
      'fahrzeitBis': fahrzeitBis,
      'fahrtVon': fahrtVon,
      'ziel': ziel,
      'grundDerFahrt': grundDerFahrt,
      'kmAnfang': kmAnfang,
      'kmEnde': kmEnde,
      'kmDienstlich': kmDienstlich,
      'kmWohnortArbeit': kmWohnortArbeit,
      'kmPrivat': kmPrivat,
      'nameFahrer': nameFahrer,
      'kostenBetrag': kostenBetrag,
      'kostenArt': kostenArt,
      'fahrzeugkennung': fahrzeugkennung,
      'kennzeichen': kennzeichen,
      'updatedAt': FieldValue.serverTimestamp(),
      'createdBy': createdBy,
    };
    map.removeWhere((_, v) => v == null);
    return map;
  }
}
