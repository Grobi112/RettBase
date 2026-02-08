/// Mitarbeiter aus kunden/{companyId}/mitarbeiter
class Mitarbeiter {
  final String id;
  final String? uid;
  final String? email;
  final String? pseudoEmail;
  final String? vorname;
  final String? nachname;
  final String? telefon;
  final String? handynummer;
  final String? strasse;
  final String? hausnummer;
  final String? plz;
  final String? ort;
  final String? fuehrerschein;
  final List<String>? qualifikation;
  final bool active;

  Mitarbeiter({
    required this.id,
    this.uid,
    this.email,
    this.pseudoEmail,
    this.vorname,
    this.nachname,
    this.telefon,
    this.handynummer,
    this.strasse,
    this.hausnummer,
    this.plz,
    this.ort,
    this.fuehrerschein,
    this.qualifikation,
    this.active = true,
  });

  String get displayName {
    final n = nachname?.trim() ?? '';
    final v = vorname?.trim() ?? '';
    if (n.isNotEmpty && v.isNotEmpty) return '$n, $v';
    if (n.isNotEmpty) return n;
    if (v.isNotEmpty) return v;
    return email ?? id;
  }

  factory Mitarbeiter.fromFirestore(String id, Map<String, dynamic> data) {
    final q = data['qualifikation'];
    List<String>? qual;
    if (q is List) qual = q.map((e) => e.toString()).toList();
    return Mitarbeiter(
      id: id,
      uid: data['uid']?.toString(),
      email: data['email']?.toString(),
      pseudoEmail: data['pseudoEmail']?.toString(),
      vorname: data['vorname']?.toString(),
      nachname: data['nachname']?.toString(),
      telefon: data['telefon']?.toString() ?? data['telefonnummer']?.toString(),
      handynummer: data['handynummer']?.toString() ?? data['handy']?.toString(),
      strasse: data['strasse']?.toString(),
      hausnummer: data['hausnummer']?.toString(),
      plz: data['plz']?.toString(),
      ort: data['ort']?.toString(),
      fuehrerschein: data['fuehrerschein']?.toString(),
      qualifikation: qual,
      active: data['active'] != false,
    );
  }
}
