import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import '../theme/app_theme.dart';
import '../services/chat_service.dart';
import '../models/app_module.dart';
import '../models/information_model.dart';
import '../models/kunde_model.dart';
import '../services/auth_service.dart';
import '../services/auth_data_service.dart';
import '../services/modules_service.dart';
import '../services/informationen_service.dart';
import '../services/kundenverwaltung_service.dart';
import '../services/menueverwaltung_service.dart';
import '../services/push_notification_service.dart';
import '../app_config.dart';
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
import 'chat_screen.dart';
import 'company_id_screen.dart';
import 'login_screen.dart';
import 'profile_screen.dart';
import 'einsatzprotokoll_ssd_screen.dart';
import 'schichtplan_nfs_screen.dart';
import 'telefonliste_nfs_screen.dart';
import 'placeholder_module_screen.dart';
import 'module_webview_screen.dart';
import 'kundenverwaltung_screen.dart';
import 'mitarbeiterverwaltung_screen.dart';
import 'modulverwaltung_screen.dart';
import 'menueverwaltung_screen.dart';
import 'package:app/utils/url_hash_stub.dart'
    if (dart.library.html) 'package:app/utils/url_hash_web.dart' as url_hash;
import 'package:app/utils/visibility_refresh_stub.dart'
    if (dart.library.html) 'package:app/utils/visibility_refresh_web.dart' as visibility_refresh;

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
  final _chatService = ChatService();
  final _bodyNavigatorKey = GlobalKey<NavigatorState>();

  final _chatUnreadNotifier = ValueNotifier<int>(0);
  StreamSubscription<int>? _chatUnreadSub;
  Timer? _badgePollTimer;

  List<AppModule?> _shortcuts = [];
  List<AppModule> _allModules = [];
  /// Menüstruktur aus Menüverwaltung (Oberbegriffe + Kinder) für Drawer
  List<Map<String, dynamic>> _menuStructure = [];
  String? _displayName;
  String? _vorname;
  String? _userRole;
  /// Effektive Company-ID für Firestore (authData.companyId oder widget.companyId)
  String _effectiveCompanyId = '';
  /// Bereich des Kunden (z.B. schulsanitaetsdienst) für bereichsspezifische UI
  String? _bereich;
  bool _loading = true;

  String get _companyId => _effectiveCompanyId.isNotEmpty ? _effectiveCompanyId : widget.companyId;

  final _containerSlotsNotifier = ValueNotifier<List<String?>>([]);
  final _infoItemsNotifier = ValueNotifier<List<Information>>([]);

  @override
  void initState() {
    super.initState();
    _load();
    _chatUnreadNotifier.addListener(_onChatUnreadChanged);
    if (kIsWeb) {
      visibility_refresh.setOnVisible(() {
        if (mounted) _restartChatUnreadListener();
      });
    }
  }

  void _onChatUnreadChanged() {
    final count = _chatUnreadNotifier.value;
    if (kIsWeb) debugPrint('RettBase Badge: _onChatUnreadChanged count=$count');
    setState(() {});
    PushNotificationService.updateBadge(count);
  }

  void _restartChatUnreadListener() {
    _chatUnreadSub?.cancel();
    _chatUnreadSub = null;
    _startChatUnreadListener();
  }

  void _startChatUnreadListener() {
    _chatUnreadSub?.cancel();
    _chatUnreadSub = null;
    _badgePollTimer?.cancel();
    _badgePollTimer = null;
    final cid = _effectiveCompanyId.isNotEmpty ? _effectiveCompanyId : widget.companyId;
    if (cid.isEmpty) return;
    if (kIsWeb) debugPrint('RettBase Badge: starte streamUnreadCount für companyId=$cid');
    _chatUnreadSub = _chatService.streamUnreadCount(cid).listen(
      (count) {
        if (kIsWeb) debugPrint('RettBase Badge: stream emit count=$count');
        if (mounted) _chatUnreadNotifier.value = count;
      },
      onError: (e) {
        debugPrint('RettBase Badge: stream Fehler: $e');
        _chatUnreadSub?.cancel();
        _chatUnreadSub = null;
        if (mounted) _chatUnreadNotifier.value = 0;
      },
    );
    if (kIsWeb) {
      _badgePollTimer = Timer.periodic(const Duration(seconds: 3), (_) async {
        if (!mounted || cid.isEmpty) return;
        final count = await _chatService.getUnreadCount(cid);
        if (mounted) {
          _chatUnreadNotifier.value = count;
        }
      });
    }
  }

  void _maybeOpenChatFromNotification(String companyId) {
    final chat = PushNotificationService.initialChatFromNotification;
    if (chat == null) return;
    if (chat.$1 != companyId) return;
    if (!mounted) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _bodyNavigatorKey.currentState?.push(
        MaterialPageRoute(
          builder: (_) => ChatScreen(companyId: companyId, initialChatId: chat.$2, onBack: _goToHome, hideAppBar: true),
        ),
      );
    });
  }

  @override
  void dispose() {
    _chatUnreadNotifier.removeListener(_onChatUnreadChanged);
    _chatUnreadNotifier.dispose();
    _chatUnreadSub?.cancel();
    _badgePollTimer?.cancel();
    _containerSlotsNotifier.dispose();
    _infoItemsNotifier.dispose();
    super.dispose();
  }

  Future<void> _load({bool forceMenuServerRead = false}) async {
    setState(() => _loading = true);
    final user = _authService.currentUser;
    if (user == null) {
      if (mounted) _goToLogin();
      return;
    }
    debugPrint('RettBase Dashboard _load: uid=${user.uid} email=${user.email} widget.companyId=${widget.companyId}');
    try {
      try {
        await FirebaseFunctions.instanceFor(region: 'europe-west1')
            .httpsCallable('ensureUsersDoc')
            .call({'companyId': widget.companyId});
        await user.getIdToken(true);
      } catch (_) {}
      final authData = await _authDataService.getAuthData(
        user.uid,
        user.email ?? '',
        widget.companyId,
      );
      debugPrint('RettBase Dashboard: authData role=${authData.role} companyId=${authData.companyId} displayName=${authData.displayName} vorname=${authData.vorname}');
      if (authData.role == 'guest' && authData.uid != null) {
        debugPrint('RettBase Dashboard: Nutzer nicht in Mitarbeiterverwaltung -> Abmelden');
        await _authService.logout();
        if (!mounted) return;
        _goToLogin();
        return;
      }
      final effectiveCompanyId = authData.companyId.trim().isNotEmpty ? authData.companyId : widget.companyId;
      // Token im Hintergrund speichern – darf Dashboard-Lade nicht blockieren (getToken kann auf Web hängen)
      unawaited(PushNotificationService().saveToken(effectiveCompanyId, user.uid));
      var bereich = await _kundenService.getCompanyBereich(effectiveCompanyId);
      final isAdminCompany = (effectiveCompanyId.trim().toLowerCase()) == 'admin';
      if (bereich == null || bereich.isEmpty) {
        bereich = isAdminCompany ? KundenBereich.admin : KundenBereich.rettungsdienst;
      }
      var allMods = await _modulesService.getModulesForCompany(effectiveCompanyId, authData.role, bereich: bereich);

      var menuStructure = <Map<String, dynamic>>[];
      debugPrint('RettBase Dashboard: getCompanyBereich($effectiveCompanyId)=$bereich');
      if (bereich != null && bereich.isNotEmpty) {
        menuStructure = await _menuService.loadMenuStructure(bereich, forceServerRead: forceMenuServerRead);
        debugPrint('RettBase Dashboard: loadMenuStructure($bereich) -> ${menuStructure.length} items');
        if (menuStructure.isEmpty) {
          menuStructure = await _menuService.loadLegacyGlobalMenu(forceServerRead: forceMenuServerRead);
          debugPrint('RettBase Dashboard: loadLegacyGlobalMenu Fallback -> ${menuStructure.length} items');
        }
        // Admin-Bereich: wenn Menü leer, Fallback auf Notfallseelsorge und Rettungsdienst
        if (menuStructure.isEmpty && (bereich == KundenBereich.admin || isAdminCompany)) {
          for (final fallbackBereich in [KundenBereich.notfallseelsorge, KundenBereich.rettungsdienst]) {
            menuStructure = await _menuService.loadMenuStructure(fallbackBereich, forceServerRead: forceMenuServerRead);
            if (menuStructure.isNotEmpty) {
              debugPrint('RettBase Dashboard: Admin-Fallback loadMenuStructure($fallbackBereich) -> ${menuStructure.length} items');
              break;
            }
          }
        }
      }

      // Menü-Module auch für _allModules ergänzen – sonst erscheinen sie im Drawer nicht
      // (z.B. Chat unter Notfallseelsorge, wenn noch nicht explizit in kunden/modules freigeschaltet)
      final menuModuleIds = MenueverwaltungService.extractModuleIdsFromMenu(menuStructure);
      final modIds = allMods.map((m) => m.id).toSet();
      final roleLower = authData.role.toLowerCase().trim();
      for (final id in menuModuleIds) {
        if (id.isEmpty || modIds.contains(id)) continue;
        for (final m in ModulesService.defaultNativeModules) {
          if (m.id == id && m.roles.any((r) => r.toLowerCase() == roleLower)) {
            allMods = [...allMods, m];
            modIds.add(id);
            break;
          }
        }
      }
      allMods.sort((a, b) => a.order.compareTo(b.order));

      // Schnellstart: Alle für Rolle und Bereich freigegebenen Module anzeigen.
      // Bei gespeicherter Nutzerauswahl (6 Slots): nur diese anzeigen.
      // menuModuleIds nutzen, damit auch im Menü sichtbare Module (z.B. Chat) in Slots auflösbar sind.
      final hasCustomSchnellstart = await _modulesService.hasCustomSchnellstart(effectiveCompanyId);
      List<AppModule?> shortcuts = hasCustomSchnellstart
          ? await _modulesService.getShortcuts(effectiveCompanyId, authData.role, bereich: bereich, menuModuleIds: menuModuleIds)
          : allMods.map((m) => m as AppModule?).toList();
      // Menü-Titel (benutzerdefinierter Label) auf Shortcuts anwenden
      final menuLabels = MenueverwaltungService.extractModuleLabelsFromMenu(menuStructure);
      if (menuLabels.isNotEmpty) {
        shortcuts = shortcuts.map((m) {
          if (m == null) return null;
          final customLabel = menuLabels[m.id];
          if (customLabel == null) return m;
          return AppModule(
            id: m.id,
            label: customLabel,
            url: m.url,
            icon: m.icon,
            roles: m.roles,
            order: m.order,
            active: m.active,
            submenu: m.submenu,
          );
        }).toList();
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
        _bereich = bereich;
        _allModules = allMods;
        _shortcuts = shortcuts;
        _menuStructure = menuStructure;
        _loading = false;
      });
      _containerSlotsNotifier.value = slots;
      _infoItemsNotifier.value = infos;
      _startChatUnreadListener();
      if (kIsWeb) {
        final h = url_hash.getInitialHash();
        PushNotificationService.setInitialChatFromHash(h);
        if (h != null && h.startsWith('#chat/')) url_hash.clearHash();
      }
      _maybeOpenChatFromNotification(effectiveCompanyId);
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
      final validOrder = _parseContainerTypeOrder(data);
      final list = data?['containerSlots'] as List?;
      if (list != null && list.isNotEmpty) {
        final validSet = validOrder.isNotEmpty ? validOrder.toSet() : null;
        final slots = <String?>[];
        for (var i = 0; i < list.length && i < 2; i++) {
          final s = list[i]?.toString();
          if (s != null && s.trim().isNotEmpty) {
            if (validSet == null || validSet.contains(s)) {
              slots.add(s);
            }
          } else {
            slots.add(null);
          }
        }
        while (slots.length < 2) slots.add(null);
        return slots;
      }
      // Default: nur Typen aus containerTypeOrder nutzen, nicht hart verdrahtet
      if (validOrder.isNotEmpty) {
        return [validOrder.first, validOrder.length > 1 ? validOrder[1] : null];
      }
    } catch (_) {}
    return ['informationen', 'verkehrslage'];
  }

  List<String> _parseContainerTypeOrder(Map<String, dynamic>? data) {
    final list = data?['containerTypeOrder'] as List?;
    if (list != null && list.isNotEmpty) {
      return list.map((e) => e.toString()).where((s) => s.trim().isNotEmpty).toList();
    }
    final types = data?['containerTypes'] as List?;
    if (types != null && types.isNotEmpty) {
      return types
          .map((e) => (e is Map ? e['id']?.toString() : null))
          .whereType<String>()
          .where((s) => s.trim().isNotEmpty)
          .toList();
    }
    return [];
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
      chatUnreadListenable: _chatUnreadNotifier,
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
          title: mod.label,
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
          title: mod.label,
          onBack: onBack,
        );
        break;
      case 'fahrtenbuch':
        screen = FahrtenbuchuebersichtScreen(
          companyId: _companyId,
          title: mod.label,
          onBack: onBack,
        );
        break;
      case 'fahrtenbuchuebersicht':
        screen = FahrtenbuchuebersichtScreen(
          companyId: _companyId,
          title: mod.label,
          onBack: onBack,
        );
        break;
      case 'wachbuch':
        screen = WachbuchScreen(
          companyId: _companyId,
          title: mod.label,
          onBack: onBack,
        );
        break;
      case 'wachbuchuebersicht':
        screen = WachbuchUebersichtScreen(
          companyId: _companyId,
          title: mod.label,
          onBack: onBack,
        );
        break;
      case 'checklisten':
        screen = ChecklistenUebersichtScreen(
          companyId: _companyId,
          userRole: _userRole ?? 'user',
          title: mod.label,
          onBack: onBack,
        );
        break;
      case 'informationssystem':
        screen = InformationssystemScreen(
          companyId: _companyId,
          userRole: _userRole,
          title: mod.label,
          onBack: onBack,
          onInfoChanged: () async {
            final infos = await _infoService.loadInformationen(_companyId);
            if (mounted) _infoItemsNotifier.value = infos;
          },
          onContainerTypesChanged: () async {
            final slots = await _loadContainerSlots(_companyId);
            if (mounted) _containerSlotsNotifier.value = slots;
          },
        );
        break;
      case 'einstellungen':
        screen = EinstellungenScreen(
          companyId: _companyId,
          bereich: _bereich,
          title: mod.label,
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
          title: mod.label,
          onBack: onBack,
        );
        break;
      case 'fahrzeugmanagement':
        screen = FleetManagementScreen(
          companyId: _companyId,
          userRole: _userRole ?? 'user',
          title: mod.label,
          onBack: onBack,
        );
        break;
      case 'dokumente':
        screen = DokumenteScreen(
          companyId: _companyId,
          userRole: _userRole,
          title: mod.label,
          onBack: onBack,
        );
        break;
      case 'unfallbericht':
        screen = UnfallberichtScreen(
          companyId: _companyId,
          title: mod.label,
          onBack: onBack,
        );
        break;
      case 'schnittstellenmeldung':
        screen = SchnittstellenmeldungScreen(
          companyId: _companyId,
          userRole: _userRole,
          title: mod.label,
          onBack: onBack,
        );
        break;
      case 'uebergriffsmeldung':
        screen = UebergriffsmeldungScreen(
          companyId: _companyId,
          userRole: _userRole,
          title: mod.label,
          onBack: onBack,
        );
        break;
      case 'telefonliste':
        screen = TelefonlisteScreen(
          companyId: _companyId,
          userRole: _userRole ?? 'user',
          currentUserUid: _authService.currentUser?.uid,
          title: mod.label,
          onBack: onBack,
        );
        break;
      case 'chat':
        screen = ChatScreen(
          companyId: _companyId,
          title: mod.label,
          onBack: onBack,
          hideAppBar: true,
        );
        break;
      case 'ssd':
        screen = EinsatzprotokollSsdScreen(
          companyId: _companyId,
          onBack: onBack,
        );
        break;
      case 'schichtplannfs':
        screen = SchichtplanNfsScreen(
          companyId: _companyId,
          userRole: _userRole,
          title: mod.label,
          onBack: onBack,
        );
        break;
      case 'telefonlistenfs':
        screen = TelefonlisteNfsScreen(
          companyId: _companyId,
          userRole: _userRole ?? 'user',
          title: mod.label,
          onBack: onBack,
        );
        break;
      case 'kundenverwaltung':
        screen = KundenverwaltungScreen(
          companyId: _companyId,
          title: mod.label,
          onBack: onBack,
          hideAppBar: true,
        );
        break;
      case 'admin':
        screen = MitarbeiterverwaltungScreen(
          companyId: _companyId,
          userRole: _userRole,
          title: mod.label,
          onBack: onBack,
          hideAppBar: true,
        );
        break;
      case 'modulverwaltung':
        screen = ModulverwaltungScreen(
          companyId: _companyId,
          userRole: _userRole,
          title: mod.label,
          onBack: onBack,
          hideAppBar: true,
        );
        break;
      case 'menueverwaltung':
        screen = MenueverwaltungScreen(
          companyId: _companyId,
          userRole: _userRole,
          title: mod.label,
          onBack: onBack,
          onMenuSaved: () => _load(forceMenuServerRead: true),
          hideAppBar: true,
        );
        break;
      default:
        // Fallback: Alte HTML-URLs → native Screens (verhindert 404)
        if (mod.url.contains('mitarbeiterverwaltung.html')) {
          screen = MitarbeiterverwaltungScreen(
            companyId: _companyId,
            userRole: _userRole,
            title: mod.label,
            onBack: onBack,
            hideAppBar: true,
          );
        } else if (mod.url.contains('kundenverwaltung.html')) {
          screen = KundenverwaltungScreen(
            companyId: _companyId,
            title: mod.label,
            onBack: onBack,
            hideAppBar: true,
          );
        } else if (mod.url.contains('modulverwaltung.html')) {
          screen = ModulverwaltungScreen(
            companyId: _companyId,
            userRole: _userRole,
            title: mod.label,
            onBack: onBack,
            hideAppBar: true,
          );
        } else if (mod.url.contains('menue.html')) {
          screen = MenueverwaltungScreen(
            companyId: _companyId,
            userRole: _userRole,
            title: mod.label,
            onBack: onBack,
            onMenuSaved: () => _load(forceMenuServerRead: true),
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
      case 'schichtuebersicht':
      case 'schichtplannfs': return Icons.calendar_today;
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
      case 'telefonlistenfs': return Icons.phone;
      case 'chat': return Icons.chat_bubble_outline;
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

  /// Erstellt AppModule aus Menü-Item (für 1:1-Anzeige auch ohne Firmen-Freischaltung).
  /// Nutzt immer das Label aus dem Menü-Item (benutzerdefinierter Titel), nicht den Modul-Namen.
  AppModule _moduleFromMenuItem(Map<String, dynamic> item) {
    final id = (item['id'] ?? '').toString();
    final menuLabel = (item['label'] ?? '').toString().trim();
    final url = (item['url'] ?? '').toString();
    final modById = {for (final m in _allModules) m.id: m};
    final base = modById[id];
    final label = menuLabel.isNotEmpty ? menuLabel : (base?.label ?? id);
    if (base != null) {
      return AppModule(
        id: base.id,
        label: label,
        url: base.url,
        icon: base.icon,
        roles: base.roles,
        order: base.order,
        active: base.active,
      );
    }
    return AppModule(id: id, label: label, url: url, order: 0);
  }

  /// Prüft ob die aktuelle Rolle Zugriff auf ein Modul hat (nur für Modul-Items).
  bool _userHasModuleAccess(String moduleId) {
    if (moduleId.isEmpty) return false;
    return _allModules.any((m) => m.id == moduleId);
  }

  /// Prüft ob der Nutzer einen Oberbegriff (Heading) sehen darf.
  /// Keine Rollen / leere Rollen = alle sichtbar; Rollen gesetzt = nur diese Rollen.
  bool _userCanSeeHeading(Map<String, dynamic> item) {
    final roles = item['roles'];
    if (roles == null || roles is! List) return true;
    final rolesList = roles.map((r) => r.toString().trim().toLowerCase()).where((r) => r.isNotEmpty).toList();
    if (rolesList.isEmpty) return true;
    final userRole = (_userRole ?? '').toLowerCase().trim();
    if (userRole.isEmpty) return false;
    return rolesList.any((r) => r == userRole);
  }

  /// Roter Kreis mit ungelesener Chat-Anzahl für Menü-Badge.
  Widget _buildChatBadge() {
    final count = _chatUnreadNotifier.value;
    if (count <= 0) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: const BoxDecoration(
        color: Colors.red,
        borderRadius: BorderRadius.all(Radius.circular(12)),
      ),
      child: Text(
        count > 99 ? '99+' : '$count',
        style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600),
      ),
    );
  }

  List<Widget> _buildDrawerMenuContent() {
    final children = <Widget>[];
    for (final item in _menuStructure) {
      final type = (item['type'] ?? 'module').toString();
      if (type == 'heading') {
        if (!_userCanSeeHeading(item)) continue;
        final label = (item['label'] ?? '').toString();
        final rawChildren = item['children'];
        final childItems = rawChildren is List ? rawChildren : <dynamic>[];
        final childTiles = <Widget>[];
        for (final c in childItems) {
          if (c is! Map) continue;
          final cType = (c['type'] ?? '').toString();
          if (cType == 'module') {
            final modId = (c['id'] ?? '').toString();
            if (modId.isEmpty) continue;
            if (!_userHasModuleAccess(modId)) continue;
            final mod = _moduleFromMenuItem(Map<String, dynamic>.from(c));
            childTiles.add(ListTile(
              dense: true,
              leading: Icon(_drawerIconForModule(mod.id), size: 22),
              title: Text(mod.label, style: const TextStyle(fontSize: 14)),
              trailing: mod.id == 'chat' ? _buildChatBadge() : null,
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
        if (childTiles.isNotEmpty) {
          children.add(Theme(
            data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
            child: ExpansionTile(
              initiallyExpanded: false,
              leading: const Icon(Icons.folder_outlined, size: 22),
              title: Text(label.isNotEmpty ? label : 'Oberbegriff', style: const TextStyle(fontWeight: FontWeight.w500)),
              children: childTiles,
            ),
          ));
        }
      } else if (type == 'module') {
        final modId = (item['id'] ?? '').toString();
        if (modId.isEmpty) continue;
        if (!_userHasModuleAccess(modId)) continue;
        final mod = _moduleFromMenuItem(item);
        children.add(ListTile(
          leading: Icon(_drawerIconForModule(mod.id)),
          title: Text(mod.label),
          trailing: mod.id == 'chat' ? _buildChatBadge() : null,
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

  /// Tab-Titel für Web: zeigt ungelesene Chat-Anzahl (Flutter-eigener Mechanismus).
  static String _pageTitleFromCount(int count) {
    if (count <= 0) return 'RettBase';
    return '(${count > 99 ? 99 : count}) RettBase';
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Title(
        title: 'RettBase',
        color: AppTheme.primary,
        child: Scaffold(
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
        ),
      );
    }

    final scaffold = Scaffold(
      backgroundColor: AppTheme.surfaceBg,
      drawer: Drawer(
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            Container(
              width: double.infinity,
              padding: EdgeInsets.only(
                left: 20,
                right: 10,
                top: MediaQuery.of(context).padding.top,
                bottom: 16,
              ),
              decoration: const BoxDecoration(color: AppTheme.headerBg),
              constraints: BoxConstraints(
                minHeight: MediaQuery.of(context).padding.top +
                    (MediaQuery.of(context).size.width < 600 ? 56.0 : 70.0),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Image.asset('img/rettbase.png', height: 32, fit: BoxFit.contain),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white),
                    onPressed: () => Navigator.pop(context),
                    tooltip: 'Menü schließen',
                  ),
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
            if (_userHasModuleAccess('einstellungen'))
              ListTile(
                leading: const Icon(Icons.settings),
                title: const Text('Einstellungen'),
                onTap: () {
                  Navigator.pop(context);
                  _openModule(const AppModule(id: 'einstellungen', label: 'Einstellungen', url: '', order: 9));
                },
              ),
            if (_userHasModuleAccess('einstellungen')) const Divider(),
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
              } else if (v == 'logout') {
                _logout();
              }
            },
            itemBuilder: (_) {
              final items = <PopupMenuItem<String>>[
                const PopupMenuItem(value: 'profil', child: ListTile(leading: Icon(Icons.person_outline), title: Text('Profil'), contentPadding: EdgeInsets.zero)),
                const PopupMenuItem(value: 'logout', child: ListTile(leading: Icon(Icons.logout), title: Text('Abmelden'), contentPadding: EdgeInsets.zero)),
              ];
              if (_userHasModuleAccess('einstellungen')) {
                items.insert(1, const PopupMenuItem(value: 'einstellungen', child: ListTile(leading: Icon(Icons.settings), title: Text('Einstellungen'), contentPadding: EdgeInsets.zero)));
              }
              return items;
            },
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
    return ValueListenableBuilder<int>(
      valueListenable: _chatUnreadNotifier,
      builder: (context, count, _) => Title(
        title: _pageTitleFromCount(count),
        color: AppTheme.primary,
        child: scaffold,
      ),
      child: scaffold,
    );
  }
}
