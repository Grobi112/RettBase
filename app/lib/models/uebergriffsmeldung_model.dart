import 'package:cloud_firestore/cloud_firestore.dart';

/// Tatverdächtige Person – persönliche Daten, Auffälligkeiten, Art des Übergriffs
class TatverdaechtigePerson {
  final String? persoenlicheDaten;
  final String? auffaelligkeiten;
  final String? artDesUebergriffs;

  TatverdaechtigePerson({
    this.persoenlicheDaten,
    this.auffaelligkeiten,
    this.artDesUebergriffs,
  });

  Map<String, dynamic> toMap() => {
        'persoenlicheDaten': persoenlicheDaten,
        'auffaelligkeiten': auffaelligkeiten,
        'artDesUebergriffs': artDesUebergriffs,
      };

  factory TatverdaechtigePerson.fromMap(dynamic d) {
    if (d == null || d is! Map) return TatverdaechtigePerson();
    return TatverdaechtigePerson(
      persoenlicheDaten: d['persoenlicheDaten']?.toString(),
      auffaelligkeiten: d['auffaelligkeiten']?.toString(),
      artDesUebergriffs: d['artDesUebergriffs']?.toString(),
    );
  }
}

/// Übergriffsmeldung – Meldung eines Übergriffs oder Sachbeschädigung
/// Firestore: kunden/{companyId}/uebergriffsmeldungen
class Uebergriffsmeldung {
  final String id;

  // EINSATZDATEN
  final bool? einsatzZusammenhang; // true=Ja, false=Nein

  // PERSÖNLICHE DATEN
  final String? melderName; // Nachname, Vorname

  // ORT UND ZEITPUNKT
  final String? ort;
  final String? datumUhrzeit;

  // ARTEN DES ÜBERGRIFFS (mehrfach möglich)
  final String? beleidigungWortlaut;
  final String? bedrohung;
  final String? bedrohungBeschreibung;
  final String? sachbeschaedigung;
  final String? koerperlicheGewalt;
  final String? koerperlicheGewaltBeschreibung;
  final String? sonstiges;

  // WEITERE ANGABEN
  final bool? polizeilichRegistriert;
  final String? zeugenKollegen;
  final String? zeugenAndere;

  // TATVERDÄCHTIGE
  final int anzahlTatverdaechtige;
  final String? tatverdaechtigWahrnehmung;
  final String? auffaelligkeitenAllgemein;
  final List<TatverdaechtigePerson> tatverdaechtigePersonen;

  // ÜBERGRIFF/SACHBESCHÄDIGUNG
  final String? beschreibung;
  final String? weitereHinweise;

  // Unterschrift
  final String? unterschriftUrl;

  final String? createdBy;
  final String? createdByName;
  final DateTime? createdAt;

  Uebergriffsmeldung({
    required this.id,
    this.einsatzZusammenhang,
    this.melderName,
    this.ort,
    this.datumUhrzeit,
    this.beleidigungWortlaut,
    this.bedrohung,
    this.bedrohungBeschreibung,
    this.sachbeschaedigung,
    this.koerperlicheGewalt,
    this.koerperlicheGewaltBeschreibung,
    this.sonstiges,
    this.polizeilichRegistriert,
    this.zeugenKollegen,
    this.zeugenAndere,
    this.anzahlTatverdaechtige = 0,
    this.tatverdaechtigWahrnehmung,
    this.auffaelligkeitenAllgemein,
    this.tatverdaechtigePersonen = const [],
    this.beschreibung,
    this.weitereHinweise,
    this.unterschriftUrl,
    this.createdBy,
    this.createdByName,
    this.createdAt,
  });

  factory Uebergriffsmeldung.fromFirestore(String id, Map<String, dynamic> d) {
    List<TatverdaechtigePerson> personen = [];
    final list = d['tatverdaechtigePersonen'];
    if (list is List) {
      for (final item in list) {
        personen.add(TatverdaechtigePerson.fromMap(item));
      }
    }

    return Uebergriffsmeldung(
      id: id,
      einsatzZusammenhang: d['einsatzZusammenhang'] as bool?,
      melderName: d['melderName']?.toString(),
      ort: d['ort']?.toString(),
      datumUhrzeit: d['datumUhrzeit']?.toString(),
      beleidigungWortlaut: d['beleidigungWortlaut']?.toString(),
      bedrohung: d['bedrohung']?.toString(),
      bedrohungBeschreibung: d['bedrohungBeschreibung']?.toString(),
      sachbeschaedigung: d['sachbeschaedigung']?.toString(),
      koerperlicheGewalt: d['koerperlicheGewalt']?.toString(),
      koerperlicheGewaltBeschreibung: d['koerperlicheGewaltBeschreibung']?.toString(),
      sonstiges: d['sonstiges']?.toString(),
      polizeilichRegistriert: d['polizeilichRegistriert'] as bool?,
      zeugenKollegen: d['zeugenKollegen']?.toString(),
      zeugenAndere: d['zeugenAndere']?.toString(),
      anzahlTatverdaechtige: (d['anzahlTatverdaechtige'] is int)
          ? d['anzahlTatverdaechtige'] as int
          : int.tryParse(d['anzahlTatverdaechtige']?.toString() ?? '0') ?? 0,
      tatverdaechtigWahrnehmung: d['tatverdaechtigWahrnehmung']?.toString(),
      auffaelligkeitenAllgemein: d['auffaelligkeitenAllgemein']?.toString(),
      tatverdaechtigePersonen: personen,
      beschreibung: d['beschreibung']?.toString(),
      weitereHinweise: d['weitereHinweise']?.toString(),
      unterschriftUrl: d['unterschriftUrl']?.toString(),
      createdBy: d['createdBy']?.toString(),
      createdByName: d['createdByName']?.toString(),
      createdAt: (d['createdAt'] is Timestamp)
          ? (d['createdAt'] as Timestamp).toDate()
          : (d['createdAt'] is DateTime)
              ? d['createdAt'] as DateTime
              : null,
    );
  }

  Map<String, dynamic> toFirestore() => {
        'einsatzZusammenhang': einsatzZusammenhang,
        'melderName': melderName,
        'ort': ort,
        'datumUhrzeit': datumUhrzeit,
        'beleidigungWortlaut': beleidigungWortlaut,
        'bedrohung': bedrohung,
        'bedrohungBeschreibung': bedrohungBeschreibung,
        'sachbeschaedigung': sachbeschaedigung,
        'koerperlicheGewalt': koerperlicheGewalt,
        'koerperlicheGewaltBeschreibung': koerperlicheGewaltBeschreibung,
        'sonstiges': sonstiges,
        'polizeilichRegistriert': polizeilichRegistriert,
        'zeugenKollegen': zeugenKollegen,
        'zeugenAndere': zeugenAndere,
        'anzahlTatverdaechtige': anzahlTatverdaechtige,
        'tatverdaechtigWahrnehmung': tatverdaechtigWahrnehmung,
        'auffaelligkeitenAllgemein': auffaelligkeitenAllgemein,
        'tatverdaechtigePersonen': tatverdaechtigePersonen.map((p) => p.toMap()).toList(),
        'beschreibung': beschreibung,
        'weitereHinweise': weitereHinweise,
        'unterschriftUrl': unterschriftUrl,
        'createdBy': createdBy,
        'createdByName': createdByName,
        'createdAt': createdAt != null ? Timestamp.fromDate(createdAt!) : FieldValue.serverTimestamp(),
      };
}
