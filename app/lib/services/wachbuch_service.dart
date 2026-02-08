import 'package:cloud_firestore/cloud_firestore.dart';

/// Wachbuch – analog Einsatztagebuch-OVD
/// Firestore: kunden/{companyId}/wachbuchTage, wachbuchEreignisse, wachbuchConfig

class WachbuchService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  static String _dayId(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.${d.year}';

  /// Tag-Dokument laden oder erstellen
  Future<WachbuchTag> ensureDay(String companyId, String dayId, String uid, String createdByName) async {
    if (companyId.isEmpty || dayId.isEmpty) throw ArgumentError('companyId und dayId dürfen nicht leer sein');
    final ref = _db.collection('kunden').doc(companyId).collection('wachbuchTage').doc(dayId);
    final snap = await ref.get();
    if (!snap.exists) {
      await ref.set({
        'datum': dayId,
        'createdAt': FieldValue.serverTimestamp(),
        'closed': false,
        'createdBy': uid,
        'createdByName': createdByName,
      });
      return WachbuchTag(id: dayId, datum: dayId, closed: false, createdAt: DateTime.now(), createdBy: uid, createdByName: createdByName);
    }
    final d = snap.data()!;
    final ca = d['createdAt'];
    return WachbuchTag(
      id: dayId,
      datum: d['datum']?.toString() ?? dayId,
      closed: d['closed'] == true,
      createdAt: ca is Timestamp ? ca.toDate() : DateTime.now(),
      createdBy: d['createdBy']?.toString(),
      createdByName: d['createdByName']?.toString(),
    );
  }

  /// Einträge eines Tages laden (sortiert nach Datum/Uhrzeit)
  Future<List<WachbuchEintrag>> loadEintraege(String companyId, String dayId) async {
    final snap = await _db
        .collection('kunden')
        .doc(companyId)
        .collection('wachbuchTage')
        .doc(dayId)
        .collection('eintraege')
        .get();
    final list = snap.docs.map((d) => WachbuchEintrag.fromFirestore(d.id, d.data())).toList();
    list.sort((a, b) {
      final dc = (a.datum).compareTo(b.datum);
      if (dc != 0) return dc;
      return (a.uhrzeit).compareTo(b.uhrzeit);
    });
    return list;
  }

  /// Stream für Live-Updates (nur aufrufen wenn companyId und dayId gültig)
  Stream<List<WachbuchEintrag>> streamEintraege(String companyId, String dayId) {
    if (companyId.isEmpty || dayId.isEmpty) return Stream.value([]);
    return _db
        .collection('kunden')
        .doc(companyId)
        .collection('wachbuchTage')
        .doc(dayId)
        .collection('eintraege')
        .snapshots()
        .map((snap) {
      final list = snap.docs.map((d) => WachbuchEintrag.fromFirestore(d.id, d.data())).toList();
      list.sort((a, b) {
        final dc = (a.datum).compareTo(b.datum);
        if (dc != 0) return dc;
        return (a.uhrzeit).compareTo(b.uhrzeit);
      });
      return list;
    });
  }

  /// Neuen Eintrag speichern
  Future<String> saveEintrag(String companyId, String dayId, WachbuchEintragData data, String uid, String createdByName) async {
    final ref = _db
        .collection('kunden')
        .doc(companyId)
        .collection('wachbuchTage')
        .doc(dayId)
        .collection('eintraege')
        .doc();
    await ref.set({
      ...data.toMap(),
      'createdAt': FieldValue.serverTimestamp(),
      'createdBy': uid,
      'createdByName': createdByName,
    });
    return ref.id;
  }

  /// Eintrag aktualisieren
  Future<void> updateEintrag(String companyId, String dayId, String eintragId, WachbuchEintragData data, String uid) async {
    await _db
        .collection('kunden')
        .doc(companyId)
        .collection('wachbuchTage')
        .doc(dayId)
        .collection('eintraege')
        .doc(eintragId)
        .update({
      ...data.toMap(),
      'updatedAt': FieldValue.serverTimestamp(),
      'updatedBy': uid,
    });
  }

  /// Eintrag löschen
  Future<void> deleteEintrag(String companyId, String dayId, String eintragId) async {
    await _db
        .collection('kunden')
        .doc(companyId)
        .collection('wachbuchTage')
        .doc(dayId)
        .collection('eintraege')
        .doc(eintragId)
        .delete();
  }

  /// Ereignisse (Master-Daten) laden
  Future<List<WachbuchEreignis>> loadEreignisse(String companyId) async {
    final snap = await _db.collection('kunden').doc(companyId).collection('wachbuchEreignisse').get();
    final list = snap.docs.map((d) => WachbuchEreignis.fromFirestore(d.id, d.data())).toList();
    list.sort((a, b) {
      final oa = a.order;
      final ob = b.order;
      if (oa != ob) return oa.compareTo(ob);
      return (a.name ?? '').compareTo(b.name ?? '');
    });
    return list;
  }

  /// Neues Ereignis speichern
  Future<String> saveEreignis(String companyId, String name, int order) async {
    final id = name.toLowerCase().replaceAll(RegExp(r'\s+'), '-').replaceAll(RegExp(r'[^a-z0-9-]'), '');
    final ref = _db.collection('kunden').doc(companyId).collection('wachbuchEreignisse').doc(id);
    await ref.set({
      'name': name.trim(),
      'order': order,
      'active': true,
      'createdAt': FieldValue.serverTimestamp(),
    });
    return ref.id;
  }

  /// Ereignis löschen
  Future<void> deleteEreignis(String companyId, String ereignisId) async {
    await _db.collection('kunden').doc(companyId).collection('wachbuchEreignisse').doc(ereignisId).delete();
  }

  /// Konfiguration laden (editAllowedRoles)
  /// Pfad: kunden/{companyId}/wachbuchConfig/config (4 Segmente = gültiges Dokument)
  Future<WachbuchConfig> loadConfig(String companyId) async {
    if (companyId.isEmpty) return WachbuchConfig(editAllowedRoles: ['superadmin', 'admin', 'leiterssd']);
    final snap = await _db.collection('kunden').doc(companyId).collection('wachbuchConfig').doc('config').get();
    if (!snap.exists) return WachbuchConfig(editAllowedRoles: ['superadmin', 'admin', 'leiterssd']);
    final d = snap.data() ?? {};
    final roles = d['editAllowedRoles'];
    List<String> list = ['superadmin', 'admin', 'leiterssd'];
    if (roles is List) list = roles.map((r) => r.toString()).toList();
    return WachbuchConfig(editAllowedRoles: list);
  }

  /// Prüft ob Tag abgeschlossen
  bool isDayClosed(WachbuchTag? tag) => tag?.closed == true;

  /// Prüft ob Tag in der Vergangenheit liegt
  bool isPastDay(String dayId) {
    try {
      final parts = dayId.split('.');
      if (parts.length != 3) return false;
      final day = int.tryParse(parts[0]) ?? 0;
      final month = int.tryParse(parts[1]) ?? 0;
      final year = int.tryParse(parts[2]) ?? 0;
      final dayDate = DateTime(year, month, day);
      final today = DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day);
      return dayDate.isBefore(today);
    } catch (_) {
      return false;
    }
  }

  static String getCurrentDayId() => _dayId(DateTime.now());
}

class WachbuchTag {
  final String id;
  final String datum;
  final bool closed;
  final DateTime? createdAt;
  final String? createdBy;
  final String? createdByName;

  WachbuchTag({required this.id, required this.datum, required this.closed, this.createdAt, this.createdBy, this.createdByName});
}

class WachbuchEintrag {
  final String id;
  final String datum;
  final String uhrzeit;
  final String ereignis;
  final String text;
  final String eintragendePerson;
  final String? createdBy;

  WachbuchEintrag({
    required this.id,
    required this.datum,
    required this.uhrzeit,
    required this.ereignis,
    required this.text,
    required this.eintragendePerson,
    this.createdBy,
  });

  factory WachbuchEintrag.fromFirestore(String id, Map<String, dynamic> d) {
    return WachbuchEintrag(
      id: id,
      datum: d['datum']?.toString() ?? '',
      uhrzeit: d['uhrzeit']?.toString() ?? '',
      ereignis: d['ereignis']?.toString() ?? '',
      text: d['text']?.toString() ?? '',
      eintragendePerson: d['eintragendePerson'] ?? d['diensthabenderOvd'] ?? d['createdByName']?.toString() ?? 'Unbekannt',
      createdBy: d['createdBy']?.toString(),
    );
  }
}

class WachbuchEintragData {
  final String datum;
  final String uhrzeit;
  final String ereignis;
  final String text;
  final String eintragendePerson;

  WachbuchEintragData({
    required this.datum,
    required this.uhrzeit,
    required this.ereignis,
    required this.text,
    required this.eintragendePerson,
  });

  Map<String, dynamic> toMap() => {
        'datum': datum,
        'uhrzeit': uhrzeit,
        'ereignis': ereignis,
        'text': text,
        'eintragendePerson': eintragendePerson,
      };
}

class WachbuchEreignis {
  final String id;
  final String name;
  final int order;
  final bool active;

  WachbuchEreignis({required this.id, required this.name, this.order = 0, this.active = true});

  factory WachbuchEreignis.fromFirestore(String id, Map<String, dynamic> d) {
    final o = d['order'];
    return WachbuchEreignis(
      id: id,
      name: d['name']?.toString() ?? id,
      order: o is int ? o : (int.tryParse(o.toString()) ?? 999),
      active: d['active'] != false,
    );
  }
}

class WachbuchConfig {
  final List<String> editAllowedRoles;

  WachbuchConfig({required this.editAllowedRoles});
}
