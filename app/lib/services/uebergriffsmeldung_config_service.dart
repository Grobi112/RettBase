import 'package:cloud_firestore/cloud_firestore.dart';

/// Konfiguration für Übergriffsmeldung – QM-Beauftragter E-Mail-Adressen
/// Firestore: kunden/{companyId}/uebergriffsmeldung/config
class UebergriffsmeldungConfigService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  static const _configPath = 'kunden/%s/uebergriffsmeldung/config';

  Future<List<String>> loadQmEmails(String companyId) async {
    try {
      final ref = _db.doc(_configPath.replaceFirst('%s', companyId));
      final snap = await ref.get();
      if (!snap.exists) return [];

      final data = snap.data();
      final emails = data?['qmBeauftragterEmails'] ?? data?['qmEmails'];
      if (emails is List) {
        return emails.map((e) => e?.toString().trim()).where((e) => e != null && e!.isNotEmpty).cast<String>().toList();
      }
      if (emails is String && emails.trim().isNotEmpty) {
        return [emails.trim()];
      }
      return [];
    } catch (_) {
      return [];
    }
  }

  Future<void> saveQmEmails(String companyId, List<String> emails) async {
    final ref = _db.doc(_configPath.replaceFirst('%s', companyId));
    await ref.set({
      'qmBeauftragterEmails': emails.where((e) => e.trim().isNotEmpty).toList(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }
}
