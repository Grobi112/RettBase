/// Vorlage für Checklisten-Ausfüllung aus Schichtanmeldung
class ChecklistenVorlage {
  final String? fahrer;
  final String? beifahrer;
  final String? praktikantAzubi;
  final String? kennzeichen;
  final String? fahrzeugRufname;
  final String? fahrzeugId; // Dokument-ID aus fahrzeuge-Collection
  final String? standort;
  final String? wachbuchSchicht;
  final List<String> fahrerOptionen;
  final List<String> beifahrerOptionen;
  final List<String> kennzeichenOptionen;

  ChecklistenVorlage({
    this.fahrer,
    this.beifahrer,
    this.praktikantAzubi,
    this.kennzeichen,
    this.fahrzeugRufname,
    this.fahrzeugId,
    this.standort,
    this.wachbuchSchicht,
    List<String>? fahrerOptionen,
    List<String>? beifahrerOptionen,
    List<String>? kennzeichenOptionen,
  })  : fahrerOptionen = fahrerOptionen ?? const [],
        beifahrerOptionen = beifahrerOptionen ?? const [],
        kennzeichenOptionen = kennzeichenOptionen ?? const [];
}
