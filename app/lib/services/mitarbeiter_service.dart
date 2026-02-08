import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/mitarbeiter_model.dart';

/// Mitarbeiter aus kunden/{companyId}/mitarbeiter
class MitarbeiterService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> _mitarbeiter(String companyId) =>
      _db.collection('kunden').doc(companyId).collection('mitarbeiter');

  /// Mitarbeiter als Stream
  Stream<List<Mitarbeiter>> streamMitarbeiter(String companyId) {
    return _mitarbeiter(companyId).snapshots().map((snap) {
      return snap.docs
          .map((d) => Mitarbeiter.fromFirestore(d.id, d.data()))
          .toList();
    });
  }

  /// Mitarbeiter einmalig laden
  Future<List<Mitarbeiter>> loadMitarbeiter(String companyId) async {
    final snap = await _mitarbeiter(companyId).get();
    return snap.docs
        .map((d) => Mitarbeiter.fromFirestore(d.id, d.data()))
        .toList();
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
}
