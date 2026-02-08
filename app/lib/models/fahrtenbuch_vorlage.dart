/// Vorlage für Fahrtenbuch-Formular aus Schichtanmeldung
class FahrtenbuchVorlage {
  final String fahrzeugId;
  final String fahrzeugRufname;
  final String? kennzeichen;
  final String? nameFahrer;
  final String? nameBeifahrer;
  final int? kmAnfang;
  final DateTime datum;
  final List<String> fahrerOptionen;
  final List<String> beifahrerOptionen;

  FahrtenbuchVorlage({
    required this.fahrzeugId,
    required this.fahrzeugRufname,
    this.kennzeichen,
    this.nameFahrer,
    this.nameBeifahrer,
    this.kmAnfang,
    required this.datum,
    List<String>? fahrerOptionen,
    List<String>? beifahrerOptionen,
  })  : fahrerOptionen = fahrerOptionen ?? const [],
        beifahrerOptionen = beifahrerOptionen ?? const [];
}
