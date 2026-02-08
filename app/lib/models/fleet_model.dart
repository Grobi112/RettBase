import 'package:cloud_firestore/cloud_firestore.dart';

/// Fahrzeug-Stammdaten – gleiche Struktur wie rettbase fahrzeugstammdaten
class Fahrzeug {
  final String id;
  final String? rufname;
  final String? fahrzeugtyp;
  final String? wache;
  final bool aktiv;
  final String? kennzeichen;
  final String? hersteller;
  final String? modell;
  final int? baujahr;
  final String? indienststellung;
  final String? traeger;
  final String? kostenstelle;
  final String? gruppe;
  final String? kraftstoff;
  final String? antrieb;
  final List<Fahrzeugbeauftragter> beauftragte;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  Fahrzeug({
    required this.id,
    this.rufname,
    this.fahrzeugtyp,
    this.wache,
    this.aktiv = true,
    this.kennzeichen,
    this.hersteller,
    this.modell,
    this.baujahr,
    this.indienststellung,
    this.traeger,
    this.kostenstelle,
    this.gruppe,
    this.kraftstoff,
    this.antrieb,
    this.beauftragte = const [],
    this.createdAt,
    this.updatedAt,
  });

  String get displayName => rufname?.trim().isNotEmpty == true ? rufname! : '(Ohne Rufname)';

  factory Fahrzeug.fromFirestore(String id, Map<String, dynamic> d) {
    List<Fahrzeugbeauftragter> beauftragte = [];
    final b = d['beauftragte'];
    if (b is List) {
      for (final item in b) {
        if (item is Map) {
          final m = Map<String, dynamic>.from(item);
          beauftragte.add(Fahrzeugbeauftragter(
            uid: m['uid']?.toString(),
            name: m['name']?.toString() ?? '',
          ));
        }
      }
    }

    DateTime? createdAt;
    final ca = d['createdAt'];
    if (ca is Timestamp) createdAt = ca.toDate();
    if (ca is DateTime) createdAt = ca;

    DateTime? updatedAt;
    final ua = d['updatedAt'];
    if (ua is Timestamp) updatedAt = ua.toDate();
    if (ua is DateTime) updatedAt = ua;

    return Fahrzeug(
      id: id,
      rufname: d['rufname']?.toString() ?? d['name']?.toString(),
      fahrzeugtyp: d['fahrzeugtyp']?.toString(),
      wache: d['wache']?.toString(),
      aktiv: d['aktiv'] != false,
      kennzeichen: () {
        final v = (d['kennzeichen'] ?? d['Kennzeichen'] ?? d['nummernschild'])?.toString().trim();
        return v != null && v.isNotEmpty ? v : null;
      }(),
      hersteller: d['hersteller']?.toString(),
      modell: d['modell']?.toString(),
      baujahr: (d['baujahr'] as num?)?.toInt(),
      indienststellung: d['indienststellung']?.toString(),
      traeger: d['traeger']?.toString(),
      kostenstelle: d['kostenstelle']?.toString(),
      gruppe: d['gruppe']?.toString(),
      kraftstoff: d['kraftstoff']?.toString(),
      antrieb: d['antrieb']?.toString(),
      beauftragte: beauftragte,
      createdAt: createdAt,
      updatedAt: updatedAt,
    );
  }

  Map<String, dynamic> toFirestore() {
    final map = <String, dynamic>{
      'rufname': rufname,
      'fahrzeugtyp': fahrzeugtyp,
      'wache': wache,
      'aktiv': aktiv,
      'kennzeichen': kennzeichen,
      'hersteller': hersteller,
      'modell': modell,
      'baujahr': baujahr,
      'indienststellung': indienststellung,
      'traeger': traeger,
      'kostenstelle': kostenstelle,
      'gruppe': gruppe,
      'kraftstoff': kraftstoff,
      'antrieb': antrieb,
      'beauftragte': beauftragte.map((b) => {'uid': b.uid, 'name': b.name}).toList(),
      'updatedAt': FieldValue.serverTimestamp(),
    };
    map.removeWhere((_, v) => v == null);
    return map;
  }
}

class Fahrzeugbeauftragter {
  final String? uid;
  final String name;

  Fahrzeugbeauftragter({this.uid, required this.name});
}

/// Termin (Werkstatt, TÜV, etc.)
class FahrzeugTermin {
  final String id;
  final String fahrzeugId;
  final String fahrzeugRufname;
  final DateTime datum;
  final String typ; // z.B. Werkstatt, TÜV, HU, AU
  final String? notiz;
  final DateTime? createdAt;

  FahrzeugTermin({
    required this.id,
    required this.fahrzeugId,
    required this.fahrzeugRufname,
    required this.datum,
    required this.typ,
    this.notiz,
    this.createdAt,
  });

  factory FahrzeugTermin.fromFirestore(String id, Map<String, dynamic> d) {
    DateTime datum = DateTime.now();
    final dVal = d['datum'];
    if (dVal is Timestamp) datum = dVal.toDate();
    if (dVal is DateTime) datum = dVal;

    DateTime? createdAt;
    final ca = d['createdAt'];
    if (ca is Timestamp) createdAt = ca.toDate();
    if (ca is DateTime) createdAt = ca;

    return FahrzeugTermin(
      id: id,
      fahrzeugId: d['fahrzeugId']?.toString() ?? '',
      fahrzeugRufname: d['fahrzeugRufname']?.toString() ?? '',
      datum: datum,
      typ: d['typ']?.toString() ?? 'Sonstiges',
      notiz: d['notiz']?.toString(),
      createdAt: createdAt,
    );
  }

  Map<String, dynamic> toFirestore() => {
        'fahrzeugId': fahrzeugId,
        'fahrzeugRufname': fahrzeugRufname,
        'datum': Timestamp.fromDate(datum),
        'typ': typ,
        'notiz': notiz,
        'createdAt': FieldValue.serverTimestamp(),
      };
}

/// Gemeldeter Fahrzeugmangel (oder MPG/Digitalfunk/Sonstiger Mangel)
class FahrzeugMangel {
  final String id;
  final String? mangelTyp; // fahrzeugmangel | mpg-mangel | digitalfunk | sonstiger-mangel
  final String fahrzeugId;
  final String fahrzeugRufname;
  final String? kennzeichen;
  final String? betreff; // Kurzbeschreibung
  final String beschreibung;
  final String? kategorie;
  final String? melderName;
  final String? melderUid;
  final String status; // offen, inBearbeitung, erledigt
  final String? prioritaet; // niedrig, mittel, hoch
  final DateTime? datum; // Erfassungsdatum
  final int? kilometerstand;
  final List<String> bilder; // Download-URLs von Firebase Storage
  final DateTime? createdAt;
  final DateTime? updatedAt;

  FahrzeugMangel({
    required this.id,
    this.mangelTyp,
    required this.fahrzeugId,
    required this.fahrzeugRufname,
    this.kennzeichen,
    this.betreff,
    required this.beschreibung,
    this.kategorie,
    this.melderName,
    this.melderUid,
    this.status = 'offen',
    this.prioritaet,
    this.datum,
    this.kilometerstand,
    this.bilder = const [],
    this.createdAt,
    this.updatedAt,
  });

  String get displayLabel => kennzeichen?.trim().isNotEmpty == true
      ? kennzeichen!
      : (fahrzeugRufname.trim().isNotEmpty ? fahrzeugRufname : '(Unbekannt)');

  factory FahrzeugMangel.fromFirestore(String id, Map<String, dynamic> d) {
    DateTime? createdAt;
    for (final key in ['createdAt', 'created', 'timestamp']) {
      final v = d[key];
      if (v is Timestamp) { createdAt = v.toDate(); break; }
      if (v is DateTime) { createdAt = v; break; }
    }
    DateTime? datum;
    for (final key in ['datum', 'date']) {
      final v = d[key];
      if (v is Timestamp) { datum = v.toDate(); break; }
      if (v is DateTime) { datum = v; break; }
    }
    datum ??= createdAt;
    DateTime? updatedAt;
    for (final key in ['updatedAt', 'updated', 'lastEdited']) {
      final v = d[key];
      if (v is Timestamp) { updatedAt = v.toDate(); break; }
      if (v is DateTime) { updatedAt = v; break; }
    }

    final fahrzeugId = d['fahrzeugId']?.toString() ?? d['fahrzeug']?.toString() ?? '';
    final fahrzeugRufname = d['fahrzeugRufname']?.toString() ?? d['fahrzeugName']?.toString() ?? d['rufname']?.toString() ?? '';
    final kennzeichen = d['kennzeichen']?.toString();
    final betreff = d['betreff']?.toString() ?? d['subject']?.toString() ?? d['kurzbeschreibung']?.toString();
    final beschreibung = d['beschreibung']?.toString() ?? d['description']?.toString() ?? d['text']?.toString() ?? '';
    final kategorie = d['kategorie']?.toString() ?? d['category']?.toString();
    final melderName = d['melderName']?.toString() ?? d['melder']?.toString() ?? d['reporter']?.toString();
    final status = d['status']?.toString() ?? d['state']?.toString() ?? 'offen';
    int? kilometerstand;
    final km = d['kilometerstand'] ?? d['km'] ?? d['mileage'];
    if (km != null) kilometerstand = (km is num) ? km.toInt() : int.tryParse(km.toString());

    List<String> bilder = [];
    final b = d['bilder'] ?? d['images'] ?? d['imageUrls'] ?? d['attachments'];
    if (b is List) bilder = b.map((e) => e.toString()).where((e) => e.isNotEmpty).toList();

    final mangelTyp = d['mangelTyp']?.toString() ?? d['mangeltyp']?.toString();
    return FahrzeugMangel(
      id: id,
      mangelTyp: mangelTyp?.isNotEmpty == true ? mangelTyp : null,
      fahrzeugId: fahrzeugId,
      fahrzeugRufname: fahrzeugRufname,
      kennzeichen: kennzeichen,
      betreff: betreff,
      beschreibung: beschreibung,
      kategorie: kategorie,
      melderName: melderName,
      melderUid: d['melderUid']?.toString() ?? d['melderId']?.toString(),
      status: status,
      prioritaet: d['prioritaet']?.toString() ?? d['priorität']?.toString() ?? d['priority']?.toString(),
      datum: datum,
      kilometerstand: kilometerstand,
      bilder: bilder,
      createdAt: createdAt,
      updatedAt: updatedAt,
    );
  }

  Map<String, dynamic> toFirestore() => {
        if (mangelTyp != null) 'mangelTyp': mangelTyp,
        'fahrzeugId': fahrzeugId,
        'fahrzeugRufname': fahrzeugRufname,
        'kennzeichen': kennzeichen,
        'betreff': betreff,
        'beschreibung': beschreibung,
        'kategorie': kategorie,
        'melderName': melderName,
        'melderUid': melderUid,
        'status': status,
        'prioritaet': prioritaet,
        'datum': datum != null ? Timestamp.fromDate(datum!) : null,
        'kilometerstand': kilometerstand,
        'bilder': bilder,
        'createdAt': createdAt != null ? Timestamp.fromDate(createdAt!) : FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      };

  FahrzeugMangel copyWith({
    String? id,
    String? mangelTyp,
    String? kennzeichen,
    String? betreff,
    String? status,
    String? prioritaet,
    String? beschreibung,
    String? kategorie,
    String? melderName,
    DateTime? datum,
    int? kilometerstand,
    List<String>? bilder,
    DateTime? updatedAt,
  }) =>
      FahrzeugMangel(
        id: id ?? this.id,
        mangelTyp: mangelTyp ?? this.mangelTyp,
        fahrzeugId: fahrzeugId,
        fahrzeugRufname: fahrzeugRufname,
        kennzeichen: kennzeichen ?? this.kennzeichen,
        betreff: betreff ?? this.betreff,
        beschreibung: beschreibung ?? this.beschreibung,
        kategorie: kategorie ?? this.kategorie,
        melderName: melderName ?? this.melderName,
        melderUid: melderUid,
        status: status ?? this.status,
        prioritaet: prioritaet ?? this.prioritaet,
        datum: datum ?? this.datum,
        kilometerstand: kilometerstand ?? this.kilometerstand,
        bilder: bilder ?? this.bilder,
        createdAt: createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
      );
}

/// Modul-Einstellungen für Flottenmanagement
class FleetSettings {
  final List<String> fahrzeugtypen;
  final List<String> terminarten;
  final int erinnerungstage;
  final List<Fahrzeugbeauftragter> fahrzeugbeauftragte;

  FleetSettings({
    this.fahrzeugtypen = const ['RTW', 'KTW', 'NEF', 'MTW', 'KEF', 'Sonstiges'],
    this.terminarten = const ['Werkstatt', 'TÜV', 'HU', 'AU', 'Sonstiges'],
    this.erinnerungstage = 14,
    this.fahrzeugbeauftragte = const [],
  });

  factory FleetSettings.fromFirestore(Map<String, dynamic>? d) {
    if (d == null) return FleetSettings();
    List<String> f = FleetSettings().fahrzeugtypen;
    if (d['fahrzeugtypen'] is List) {
      f = (d['fahrzeugtypen'] as List).map((e) => e.toString().trim()).where((e) => e.isNotEmpty).toList();
      if (f.isEmpty) f = FleetSettings().fahrzeugtypen;
    }
    List<String> t = FleetSettings().terminarten;
    if (d['terminarten'] is List) {
      t = (d['terminarten'] as List).map((e) => e.toString().trim()).where((e) => e.isNotEmpty).toList();
      if (t.isEmpty) t = FleetSettings().terminarten;
    }
    final e = (d['erinnerungstage'] as num?)?.toInt() ?? 14;
    List<Fahrzeugbeauftragter> fb = [];
    if (d['fahrzeugbeauftragte'] is List) {
      for (final item in d['fahrzeugbeauftragte'] as List) {
        if (item is Map) {
          final m = Map<String, dynamic>.from(item);
          fb.add(Fahrzeugbeauftragter(
            uid: m['uid']?.toString(),
            name: m['name']?.toString() ?? '',
          ));
        }
      }
    }
    return FleetSettings(
      fahrzeugtypen: f,
      terminarten: t,
      erinnerungstage: e.clamp(1, 365),
      fahrzeugbeauftragte: fb,
    );
  }

  Map<String, dynamic> toFirestore() => {
        'fahrzeugtypen': fahrzeugtypen,
        'terminarten': terminarten,
        'erinnerungstage': erinnerungstage,
        'fahrzeugbeauftragte': fahrzeugbeauftragte.map((b) => {'uid': b.uid, 'name': b.name}).toList(),
      };
}
