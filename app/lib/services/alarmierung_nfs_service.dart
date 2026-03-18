import 'package:cloud_firestore/cloud_firestore.dart';
import 'mitarbeiter_service.dart';
import 'schichtplan_nfs_service.dart';

/// Alarmierung NFS (Notfallseelsorge) – Einsätze anlegen und Kräfte zuordnen.
/// Firestore: kunden/{companyId}/alarmierung-nfs
class AlarmierungNfsService {
  final _db = FirebaseFirestore.instance;
  final _mitarbeiterService = MitarbeiterService();
  final _schichtplanNfsService = SchichtplanNfsService();

  CollectionReference<Map<String, dynamic>> _col(String companyId) =>
      _db.collection('kunden').doc(companyId).collection('alarmierung-nfs');

  DocumentReference<Map<String, dynamic>> _counterDoc(String companyId, int year) =>
      _db.collection('kunden').doc(companyId).collection('alarmierung-nfs-zähler').doc(year.toString());

  /// Vorschau der nächsten Laufende-Nr (ohne Zähler zu erhöhen). Format: YYYYNNNN.
  Future<String> getNextLaufendeNrPreview(String companyId) async {
    final year = DateTime.now().year;
    final ref = _counterDoc(companyId, year);
    final snap = await ref.get();
    final next = (snap.data()?['lastNumber'] as int? ?? 0) + 1;
    return '$year${next.toString().padLeft(4, '0')}';
  }

  /// Einsatz erstellen. Gibt docId zurück.
  /// [laufendeNr] wird nur beim Erstellen gesetzt; Zähler wird nur bei erfolgreichem Anlegen aktualisiert.
  Future<String> create(
    String companyId,
    Map<String, dynamic> data, {
    String? creatorUid,
    String? creatorName,
    String? laufendeNr,
  }) async {
    final clean = Map<String, dynamic>.from(data);
    if (laufendeNr != null && laufendeNr.trim().isNotEmpty) {
      clean['laufendeNr'] = laufendeNr.trim();
      await _updateCounterForLaufendeNr(companyId, laufendeNr.trim());
    }
    clean['createdAt'] = FieldValue.serverTimestamp();
    clean['createdBy'] = creatorUid;
    clean['createdByName'] = creatorName;
    clean['status'] = 'offen'; // offen | abgeschlossen
    final now = DateTime.now();
    final datumUhrzeit =
        '${now.day.toString().padLeft(2, '0')}.${now.month.toString().padLeft(2, '0')}.${now.year} '
        '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}:${now.second.toString().padLeft(2, '0')}';
    clean['massnahmen'] = [
      {
        'datumUhrzeit': datumUhrzeit,
        'benutzer': creatorName ?? 'System',
        'eintrag': 'Einsatz angelegt',
      },
    ];
    clean['rueckmeldungen'] = clean['rueckmeldungen'] ?? [];
    final ref = await _col(companyId).add(clean);
    return ref.id;
  }

  /// Abgeschlossenen Einsatz löschen (nur Superadmin). Zähler wird anschließend
  /// anhand der noch vorhandenen Einsätze neu berechnet.
  Future<void> deleteAbgeschlossenerEinsatz(String companyId, String docId) async {
    final doc = await _col(companyId).doc(docId).get();
    final data = doc.data();
    if (data == null) return;
    if ((data['status'] ?? 'offen') != 'abgeschlossen') {
      throw StateError('Nur abgeschlossene Einsätze können gelöscht werden.');
    }
    final laufendeNr = (data['laufendeNr'] ?? '').toString().trim();
    await _col(companyId).doc(docId).delete();
    if (laufendeNr.length >= 8 && !laufendeNr.contains('-')) {
      final year = int.tryParse(laufendeNr.substring(0, 4));
      if (year != null) await _recalculateCounterForYear(companyId, year);
    }
  }

  /// Zähler für ein Jahr anhand der noch vorhandenen Einsätze neu berechnen.
  /// Setzt lastNumber auf die höchste noch vorhandene laufendeNr dieses Jahres.
  /// Sind keine Einsätze mehr vorhanden, wird lastNumber auf 0 gesetzt.
  Future<void> _recalculateCounterForYear(String companyId, int year) async {
    final yearStr = year.toString();
    final snap = await _col(companyId).get();
    int maxNum = 0;
    for (final doc in snap.docs) {
      final nr = doc.data()['laufendeNr']?.toString().trim() ?? '';
      if (nr.length >= 8 && nr.startsWith(yearStr) && !nr.contains('-')) {
        final num = int.tryParse(nr.substring(4));
        if (num != null && num > maxNum) maxNum = num;
      }
    }
    await _counterDoc(companyId, year).set({'lastNumber': maxNum});
  }

  /// Zähler manuell setzen (nur Superadmin).
  /// [lastNumber] = 0 → nächste vergebene Nummer wird YYYY0001 (z.B. 20260001).
  Future<void> setCounter(String companyId, int year, int lastNumber) async {
    await _counterDoc(companyId, year).set({'lastNumber': lastNumber});
  }

  /// Zähler aktualisieren, damit die vergebene Laufende-Nr nicht erneut vergeben wird.
  Future<void> _updateCounterForLaufendeNr(String companyId, String laufendeNr) async {
    if (laufendeNr.length < 8) return;
    final yearStr = laufendeNr.substring(0, 4);
    final numStr = laufendeNr.substring(4);
    final year = int.tryParse(yearStr);
    final num = int.tryParse(numStr);
    if (year == null || num == null) return;
    await _db.runTransaction((tx) async {
      final ref = _counterDoc(companyId, year);
      final snap = await tx.get(ref);
      final last = snap.data()?['lastNumber'] as int? ?? 0;
      if (num > last) {
        tx.set(ref, {'lastNumber': num});
      }
    });
  }

  /// Maßnahme hinzufügen (Datum/Uhrzeit, Benutzer, Eintrag).
  Future<void> addMassnahme(
    String companyId,
    String docId, {
    required String benutzer,
    required String eintrag,
  }) async {
    final now = DateTime.now();
    final datumUhrzeit =
        '${now.day.toString().padLeft(2, '0')}.${now.month.toString().padLeft(2, '0')}.${now.year} '
        '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}:${now.second.toString().padLeft(2, '0')}';
    await _col(companyId).doc(docId).update({
      'massnahmen': FieldValue.arrayUnion([
        {
          'datumUhrzeit': datumUhrzeit,
          'benutzer': benutzer,
          'eintrag': eintrag,
        }
      ]),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  /// Rückmeldung hinzufügen (Datum/Uhrzeit, EM, Eintrag).
  Future<void> addRueckmeldung(
    String companyId,
    String docId, {
    required String mitarbeiterId,
    required String mitarbeiterName,
    required String eintrag,
  }) async {
    final now = DateTime.now();
    final datumUhrzeit =
        '${now.day.toString().padLeft(2, '0')}.${now.month.toString().padLeft(2, '0')}.${now.year} '
        '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}:${now.second.toString().padLeft(2, '0')}';
    await _col(companyId).doc(docId).update({
      'rueckmeldungen': FieldValue.arrayUnion([
        {
          'datumUhrzeit': datumUhrzeit,
          'mitarbeiterId': mitarbeiterId,
          'mitarbeiterName': mitarbeiterName,
          'eintrag': eintrag,
        }
      ]),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  /// Einsatz aktualisieren (z.B. weitere Kräfte hinzufügen).
  Future<void> update(
    String companyId,
    String docId,
    Map<String, dynamic> updates,
  ) async {
    updates['updatedAt'] = FieldValue.serverTimestamp();
    await _col(companyId).doc(docId).update(updates);
  }

  /// Einsatz laden (immer vom Server, um aktuelle Maßnahmen/Rückmeldungen zu erhalten)
  Future<Map<String, dynamic>?> get(String companyId, String docId) async {
    final snap = await _col(companyId)
        .doc(docId)
        .get(const GetOptions(source: Source.server));
    if (!snap.exists || snap.data() == null) return null;
    return {'id': snap.id, ...?snap.data()};
  }

  /// Einsatz live streamen (für Status-Updates der eingesetzten Kräfte).
  Stream<Map<String, dynamic>?> streamEinsatz(String companyId, String docId) {
    return _col(companyId)
        .doc(docId)
        .snapshots()
        .map((s) {
          if (!s.exists || s.data() == null) return null;
          return {'id': s.id, ...?s.data()};
        });
  }

  /// Alle Einsätze streamen (neueste zuerst)
  Stream<List<Map<String, dynamic>>> streamEinsaetze(String companyId) {
    return _col(companyId)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((s) => s.docs.map((d) => {'id': d.id, ...d.data()}).toList());
  }

  /// Alle abgeschlossenen Einsätze (für Protokoll-Dropdown, wenn kein mitarbeiterId).
  Stream<List<Map<String, dynamic>>> streamAbgeschlosseneEinsaetze(
    String companyId,
  ) {
    return _col(companyId)
        .where('status', isEqualTo: 'abgeschlossen')
        .orderBy('einsatzDatum', descending: true)
        .limit(100)
        .snapshots()
        .map((s) => s.docs.map((d) => {'id': d.id, ...d.data()}).toList());
  }

  /// Abgeschlossene Einsätze, in denen der Mitarbeiter alarmiert wurde (für Protokoll-Dropdown).
  Stream<List<Map<String, dynamic>>> streamAbgeschlosseneEinsaetzeForMitarbeiter(
    String companyId,
    String mitarbeiterId,
  ) {
    return _col(companyId)
        .where('alarmierteMitarbeiterIds', arrayContains: mitarbeiterId)
        .where('status', isEqualTo: 'abgeschlossen')
        .orderBy('einsatzDatum', descending: true)
        .limit(50)
        .snapshots()
        .map((s) => s.docs.map((d) => {'id': d.id, ...d.data()}).toList());
  }

  /// Einmal-Abfrage abgeschlossener Einsätze vom Server (um Cache zu umgehen, z.B. nach Löschung durch Superadmin).
  Future<List<Map<String, dynamic>>> getAbgeschlosseneEinsaetzeForMitarbeiter(
    String companyId,
    String mitarbeiterId,
  ) async {
    final snap = await _col(companyId)
        .where('alarmierteMitarbeiterIds', arrayContains: mitarbeiterId)
        .where('status', isEqualTo: 'abgeschlossen')
        .orderBy('einsatzDatum', descending: true)
        .limit(50)
        .get(const GetOptions(source: Source.server));
    return snap.docs.map((d) => {'id': d.id, ...d.data()}).toList();
  }

  /// Aktiven Einsatz für einen alarmierten Mitarbeiter streamen (status != abgeschlossen).
  Stream<Map<String, dynamic>?> streamActiveEinsatzForMitarbeiter(
    String companyId,
    String mitarbeiterId,
  ) {
    return _col(companyId)
        .where('alarmierteMitarbeiterIds', arrayContains: mitarbeiterId)
        .snapshots()
        .map((s) {
          for (final d in s.docs) {
            final data = d.data();
            if ((data['status'] ?? 'offen') != 'abgeschlossen') {
              return {'id': d.id, ...data};
            }
          }
          return null;
        });
  }

  /// Status eines alarmierten Mitarbeiters setzen (2, 3, 4, 7) mit Zeitstempel.
  /// Speichert pro Mitarbeiter: alarmierteMitarbeiterStatus + alarmierteMitarbeiterZeiten.
  /// Bei Status 2 (Einsatz beendet): Wenn nur eine Einsatzkraft alarmiert ist, wird der Einsatz
  /// automatisch abgeschlossen. Bei mehreren Kräften schließt nur der Koordinator über „Einsatz bearbeiten“.
  /// Returns true wenn der Einsatz automatisch abgeschlossen wurde.
  Future<bool> setAlarmierterStatus(
    String companyId,
    String docId,
    String mitarbeiterId,
    int status,
  ) async {
    final now = DateTime.now();
    final timeStr = _formatTimeFromDateTime(now);
    final updates = <String, dynamic>{
      'updatedAt': FieldValue.serverTimestamp(),
      'alarmierteMitarbeiterStatus.$mitarbeiterId': status,
    };
    final zeitenKey = 'alarmierteMitarbeiterZeiten.$mitarbeiterId';
    if (status == 3) {
      updates['$zeitenKey.uhrzeitEinsatzUebernommen'] = timeStr;
    } else if (status == 4) {
      updates['$zeitenKey.uhrzeitAnEinsatzort'] = timeStr;
    } else if (status == 7) {
      updates['$zeitenKey.uhrzeitAbfahrt'] = timeStr;
    } else if (status == 2) {
      updates['$zeitenKey.uhrzeitZuHause'] = timeStr;
    }
    var autoAbgeschlossen = false;
    if (status == 2) {
      final doc = await _col(companyId).doc(docId).get();
      final ids = doc.data()?['alarmierteMitarbeiterIds'] as List?;
      if (ids != null && ids.length == 1) {
        updates['status'] = 'abgeschlossen';
        autoAbgeschlossen = true;
      }
    }
    await _col(companyId).doc(docId).update(updates);
    return autoAbgeschlossen;
  }

  /// Labels für Status 2, 3, 4, 7
  static const statusLabels = {
    2: 'Einsatz beendet',
    3: 'Einsatz übernommen',
    4: 'Am Einsatzort',
    7: 'Einsatzstelle verlassen',
  };

  static String _formatTimeFromDateTime(DateTime d) =>
      '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

  /// Mitarbeiter, die an [dayId] zur [stunde] (0–23) im Schichtplan eingetragen sind (verfügbar).
  /// Gibt Liste mit id, vorname, nachname, displayName, ort, telefon, typId, typName zurück.
  /// dayId Format: DD.MM.YYYY
  /// [forceServerRead]: Frische Daten vom Server (kein Cache).
  Future<List<Map<String, dynamic>>> getVerfuegbareMitarbeiterMitDetails(
    String companyId,
    String dayId,
    int stunde, {
    bool forceServerRead = true,
  }) async {
    final eintraege = await _schichtplanNfsService.loadStundenplanEintraege(
      companyId,
      dayId,
      forceServerRead: forceServerRead,
    );
    final typen = await _schichtplanNfsService.loadBereitschaftsTypen(companyId);
    final typNameMap = {for (final t in typen) t.id: t.name};
    final typColorMap = {for (final t in typen) t.id: t.color};
    final mitarbeiter = await _mitarbeiterService.loadMitarbeiter(companyId);
    final maMap = {for (final m in mitarbeiter.where((x) => x.active)) m.id: m};

    final result = <Map<String, dynamic>>[];
    final seenIds = <String>{};
    for (final e in eintraege.entries) {
      if ((e.value).trim().isEmpty) continue;
      final parts = e.key.split('_');
      if (parts.length != 2) continue;
      final h = int.tryParse(parts[1]);
      if (h != stunde) continue;
      final id = parts[0];
      if (seenIds.contains(id)) continue;
      seenIds.add(id);
      final m = maMap[id];
      if (m == null) continue;
      final typId = e.value.trim();
      final typName = typNameMap[typId] ?? typId;
      final typColor = typColorMap[typId];
      result.add({
        'id': id,
        'vorname': m.vorname ?? '',
        'nachname': m.nachname ?? '',
        'displayName': '${m.vorname ?? ''} ${m.nachname ?? ''}'.trim(),
        'ort': m.ort ?? '',
        'telefon': m.handynummer ?? m.telefon ?? '',
        'typId': typId,
        'typName': typName,
        'typColor': typColor,
      });
    }
    result.sort((a, b) => (a['displayName'] ?? '').toString().compareTo((b['displayName'] ?? '').toString()));
    return result;
  }

  /// IDs der verfügbaren Mitarbeiter (für Abwärtskompatibilität).
  Future<List<String>> getVerfuegbareMitarbeiterIds(
    String companyId,
    String dayId,
    int stunde,
  ) async {
    final list = await getVerfuegbareMitarbeiterMitDetails(companyId, dayId, stunde);
    return list.map((m) => m['id'] as String).toList();
  }

  /// Alle Mitglieder mit Status für Mitglieder-Status-Grid.
  /// Status aus Schichtplan für [dayId] und [stunde]: typId, typName, typColor.
  /// Nicht im Plan = rot (nicht einsatzbereit).
  Future<List<Map<String, dynamic>>> loadMitgliederStatus(
    String companyId,
    String dayId,
    int stunde, {
    bool forceServerRead = true,
  }) async {
    final eintraege = await _schichtplanNfsService.loadStundenplanEintraege(
      companyId,
      dayId,
      forceServerRead: forceServerRead,
    );
    final typen = await _schichtplanNfsService.loadBereitschaftsTypen(companyId);
    final typNameMap = {for (final t in typen) t.id: t.name};
    final typColorMap = {for (final t in typen) t.id: t.color};
    final mitarbeiter = await _mitarbeiterService.loadMitarbeiter(companyId);
    final active = mitarbeiter.where((m) => m.active).toList();
    active.sort((a, b) {
      final na = '${a.nachname ?? ''} ${a.vorname ?? ''}'.toLowerCase();
      final nb = '${b.nachname ?? ''} ${b.vorname ?? ''}'.toLowerCase();
      return na.compareTo(nb);
    });

    final statusByMa = <String, ({String typId, String typName, int? typColor})>{};
    for (final e in eintraege.entries) {
      if ((e.value).trim().isEmpty) continue;
      final parts = e.key.split('_');
      if (parts.length != 2) continue;
      final h = int.tryParse(parts[1]);
      if (h != stunde) continue;
      final id = parts[0];
      final typId = e.value.trim();
      statusByMa[id] = (
        typId: typId,
        typName: typNameMap[typId] ?? typId,
        typColor: typColorMap[typId],
      );
    }

    return active.map((m) {
      final s = statusByMa[m.id];
      return {
        'id': m.id,
        'vorname': m.vorname ?? '',
        'nachname': m.nachname ?? '',
        'displayName': '${m.vorname ?? ''} ${m.nachname ?? ''}'.trim(),
        'ort': m.ort ?? '',
        'typId': s?.typId ?? '',
        'typName': s?.typName ?? '',
        'typColor': s?.typColor,
      };
    }).toList();
  }

  /// Alle aktiven Mitarbeiter laden (für Sekundär-Auswahl).
  Future<List<Map<String, dynamic>>> loadMitarbeiter(String companyId) async {
    final list = await _mitarbeiterService.loadMitarbeiter(companyId);
    return list
        .where((m) => m.active)
        .map((m) => {
              'id': m.id,
              'vorname': m.vorname ?? '',
              'nachname': m.nachname ?? '',
              'displayName': '${m.vorname ?? ''} ${m.nachname ?? ''}'.trim(),
              'ort': m.ort ?? '',
              'telefon': m.handynummer ?? m.telefon ?? '',
            })
        .toList();
  }
}
