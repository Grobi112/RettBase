import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_svg/flutter_svg.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import '../theme/app_theme.dart';
import '../services/chat_service.dart';
import '../services/email_service.dart';
import '../models/app_module.dart';
import '../models/information_model.dart';
import '../models/kunde_model.dart';
import '../services/auth_service.dart';
import '../services/auth_data_service.dart';
import '../services/modules_service.dart';
import '../services/informationen_service.dart';
import '../services/informationssystem_service.dart';
import '../services/kundenverwaltung_service.dart';
import '../services/menueverwaltung_service.dart';
import '../services/module_variants_service.dart';
import '../services/fahrtenbuch_v2_service.dart';
import '../services/push_notification_service.dart';
import '../app_config.dart';
import 'home_screen.dart';
import 'schichtanmeldung_screen.dart';
import 'schichtuebersicht_screen.dart';
import 'fahrtenbuch_screen.dart';
import 'fahrtenbuchuebersicht_screen.dart';
import 'fahrtenbuch_v2_screen.dart';
import 'fahrtenbuch_v2_uebersicht_screen.dart';
import '../models/fahrtenbuch_v2_vorlage.dart';
import '../models/fahrtenbuch_vorlage.dart';
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
import 'email_screen.dart';
import 'telefonliste_screen.dart';
import 'chat_screen.dart';
import 'company_id_screen.dart';
import 'login_screen.dart';
import 'profile_screen.dart';
import 'einsatzprotokoll_ssd_screen.dart';
import 'einsatzprotokoll_nfs_screen.dart';
import 'schichtplan_nfs_screen.dart';
import '../services/schichtplan_nfs_service.dart';
import '../services/alarm_quittierung_service.dart';
import '../services/alarmierung_nfs_service.dart';
import '../services/mitarbeiter_service.dart';
import 'telefonliste_nfs_screen.dart';
import 'alarmierung_nfs_screen.dart';
import 'einsatzdetails_nfs_screen.dart';
import 'fahrzeugstatus_screen.dart';
import 'placeholder_module_screen.dart';
import 'module_webview_screen.dart';
import 'kundenverwaltung_screen.dart';
import 'mitarbeiterverwaltung_screen.dart';
import 'modulverwaltung_screen.dart';
import 'menueverwaltung_screen.dart';
import 'package:app/utils/ensure_users_doc_cache.dart';
import 'package:app/utils/web_version_check.dart';
import 'package:app/utils/reload_web.dart' show reload;
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

class _DashboardScreenState extends State<DashboardScreen> with WidgetsBindingObserver {
  final _authService = AuthService();
  final _kundenService = KundenverwaltungService();
  final _menuService = MenueverwaltungService();
  final _variantsService = ModuleVariantsService();
  final _authDataService = AuthDataService();
  final _modulesService = ModulesService();
  final _infoService = InformationenService();
  final _chatService = ChatService();
  final _emailService = EmailService();
  final _schichtplanNfsService = SchichtplanNfsService();
  final _alarmierungNfsService = AlarmierungNfsService();
  final _mitarbeiterService = MitarbeiterService();
  final _bodyNavigatorKey = GlobalKey<NavigatorState>();

  final _activeEinsatzNotifier = ValueNotifier<Map<String, dynamic>?>(null);
  StreamSubscription<Map<String, dynamic>?>? _activeEinsatzSub;
  final _hatAbgeschlosseneEinsaetzeNotifier = ValueNotifier<bool>(false);
  StreamSubscription<List<Map<String, dynamic>>>? _abgeschlosseneEinsaetzeSub;
  String? _mitarbeiterId;

  final _chatUnreadNotifier = ValueNotifier<int>(0);
  StreamSubscription<int>? _chatUnreadSub;
  Timer? _badgePollTimer;

  final _emailUnreadNotifier = ValueNotifier<int>(0);
  StreamSubscription<int>? _emailUnreadSub;

  final _schichtplanNfsMeldungenNotifier = ValueNotifier<int>(0);
  StreamSubscription<int>? _schichtplanNfsMeldungenSub;

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
    WidgetsBinding.instance.addObserver(this);
    _load();
    _chatUnreadNotifier.addListener(_onChatUnreadChanged);
    _emailUnreadNotifier.addListener(_onEmailUnreadChanged);
    if (kIsWeb) {
      visibility_refresh.setOnVisible(() {
        if (mounted) _restartChatUnreadListener();
      });
    }
  }

  void _onChatUnreadChanged() {
    final count = _chatUnreadNotifier.value;
    PushNotificationService.updateBadge(count);
    setState(() {});
  }

  void _onEmailUnreadChanged() => setState(() {});

  void _startEmailUnreadListener() {
    _emailUnreadSub?.cancel();
    _emailUnreadSub = null;
    final cid = _effectiveCompanyId.isNotEmpty ? _effectiveCompanyId : widget.companyId;
    if (cid.isEmpty) return;
    _emailUnreadSub = _emailService.streamUnreadCount(cid).listen(
      (count) {
        if (mounted) _emailUnreadNotifier.value = count;
      },
      onError: (e) {
        debugPrint('RettBase Email Badge: stream Fehler: $e');
        _emailUnreadSub?.cancel();
        _emailUnreadSub = null;
        if (mounted) _emailUnreadNotifier.value = 0;
      },
    );
  }

  void _restartChatUnreadListener() {
    _chatUnreadSub?.cancel();
    _chatUnreadSub = null;
    _startChatUnreadListener();
  }

  static bool _canSeeSchichtplanNfsMeldungen(String? role) {
    if (role == null || role.isEmpty) return false;
    final r = role.trim().toLowerCase();
    return r == 'superadmin' || r == 'admin' || r == 'koordinator';
  }

  void _startChatUnreadListener() {
    _chatUnreadSub?.cancel();
    _chatUnreadSub = null;
    _badgePollTimer?.cancel();
    _badgePollTimer = null;
    final cid = _effectiveCompanyId.isNotEmpty ? _effectiveCompanyId : widget.companyId;
    if (cid.isEmpty) return;
    // Nur für UI (Chat-Tile) – Badge am App-Icon kommt ausschließlich aus Push
    void refreshForUi() async {
      if (!mounted || cid.isEmpty) return;
      try {
        final count = await _chatService.getUnreadCount(cid);
        if (mounted) _chatUnreadNotifier.value = count;
      } catch (e) {
        debugPrint('RettBase Chat UI: getUnreadCount Fehler: $e');
      }
    }
    refreshForUi();
    _badgePollTimer = Timer.periodic(const Duration(seconds: 5), (_) => refreshForUi());
  }

  void _startSchichtplanNfsMeldungenStream() {
    if (!_canSeeSchichtplanNfsMeldungen(_userRole)) return;
    final hasSchichtplanNfs = _shortcuts.any((m) => m?.id == 'schichtplannfs');
    if (!hasSchichtplanNfs) return;
    final cid = _effectiveCompanyId.isNotEmpty ? _effectiveCompanyId : widget.companyId;
    if (cid.isEmpty) return;
    _schichtplanNfsMeldungenSub?.cancel();
    _schichtplanNfsMeldungenSub = _schichtplanNfsService
        .streamMeldungenCount(cid)
        .listen((count) {
      if (mounted) _schichtplanNfsMeldungenNotifier.value = count;
    });
  }

  void _stopSchichtplanNfsMeldungenStream() {
    _schichtplanNfsMeldungenSub?.cancel();
    _schichtplanNfsMeldungenSub = null;
  }

  void _startActiveEinsatzStream(String companyId, String uid) async {
    _activeEinsatzSub?.cancel();
    _activeEinsatzSub = null;
    _activeEinsatzNotifier.value = null;
    _mitarbeiterId = null;
    try {
      _mitarbeiterId = await _mitarbeiterService.getMitarbeiterIdForUid(companyId, uid);
      if (_mitarbeiterId == null || _mitarbeiterId!.isEmpty) return;
      _activeEinsatzSub = _alarmierungNfsService
          .streamActiveEinsatzForMitarbeiter(companyId, _mitarbeiterId!)
          .listen((e) {
        if (mounted) _activeEinsatzNotifier.value = e;
      });
    } catch (_) {}
  }

  void _stopActiveEinsatzStream() {
    _activeEinsatzSub?.cancel();
    _activeEinsatzSub = null;
    _activeEinsatzNotifier.value = null;
    _mitarbeiterId = null;
  }

  void _startAbgeschlosseneEinsaetzeStream(String companyId, String uid) async {
    _abgeschlosseneEinsaetzeSub?.cancel();
    _abgeschlosseneEinsaetzeSub = null;
    _hatAbgeschlosseneEinsaetzeNotifier.value = false;
    try {
      final mid = await _mitarbeiterService.getMitarbeiterIdForUid(companyId, uid);
      if (mid == null || mid.isEmpty) return;
      _abgeschlosseneEinsaetzeSub = _alarmierungNfsService
          .streamAbgeschlosseneEinsaetzeForMitarbeiter(companyId, mid)
          .listen((list) {
        if (mounted) _hatAbgeschlosseneEinsaetzeNotifier.value = list.isNotEmpty;
      });
    } catch (_) {}
  }

  void _stopAbgeschlosseneEinsaetzeStream() {
    _abgeschlosseneEinsaetzeSub?.cancel();
    _abgeschlosseneEinsaetzeSub = null;
    _hatAbgeschlosseneEinsaetzeNotifier.value = false;
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
          builder: (_) => ChatScreen(
            companyId: companyId,
            initialChatId: chat.$2,
            onBack: _goToHome,
            hideAppBar: true,
            userRole: _userRole,
            onChatOpened: (chatId, unreadInChat) {
              _chatUnreadNotifier.value = _chatUnreadNotifier.value - unreadInChat;
              if (_chatUnreadNotifier.value < 0) _chatUnreadNotifier.value = 0;
              PushNotificationService.updateBadge(_chatUnreadNotifier.value);
              unawaited(_chatService.markChatReadPublic(companyId, chatId));
            },
          ),
        ),
      );
    });
  }

  void _maybeOpenAlarmFromNotification(String companyId, String? mitarbeiterId) {
    final alarm = PushNotificationService.initialAlarmFromNotification;
    if (alarm == null) return;
    if (alarm.$1 != companyId) return;
    if (mitarbeiterId == null || mitarbeiterId.isEmpty) return;
    if (!mounted) return;
    final einsatzId = alarm.$2;
    unawaited(
      FirebaseFirestore.instance
          .collection('kunden')
          .doc(companyId)
          .collection('alarmierung-nfs')
          .doc(einsatzId)
          .get()
          .then((snap) {
        if (!snap.exists || !mounted) return;
        final einsatz = Map<String, dynamic>.from(snap.data()!);
        einsatz['id'] = einsatzId;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          _bodyNavigatorKey.currentState?.push(
            MaterialPageRoute(
              builder: (_) => EinsatzdetailsNfsScreen(
                companyId: companyId,
                mitarbeiterId: mitarbeiterId,
                einsatz: einsatz,
                onBack: () => _bodyNavigatorKey.currentState?.pop(),
              ),
            ),
          ).then((result) {
            if (result == 'abgeschlossen' && mounted) {
              _hatAbgeschlosseneEinsaetzeNotifier.value = true;
            }
          });
        });
      }),
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      PushNotificationService.retrySaveTokenIfNeeded();
      _refreshBadgeOnResume();
    }
  }

  void _refreshBadgeOnResume() {
    final cid = _effectiveCompanyId.isNotEmpty ? _effectiveCompanyId : widget.companyId;
    if (cid.isEmpty) return;
    // Nur Chat-UI aktualisieren – Badge am App-Icon kommt ausschließlich aus Push
    unawaited(_chatService.getUnreadCount(cid).then((count) {
      if (mounted) _chatUnreadNotifier.value = count;
    }));
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _chatUnreadNotifier.removeListener(_onChatUnreadChanged);
    _chatUnreadNotifier.dispose();
    _emailUnreadNotifier.removeListener(_onEmailUnreadChanged);
    _emailUnreadNotifier.dispose();
    _chatUnreadSub?.cancel();
    _emailUnreadSub?.cancel();
    _badgePollTimer?.cancel();
    _stopSchichtplanNfsMeldungenStream();
    _stopActiveEinsatzStream();
    _stopAbgeschlosseneEinsaetzeStream();
    _schichtplanNfsMeldungenNotifier.dispose();
    _activeEinsatzNotifier.dispose();
    _hatAbgeschlosseneEinsaetzeNotifier.dispose();
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
    if (kIsWeb) {
      unawaited(updateWebVersionFromServer());
      unawaited(runWebVersionCheckOnce(() => reload()));
    }
    debugPrint('RettBase Dashboard _load: uid=${user.uid} email=${user.email} widget.companyId=${widget.companyId}');
    try {
      try {
        if (!EnsureUsersDocCache.shouldSkip(widget.companyId)) {
          await FirebaseFunctions.instanceFor(region: 'europe-west1')
              .httpsCallable('ensureUsersDoc')
              .call({'companyId': widget.companyId});
          EnsureUsersDocCache.record(widget.companyId);
        }
        await user.getIdToken(true);
      } catch (_) {}
      AuthData authData;
      try {
        authData = await _authDataService.getAuthData(
          user.uid,
          user.email ?? '',
          widget.companyId,
        );
      } on AuthNotAuthorizedException catch (_) {
        debugPrint('RettBase Dashboard: Nutzer nicht in Mitarbeiterverwaltung -> Abmelden');
        await _authService.logout();
        if (!mounted) return;
        _goToLogin();
        return;
      }
      debugPrint('RettBase Dashboard: authData role=${authData.role} companyId=${authData.companyId} displayName=${authData.displayName} vorname=${authData.vorname}');
      final effectiveCompanyId = authData.companyId.trim().isNotEmpty ? authData.companyId : widget.companyId;
      // Token im Hintergrund speichern – darf Dashboard-Lade nicht blockieren (getToken kann auf Web hängen)
      unawaited(PushNotificationService().saveToken(effectiveCompanyId, user.uid).timeout(const Duration(seconds: 30), onTimeout: () {}));
      var bereich = await _kundenService.getCompanyBereich(effectiveCompanyId);
      final isAdminCompany = (effectiveCompanyId.trim().toLowerCase()) == 'admin';
      if (bereich == null || bereich.isEmpty) {
        bereich = isAdminCompany ? KundenBereich.admin : KundenBereich.rettungsdienst;
      }
      debugPrint('RettBase Dashboard: getCompanyBereich($effectiveCompanyId)=$bereich');

      // Module und Menü parallel laden (beide benötigen bereich)
      final modsFuture = _modulesService.getModulesForCompany(effectiveCompanyId, authData.role, bereich: bereich);
      final menuFuture = _loadMenuStructure(bereich, isAdminCompany, forceMenuServerRead);

      var allMods = await modsFuture;
      var menuStructure = await menuFuture;

      // Menü-Module auch für _allModules ergänzen – sonst erscheinen sie im Drawer nicht
      // (z.B. Chat unter Notfallseelsorge, wenn noch nicht explizit in kunden/modules freigeschaltet)
      final menuModuleIds = MenueverwaltungService.extractModuleIdsFromMenu(menuStructure)
          .where((id) => id != 'schichtuebersicht') // Nur über Schichtanmeldung → Einstellungen
          .toList();
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

      // Schnellstart: Max. 6 Kacheln. Bei gespeicherter Nutzerauswahl: nur diese (inkl. leere Slots).
      // Ohne Custom: erste 6 Menü-Module. Mit Custom: gespeicherte Slots (leere = null, werden ausgeblendet).
      List<AppModule?> shortcuts = await _modulesService.getShortcuts(
        effectiveCompanyId,
        authData.role,
        bereich: bereich,
        menuModuleIds: menuModuleIds,
      );
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

      // Container-Slots und Informationen lazy laden – Haupt-Dashboard erscheint sofort
      unawaited(_loadContainerSlots(effectiveCompanyId).then((slots) {
        if (mounted) _containerSlotsNotifier.value = slots;
      }));
      unawaited(_infoService.loadInformationen(effectiveCompanyId).then((infos) {
        if (mounted) _infoItemsNotifier.value = infos;
      }));
      _startChatUnreadListener();
      _startEmailUnreadListener();
      _startSchichtplanNfsMeldungenStream();
      _startActiveEinsatzStream(effectiveCompanyId, user.uid);
      _startAbgeschlosseneEinsaetzeStream(effectiveCompanyId, user.uid);
      if (kIsWeb) {
        final h = url_hash.getInitialHash();
        PushNotificationService.setInitialChatFromHash(h);
        PushNotificationService.setInitialAlarmFromHash(h);
        if (h != null && (h.startsWith('#chat/') || h.startsWith('#einsatz/'))) {
          url_hash.clearHash();
        }
      }
      _maybeOpenChatFromNotification(effectiveCompanyId);
      _maybeOpenAlarmFromNotification(effectiveCompanyId, _mitarbeiterId);
    } catch (e, st) {
      debugPrint('RettBase Dashboard _load FEHLER: $e');
      debugPrint('RettBase Dashboard _load StackTrace: $st');
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<List<Map<String, dynamic>>> _loadMenuStructure(
      String? bereich, bool isAdminCompany, bool forceMenuServerRead) async {
    var menuStructure = <Map<String, dynamic>>[];
    if (bereich != null && bereich.isNotEmpty) {
      menuStructure = await _menuService.loadMenuStructure(bereich, forceServerRead: forceMenuServerRead);
      debugPrint('RettBase Dashboard: loadMenuStructure($bereich) -> ${menuStructure.length} items');
      if (menuStructure.isEmpty) {
        menuStructure = await _menuService.loadLegacyGlobalMenu(forceServerRead: forceMenuServerRead);
        debugPrint('RettBase Dashboard: loadLegacyGlobalMenu Fallback -> ${menuStructure.length} items');
      }
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
    return menuStructure;
  }

  /// Lädt Container-Slots für Hauptseite – firmenweit und bereichsübergreifend.
  /// companyId = effectiveCompanyId (Firestore docId), keine Bereichs-Trennung.
  Future<List<String?>> _loadContainerSlots(String companyId) async {
    try {
      final cid = companyId.trim().toLowerCase();
      final ref = FirebaseFirestore.instance
          .collection('kunden')
          .doc(cid)
          .collection('settings')
          .doc('informationssystem');
      final snap = await ref.get();
      final data = snap.data();
      final validOrder = _parseContainerTypeOrder(data);
      final list = data?['containerSlots'] as List?;
      if (list != null && list.isNotEmpty) {
        final maxSlots = InformationssystemService.maxContainerSlots;
        final validSet = validOrder.isNotEmpty ? validOrder.toSet() : null;
        final slots = <String?>[];
        for (var i = 0; i < list.length && i < maxSlots; i++) {
          final raw = list[i];
          final s = raw?.toString().trim();
          if (s != null && s.isNotEmpty && s != 'null') {
            if (validSet == null || validSet.contains(s)) {
              slots.add(s);
            } else {
              slots.add(null);
            }
          } else {
            slots.add(null);
          }
        }
        while (slots.length < maxSlots) {
          slots.add(null);
        }
        return slots.take(maxSlots).toList();
      }
      // Kein Fallback: Wenn containerSlots fehlt/leer, nichts anzeigen.
      // „Container auf Hauptseite“ muss explizit in den Einstellungen konfiguriert werden.
    } catch (_) {}
    return List.filled(InformationssystemService.maxContainerSlots, null);
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
      emailUnreadListenable: _emailUnreadNotifier,
      schichtplanNfsMeldungenListenable: _schichtplanNfsMeldungenNotifier,
      containerSlotsListenable: _containerSlotsNotifier,
      informationenItemsListenable: _infoItemsNotifier,
      companyId: _companyId,
      userRole: _userRole,
      activeEinsatzListenable: _activeEinsatzNotifier,
      mitarbeiterId: _mitarbeiterId,
      onEinsatzDetailsTap: _openEinsatzDetails,
      onProtokollErstellenTap: _openProtokollErstellen,
      hatAbgeschlosseneEinsaetzeListenable: _hatAbgeschlosseneEinsaetzeNotifier,
      onInfoDeleted: () async {
        final infos = await _infoService.loadInformationen(_companyId);
        if (mounted) _infoItemsNotifier.value = infos;
      },
    );
  }

  void _openProtokollErstellen() {
    _bodyNavigatorKey.currentState?.push(
      MaterialPageRoute(
        builder: (_) => EinsatzprotokollNfsScreen(
          companyId: _companyId,
          mitarbeiterId: _mitarbeiterId,
          onBack: () => _bodyNavigatorKey.currentState?.pop(),
        ),
      ),
    );
  }

  void _openEinsatzDetails() {
    final einsatz = _activeEinsatzNotifier.value;
    final mid = _mitarbeiterId;
    if (einsatz == null || mid == null) return;
    final einsatzId = einsatz['id'] as String?;
    if (einsatzId != null) {
      unawaited(AlarmQuittierungService().markQuittiert(_companyId, einsatzId));
      unawaited(PushNotificationService.stopAlarmTone());
    }
    _bodyNavigatorKey.currentState?.push(
      MaterialPageRoute(
        builder: (_) => EinsatzdetailsNfsScreen(
          companyId: _companyId,
          mitarbeiterId: mid,
          einsatz: Map<String, dynamic>.from(einsatz),
          onBack: () => _bodyNavigatorKey.currentState?.pop(),
        ),
      ),
    ).then((result) {
      if (result == 'abgeschlossen' && mounted) {
        _activeEinsatzNotifier.value = null;
        _hatAbgeschlosseneEinsaetzeNotifier.value = true;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Einsatz beendet und abgeschlossen. Er erscheint unter „Abgeschlossene Einsätze“.',
            ),
          ),
        );
      }
    });
  }

  /// Öffnet Modul im Body-Bereich (Header bleibt sichtbar)
  Future<void> _openModule(AppModule mod) async {
    Widget screen;
    final onBack = _goToHome;
    switch (mod.id) {
      case 'schichtanmeldung':
        final fbVariantSchicht = await _variantsService.getModuleVariant(_companyId, 'fahrtenbuch');
        screen = SchichtanmeldungScreen(
          companyId: _companyId,
          title: mod.label,
          onBack: onBack,
          hideAppBar: true,
          userRole: _userRole,
          fahrtenbuchVariant: fbVariantSchicht,
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
        final fbVariant = await _variantsService.getModuleVariant(_companyId, 'fahrtenbuch');
        screen = fbVariant == 'v2'
            ? FahrtenbuchV2Screen(companyId: _companyId, onBack: onBack, userRole: _userRole)
            : FahrtenbuchScreen(companyId: _companyId, onBack: onBack, userRole: _userRole);
        break;
      case 'fahrtenbuchuebersicht':
        final fbVariant = await _variantsService.getModuleVariant(_companyId, 'fahrtenbuch');
        screen = fbVariant == 'v2'
            ? FahrtenbuchV2UebersichtScreen(
                companyId: _companyId,
                title: mod.label,
                onBack: onBack,
                onAddTap: (_) {
                  onBack();
                  _openModule(AppModule(id: 'fahrtenbuch', label: mod.label, url: '', order: 16));
                },
                service: FahrtenbuchV2Service(),
                userRole: _userRole,
              )
            : FahrtenbuchuebersichtScreen(
                companyId: _companyId,
                title: mod.label,
                onBack: onBack,
                userRole: _userRole,
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
          userRole: _userRole,
          onChatOpened: (chatId, unreadInChat) {
            _chatUnreadNotifier.value = _chatUnreadNotifier.value - unreadInChat;
            if (_chatUnreadNotifier.value < 0) _chatUnreadNotifier.value = 0;
            PushNotificationService.updateBadge(_chatUnreadNotifier.value);
            unawaited(_chatService.markChatReadPublic(_companyId, chatId));
          },
        );
        break;
      case 'email':
      case 'office':
        screen = EmailScreen(
          companyId: _companyId,
          onBack: onBack,
        );
        break;
      case 'ssd':
        screen = EinsatzprotokollSsdScreen(
          companyId: _companyId,
          onBack: onBack,
        );
        break;
      case 'einsatzprotokollnfs':
        screen = EinsatzprotokollNfsScreen(
          companyId: _companyId,
          title: 'Einsatzprotokoll Notfallseelsorge',
          mitarbeiterId: _mitarbeiterId,
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
      case 'alarmierungnfs':
        screen = AlarmierungNfsScreen(
          companyId: _companyId,
          userRole: _userRole,
          title: mod.label ?? 'Einsatzverwaltung',
          onBack: onBack,
        );
        break;
      case 'fahrzeugstatus':
        screen = FahrzeugstatusScreen(
          companyId: _companyId,
          title: mod.label,
          onBack: onBack,
          onOpenSchichtanmeldung: () {
            unawaited(_openModule(const AppModule(id: 'schichtanmeldung', label: 'Schichtanmeldung', url: '', order: 14)));
          },
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
          bereich: _bereich,
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
        // Unbekanntes Modul: WebView bei URL (Custom-Link), sonst Platzhalter
        if (mod.url.isNotEmpty) {
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

  Future<void> _openFahrtenbuch(dynamic vorlage) async {
    final variant = await _variantsService.getModuleVariant(_companyId, 'fahrtenbuch');
    FahrtenbuchV2Vorlage? v2Vorlage;
    if (vorlage is FahrtenbuchV2Vorlage) {
      v2Vorlage = vorlage;
    } else if (vorlage is FahrtenbuchVorlage) {
      v2Vorlage = FahrtenbuchV2Vorlage(
        fahrzeugId: vorlage.fahrzeugId,
        fahrzeugRufname: vorlage.fahrzeugRufname,
        kennzeichen: vorlage.kennzeichen,
        nameFahrer: vorlage.nameFahrer,
        kmAnfang: vorlage.kmAnfang,
        datum: vorlage.datum,
        fahrerOptionen: vorlage.fahrerOptionen,
      );
    }
    if (variant == 'v2' && v2Vorlage != null) {
      _bodyNavigatorKey.currentState?.pushAndRemoveUntil(
        MaterialPageRoute(
          builder: (_) => FahrtenbuchV2Screen(
            companyId: _companyId,
            onBack: _goToHome,
            initialVorlage: v2Vorlage,
            userRole: _userRole,
          ),
        ),
        (_) => false,
      );
    } else if (variant == 'v2') {
      _openModule(const AppModule(id: 'fahrtenbuch', label: 'Fahrtenbuch', url: '', order: 16));
    } else {
      _bodyNavigatorKey.currentState?.pushAndRemoveUntil(
        MaterialPageRoute(
          builder: (_) => FahrtenbuchScreen(
            companyId: _companyId,
            onBack: _goToHome,
            initialVorlage: vorlage is FahrtenbuchVorlage ? vorlage : null,
            userRole: _userRole,
          ),
        ),
        (_) => false,
      );
    }
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
      case 'fahrzeugstatus': return Icons.directions_car;
      case 'chat': return Icons.chat_bubble_outline;
      default: return Icons.apps;
    }
  }

  /// SVG-Icon für alle Einsatzprotokolle (Punkt 2: Dokument mit Stift)
  Widget _drawerLeadingForModule(String id, {double size = 22}) {
    const iconColor = Colors.black;
    if (id == 'ssd' || id == 'einsatzprotokollnfs' || id == 'alarmierungnfs') {
      return SvgPicture.asset(
        'img/icon_einsatzprotokoll_nfs.svg',
        width: size,
        height: size,
        colorFilter: ColorFilter.mode(iconColor, BlendMode.srcIn),
      );
    }
    return Icon(_drawerIconForModule(id), size: size);
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

  /// Roter Kreis mit ungelesener E-Mail-Anzahl für Menü-Badge.
  Widget _buildEmailBadge() {
    final count = _emailUnreadNotifier.value;
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
            if (modId == 'schichtuebersicht') continue; // Nur über Schichtanmeldung → Einstellungen
            if (!_userHasModuleAccess(modId)) continue;
            final mod = _moduleFromMenuItem(Map<String, dynamic>.from(c));
            childTiles.add(Padding(
              padding: const EdgeInsets.only(left: 20),
              child: ListTile(
                dense: true,
                leading: _drawerLeadingForModule(mod.id, size: 22),
                title: Text(mod.label, style: const TextStyle(fontSize: 14)),
                trailing: mod.id == 'chat' ? _buildChatBadge() : (mod.id == 'email' || mod.id == 'office') ? _buildEmailBadge() : null,
                onTap: () {
                  Navigator.pop(context);
                  _openModule(mod);
                },
              ),
            ));
          } else if (cType == 'custom') {
            final cLabel = (c['label'] ?? '').toString();
            final cUrl = c['url']?.toString();
            childTiles.add(Padding(
              padding: const EdgeInsets.only(left: 20),
              child: ListTile(
                dense: true,
                leading: const Icon(Icons.link, size: 22),
                title: Text(cLabel.isNotEmpty ? cLabel : 'Link', style: const TextStyle(fontSize: 14)),
                onTap: () {
                  Navigator.pop(context);
                  _openCustomLink(cLabel, cUrl);
                },
              ),
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
        if (modId == 'schichtuebersicht') continue; // Nur über Schichtanmeldung → Einstellungen
        if (!_userHasModuleAccess(modId)) continue;
        final mod = _moduleFromMenuItem(item);
        children.add(ListTile(
          leading: _drawerLeadingForModule(mod.id),
          title: Text(mod.label),
          trailing: mod.id == 'chat' ? _buildChatBadge() : (mod.id == 'email' || mod.id == 'office') ? _buildEmailBadge() : null,
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
            if ((_userRole ?? '').toLowerCase().trim() == 'superadmin') ...[
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
            itemBuilder: (_) => [
              const PopupMenuItem(value: 'profil', child: ListTile(leading: Icon(Icons.person_outline), title: Text('Profil'), contentPadding: EdgeInsets.zero)),
              const PopupMenuItem(value: 'einstellungen', child: ListTile(leading: Icon(Icons.settings), title: Text('Einstellungen'), contentPadding: EdgeInsets.zero)),
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
