import 'package:cloud_firestore/cloud_firestore.dart';

/// Fahrtenbuch-Eintrag – digitales Fahrtenbuch
/// Firestore: kunden/{companyId}/fahrtenbuchEintraege
class FahrtenbuchEintrag {
  final String id;
  final String? fahrzeugkennung;
  final String? kennzeichen;
  final String? nameFahrer;
  final String? nameBeifahrer;
  final String? praktikantAzubi;
  final DateTime? datum;
  final String? alarm; // HH:mm
  final String? ende; // HH:mm
  final String? einsatzart;
  final bool transportschein;
  final String? einsatzort;
  final String? transportziel;
  final String? einsatznummer;
  final int? kmAnfang;
  final int? kmEnde;
  final int? gesamtKm;
  final int? besetztKm;
  final String? sonderrechteAnfahrtTransport;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final String? createdBy;
  /// true = manuelle KM-Korrektur aus Checkliste (kein realer Fahrt-Eintrag)
  final bool manuellKmKorrektur;

  FahrtenbuchEintrag({
    required this.id,
    this.fahrzeugkennung,
    this.kennzeichen,
    this.nameFahrer,
    this.nameBeifahrer,
    this.praktikantAzubi,
    this.datum,
    this.alarm,
    this.ende,
    this.einsatzart,
    this.transportschein = false,
    this.einsatzort,
    this.transportziel,
    this.einsatznummer,
    this.kmAnfang,
    this.kmEnde,
    this.gesamtKm,
    this.besetztKm,
    this.sonderrechteAnfahrtTransport,
    this.createdAt,
    this.updatedAt,
    this.createdBy,
    this.manuellKmKorrektur = false,
  });

  factory FahrtenbuchEintrag.fromFirestore(String id, Map<String, dynamic> d) {
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

    int? kmAnfang;
    final kmA = d['kmAnfang'];
    if (kmA != null) kmAnfang = (kmA is num) ? kmA.toInt() : int.tryParse(kmA.toString());

    int? kmEnde;
    final kmE = d['kmEnde'];
    if (kmE != null) kmEnde = (kmE is num) ? kmE.toInt() : int.tryParse(kmE.toString());

    int? gesamtKm;
    final gkm = d['gesamtKm'];
    if (gkm != null) gesamtKm = (gkm is num) ? gkm.toInt() : int.tryParse(gkm.toString());

    int? besetztKm;
    final bkm = d['besetztKm'];
    if (bkm != null) besetztKm = (bkm is num) ? bkm.toInt() : int.tryParse(bkm.toString());

    return FahrtenbuchEintrag(
      id: id,
      fahrzeugkennung: d['fahrzeugkennung']?.toString(),
      kennzeichen: d['kennzeichen']?.toString(),
      nameFahrer: d['nameFahrer']?.toString(),
      nameBeifahrer: d['nameBeifahrer']?.toString(),
      praktikantAzubi: d['praktikantAzubi']?.toString(),
      datum: datum,
      alarm: d['alarm']?.toString(),
      ende: d['ende']?.toString(),
      einsatzart: d['einsatzart']?.toString(),
      transportschein: d['transportschein'] == true,
      einsatzort: d['einsatzort']?.toString(),
      transportziel: d['transportziel']?.toString(),
      einsatznummer: d['einsatznummer']?.toString(),
      kmAnfang: kmAnfang,
      kmEnde: kmEnde,
      gesamtKm: gesamtKm,
      besetztKm: besetztKm,
      sonderrechteAnfahrtTransport: d['sonderrechteAnfahrtTransport']?.toString(),
      createdAt: createdAt,
      updatedAt: updatedAt,
      createdBy: d['createdBy']?.toString(),
      manuellKmKorrektur: d['manuellKmKorrektur'] == true,
    );
  }

  Map<String, dynamic> toFirestore() {
    final map = <String, dynamic>{
      'fahrzeugkennung': fahrzeugkennung,
      'kennzeichen': kennzeichen,
      'nameFahrer': nameFahrer,
      'nameBeifahrer': nameBeifahrer,
      'praktikantAzubi': praktikantAzubi,
      'datum': datum != null ? Timestamp.fromDate(datum!) : null,
      'alarm': alarm,
      'ende': ende,
      'einsatzart': einsatzart,
      'transportschein': transportschein,
      'einsatzort': einsatzort,
      'transportziel': transportziel,
      'einsatznummer': einsatznummer,
      'kmAnfang': kmAnfang,
      'kmEnde': kmEnde,
      'gesamtKm': gesamtKm,
      'besetztKm': besetztKm,
      'sonderrechteAnfahrtTransport': sonderrechteAnfahrtTransport,
      'updatedAt': FieldValue.serverTimestamp(),
      'createdBy': createdBy,
      if (manuellKmKorrektur) 'manuellKmKorrektur': true,
    };
    map.removeWhere((_, v) => v == null);
    return map;
  }
}
