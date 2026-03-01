/// Vorlage für Fahrtenbuch V2 aus Schichtanmeldung
class FahrtenbuchV2Vorlage {
  final String fahrzeugId;
  final String fahrzeugRufname;
  final String? kennzeichen;
  final String? nameFahrer;
  final int? kmAnfang;
  final DateTime datum;
  final List<String> fahrerOptionen;

  FahrtenbuchV2Vorlage({
    required this.fahrzeugId,
    required this.fahrzeugRufname,
    this.kennzeichen,
    this.nameFahrer,
    this.kmAnfang,
    required this.datum,
    List<String>? fahrerOptionen,
  }) : fahrerOptionen = fahrerOptionen ?? const [];
}
