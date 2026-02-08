import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import '../models/unfallbericht_model.dart';

/// Unfallbericht – Firestore kunden/{companyId}/unfallberichte
class UnfallberichtService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirebaseStorage _storage = FirebaseStorage.instance;

  static const _maxFileSizeBytes = 32 * 1024 * 1024; // 32 MB
  static const _maxFiles = 10;

  CollectionReference<Map<String, dynamic>> _col(String companyId) =>
      _db.collection('kunden').doc(companyId).collection('unfallberichte');

  /// Alle Unfallberichte streamen (neueste zuerst)
  Stream<List<Unfallbericht>> streamUnfallberichte(String companyId) {
    return _col(companyId)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((s) => s.docs.map((d) => Unfallbericht.fromFirestore(d.id, d.data())).toList());
  }

  /// Unfallbericht erstellen
  Future<String> create(String companyId, Unfallbericht u) async {
    final data = u.toFirestore();
    data['createdAt'] = FieldValue.serverTimestamp();
    final ref = await _col(companyId).add(data);
    return ref.id;
  }

  /// Unfallbericht aktualisieren
  Future<void> update(String companyId, Unfallbericht u) async {
    final data = u.toFirestore();
    await _col(companyId).doc(u.id).update(data);
  }

  /// Anhänge hochladen
  /// Pfad: kunden/{companyId}/unfallbericht-attachments/{docId}/{ts}_{i}_{name}
  Future<List<String>> uploadAnhaenge(
    String companyId,
    String docId,
    List<Uint8List> bytes,
    List<String> names,
    List<String> mimeTypes,
  ) async {
    if (bytes.isEmpty) return [];
    if (bytes.length > _maxFiles) {
      bytes = bytes.take(_maxFiles).toList();
      names = names.take(_maxFiles).toList();
      mimeTypes = mimeTypes.take(_maxFiles).toList();
    }
    final urls = <String>[];
    final ts = DateTime.now().millisecondsSinceEpoch;
    for (var i = 0; i < bytes.length; i++) {
      if (bytes[i].length > _maxFileSizeBytes) continue;
      final name = (i < names.length ? names[i] : 'anhang_$i')
          .replaceAll(RegExp(r'[^a-zA-Z0-9.-]'), '_');
      final ext = name.contains('.') ? name.split('.').last : 'jpg';
      final contentType = i < mimeTypes.length && mimeTypes[i].isNotEmpty
          ? mimeTypes[i]
          : (ext == 'pdf' ? 'application/pdf' : 'image/jpeg');
      final path = 'kunden/$companyId/unfallbericht-attachments/$docId/${ts}_${i}_$name';
      final ref = _storage.ref(path);
      await ref.putData(bytes[i], SettableMetadata(contentType: contentType));
      final url = await ref.getDownloadURL();
      urls.add(url);
    }
    return urls;
  }
}
