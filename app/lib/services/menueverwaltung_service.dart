import 'package:cloud_firestore/cloud_firestore.dart';

/// Service für globale Menüverwaltung – settings/globalMenu
class MenueverwaltungService {
  final _db = FirebaseFirestore.instance;

  DocumentReference<Map<String, dynamic>> get _menuRef =>
      _db.collection('settings').doc('globalMenu');

  /// Lädt die Menüstruktur
  Future<List<Map<String, dynamic>>> loadMenuStructure() async {
    final snap = await _menuRef.get();
    if (!snap.exists) return [];
    final items = snap.data()?['items'];
    if (items is List) {
      return items.map((e) => Map<String, dynamic>.from(e as Map)).toList();
    }
    return [];
  }

  /// Speichert die Menüstruktur
  Future<void> saveMenuStructure(List<Map<String, dynamic>> items) async {
    await _menuRef.set({
      'items': items,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }
}
