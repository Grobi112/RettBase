import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/mitarbeiter_model.dart';

/// Mitarbeiter aus kunden/{companyId}/mitarbeiter
class MitarbeiterService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> _mitarbeiter(String companyId) =>
      _db.collection('kunden').doc(companyId).collection('mitarbeiter');

  CollectionReference<Map<String, dynamic>> _users(String companyId) =>
      _db.collection('kunden').doc(companyId).collection('users');

  /// Mitarbeiter als Stream
  Stream<List<Mitarbeiter>> streamMitarbeiter(String companyId) {
    return _mitarbeiter(companyId).snapshots().map((snap) {
      return snap.docs
          .map((d) => Mitarbeiter.fromFirestore(d.id, d.data()))
          .toList();
    });
  }

  /// Mitarbeiter einmalig laden.
  /// Bei companyId='admin': auch kunden/admin/users laden (Admin-Superadmins ohne Mitarb.-Eintrag).
  Future<List<Mitarbeiter>> loadMitarbeiter(String companyId) async {
    final fromMitarbeiter = await _mitarbeiter(companyId).get();
    var list = fromMitarbeiter.docs
        .map((d) => Mitarbeiter.fromFirestore(d.id, d.data()))
        .toList();

    if (companyId.toLowerCase() == 'admin') {
      final usersSnap = await _users(companyId).get();
      final uidsFromMitarbeiter = list.map((m) => m.uid).whereType<String>().toSet();
      final mitarbeiterIdsFromUsers = list.map((m) => m.id).toSet();

      for (final d in usersSnap.docs) {
        final uid = d.id;
        if (uidsFromMitarbeiter.contains(uid)) continue;
        final data = d.data();
        final mitarbeiterDocId = data['mitarbeiterDocId']?.toString();
        if (mitarbeiterDocId != null && mitarbeiterIdsFromUsers.contains(mitarbeiterDocId)) continue;

        final m = Mitarbeiter.fromUsersDoc(uid, data);
        list.add(m);
      }
    }

    return list;
  }

  /// Bestimmte Felder aktualisieren
  Future<void> updateMitarbeiterFields(
    String companyId,
    String mitarbeiterId,
    Map<String, dynamic> updates,
  ) async {
    final clean = <String, dynamic>{};
    for (final e in updates.entries) {
      if (e.value is FieldValue) {
        clean[e.key] = e.value;
      } else if (e.value != null) {
        clean[e.key] = e.value;
      } else if (e.value == null) {
        clean[e.key] = FieldValue.delete();
      }
    }
    clean['updatedAt'] = FieldValue.serverTimestamp();
    await _mitarbeiter(companyId).doc(mitarbeiterId).update(clean);
  }

  /// Prüft ob Personalnummer bereits existiert
  Future<bool> personalnummerExists(String companyId, String personalnummer, {String? excludeId}) async {
    final q = await _mitarbeiter(companyId)
        .where('personalnummer', isEqualTo: personalnummer)
        .get();
    for (final d in q.docs) {
      if (excludeId == null || d.id != excludeId) return true;
    }
    return false;
  }

  /// Prüft ob E-Mail bereits existiert (echte E-Mail, nicht pseudoEmail)
  Future<bool> emailExists(String companyId, String email, {String? excludeId}) async {
    if (email.endsWith('.rettbase.de')) return false;
    final q = await _mitarbeiter(companyId).where('email', isEqualTo: email).get();
    for (final d in q.docs) {
      if (excludeId == null || d.id != excludeId) return true;
    }
    return false;
  }

  /// Neuen Mitarbeiter anlegen
  Future<String> createMitarbeiter(String companyId, Mitarbeiter mitarbeiter) async {
    final data = mitarbeiter.toFirestore();
    data['createdAt'] = FieldValue.serverTimestamp();
    data['updatedAt'] = FieldValue.serverTimestamp();
    final name = '${mitarbeiter.nachname ?? ''}, ${mitarbeiter.vorname ?? ''}'.trim();
    if (name.isNotEmpty) data['name'] = name;
    final ref = _mitarbeiter(companyId).doc();
    await ref.set(data);
    return ref.id;
  }

  /// users-Dokument anlegen (für Login-Berechtigung)
  Future<void> setUsersDoc(String companyId, String uid, String email, String role, String mitarbeiterDocId) async {
    await _users(companyId).doc(uid).set({
      'email': email,
      'role': role,
      'companyId': companyId,
      'status': true,
      'mitarbeiterDocId': mitarbeiterDocId,
      'createdAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  /// Mitarbeiter-Dokument mit neuer UID aktualisieren
  Future<void> setMitarbeiterUid(String companyId, String mitarbeiterId, String uid) async {
    await _mitarbeiter(companyId).doc(mitarbeiterId).update({
      'uid': uid,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  /// Mitarbeiter löschen (nur Firestore; Firebase Auth muss separat bereinigt werden)
  Future<void> deleteMitarbeiter(String companyId, String mitarbeiterId) async {
    await _mitarbeiter(companyId).doc(mitarbeiterId).delete();
  }

  /// users-Dokument löschen
  Future<void> deleteUsersDoc(String companyId, String uid) async {
    await _users(companyId).doc(uid).delete();
  }

  /// users-Dokument aktualisieren (für Admin-User ohne Mitarb.-Doc)
  Future<void> updateUsersDoc(String companyId, String uid, Map<String, dynamic> updates) async {
    final clean = <String, dynamic>{};
    for (final e in updates.entries) {
      if (e.value is FieldValue) {
        clean[e.key] = e.value;
      } else if (e.value != null) {
        clean[e.key] = e.value;
      } else if (e.value == null) {
        clean[e.key] = FieldValue.delete();
      }
    }
    clean['updatedAt'] = FieldValue.serverTimestamp();
    clean['companyId'] = companyId;
    await _users(companyId).doc(uid).set(clean, SetOptions(merge: true));
  }
}
