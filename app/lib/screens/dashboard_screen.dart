import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../theme/app_theme.dart';
import '../models/app_module.dart';
import '../models/information_model.dart';
import '../models/kunde_model.dart';
import '../services/auth_service.dart';
import '../services/auth_data_service.dart';
import '../services/modules_service.dart';
import '../services/informationen_service.dart';
import '../services/kundenverwaltung_service.dart';
import '../services/menueverwaltung_service.dart';
import 'home_screen.dart';
import 'schichtanmeldung_screen.dart';
import 'schichtuebersicht_screen.dart';
import 'fahrtenbuchuebersicht_screen.dart';
import 'wachbuch_screen.dart';
import 'wachbuch_uebersicht_screen.dart';
import 'checklisten_uebersicht_screen.dart';
import 'informationssystem_screen.dart';
import 'einstellungen_screen.dart';
import 'maengelmelder_screen.dart';
import 'fleet_management_screen.dart';
import 'dokumente_screen.dart';
import 'unfallbericht_screen.dart';
import 'schnittstellenmeldung_screen.dart';
import 'uebergriffsmeldung_screen.dart';
import 'telefonliste_screen.dart';
import 'company_id_screen.dart';
import 'login_screen.dart';
import 'profile_screen.dart';
import 'placeholder_module_screen.dart';
import 'module_webview_screen.dart';
import 'kundenverwaltung_screen.dart';
import 'mitarbeiterverwaltung_screen.dart';
import 'modulverwaltung_screen.dart';
import 'menueverwaltung_screen.dart';

/// Natives Dashboard nach Login – HomeScreen mit Modul-Shortcuts.
class DashboardScreen extends StatefulWidget {
  final String companyId;

  const DashboardScreen({
    super.key,
    required this.companyId,
  });

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  final _authService = AuthService();
  final _kundenService = KundenverwaltungService();
  final _menuService = MenueverwaltungService();
  final _authDataService = AuthDataService();
  final _modulesService = ModulesService();
  final _infoService = InformationenService();
  final _bodyNavigatorKey = GlobalKey<NavigatorState>();

  List<AppModule?> _shortcuts = [];
  List<AppModule> _allModules = [];
  /// Menüstruktur aus Menüverwaltung (Oberbegriffe + Kinder) für Drawer
  List<Map<String, dynamic>> _menuStructure = [];
  String? _displayName;
  String? _vorname;
  String? _userRole;
  /// Effektive Company-ID für Firestore (authData.companyId oder widget.companyId)
  String _effectiveCompanyId = '';
  bool _loading = true;

  String get _companyId => _effectiveCompanyId.isNotEmpty ? _effectiveCompanyId : widget.companyId;

  final _containerSlotsNotifier = ValueNotifier<List<String?>>([]);
  final _infoItemsNotifier = ValueNotifier<List<Information>>([]);

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _containerSlotsNotifier.dispose();
    _infoItemsNotifier.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final user = _authService.currentUser;
    if (user == null) {
      if (mounted) _goToLogin();
      return;
    }
    debugPrint('RettBase Dashboard _load: uid=${user.uid} email=${user.email} widget.companyId=${widget.companyId}');
    try {
      final authData = await _authDataService.getAuthData(
        user.uid,
        user.email ?? '',
        widget.companyId,
      );
      debugPrint('RettBase Dashboard: authData role=${authData.role} companyId=${authData.companyId} displayName=${authData.displayName} vorname=${authData.vorname}');
      final effectiveCompanyId = authData.companyId.trim().isNotEmpty ? authData.companyId : widget.companyId;
      var allMods = await _modulesService.getModulesForCompany(effectiveCompanyId, authData.role);
      var shortcuts = await _modulesService.getShortcuts(effectiveCompanyId, authData.role);

      var menuStructure = <Map<String, dynamic>>[];
      final isAdminCompany = (effectiveCompanyId.trim().toLowerCase()) == 'admin';
      var bereich = await _kundenService.getCompanyBereich(effectiveCompanyId);
      debugPrint('RettBase Dashboard: getCompanyBereich($effectiveCompanyId)=$bereich');
      if (bereich == null || bereich.isEmpty) {
        bereich = isAdminCompany ? KundenBereich.admin : KundenBereich.rettungsdienst;
      }
      if (bereich != null && bereich.isNotEmpty) {
        menuStructure = await _menuService.loadMenuStructure(bereich);
        debugPrint('RettBase Dashboard: loadMenuStructure($bereich) -> ${menuStructure.length} items');
        if (menuStructure.isEmpty) {
          menuStructure = await _menuService.loadLegacyGlobalMenu();
          debugPrint('RettBase Dashboard: loadLegacyGlobalMenu Fallback -> ${menuStructure.length} items');
        }
        final isSuperadmin = (authData.role ?? '').toLowerCase().trim() == 'superadmin';
        if (menuStructure.isNotEmpty && !isAdminCompany && !isSuperadmin) {
          // Shortcuts auf Menü-Module beschränken (Superadmin behält alle)
          final menuModuleIds = MenueverwaltungService.extractModuleIdsFromMenu(menuStructure);
          if (menuModuleIds.isNotEmpty) {
            final shortcutList = shortcuts.whereType<AppModule>().toList();
            final filtered = shortcutList.where((m) => menuModuleIds.contains(m.id)).toList();
            if (filtered.isNotEmpty) {
              shortcuts = List<AppModule?>.from(filtered);
              while (shortcuts.length < 6) shortcuts.add(null);
              shortcuts = shortcuts.take(6).toList();
            }
          }
        }
      }

      final slots = await _loadContainerSlots(effectiveCompanyId);
      final infos = await _infoService.loadInformationen(effectiveCompanyId);

      if (!mounted) return;
      final displayName = authData.displayName?.trim().isNotEmpty == true
          ? authData.displayName
          : (user.email != null && user.email!.contains('@')
              ? user.email!.split('@').first
              : null);
      setState(() {
        _displayName = displayName ?? authData.displayName;
        _vorname = authData.vorname;
        _userRole = authData.role;
        _effectiveCompanyId = effectiveCompanyId;
        _allModules = allMods;
        _shortcuts = shortcuts;
        _menuStructure = menuStructure;
        _loading = false;
      });
      _containerSlotsNotifier.value = slots;
      _infoItemsNotifier.value = infos;
    } catch (e, st) {
      debugPrint('RettBase Dashboard _load FEHLER: $e');
      debugPrint('RettBase Dashboard _load StackTrace: $st');
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<List<String?>> _loadContainerSlots(String companyId) async {
    try {
      final ref = FirebaseFirestore.instance
          .collection('kunden')
          .doc(companyId)
          .collection('settings')
          .doc('informationssystem');
      final snap = await ref.get();
      final data = snap.data();
      final list = data?['containerSlots'] as List?;
      if (list != null && list.length >= 2) {
        return [list[0]?.toString(), list[1]?.toString()];
      }
    } catch (_) {}
    return ['informationen', 'verkehrslage'];
  }

  void _goToLogin() {
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => LoginScreen(companyId: _companyId)),
      (r) => false,
    );
  }

  void _onShortcutTap(int index) {
    if (index >= _shortcuts.length) return;
    final mod = _shortcuts[index];
    if (mod == null) return;
    _openModule(mod);
  }

  /// Zurück zum Dashboard-Home (Header bleibt sichtbar)
  void _goToHome() {
    _bodyNavigatorKey.currentState?.pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => _buildHomeContent()),
      (_) => false,
    );
  }

  Widget _buildHomeContent() {
    return HomeScreen(
      displayName: _displayName,
      vorname: _vorname,
      shortcuts: _shortcuts,
      onShortcutTap: _onShortcutTap,
      containerSlotsListenable: _containerSlotsNotifier,
      informationenItemsListenable: _infoItemsNotifier,
      companyId: _companyId,
      userRole: _userRole,
      onInfoDeleted: () async {
        final infos = await _infoService.loadInformationen(_companyId);
        if (mounted) _infoItemsNotifier.value = infos;
      },
    );
  }

  /// Öffnet Modul im Body-Bereich (Header bleibt sichtbar)
  void _openModule(AppModule mod) {
    Widget screen;
    final onBack = _goToHome;
    switch (mod.id) {
      case 'schichtanmeldung':
        screen = SchichtanmeldungScreen(
          companyId: _companyId,
          onBack: onBack,
          hideAppBar: true,
          onFahrtenbuchOpen: (v) {
            onBack();
            _openFahrtenbuch(v);
          },
        );
        break;
      case 'schichtuebersicht':
        screen = SchichtuebersichtScreen(
          companyId: _companyId,
          onBack: onBack,
        );
        break;
      case 'fahrtenbuch':
        screen = FahrtenbuchuebersichtScreen(
          companyId: _companyId,
          onBack: onBack,
        );
        break;
      case 'fahrtenbuchuebersicht':
        screen = FahrtenbuchuebersichtScreen(
          companyId: _companyId,
          onBack: onBack,
        );
        break;
      case 'wachbuch':
        screen = WachbuchScreen(
          companyId: _companyId,
          onBack: onBack,
        );
        break;
      case 'wachbuchuebersicht':
        screen = WachbuchUebersichtScreen(
          companyId: _companyId,
          onBack: onBack,
        );
        break;
      case 'checklisten':
        screen = ChecklistenUebersichtScreen(
          companyId: _companyId,
          userRole: _userRole ?? 'user',
          onBack: onBack,
        );
        break;
      case 'informationssystem':
        screen = InformationssystemScreen(
          companyId: _companyId,
          userRole: _userRole,
          onBack: onBack,
          onInfoChanged: () async {
            final infos = await _infoService.loadInformationen(_companyId);
            if (mounted) _infoItemsNotifier.value = infos;
          },
        );
        break;
      case 'einstellungen':
        screen = EinstellungenScreen(
          companyId: _companyId,
          onBack: onBack,
          onInformationssystemSaved: _load,
          hideAppBar: true,
        );
        break;
      case 'maengelmelder':
        screen = MaengelmelderScreen(
          companyId: _companyId,
          userId: _authService.currentUser?.uid ?? '',
          userRole: _userRole ?? 'user',
          onBack: onBack,
        );
        break;
      case 'fahrzeugmanagement':
        screen = FleetManagementScreen(
          companyId: _companyId,
          userRole: _userRole ?? 'user',
          onBack: onBack,
        );
        break;
      case 'dokumente':
        screen = DokumenteScreen(
          companyId: _companyId,
          userRole: _userRole,
          onBack: onBack,
        );
        break;
      case 'unfallbericht':
        screen = UnfallberichtScreen(
          companyId: _companyId,
          onBack: onBack,
        );
        break;
      case 'schnittstellenmeldung':
        screen = SchnittstellenmeldungScreen(
          companyId: _companyId,
          userRole: _userRole,
          onBack: onBack,
        );
        break;
      case 'uebergriffsmeldung':
        screen = UebergriffsmeldungScreen(
          companyId: _companyId,
          userRole: _userRole,
          onBack: onBack,
        );
        break;
      case 'telefonliste':
        screen = TelefonlisteScreen(
          companyId: _companyId,
          userRole: _userRole ?? 'user',
          currentUserUid: _authService.currentUser?.uid,
          onBack: onBack,
        );
        break;
      case 'ssd':
        screen = PlaceholderModuleScreen(
          moduleName: 'Notfallprotokoll SSD',
          onBack: onBack,
          hideAppBar: true,
        );
        break;
      case 'kundenverwaltung':
        screen = KundenverwaltungScreen(
          companyId: _companyId,
          onBack: onBack,
          hideAppBar: true,
        );
        break;
      case 'admin':
        screen = MitarbeiterverwaltungScreen(
          companyId: _companyId,
          userRole: _userRole,
          onBack: onBack,
          hideAppBar: true,
        );
        break;
      case 'modulverwaltung':
        screen = ModulverwaltungScreen(
          companyId: _companyId,
          userRole: _userRole,
          onBack: onBack,
          hideAppBar: true,
        );
        break;
      case 'menueverwaltung':
        screen = MenueverwaltungScreen(
          companyId: _companyId,
          userRole: _userRole,
          onBack: onBack,
          onMenuSaved: _load,
          hideAppBar: true,
        );
        break;
      default:
        // Fallback: Alte HTML-URLs → native Screens (verhindert 404)
        if (mod.url.contains('mitarbeiterverwaltung.html')) {
          screen = MitarbeiterverwaltungScreen(
            companyId: _companyId,
            userRole: _userRole,
            onBack: onBack,
            hideAppBar: true,
          );
        } else if (mod.url.contains('kundenverwaltung.html')) {
          screen = KundenverwaltungScreen(
            companyId: _companyId,
            onBack: onBack,
            hideAppBar: true,
          );
        } else if (mod.url.contains('modulverwaltung.html')) {
          screen = ModulverwaltungScreen(
            companyId: _companyId,
            userRole: _userRole,
            onBack: onBack,
            hideAppBar: true,
          );
        } else if (mod.url.contains('menue.html')) {
          screen = MenueverwaltungScreen(
            companyId: _companyId,
            userRole: _userRole,
            onBack: onBack,
            onMenuSaved: _load,
            hideAppBar: true,
          );
        } else if (mod.url.isNotEmpty) {
          screen = ModuleWebViewScreen(
            module: mod,
            companyId: _companyId,
            onBack: onBack,
            hideAppBar: true,
          );
        } else {
          screen = PlaceholderModuleScreen(
            moduleName: mod.label,
            onBack: onBack,
            hideAppBar: true,
          );
        }
    }
    _bodyNavigatorKey.currentState?.pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => screen),
      (_) => false,
    );
  }

  void _openFahrtenbuch(dynamic vorlage) {
    _openModule(const AppModule(id: 'fahrtenbuchuebersicht', label: 'Fahrtenbuch-Übersicht', url: '', order: 17));
  }

  Future<void> _logout() async {
    await _authService.logout();
    if (!mounted) return;
    _goToLogin();
  }

  /// Formatiert Anzeigename als "Nachname V." (z.B. Füllbeck M.)
  String get _userDisplayShort {
    final parts = _displayName?.split(', ');
    if (parts != null && parts.length >= 2 && parts[1].isNotEmpty) {
      return '${parts[0]} ${parts[1][0]}.';
    }
    return _displayName ?? _vorname ?? 'Benutzer';
  }

  IconData _drawerIconForModule(String id) {
    switch (id) {
      case 'admin': return Icons.people;
      case 'kundenverwaltung': return Icons.business;
      case 'modulverwaltung': return Icons.apps;
      case 'menueverwaltung': return Icons.menu;
      case 'schichtanmeldung':
      case 'schichtuebersicht': return Icons.calendar_today;
      case 'fahrtenbuch':
      case 'fahrtenbuchuebersicht': return Icons.directions_car;
      case 'wachbuch':
      case 'wachbuchuebersicht': return Icons.book;
      case 'checklisten': return Icons.checklist;
      case 'informationssystem': return Icons.info_outline;
      case 'maengelmelder': return Icons.build;
      case 'fahrzeugmanagement': return Icons.directions_car;
      case 'dokumente': return Icons.folder;
      case 'unfallbericht': return Icons.report;
      case 'schnittstellenmeldung': return Icons.call_split;
      case 'uebergriffsmeldung': return Icons.warning;
      case 'telefonliste': return Icons.phone;
      case 'ssd': return Icons.medical_services;
      default: return Icons.apps;
    }
  }

  void _openCustomLink(String label, String? url) {
    final u = (url ?? '').trim();
    if (u.isEmpty || u == '#') {
      _bodyNavigatorKey.currentState?.pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => PlaceholderModuleScreen(moduleName: label, onBack: _goToHome, hideAppBar: true)),
        (_) => false,
      );
    } else {
      _openModule(AppModule(id: 'custom', label: label, url: u, order: 0));
    }
  }

  /// Erstellt AppModule aus Menü-Item (für 1:1-Anzeige auch ohne Firmen-Freischaltung)
  AppModule _moduleFromMenuItem(Map<String, dynamic> item) {
    final id = (item['id'] ?? '').toString();
    final label = (item['label'] ?? id).toString();
    final url = (item['url'] ?? '').toString();
    final modById = {for (final m in _allModules) m.id: m};
    return modById[id] ?? AppModule(id: id, label: label, url: url, order: 0);
  }

  List<Widget> _buildDrawerMenuContent() {
    final children = <Widget>[];
    for (final item in _menuStructure) {
      final type = (item['type'] ?? 'module').toString();
      if (type == 'heading') {
        final label = (item['label'] ?? '').toString();
        final rawChildren = item['children'];
        final childItems = rawChildren is List ? rawChildren : <dynamic>[];
        final childTiles = <Widget>[];
        for (final c in childItems) {
          if (c is! Map) continue;
          final cType = (c['type'] ?? '').toString();
          if (cType == 'module') {
            final mod = _moduleFromMenuItem(Map<String, dynamic>.from(c));
            childTiles.add(ListTile(
              dense: true,
              leading: Icon(_drawerIconForModule(mod.id), size: 22),
              title: Text(mod.label, style: const TextStyle(fontSize: 14)),
              onTap: () {
                Navigator.pop(context);
                _openModule(mod);
              },
            ));
          } else if (cType == 'custom') {
            final cLabel = (c['label'] ?? '').toString();
            final cUrl = c['url']?.toString();
            childTiles.add(ListTile(
              dense: true,
              leading: const Icon(Icons.link, size: 22),
              title: Text(cLabel.isNotEmpty ? cLabel : 'Link', style: const TextStyle(fontSize: 14)),
              onTap: () {
                Navigator.pop(context);
                _openCustomLink(cLabel, cUrl);
              },
            ));
          }
        }
        children.add(Theme(
          data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
          child: ExpansionTile(
            initiallyExpanded: false,
            leading: const Icon(Icons.folder_outlined, size: 22),
            title: Text(label.isNotEmpty ? label : 'Oberbegriff', style: const TextStyle(fontWeight: FontWeight.w500)),
            children: childTiles.isEmpty
                ? [Padding(padding: const EdgeInsets.all(12), child: Text('Keine Unterpunkte', style: TextStyle(fontSize: 13, color: Colors.grey[600])))]
                : childTiles,
          ),
        ));
      } else if (type == 'module') {
        final mod = _moduleFromMenuItem(item);
        children.add(ListTile(
          leading: Icon(_drawerIconForModule(mod.id)),
          title: Text(mod.label),
          onTap: () {
            Navigator.pop(context);
            _openModule(mod);
          },
        ));
      } else if (type == 'custom') {
        final label = (item['label'] ?? '').toString();
        final url = item['url']?.toString();
        children.add(ListTile(
          leading: const Icon(Icons.link),
          title: Text(label.isNotEmpty ? label : 'Link'),
          onTap: () {
            Navigator.pop(context);
            _openCustomLink(label, url);
          },
        ));
      }
    }
    return children;
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(
        backgroundColor: AppTheme.surfaceBg,
        body: const Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(color: AppTheme.primary),
              SizedBox(height: 16),
              Text('Lade Dashboard…'),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: AppTheme.surfaceBg,
      drawer: Drawer(
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            DrawerHeader(
              decoration: const BoxDecoration(color: AppTheme.headerBg),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Image.asset('img/rettbase.png', height: 36, fit: BoxFit.contain),
                  if (_displayName != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      _displayName!,
                      style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w500),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ],
              ),
            ),
            ..._buildDrawerMenuContent(),
            if ((_userRole ?? '').toLowerCase().trim() == 'superadmin' &&
                (_companyId.trim().toLowerCase()) != 'admin') ...[
              const Divider(),
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 8, 16, 4),
                child: Text('Administration', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.grey)),
              ),
              ..._allModules.where((m) => ['kundenverwaltung', 'modulverwaltung', 'menueverwaltung'].contains(m.id)).map((mod) => ListTile(
                leading: Icon(_drawerIconForModule(mod.id), size: 22),
                title: Text(mod.label),
                onTap: () {
                  Navigator.pop(context);
                  _openModule(mod);
                },
              )),
            ],
            const Divider(),
            ListTile(
              leading: const Icon(Icons.person_outline),
              title: const Text('Profil'),
              onTap: () {
                Navigator.pop(context);
                _bodyNavigatorKey.currentState?.pushAndRemoveUntil(
                  MaterialPageRoute(
                    builder: (_) => ProfileScreen(
                      companyId: _companyId,
                      onBack: _goToHome,
                      onSchnellstartChanged: _load,
                      hideAppBar: true,
                    ),
                  ),
                  (_) => false,
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.settings),
              title: const Text('Einstellungen'),
              onTap: () {
                Navigator.pop(context);
                _openModule(const AppModule(id: 'einstellungen', label: 'Einstellungen', url: '', order: 9));
              },
            ),
            ListTile(
              leading: const Icon(Icons.business),
              title: const Text('Unternehmen wechseln'),
              onTap: () {
                Navigator.pop(context);
                Navigator.of(context).pushReplacement(
                  MaterialPageRoute(builder: (_) => const CompanyIdScreen()),
                );
              },
            ),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.logout),
              title: const Text('Abmelden'),
              onTap: () {
                Navigator.pop(context);
                _logout();
              },
            ),
          ],
        ),
      ),
      appBar: AppBar(
        backgroundColor: AppTheme.headerBg,
        foregroundColor: Colors.white,
        toolbarHeight: MediaQuery.of(context).size.width < 600 ? 56 : 70,
        title: GestureDetector(
          onTap: _goToHome,
          child: Image.asset(
            'img/rettbase.png',
            height: MediaQuery.of(context).size.width < 600 ? 36 : 48,
            fit: BoxFit.contain,
          ),
        ),
        actions: [
          Theme(
            data: Theme.of(context).copyWith(
              popupMenuTheme: PopupMenuThemeData(
                color: AppTheme.surfaceBg,
                surfaceTintColor: Colors.transparent,
              ),
            ),
              child: PopupMenuButton<String>(
              offset: const Offset(0, 48),
              color: AppTheme.surfaceBg,
              surfaceTintColor: Colors.transparent,
              child: Builder(
                builder: (context) {
                  final showLabel = MediaQuery.sizeOf(context).width > 360;
                  return Container(
                    margin: const EdgeInsets.only(right: 8),
                    padding: EdgeInsets.symmetric(
                      horizontal: showLabel ? 12 : 8,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: AppTheme.surfaceBg,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: AppTheme.border),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.person_outline, size: 20, color: AppTheme.textPrimary),
                        if (showLabel) ...[
                          const SizedBox(width: 8),
                          Text(
                            _userDisplayShort,
                            style: TextStyle(color: AppTheme.textPrimary, fontSize: 15, fontWeight: FontWeight.w500),
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(width: 4),
                        ],
                        Icon(Icons.arrow_drop_down, color: AppTheme.textPrimary, size: 24),
                      ],
                    ),
                  );
                },
              ),
            onSelected: (v) {
              if (v == 'profil') {
                _bodyNavigatorKey.currentState?.pushAndRemoveUntil(
                  MaterialPageRoute(
                    builder: (_) => ProfileScreen(
                      companyId: _companyId,
                      onBack: _goToHome,
                      onSchnellstartChanged: _load,
                      hideAppBar: true,
                    ),
                  ),
                  (_) => false,
                );
              } else if (v == 'einstellungen') {
                _openModule(const AppModule(id: 'einstellungen', label: 'Einstellungen', url: '', order: 9));
              } else if (v == 'company') {
                Navigator.of(context).pushReplacement(
                  MaterialPageRoute(builder: (_) => const CompanyIdScreen()),
                );
              } else if (v == 'logout') {
                _logout();
              }
            },
            itemBuilder: (_) => [
              const PopupMenuItem(value: 'profil', child: ListTile(leading: Icon(Icons.person_outline), title: Text('Profil'), contentPadding: EdgeInsets.zero)),
              const PopupMenuItem(value: 'einstellungen', child: ListTile(leading: Icon(Icons.settings), title: Text('Einstellungen'), contentPadding: EdgeInsets.zero)),
              const PopupMenuItem(value: 'company', child: ListTile(leading: Icon(Icons.business), title: Text('Unternehmen wechseln'), contentPadding: EdgeInsets.zero)),
              const PopupMenuItem(value: 'logout', child: ListTile(leading: Icon(Icons.logout), title: Text('Abmelden'), contentPadding: EdgeInsets.zero)),
            ],
          ),
          ),
        ],
      ),
      body: Navigator(
        key: _bodyNavigatorKey,
        onGenerateRoute: (_) => MaterialPageRoute(
          builder: (_) => _buildHomeContent(),
        ),
      ),
    );
  }
}
