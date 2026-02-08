import 'package:cloud_firestore/cloud_firestore.dart';

/// Unfallbericht – Erfassung von Unfällen mit eigenem und gegnerischem Fahrzeug
/// Firestore: kunden/{companyId}/unfallberichte
class Unfallbericht {
  final String id;
  final String? createdBy;

  // Eigenes Fahrzeug
  final DateTime? schadentag;
  final String? schadenuhrzeit;
  final String? schadenort;
  final bool polizeiAmUnfallort;
  final String? dienststelleTagebuchnummer;
  final int? kilometerstand;
  final String? fahrzeugId;
  final String? fahrzeugDisplay;
  final String? anhangerKennzeichen;
  final String? schadenhoehe;
  final String? schadenEigenesFahrzeug; // max 315 Zeichen

  // Fahrer eigenes Fahrzeug
  final String? mitarbeiterId;
  final String? vornameFahrer;
  final String? nachnameFahrer;
  final String? telefonFahrer;
  final String? strasseFahrer;
  final String? plzFahrer;
  final String? ortFahrer;
  final String? fuehrerscheinklasse;
  final DateTime? ausstellungsdatum;
  final String? behoerde;
  final bool alkoholgenuss;
  final bool blutprobeEntnommen;
  final String? blutprobeErgebnis;

  // Gegnerisches Fahrzeug
  final String? kennzeichenGegner;
  final String? versicherungsscheinNr;
  final String? geschaetzteSchadenhoeheGegner;
  final String? schadenGegner; // max 315 Zeichen

  // Fahrer gegnerisches Fahrzeug
  final String? vornameGegner;
  final String? nachnameGegner;
  final String? telefonGegner;
  final String? strasseGegner;
  final String? plzGegner;
  final String? ortGegner;
  final String? kurzeSchadenschilderung; // max 420 Zeichen

  // Fahrzeughalter
  final String? vornameFahrzeughalter;
  final String? nachnameFahrzeughalter;
  final String? strasseFahrzeughalter;
  final String? plzFahrzeughalter;
  final String? ortFahrzeughalter;

  // Anhänge
  final List<String> bilderDokumente; // Download-URLs, max 10, je 32 MB

  // Abschließend
  final String? kurzeBemerkung; // max 260 Zeichen
  final String? unterschriftUrl; // Download-URL der Unterschrift
  final String? ausfuehrlicherSchadensbericht; // optional, detailliert

  final DateTime? createdAt;
  final DateTime? updatedAt;

  Unfallbericht({
    required this.id,
    this.createdBy,
    this.schadentag,
    this.schadenuhrzeit,
    this.schadenort,
    this.polizeiAmUnfallort = false,
    this.dienststelleTagebuchnummer,
    this.kilometerstand,
    this.fahrzeugId,
    this.fahrzeugDisplay,
    this.anhangerKennzeichen,
    this.schadenhoehe,
    this.schadenEigenesFahrzeug,
    this.mitarbeiterId,
    this.vornameFahrer,
    this.nachnameFahrer,
    this.telefonFahrer,
    this.strasseFahrer,
    this.plzFahrer,
    this.ortFahrer,
    this.fuehrerscheinklasse,
    this.ausstellungsdatum,
    this.behoerde,
    this.alkoholgenuss = false,
    this.blutprobeEntnommen = false,
    this.blutprobeErgebnis,
    this.kennzeichenGegner,
    this.versicherungsscheinNr,
    this.geschaetzteSchadenhoeheGegner,
    this.schadenGegner,
    this.vornameGegner,
    this.nachnameGegner,
    this.telefonGegner,
    this.strasseGegner,
    this.plzGegner,
    this.ortGegner,
    this.kurzeSchadenschilderung,
    this.vornameFahrzeughalter,
    this.nachnameFahrzeughalter,
    this.strasseFahrzeughalter,
    this.plzFahrzeughalter,
    this.ortFahrzeughalter,
    this.bilderDokumente = const [],
    this.kurzeBemerkung,
    this.unterschriftUrl,
    this.ausfuehrlicherSchadensbericht,
    this.createdAt,
    this.updatedAt,
  });

  factory Unfallbericht.fromFirestore(String id, Map<String, dynamic> d) {
    DateTime? _date(dynamic v) {
      if (v is Timestamp) return v.toDate();
      if (v is DateTime) return v;
      return null;
    }

    return Unfallbericht(
      id: id,
      createdBy: d['createdBy']?.toString(),
      schadentag: _date(d['schadentag']),
      schadenuhrzeit: d['schadenuhrzeit']?.toString(),
      schadenort: d['schadenort']?.toString(),
      polizeiAmUnfallort: d['polizeiAmUnfallort'] == true,
      dienststelleTagebuchnummer: d['dienststelleTagebuchnummer']?.toString(),
      kilometerstand: (d['kilometerstand'] as num?)?.toInt(),
      fahrzeugId: d['fahrzeugId']?.toString(),
      fahrzeugDisplay: d['fahrzeugDisplay']?.toString(),
      anhangerKennzeichen: d['anhangerKennzeichen']?.toString(),
      schadenhoehe: d['schadenhoehe']?.toString(),
      schadenEigenesFahrzeug: d['schadenEigenesFahrzeug']?.toString(),
      mitarbeiterId: d['mitarbeiterId']?.toString(),
      vornameFahrer: d['vornameFahrer']?.toString(),
      nachnameFahrer: d['nachnameFahrer']?.toString(),
      telefonFahrer: d['telefonFahrer']?.toString(),
      strasseFahrer: d['strasseFahrer']?.toString(),
      plzFahrer: d['plzFahrer']?.toString(),
      ortFahrer: d['ortFahrer']?.toString(),
      fuehrerscheinklasse: d['fuehrerscheinklasse']?.toString(),
      ausstellungsdatum: _date(d['ausstellungsdatum']),
      behoerde: d['behoerde']?.toString(),
      alkoholgenuss: d['alkoholgenuss'] == true,
      blutprobeEntnommen: d['blutprobeEntnommen'] == true,
      blutprobeErgebnis: d['blutprobeErgebnis']?.toString(),
      kennzeichenGegner: d['kennzeichenGegner']?.toString(),
      versicherungsscheinNr: d['versicherungsscheinNr']?.toString(),
      geschaetzteSchadenhoeheGegner: d['geschaetzteSchadenhoeheGegner']?.toString(),
      schadenGegner: d['schadenGegner']?.toString(),
      vornameGegner: d['vornameGegner']?.toString(),
      nachnameGegner: d['nachnameGegner']?.toString(),
      telefonGegner: d['telefonGegner']?.toString(),
      strasseGegner: d['strasseGegner']?.toString(),
      plzGegner: d['plzGegner']?.toString(),
      ortGegner: d['ortGegner']?.toString(),
      kurzeSchadenschilderung: d['kurzeSchadenschilderung']?.toString(),
      vornameFahrzeughalter: d['vornameFahrzeughalter']?.toString(),
      nachnameFahrzeughalter: d['nachnameFahrzeughalter']?.toString(),
      strasseFahrzeughalter: d['strasseFahrzeughalter']?.toString(),
      plzFahrzeughalter: d['plzFahrzeughalter']?.toString(),
      ortFahrzeughalter: d['ortFahrzeughalter']?.toString(),
      bilderDokumente: (d['bilderDokumente'] as List?)?.map((e) => e.toString()).toList() ?? [],
      kurzeBemerkung: d['kurzeBemerkung']?.toString(),
      unterschriftUrl: d['unterschriftUrl']?.toString(),
      ausfuehrlicherSchadensbericht: d['ausfuehrlicherSchadensbericht']?.toString(),
      createdAt: _date(d['createdAt'] ?? d['created']),
      updatedAt: _date(d['updatedAt'] ?? d['updated']),
    );
  }

  Map<String, dynamic> toFirestore() {
    final m = <String, dynamic>{
      'createdBy': createdBy,
      'schadentag': schadentag != null ? Timestamp.fromDate(schadentag!) : null,
      'schadenuhrzeit': schadenuhrzeit,
      'schadenort': schadenort,
      'polizeiAmUnfallort': polizeiAmUnfallort,
      'dienststelleTagebuchnummer': dienststelleTagebuchnummer,
      'kilometerstand': kilometerstand,
      'fahrzeugId': fahrzeugId,
      'fahrzeugDisplay': fahrzeugDisplay,
      'anhangerKennzeichen': anhangerKennzeichen,
      'schadenhoehe': schadenhoehe,
      'schadenEigenesFahrzeug': schadenEigenesFahrzeug,
      'mitarbeiterId': mitarbeiterId,
      'vornameFahrer': vornameFahrer,
      'nachnameFahrer': nachnameFahrer,
      'telefonFahrer': telefonFahrer,
      'strasseFahrer': strasseFahrer,
      'plzFahrer': plzFahrer,
      'ortFahrer': ortFahrer,
      'fuehrerscheinklasse': fuehrerscheinklasse,
      'ausstellungsdatum': ausstellungsdatum != null ? Timestamp.fromDate(ausstellungsdatum!) : null,
      'behoerde': behoerde,
      'alkoholgenuss': alkoholgenuss,
      'blutprobeEntnommen': blutprobeEntnommen,
      'blutprobeErgebnis': blutprobeErgebnis,
      'kennzeichenGegner': kennzeichenGegner,
      'versicherungsscheinNr': versicherungsscheinNr,
      'geschaetzteSchadenhoeheGegner': geschaetzteSchadenhoeheGegner,
      'schadenGegner': schadenGegner,
      'vornameGegner': vornameGegner,
      'nachnameGegner': nachnameGegner,
      'telefonGegner': telefonGegner,
      'strasseGegner': strasseGegner,
      'plzGegner': plzGegner,
      'ortGegner': ortGegner,
      'kurzeSchadenschilderung': kurzeSchadenschilderung,
      'vornameFahrzeughalter': vornameFahrzeughalter,
      'nachnameFahrzeughalter': nachnameFahrzeughalter,
      'strasseFahrzeughalter': strasseFahrzeughalter,
      'plzFahrzeughalter': plzFahrzeughalter,
      'ortFahrzeughalter': ortFahrzeughalter,
      'bilderDokumente': bilderDokumente,
      'kurzeBemerkung': kurzeBemerkung,
      'unterschriftUrl': unterschriftUrl,
      'ausfuehrlicherSchadensbericht': ausfuehrlicherSchadensbericht,
      'updatedAt': FieldValue.serverTimestamp(),
    };
    m.removeWhere((_, v) => v == null);
    return m;
  }
}
