import 'dart:typed_data';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:firebase_storage/firebase_storage.dart';

/// Service für Profil-Daten: Laden, Speichern, Foto-Upload.
/// Nutzt kunden/{companyId}/mitarbeiter oder kunden/admin/users.
class ProfileService {
  final _db = FirebaseFirestore.instance;
  final _storage = FirebaseStorage.instance;

  /// Lädt Profil (gibt docId, data und ob aus users-Collection).
  Future<({String docId, Map<String, dynamic> data, bool fromUsers})?> loadProfile(
    String companyId,
    String uid,
    String email,
  ) async {
    try {
      // 1. Versuche mitarbeiter/doc(uid)
      var snap = await _db
          .collection('kunden')
          .doc(companyId)
          .collection('mitarbeiter')
          .doc(uid)
          .get();
      if (snap.exists && snap.data() != null) {
        return (docId: snap.id, data: snap.data()!, fromUsers: false);
      }
      // 2. Query mitarbeiter by uid
      final qUid = await _db
          .collection('kunden')
          .doc(companyId)
          .collection('mitarbeiter')
          .where('uid', isEqualTo: uid)
          .limit(1)
          .get();
      if (qUid.docs.isNotEmpty) {
        final d = qUid.docs.first;
        return (docId: d.id, data: d.data(), fromUsers: false);
      }
      // 3. Query mitarbeiter by email
      final qEmail = await _db
          .collection('kunden')
          .doc(companyId)
          .collection('mitarbeiter')
          .where('email', isEqualTo: email)
          .limit(1)
          .get();
      if (qEmail.docs.isNotEmpty) {
        final d = qEmail.docs.first;
        return (docId: d.id, data: d.data(), fromUsers: false);
      }
      // 4. Query mitarbeiter by pseudoEmail (Login kann über pseudoEmail erfolgen)
      if (email.isNotEmpty) {
        final qPseudo = await _db
            .collection('kunden')
            .doc(companyId)
            .collection('mitarbeiter')
            .where('pseudoEmail', isEqualTo: email)
            .limit(1)
            .get();
        if (qPseudo.docs.isNotEmpty) {
          final d = qPseudo.docs.first;
          return (docId: d.id, data: d.data(), fromUsers: false);
        }
      }
      // 5. Admin: users collection
      if (companyId.toLowerCase() == 'admin') {
        final userSnap = await _db.doc('kunden/admin/users/$uid').get();
        if (userSnap.exists && userSnap.data() != null) {
          return (docId: uid, data: userSnap.data()!, fromUsers: true);
        }
      }
    } catch (e, st) {
      debugPrint('ProfileService.loadProfile Fehler: $e');
      debugPrint(st.toString());
    }
    return null;
  }

  /// Speichert Profil. Erstellt Dokument falls nicht vorhanden (mit merge).
  Future<void> saveProfile(
    String companyId,
    String docId,
    bool isUsersCollection,
    Map<String, dynamic> updates,
    String uid,
  ) async {
    final clean = <String, dynamic>{};
    for (final e in updates.entries) {
      if (e.value is FieldValue) {
        clean[e.key] = e.value;
      } else if (e.value != null) {
        if (e.value is Timestamp) {
          clean[e.key] = e.value;
        } else if (e.value.toString().isNotEmpty) {
          clean[e.key] = e.value;
        }
      }
    }
    clean['updatedAt'] = FieldValue.serverTimestamp();

    if (isUsersCollection) {
      await _db.doc('kunden/admin/users/$docId').update(clean);
    } else {
      clean['uid'] = uid;
      final ref = _db.collection('kunden').doc(companyId).collection('mitarbeiter').doc(docId);
      await ref.set(clean, SetOptions(merge: true));
    }
  }

  /// Unterstützte Bildformate (alle gängigen)
  static const allowedExtensions = {
    'jpg', 'jpeg', 'png', 'gif', 'webp', 'bmp', 'tiff', 'tif', 'heic', 'ico',
  };

  static const _mimeTypes = {
    'jpg': 'image/jpeg',
    'jpeg': 'image/jpeg',
    'png': 'image/png',
    'gif': 'image/gif',
    'webp': 'image/webp',
    'bmp': 'image/bmp',
    'tiff': 'image/tiff',
    'tif': 'image/tiff',
    'heic': 'image/heic',
    'ico': 'image/x-icon',
  };

  /// Lädt Foto in Firebase Storage, gibt Download-URL zurück.
  /// Akzeptiert bytes + Dateiname (funktioniert auf Web und Mobile).
  Future<String> uploadProfilePhoto(
    String companyId,
    String uid,
    Uint8List bytes,
    String filename,
  ) async {
    var ext = filename.split('.').last.toLowerCase();
    if (ext.isEmpty || !allowedExtensions.contains(ext)) {
      ext = 'jpg';
    }
    if (ext == 'jpg') ext = 'jpeg';
    final path = 'kunden/$companyId/profile-images/$uid.$ext';
    final ref = _storage.ref().child(path);
    final contentType = _mimeTypes[ext] ?? 'image/jpeg';
    await ref.putData(
      bytes,
      SettableMetadata(contentType: contentType),
    );
    return ref.getDownloadURL();
  }

}
