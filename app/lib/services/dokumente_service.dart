import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import '../models/dokumente_model.dart';

/// Service für Dokumente-Modul: Ordner, Dateien, Lesebestätigungen
class DokumenteService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirebaseStorage _storage = FirebaseStorage.instance;

  static const _folderCreateRoles = {
    'superadmin', 'admin', 'geschaeftsfuehrung', 'rettungsdienstleitung',
    'leiterssd', 'wachleitung', 'mpg-beauftragter', 'desinfektor',
  };

  bool canCreateFolders(String? role) =>
      role != null && _folderCreateRoles.contains(role.toLowerCase().trim());

  /// Lädt alle Ordner einer Firma
  Future<List<DokumenteOrdner>> loadOrdner(String companyId) async {
    try {
      final snap = await _db
          .collection('kunden')
          .doc(companyId)
          .collection('dokumente_ordner')
          .get();
      return snap.docs.map((d) => DokumenteOrdner.fromFirestore(d.id, d.data())).toList();
    } catch (_) {
      return [];
    }
  }

  /// Lädt Unterordner eines Ordners (parentId = null für Root), sortiert nach order dann name
  List<DokumenteOrdner> getChildFolders(List<DokumenteOrdner> all, String? parentId) {
    return all.where((f) => (f.parentId ?? '') == (parentId ?? '')).toList()
      ..sort((a, b) {
        final o = a.order.compareTo(b.order);
        return o != 0 ? o : a.name.compareTo(b.name);
      });
  }

  /// Ordner anlegen
  Future<String> createOrdner(String companyId, String name, String? parentId, String createdBy) async {
    final all = await loadOrdner(companyId);
    final siblings = all.where((f) => (f.parentId ?? '') == (parentId ?? '')).toList();
    final maxOrder = siblings.isEmpty ? -1 : siblings.map((f) => f.order).fold<int>(-1, (a, b) => a > b ? a : b);
    final order = maxOrder + 1;

    final ref = _db.collection('kunden').doc(companyId).collection('dokumente_ordner').doc();
    await ref.set({
      'name': name,
      'parentId': parentId,
      'companyId': companyId,
      'createdAt': FieldValue.serverTimestamp(),
      'createdBy': createdBy,
      'order': order,
    });
    return ref.id;
  }

  /// Reihenfolge eines Ordners aktualisieren
  Future<void> updateOrdnerOrder(String companyId, String folderId, int order) async {
    await _db
        .collection('kunden')
        .doc(companyId)
        .collection('dokumente_ordner')
        .doc(folderId)
        .update({'order': order});
  }

  /// Ordner löschen (nur wenn leer)
  Future<void> deleteOrdner(String companyId, String folderId) async {
    final subs = await loadOrdner(companyId);
    final hasChildren = subs.any((f) => f.parentId == folderId);
    if (hasChildren) throw Exception('Ordner enthält Unterordner');
    final docs = await loadDokumente(companyId, folderId);
    if (docs.isNotEmpty) throw Exception('Ordner enthält noch Dokumente');
    await _db.collection('kunden').doc(companyId).collection('dokumente_ordner').doc(folderId).delete();
  }

  /// Dokumente in einem Ordner laden
  Future<List<DokumenteDatei>> loadDokumente(String companyId, String folderId) async {
    try {
      final snap = await _db
          .collection('kunden')
          .doc(companyId)
          .collection('dokumente')
          .where('folderId', isEqualTo: folderId)
          .get();
      final list = snap.docs.map((d) => DokumenteDatei.fromFirestore(d.id, d.data())).toList();
      list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return list;
    } catch (_) {
      return [];
    }
  }

  /// Datei hochladen
  Future<DokumenteDatei> uploadDokument({
    required String companyId,
    required String folderId,
    required File file,
    required String priority,
    required bool lesebestaetigungNoetig,
    required String createdBy,
    required String createdByName,
  }) async {
    final fileName = file.path.split(RegExp(r'[/\\]')).last;
    final path = 'kunden/$companyId/dokumente/${DateTime.now().millisecondsSinceEpoch}_$fileName';
    final ref = _storage.ref().child(path);
    await ref.putFile(file);
    final url = await ref.getDownloadURL();

    final docRef = _db.collection('kunden').doc(companyId).collection('dokumente').doc();
    final data = DokumenteDatei(
      id: docRef.id,
      folderId: folderId,
      name: fileName,
      fileUrl: url,
      filePath: path,
      priority: priority,
      lesebestaetigungNoetig: lesebestaetigungNoetig,
      companyId: companyId,
      createdAt: DateTime.now(),
      createdBy: createdBy,
      createdByName: createdByName,
    );
    await docRef.set(data.toMap());
    return data;
  }

  /// Dokument löschen
  Future<void> deleteDokument(String companyId, String docId) async {
    final doc = await _db.collection('kunden').doc(companyId).collection('dokumente').doc(docId).get();
    if (doc.exists && doc.data() != null) {
      final path = doc.data()!['filePath']?.toString();
      if (path != null && path.isNotEmpty) {
        try {
          await _storage.ref().child(path).delete();
        } catch (_) {}
      }
    }
    await _db.collection('kunden').doc(companyId).collection('dokumente').doc(docId).delete();
    await _db.collection('kunden').doc(companyId).collection('dokumente').doc(docId).collection('gelesen').get().then((s) async {
      for (final d in s.docs) await d.reference.delete();
    });
  }

  /// Lesebestätigung: als gelesen markieren
  Future<void> markAsRead(String companyId, String docId, String userId) async {
    await _db
        .collection('kunden')
        .doc(companyId)
        .collection('dokumente')
        .doc(docId)
        .collection('gelesen')
        .doc(userId)
        .set({'at': FieldValue.serverTimestamp()});
  }

  /// Prüfen ob User das Dokument als gelesen markiert hat
  Future<bool> hasUserRead(String companyId, String docId, String userId) async {
    final snap = await _db
        .collection('kunden')
        .doc(companyId)
        .collection('dokumente')
        .doc(docId)
        .collection('gelesen')
        .doc(userId)
        .get();
    return snap.exists;
  }

  /// Alle Lesebestätigungen für ein Dokument
  Future<Map<String, DateTime>> getReadStatus(String companyId, String docId) async {
    try {
      final snap = await _db
          .collection('kunden')
          .doc(companyId)
          .collection('dokumente')
          .doc(docId)
          .collection('gelesen')
          .get();
      final map = <String, DateTime>{};
      for (final d in snap.docs) {
        final at = d.data()['at'];
        if (at is Timestamp) map[d.id] = at.toDate();
      }
      return map;
    } catch (_) {
      return {};
    }
  }
}
