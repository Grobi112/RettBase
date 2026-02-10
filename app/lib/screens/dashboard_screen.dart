import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../theme/app_theme.dart';
import '../models/app_module.dart';
import '../models/information_model.dart';
import '../services/auth_service.dart';
import '../services/auth_data_service.dart';
import '../services/modules_service.dart';
import '../services/informationen_service.dart';
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
  final _authDataService = AuthDataService();
  final _modulesService = ModulesService();
  final _infoService = InformationenService();
  final _bodyNavigatorKey = GlobalKey<NavigatorState>();

  List<AppModule?> _shortcuts = [];
  List<AppModule> _allModules = [];
  String? _displayName;
  String? _vorname;
  String? _userRole;
  bool _loading = true;

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
    try {
      final authData = await _authDataService.getAuthData(
        user.uid,
        user.email ?? '',
        widget.companyId,
      );
      final allMods = await _modulesService.getModulesForCompany(widget.companyId, authData.role);
      final shortcuts = await _modulesService.getShortcuts(widget.companyId, authData.role);
      final slots = await _loadContainerSlots();
      final infos = await _infoService.loadInformationen(widget.companyId);

      if (!mounted) return;
      setState(() {
        _displayName = authData.displayName;
        _vorname = authData.vorname;
        _userRole = authData.role;
        _allModules = allMods;
        _shortcuts = shortcuts;
        _loading = false;
      });
      _containerSlotsNotifier.value = slots;
      _infoItemsNotifier.value = infos;
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<List<String?>> _loadContainerSlots() async {
    try {
      final ref = FirebaseFirestore.instance
          .collection('kunden')
          .doc(widget.companyId)
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
      MaterialPageRoute(builder: (_) => LoginScreen(companyId: widget.companyId)),
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
      companyId: widget.companyId,
      userRole: _userRole,
      onInfoDeleted: () async {
        final infos = await _infoService.loadInformationen(widget.companyId);
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
          companyId: widget.companyId,
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
          companyId: widget.companyId,
          onBack: onBack,
        );
        break;
      case 'fahrtenbuch':
        screen = FahrtenbuchuebersichtScreen(
          companyId: widget.companyId,
          onBack: onBack,
        );
        break;
      case 'fahrtenbuchuebersicht':
        screen = FahrtenbuchuebersichtScreen(
          companyId: widget.companyId,
          onBack: onBack,
        );
        break;
      case 'wachbuch':
        screen = WachbuchScreen(
          companyId: widget.companyId,
          onBack: onBack,
        );
        break;
      case 'wachbuchuebersicht':
        screen = WachbuchUebersichtScreen(
          companyId: widget.companyId,
          onBack: onBack,
        );
        break;
      case 'checklisten':
        screen = ChecklistenUebersichtScreen(
          companyId: widget.companyId,
          userRole: _userRole ?? 'user',
          onBack: onBack,
        );
        break;
      case 'informationssystem':
        screen = InformationssystemScreen(
          companyId: widget.companyId,
          onBack: onBack,
        );
        break;
      case 'einstellungen':
        screen = EinstellungenScreen(
          companyId: widget.companyId,
          onBack: onBack,
          onInformationssystemSaved: _load,
          hideAppBar: true,
        );
        break;
      case 'maengelmelder':
        screen = MaengelmelderScreen(
          companyId: widget.companyId,
          userId: _authService.currentUser?.uid ?? '',
          userRole: _userRole ?? 'user',
          onBack: onBack,
        );
        break;
      case 'fahrzeugmanagement':
        screen = FleetManagementScreen(
          companyId: widget.companyId,
          userRole: _userRole ?? 'user',
          onBack: onBack,
        );
        break;
      case 'dokumente':
        screen = DokumenteScreen(
          companyId: widget.companyId,
          userRole: _userRole,
          onBack: onBack,
        );
        break;
      case 'unfallbericht':
        screen = UnfallberichtScreen(
          companyId: widget.companyId,
          onBack: onBack,
        );
        break;
      case 'schnittstellenmeldung':
        screen = SchnittstellenmeldungScreen(
          companyId: widget.companyId,
          userRole: _userRole,
          onBack: onBack,
        );
        break;
      case 'uebergriffsmeldung':
        screen = UebergriffsmeldungScreen(
          companyId: widget.companyId,
          userRole: _userRole,
          onBack: onBack,
        );
        break;
      case 'telefonliste':
        screen = TelefonlisteScreen(
          companyId: widget.companyId,
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
          companyId: widget.companyId,
          onBack: onBack,
          hideAppBar: true,
        );
        break;
      case 'admin':
        screen = MitarbeiterverwaltungScreen(
          companyId: widget.companyId,
          userRole: _userRole,
          onBack: onBack,
          hideAppBar: true,
        );
        break;
      case 'modulverwaltung':
        screen = ModulverwaltungScreen(
          companyId: widget.companyId,
          userRole: _userRole,
          onBack: onBack,
          hideAppBar: true,
        );
        break;
      case 'menueverwaltung':
        screen = MenueverwaltungScreen(
          companyId: widget.companyId,
          userRole: _userRole,
          onBack: onBack,
          hideAppBar: true,
        );
        break;
      default:
        // Fallback: Alte HTML-URLs → native Screens (verhindert 404)
        if (mod.url.contains('mitarbeiterverwaltung.html')) {
          screen = MitarbeiterverwaltungScreen(
            companyId: widget.companyId,
            userRole: _userRole,
            onBack: onBack,
            hideAppBar: true,
          );
        } else if (mod.url.contains('kundenverwaltung.html')) {
          screen = KundenverwaltungScreen(
            companyId: widget.companyId,
            onBack: onBack,
            hideAppBar: true,
          );
        } else if (mod.url.contains('modulverwaltung.html')) {
          screen = ModulverwaltungScreen(
            companyId: widget.companyId,
            userRole: _userRole,
            onBack: onBack,
            hideAppBar: true,
          );
        } else if (mod.url.contains('menue.html')) {
          screen = MenueverwaltungScreen(
            companyId: widget.companyId,
            userRole: _userRole,
            onBack: onBack,
            hideAppBar: true,
          );
        } else if (mod.url.isNotEmpty) {
          screen = ModuleWebViewScreen(
            module: mod,
            companyId: widget.companyId,
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
            ListTile(
              leading: const Icon(Icons.home),
              title: const Text('Dashboard'),
              onTap: () {
                Navigator.pop(context);
                _goToHome();
              },
            ),
            ..._allModules.map((mod) => ListTile(
              leading: Icon(_drawerIconForModule(mod.id)),
              title: Text(mod.label),
              onTap: () {
                Navigator.pop(context);
                _openModule(mod);
              },
            )),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.person_outline),
              title: const Text('Profil'),
              onTap: () {
                Navigator.pop(context);
                _bodyNavigatorKey.currentState?.pushAndRemoveUntil(
                  MaterialPageRoute(
                    builder: (_) => ProfileScreen(
                      companyId: widget.companyId,
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
                      companyId: widget.companyId,
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
