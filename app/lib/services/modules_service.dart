import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/app_module.dart';

/// Lädt Module für die native App (Firestore + Firmen-Freischaltung).
class ModulesService {
  final _db = FirebaseFirestore.instance;

  /// Default-Module für die native App (falls Firestore leer)
  static List<AppModule> get defaultNativeModules => [
    const AppModule(id: 'schichtanmeldung', label: 'Schichtanmeldung', url: '', order: 1),
    const AppModule(id: 'schichtuebersicht', label: 'Schichtübersicht', url: '', order: 2),
    const AppModule(id: 'fahrtenbuch', label: 'Fahrtenbuch', url: '', order: 3),
    const AppModule(id: 'fahrtenbuchuebersicht', label: 'Fahrtenbuch-Übersicht', url: '', order: 4),
    const AppModule(id: 'wachbuch', label: 'Wachbuch', url: '', order: 5),
    const AppModule(id: 'wachbuchuebersicht', label: 'Wachbuch-Übersicht', url: '', order: 6),
    const AppModule(id: 'checklisten', label: 'Checklisten', url: '', order: 7),
    const AppModule(id: 'informationssystem', label: 'Informationssystem', url: '', order: 8),
    const AppModule(id: 'einstellungen', label: 'Einstellungen', url: '', order: 9),
    const AppModule(id: 'maengelmelder', label: 'Mängelmelder', url: '', order: 10),
    const AppModule(id: 'fahrzeugmanagement', label: 'Fahrzeugmanagement', url: '', order: 11),
    const AppModule(id: 'dokumente', label: 'Dokumente', url: '', order: 12),
    const AppModule(id: 'unfallbericht', label: 'Unfallbericht', url: '', order: 13),
    const AppModule(id: 'schnittstellenmeldung', label: 'Schnittstellenmeldung', url: '', order: 14),
    const AppModule(id: 'uebergriffsmeldung', label: 'Übergriffsmeldung', url: '', order: 15),
    const AppModule(id: 'telefonliste', label: 'Telefonliste', url: '', order: 16),
    const AppModule(id: 'ssd', label: 'Notfallprotokoll SSD', url: '', order: 17),
  ];

  /// Lädt Shortcuts für die Dashboard-Kacheln (erste 6 für 2x3 Grid).
  Future<List<AppModule?>> getShortcuts(String companyId, String role) async {
    final modules = await getModulesForCompany(companyId, role);
    final list = modules.take(6).map((m) => m as AppModule?).toList();
    while (list.length < 6) {
      list.add(null);
    }
    return list;
  }

  /// Lädt alle für Firma+Rolle freigegebenen Module.
  Future<List<AppModule>> getModulesForCompany(String companyId, String role) async {
    try {
      final roleLower = role.toLowerCase().trim();
      final companyMods = await _getCompanyEnabled(companyId);
      final allMods = await _getAllModuleDefs();
      final result = <AppModule>[];

      for (final m in defaultNativeModules) {
        final enabled = companyMods[m.id] ?? true;
        if (!enabled) continue;
        final def = allMods[m.id];
        final roles = def?['roles'] as List? ?? m.roles;
        if (roles.any((r) => r.toString().toLowerCase() == roleLower)) {
          result.add(AppModule(
            id: m.id,
            label: def?['label']?.toString() ?? m.label,
            url: def?['url']?.toString() ?? m.url,
            icon: def?['icon']?.toString() ?? m.icon,
            roles: List<String>.from(roles.map((r) => r.toString())),
            order: (def?['order'] as num?)?.toInt() ?? m.order,
            active: def?['active'] != false,
          ));
        }
      }
      result.sort((a, b) => a.order.compareTo(b.order));
      return result;
    } catch (_) {
      return defaultNativeModules;
    }
  }

  Future<Map<String, bool>> _getCompanyEnabled(String companyId) async {
    try {
      final snap = await _db.collection('kunden').doc(companyId).collection('modules').get();
      return {for (final d in snap.docs) d.id: d.data()['enabled'] == true};
    } catch (_) {
      return {};
    }
  }

  Future<Map<String, Map<String, dynamic>>> _getAllModuleDefs() async {
    try {
      final snap = await _db.doc('settings/modules').collection('items').orderBy('order').get();
      return {for (final d in snap.docs) d.id: d.data()};
    } catch (_) {
      return {};
    }
  }
}
