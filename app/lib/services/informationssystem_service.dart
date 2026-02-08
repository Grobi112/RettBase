import 'package:cloud_firestore/cloud_firestore.dart';

/// Einstellungen für das Informationssystem
/// Firestore: kunden/{companyId}/settings/informationssystem
class InformationssystemService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  static const List<String> containerTypes = ['informationen', 'verkehrslage'];
  static const Map<String, String> containerLabels = {
    'informationen': 'Informationen',
    'verkehrslage': 'Verkehrslage',
  };

  DocumentReference<Map<String, dynamic>> _settingsRef(String companyId) =>
      _db.collection('kunden').doc(companyId).collection('settings').doc('informationssystem');

  /// Container-Reihenfolge laden (2 Slots für Hauptseite)
  Future<List<String?>> loadContainerOrder(String companyId) async {
    try {
      final snap = await _settingsRef(companyId).get();
      final data = snap.data();
      final list = data?['containerSlots'] as List?;
      if (list != null && list.length >= 2) {
        return [list[0]?.toString(), list[1]?.toString()];
      }
    } catch (_) {}
    return ['informationen', 'verkehrslage'];
  }

  /// Kategorien laden
  Future<List<String>> loadKategorien(String companyId) async {
    try {
      final snap = await _settingsRef(companyId).get();
      final data = snap.data();
      final list = data?['kategorien'] as List?;
      if (list != null) {
        return list.map((e) => e.toString()).where((s) => s.isNotEmpty).toList()..sort();
      }
    } catch (_) {}
    return [];
  }

  /// Einstellungen speichern
  Future<void> saveAll(
    String companyId, {
    required List<String?> containerSlots,
    required List<String> kategorien,
  }) async {
    await _settingsRef(companyId).set({
      'containerSlots': containerSlots,
      'kategorien': kategorien,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }
}
