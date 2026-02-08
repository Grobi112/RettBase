import 'package:cloud_firestore/cloud_firestore.dart';

/// Speichert die Menüreihenfolge im Mängelmelder für Admins/Geschäftsführung/Rettungsdienstleitung
/// Pfad: kunden/{companyId}/users/{uid}/maengelmelder/config
class MaengelmelderConfigService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  static const List<String> defaultOrder = [
    'fahrzeugmangel',
    'mpg-mangel',
    'digitalfunk',
    'sonstiger-mangel',
    'schnittstellenmeldung',
    'uebergriffsmeldung',
  ];

  Future<List<String>> loadMenuOrder(String companyId, String uid) async {
    try {
      final ref = _db.doc('kunden/$companyId/users/$uid/maengelmelder/config');
      final snap = await ref.get();
      if (!snap.exists) return List.from(defaultOrder);

      final data = snap.data();
      final order = data?['menuOrder'];
      if (order is! List) return List.from(defaultOrder);

      final ids = order.map((e) => e?.toString()).whereType<String>().toList();
      final result = <String>[];
      for (final id in ids) {
        if (defaultOrder.contains(id) && !result.contains(id)) result.add(id);
      }
      for (final id in defaultOrder) {
        if (!result.contains(id)) result.add(id);
      }
      return result;
    } catch (_) {
      return List.from(defaultOrder);
    }
  }

  Future<void> saveMenuOrder(String companyId, String uid, List<String> order) async {
    final ref = _db.doc('kunden/$companyId/users/$uid/maengelmelder/config');
    await ref.set({
      'menuOrder': order,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }
}
