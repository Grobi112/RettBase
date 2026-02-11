import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/app_module.dart';

/// Lädt Module für die native App (Firestore + Firmen-Freischaltung).
/// Firestore-Pfade nutzen immer normalisierte Kunden-ID (kleingeschrieben).
class ModulesService {
  final _db = FirebaseFirestore.instance;

  static String _normalizeCompanyId(String companyId) =>
      companyId.trim().toLowerCase();

  /// Default-Module für die native App (falls Firestore leer).
  /// Rollen möglichst breit, damit verschiedene Nutzerrollen Zugriff haben.
  static const _defaultRoles = [
    'superadmin', 'admin', 'leiterssd', 'geschaeftsfuehrung', 'rettungsdienstleitung',
    'koordinator', 'wachleitung', 'ovd', 'user', 'fahrzeugbeauftragter', 'mpg-beauftragter',
  ];

  static List<AppModule> get defaultNativeModules => [
    // Native Admin-Module (keine WebView/iframe mehr)
    AppModule(id: 'admin', label: 'Mitgliederverwaltung', url: '', order: 4, roles: ['superadmin', 'admin', 'geschaeftsfuehrung', 'rettungsdienstleitung', 'wachleitung', 'leiterssd']),
    AppModule(id: 'kundenverwaltung', label: 'Kundenverwaltung', url: '', order: 5, roles: ['superadmin']),
    AppModule(id: 'modulverwaltung', label: 'Modul-Verwaltung', url: '', order: 6, roles: ['superadmin']),
    AppModule(id: 'menueverwaltung', label: 'Menü-Verwaltung', url: '', order: 10, roles: ['superadmin']),
    // Native Module
    AppModule(id: 'schichtanmeldung', label: 'Schichtanmeldung', url: '', order: 14, roles: _defaultRoles),
    AppModule(id: 'schichtuebersicht', label: 'Schichtübersicht', url: '', order: 15, roles: _defaultRoles),
    AppModule(id: 'fahrtenbuch', label: 'Fahrtenbuch', url: '', order: 16, roles: _defaultRoles),
    AppModule(id: 'fahrtenbuchuebersicht', label: 'Fahrtenbuch-Übersicht', url: '', order: 17, roles: _defaultRoles),
    AppModule(id: 'wachbuch', label: 'Wachbuch', url: '', order: 18, roles: _defaultRoles),
    AppModule(id: 'wachbuchuebersicht', label: 'Wachbuch-Übersicht', url: '', order: 19, roles: ['superadmin', 'admin', 'geschaeftsfuehrung', 'rettungsdienstleitung', 'wachleitung', 'leiterssd']),
    AppModule(id: 'checklisten', label: 'Checklisten', url: '', order: 20, roles: _defaultRoles),
    AppModule(id: 'informationssystem', label: 'Informationssystem', url: '', order: 21, roles: ['superadmin', 'admin', 'leiterssd', 'geschaeftsfuehrung', 'rettungsdienstleitung', 'wachleitung', 'koordinator']),
    AppModule(id: 'einstellungen', label: 'Einstellungen', url: '', order: 9, roles: ['superadmin', 'admin', 'geschaeftsfuehrung', 'rettungsdienstleitung']),
    AppModule(id: 'maengelmelder', label: 'Mängelmelder', url: '', order: 22, roles: _defaultRoles),
    AppModule(id: 'fahrzeugmanagement', label: 'Fahrzeugmanagement', url: '', order: 23, roles: _defaultRoles),
    AppModule(id: 'dokumente', label: 'Dokumente', url: '', order: 24, roles: _defaultRoles),
    AppModule(id: 'unfallbericht', label: 'Unfallbericht', url: '', order: 25, roles: _defaultRoles),
    AppModule(id: 'schnittstellenmeldung', label: 'Schnittstellenmeldung', url: '', order: 26, roles: _defaultRoles),
    AppModule(id: 'uebergriffsmeldung', label: 'Übergriffsmeldung', url: '', order: 27, roles: _defaultRoles),
    AppModule(id: 'telefonliste', label: 'Telefonliste', url: '', order: 28, roles: _defaultRoles),
    AppModule(id: 'chat', label: 'Chat', url: '', order: 30, roles: _defaultRoles),
    AppModule(id: 'email', label: 'E-Mail', url: '', order: 31, roles: _defaultRoles),
    AppModule(id: 'ssd', label: 'Notfallprotokoll SSD', url: '', order: 29, roles: _defaultRoles),
  ];

  /// Lädt Shortcuts für die Dashboard-Kacheln (6 Slots).
  /// Nutzt kunden/{companyId}/settings/schnellstart falls vorhanden, sonst erste 6 Module.
  Future<List<AppModule?>> getShortcuts(String companyId, String role) async {
    final modules = await getModulesForCompany(companyId, role);
    final modById = {for (final m in modules) m.id: m};

    final custom = await _getSchnellstartSlots(companyId);
    if (custom != null) {
      final list = custom.map((id) => id != null && id.isNotEmpty ? modById[id] : null).toList();
      while (list.length < 6) list.add(null);
      return list.take(6).toList();
    }

    final list = modules.take(6).map((m) => m as AppModule?).toList();
    while (list.length < 6) list.add(null);
    return list;
  }

  /// Lädt Schnellstart-Slot-IDs für Bearbeitung (custom oder Default = erste 6 Module).
  Future<List<String?>> getSchnellstartSlotIds(String companyId, String role) async {
    final custom = await _getSchnellstartSlots(companyId);
    if (custom != null) return custom;
    final modules = await getModulesForCompany(companyId, role);
    final list = <String?>[...modules.take(6).map((m) => m.id)];
    while (list.length < 6) list.add(null);
    return list;
  }

  /// Lädt gespeicherte Schnellstart-Slots aus Firestore (intern).
  Future<List<String?>?> _getSchnellstartSlots(String companyId) async {
    try {
      final cid = _normalizeCompanyId(companyId);
      final snap = await _db
          .collection('kunden')
          .doc(cid)
          .collection('settings')
          .doc('schnellstart')
          .get();
      final list = snap.data()?['slots'] as List?;
      if (list != null && list.isNotEmpty) {
        return List.generate(6, (i) => i < list.length ? list[i]?.toString() : null);
      }
    } catch (_) {}
    return null;
  }

  /// Speichert Schnellstart-Slots in Firestore.
  Future<void> saveSchnellstartSlots(String companyId, List<String?> slotIds) async {
    final list = List.generate(6, (i) => i < slotIds.length && (slotIds[i] ?? '').isNotEmpty ? slotIds[i] : null);
    final cid = _normalizeCompanyId(companyId);
    await _db
        .collection('kunden')
        .doc(cid)
          .collection('settings')
          .doc('schnellstart')
          .set({'slots': list, 'updatedAt': FieldValue.serverTimestamp()});
  }

  /// Lädt alle für Firma+Rolle freigegebenen Module.
  /// Firestore: settings/modules/items (Definitionen), kunden/{companyId}/modules (Freischaltung).
  /// Admin-Firma: alle Module frei. Andere Firmen: nur explizit enabled.
  Future<List<AppModule>> getModulesForCompany(String companyId, String role) async {
    try {
      final cid = _normalizeCompanyId(companyId);
      final roleLower = role.toLowerCase().trim();
      final companyMods = await _getCompanyEnabled(cid);
      final allMods = await _getAllModuleDefs();
      final result = <AppModule>[];
      final isAdminCompany = cid == 'admin';
      // admin@rettbase.de = Superadmin in JEDER Firma – alle Module sichtbar
      final isGlobalSuperadmin = roleLower == 'superadmin';

      for (final m in defaultNativeModules) {
        // Admin-Firma oder Superadmin: alle Module; sonst: nur explizit enabled
        final enabled = isAdminCompany || isGlobalSuperadmin || (companyMods[m.id] == true);
        if (!enabled) continue;
        final def = allMods[m.id];
        final roles = def?['roles'] as List? ?? m.roles;
        if (roles.any((r) => r.toString().toLowerCase() == roleLower)) {
          // Native Module: url immer leer, damit nie alte HTML-URLs aus Firestore geladen werden
          final forceNative = ['admin', 'kundenverwaltung', 'modulverwaltung', 'menueverwaltung'].contains(m.id);
          result.add(AppModule(
            id: m.id,
            label: def?['label']?.toString() ?? m.label,
            url: forceNative ? '' : (def?['url']?.toString() ?? m.url),
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
      final cid = _normalizeCompanyId(companyId);
      final snap = await _db.collection('kunden').doc(cid).collection('modules').get();
      return {for (final d in snap.docs) d.id: d.data()['enabled'] == true};
    } catch (_) {
      return {};
    }
  }

  /// Lädt Modul-Definitionen aus Firestore: settings/modules/items
  Future<Map<String, Map<String, dynamic>>> _getAllModuleDefs() async {
    try {
      final snap = await _db
          .collection('settings')
          .doc('modules')
          .collection('items')
          .orderBy('order')
          .get();
      return {for (final d in snap.docs) d.id: d.data()};
    } catch (_) {
      return {};
    }
  }
}
