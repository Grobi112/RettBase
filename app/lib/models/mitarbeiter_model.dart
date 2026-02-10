import 'package:cloud_firestore/cloud_firestore.dart' show Timestamp;

/// Mitarbeiter aus kunden/{companyId}/mitarbeiter
class Mitarbeiter {
  final String id;
  final String? uid;
  final String? email;
  final String? pseudoEmail;
  final String? vorname;
  final String? nachname;
  final String? personalnummer;
  final String? role;
  final String? telefon;
  final String? handynummer;
  final String? strasse;
  final String? hausnummer;
  final String? plz;
  final String? ort;
  final String? fuehrerschein;
  final List<String>? qualifikation;
  final List<String>? angestelltenverhaeltnis;
  final DateTime? geburtsdatum;
  final bool active;
  /// Nur bei Admin: true wenn Eintrag aus users-Collection (ohne Mitarb.-Doc)
  final bool fromUsersOnly;

  Mitarbeiter({
    required this.id,
    this.uid,
    this.email,
    this.pseudoEmail,
    this.vorname,
    this.nachname,
    this.personalnummer,
    this.role,
    this.telefon,
    this.handynummer,
    this.strasse,
    this.hausnummer,
    this.plz,
    this.ort,
    this.fuehrerschein,
    this.qualifikation,
    this.angestelltenverhaeltnis,
    this.geburtsdatum,
    this.active = true,
    this.fromUsersOnly = false,
  });

  Mitarbeiter copyWith({
    String? id,
    String? uid,
    String? email,
    String? pseudoEmail,
    String? vorname,
    String? nachname,
    String? personalnummer,
    String? role,
    String? telefon,
    String? handynummer,
    String? strasse,
    String? hausnummer,
    String? plz,
    String? ort,
    String? fuehrerschein,
    List<String>? qualifikation,
    List<String>? angestelltenverhaeltnis,
    DateTime? geburtsdatum,
    bool? active,
  }) =>
      Mitarbeiter(
        id: id ?? this.id,
        uid: uid ?? this.uid,
        email: email ?? this.email,
        pseudoEmail: pseudoEmail ?? this.pseudoEmail,
        vorname: vorname ?? this.vorname,
        nachname: nachname ?? this.nachname,
        personalnummer: personalnummer ?? this.personalnummer,
        role: role ?? this.role,
        telefon: telefon ?? this.telefon,
        handynummer: handynummer ?? this.handynummer,
        strasse: strasse ?? this.strasse,
        hausnummer: hausnummer ?? this.hausnummer,
        plz: plz ?? this.plz,
        ort: ort ?? this.ort,
        fuehrerschein: fuehrerschein ?? this.fuehrerschein,
        qualifikation: qualifikation ?? this.qualifikation,
        angestelltenverhaeltnis: angestelltenverhaeltnis ?? this.angestelltenverhaeltnis,
        geburtsdatum: geburtsdatum ?? this.geburtsdatum,
        active: active ?? this.active,
        fromUsersOnly: this.fromUsersOnly,
      );

  String get displayName {
    final n = nachname?.trim() ?? '';
    final v = vorname?.trim() ?? '';
    if (n.isNotEmpty && v.isNotEmpty) return '$n, $v';
    if (n.isNotEmpty) return n;
    if (v.isNotEmpty) return v;
    return email ?? id;
  }

  /// Erstellt Mitarbeiter aus kunden/{companyId}/users-Dokument (Admin-Firma).
  factory Mitarbeiter.fromUsersDoc(String uid, Map<String, dynamic> data) {
    return Mitarbeiter(
      id: uid,
      uid: uid,
      email: data['email']?.toString(),
      pseudoEmail: data['pseudoEmail']?.toString(),
      vorname: data['vorname']?.toString(),
      nachname: data['nachname']?.toString(),
      personalnummer: data['personalnummer']?.toString(),
      role: data['role']?.toString(),
      telefon: data['telefon']?.toString(),
      handynummer: data['handynummer']?.toString(),
      strasse: data['strasse']?.toString(),
      hausnummer: data['hausnummer']?.toString(),
      plz: data['plz']?.toString(),
      ort: data['ort']?.toString(),
      fuehrerschein: data['fuehrerschein']?.toString(),
      qualifikation: (data['qualifikation'] as List?)?.map((e) => e.toString()).toList(),
      angestelltenverhaeltnis: (data['angestelltenverhaeltnis'] as List?)?.map((e) => e.toString()).toList(),
      geburtsdatum: null,
      active: data['status'] != false && data['active'] != false,
      fromUsersOnly: true,
    );
  }

  factory Mitarbeiter.fromFirestore(String id, Map<String, dynamic> data) {
    final q = data['qualifikation'];
    List<String>? qual;
    if (q is List) qual = q.map((e) => e.toString()).toList();
    final av = data['angestelltenverhaeltnis'];
    List<String>? avList;
    if (av is List) avList = av.map((e) => e.toString()).toList();
    final gb = data['geburtsdatum'];
    DateTime? geb;
    if (gb is DateTime) {
      geb = gb;
    } else if (gb is Timestamp) {
      geb = gb.toDate();
    } else if (gb is String && gb.isNotEmpty) {
      geb = DateTime.tryParse(gb);
    }
    return Mitarbeiter(
      id: id,
      uid: data['uid']?.toString(),
      email: data['email']?.toString(),
      pseudoEmail: data['pseudoEmail']?.toString(),
      vorname: data['vorname']?.toString(),
      nachname: data['nachname']?.toString(),
      personalnummer: data['personalnummer']?.toString(),
      role: data['role']?.toString(),
      telefon: data['telefon']?.toString() ?? data['telefonnummer']?.toString(),
      handynummer: data['handynummer']?.toString() ?? data['handy']?.toString(),
      strasse: data['strasse']?.toString(),
      hausnummer: data['hausnummer']?.toString(),
      plz: data['plz']?.toString(),
      ort: data['ort']?.toString(),
      fuehrerschein: data['fuehrerschein']?.toString(),
      qualifikation: qual,
      angestelltenverhaeltnis: avList,
      geburtsdatum: geb,
      active: data['active'] != false,
    );
  }

  Map<String, dynamic> toFirestore() {
    final m = <String, dynamic>{
      'vorname': vorname,
      'nachname': nachname,
      'personalnummer': personalnummer,
      'role': role,
      'email': email,
      'pseudoEmail': pseudoEmail,
      'uid': uid,
      'telefon': telefon,
      'handynummer': handynummer,
      'strasse': strasse,
      'hausnummer': hausnummer,
      'plz': plz,
      'ort': ort,
      'fuehrerschein': fuehrerschein,
      'qualifikation': qualifikation,
      'angestelltenverhaeltnis': angestelltenverhaeltnis,
      'active': active,
    };
    if (geburtsdatum != null) m['geburtsdatum'] = Timestamp.fromDate(geburtsdatum!);
    return m;
  }
}
