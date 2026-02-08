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

  List<AppModule?> _shortcuts = [];
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
      final shortcuts = await _modulesService.getShortcuts(widget.companyId, authData.role);
      final slots = await _loadContainerSlots();
      final infos = await _infoService.loadInformationen(widget.companyId);

      if (!mounted) return;
      setState(() {
        _displayName = authData.displayName;
        _vorname = authData.vorname;
        _userRole = authData.role;
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

  void _openModule(AppModule mod) {
    final ctx = context;
    Widget screen;
    switch (mod.id) {
      case 'schichtanmeldung':
        screen = SchichtanmeldungScreen(
          companyId: widget.companyId,
          onBack: () => Navigator.of(ctx).pop(),
          onFahrtenbuchOpen: (v) {
            Navigator.of(ctx).pop();
            _openFahrtenbuch(v);
          },
        );
        break;
      case 'schichtuebersicht':
        screen = SchichtuebersichtScreen(
          companyId: widget.companyId,
          onBack: () => Navigator.of(ctx).pop(),
        );
        break;
      case 'fahrtenbuch':
        screen = FahrtenbuchuebersichtScreen(
          companyId: widget.companyId,
          onBack: () => Navigator.of(ctx).pop(),
        );
        break;
      case 'fahrtenbuchuebersicht':
        screen = FahrtenbuchuebersichtScreen(
          companyId: widget.companyId,
          onBack: () => Navigator.of(ctx).pop(),
        );
        break;
      case 'wachbuch':
        screen = WachbuchScreen(
          companyId: widget.companyId,
          onBack: () => Navigator.of(ctx).pop(),
        );
        break;
      case 'wachbuchuebersicht':
        screen = WachbuchUebersichtScreen(
          companyId: widget.companyId,
          onBack: () => Navigator.of(ctx).pop(),
        );
        break;
      case 'checklisten':
        screen = ChecklistenUebersichtScreen(
          companyId: widget.companyId,
          userRole: _userRole ?? 'user',
          onBack: () => Navigator.of(ctx).pop(),
        );
        break;
      case 'informationssystem':
        screen = InformationssystemScreen(
          companyId: widget.companyId,
          onBack: () => Navigator.of(ctx).pop(),
        );
        break;
      case 'einstellungen':
        screen = EinstellungenScreen(
          companyId: widget.companyId,
          onBack: () => Navigator.of(ctx).pop(),
          onInformationssystemSaved: _load,
        );
        break;
      case 'maengelmelder':
        screen = MaengelmelderScreen(
          companyId: widget.companyId,
          userId: _authService.currentUser?.uid ?? '',
          userRole: _userRole ?? 'user',
          onBack: () => Navigator.of(ctx).pop(),
        );
        break;
      case 'fahrzeugmanagement':
        screen = FleetManagementScreen(
          companyId: widget.companyId,
          userRole: _userRole ?? 'user',
          onBack: () => Navigator.of(ctx).pop(),
        );
        break;
      case 'dokumente':
        screen = DokumenteScreen(
          companyId: widget.companyId,
          userRole: _userRole,
          onBack: () => Navigator.of(ctx).pop(),
        );
        break;
      case 'unfallbericht':
        screen = UnfallberichtScreen(
          companyId: widget.companyId,
          onBack: () => Navigator.of(ctx).pop(),
        );
        break;
      case 'schnittstellenmeldung':
        screen = SchnittstellenmeldungScreen(
          companyId: widget.companyId,
          userRole: _userRole,
          onBack: () => Navigator.of(ctx).pop(),
        );
        break;
      case 'uebergriffsmeldung':
        screen = UebergriffsmeldungScreen(
          companyId: widget.companyId,
          userRole: _userRole,
          onBack: () => Navigator.of(ctx).pop(),
        );
        break;
      case 'telefonliste':
        screen = TelefonlisteScreen(
          companyId: widget.companyId,
          userRole: _userRole ?? 'user',
          currentUserUid: _authService.currentUser?.uid,
          onBack: () => Navigator.of(ctx).pop(),
        );
        break;
      case 'ssd':
        screen = PlaceholderModuleScreen(
          moduleName: 'Notfallprotokoll SSD',
          onBack: () => Navigator.of(ctx).pop(),
        );
        break;
      default:
        screen = PlaceholderModuleScreen(
          moduleName: mod.label,
          onBack: () => Navigator.of(ctx).pop(),
        );
    }
    Navigator.of(ctx).push(MaterialPageRoute(builder: (_) => screen));
  }

  void _openFahrtenbuch(dynamic vorlage) {
    // FahrtenbuchScreen braucht FahrtenbuchVorlage – Placeholder oder Übersicht
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => FahrtenbuchuebersichtScreen(
          companyId: widget.companyId,
          onBack: () => Navigator.of(context).pop(),
        ),
      ),
    );
  }

  Future<void> _logout() async {
    await _authService.logout();
    if (!mounted) return;
    _goToLogin();
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
              onTap: () => Navigator.pop(context),
            ),
            ListTile(
              leading: const Icon(Icons.person_outline),
              title: const Text('Profil'),
              onTap: () {
                Navigator.pop(context);
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => ProfileScreen(
                      companyId: widget.companyId,
                      onBack: () => Navigator.of(context).pop(),
                    ),
                  ),
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
        toolbarHeight: 70,
        title: Image.asset(
          'img/rettbase.png',
          height: 48,
          fit: BoxFit.contain,
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _load,
            tooltip: 'Aktualisieren',
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert),
            onSelected: (v) {
              if (v == 'profil') {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => ProfileScreen(
                      companyId: widget.companyId,
                      onBack: () => Navigator.of(context).pop(),
                    ),
                  ),
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
        ],
      ),
      body: HomeScreen(
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
      ),
    );
  }
}
