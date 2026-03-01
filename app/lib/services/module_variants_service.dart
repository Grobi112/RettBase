import 'package:cloud_firestore/cloud_firestore.dart';

/// Service für Modul-Varianten pro Kunde (z.B. Fahrtenbuch V1 vs. V2).
/// Firestore: kunden/{companyId}/settings/moduleVariants
class ModuleVariantsService {
  final _db = FirebaseFirestore.instance;

  static String _normalizeCompanyId(String companyId) =>
      companyId.trim().toLowerCase();

  DocumentReference<Map<String, dynamic>> _ref(String companyId) =>
      _db
          .collection('kunden')
          .doc(_normalizeCompanyId(companyId))
          .collection('settings')
          .doc('moduleVariants');

  /// Lädt die Variante eines Moduls für einen Kunden.
  /// Rückgabe: 'v1' | 'v2' | null (null = V1 als Standard)
  Future<String?> getModuleVariant(String companyId, String moduleId) async {
    if (companyId.isEmpty || moduleId.isEmpty) return null;
    try {
      final snap = await _ref(companyId).get();
      final data = snap.data();
      final value = data?[moduleId]?.toString().trim().toLowerCase();
      if (value == 'v2') return 'v2';
      return null; // v1 oder fehlend = Standard
    } catch (_) {
      return null;
    }
  }

  /// Lädt alle Modul-Varianten für einen Kunden.
  Future<Map<String, String>> getModuleVariants(String companyId) async {
    if (companyId.isEmpty) return {};
    try {
      final snap = await _ref(companyId).get();
      final data = snap.data();
      if (data == null) return {};
      return data.map((k, v) => MapEntry(k, (v?.toString() ?? '').trim().toLowerCase()));
    } catch (_) {
      return {};
    }
  }

  /// Speichert die Variante eines Moduls.
  Future<void> setModuleVariant(
    String companyId,
    String moduleId,
    String? variant,
  ) async {
    if (companyId.isEmpty || moduleId.isEmpty) return;
    final ref = _ref(companyId);
    if (variant == null || variant.trim().isEmpty || variant.toLowerCase() == 'v1') {
      await ref.set({moduleId: 'v1'}, SetOptions(merge: true));
    } else {
      await ref.set({moduleId: variant.trim().toLowerCase()}, SetOptions(merge: true));
    }
  }

  /// Speichert alle Modul-Varianten.
  Future<void> setModuleVariants(
    String companyId,
    Map<String, String> variants,
  ) async {
    if (companyId.isEmpty) return;
    final normalized = variants.map((k, v) => MapEntry(
      k,
      (v.trim().toLowerCase().isEmpty || v == 'v1') ? 'v1' : v.trim().toLowerCase(),
    ));
    await _ref(companyId).set(normalized, SetOptions(merge: true));
  }
}
