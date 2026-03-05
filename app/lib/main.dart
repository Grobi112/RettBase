import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart' show kIsWeb, kDebugMode;
import 'dart:ui' show PlatformDispatcher;
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'firebase_options.dart';
import 'services/push_notification_service.dart';
import 'theme/app_theme.dart';
import 'app_config.dart';
import 'screens/splash_screen.dart';
import 'screens/login_screen.dart';
import 'screens/dashboard_screen.dart';
import 'utils/service_worker_update_stub.dart'
    if (dart.library.html) 'utils/service_worker_update_web.dart' as sw_update;
import 'utils/firebase_sw_register_stub.dart'
    if (dart.library.html) 'utils/firebase_sw_register_web.dart' as firebase_sw;
import 'utils/splash_loader_stub.dart'
    if (dart.library.html) 'utils/splash_loader_web.dart' as splash_loader;

/// Top-Level-Handler für Push-Nachrichten im Hintergrund/beendet – Badge sofort setzen.
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  final data = message.data;
  if (data != null && data['type'] == 'chat') {
    final badgeStr = data['totalUnread'] ?? data['badge'];
    if (badgeStr != null && badgeStr.toString().isNotEmpty) {
      final badge = int.tryParse(badgeStr.toString());
      if (badge != null && badge >= 0) {
        await PushNotificationService.updateBadge(badge);
      }
    }
  }
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Background-Handler MUSS vor allen async-Aufrufen registriert werden (iOS: erste Push nach App-Kill)
  if (!kIsWeb) {
    FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);
  }

  // Uncaught Errors abfangen (z.B. async Fehler in _initApp, Push-Service)
  FlutterError.onError = (details) {
    if (kDebugMode) debugPrint('RettBase FlutterError: ${details.exception}\n${details.stack}');
  };
  PlatformDispatcher.instance.onError = (Object error, StackTrace stack) {
    if (kDebugMode) debugPrint('RettBase Uncaught: $error\n$stack');
    return true; // verhindert weiteren Abbruch
  };

  // Web: Service-Worker auf Updates prüfen → automatischer Reload bei neuem Build
  sw_update.initServiceWorkerUpdateListener();


  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    debugPrint('RettBase Firebase: project=${Firebase.app().options.projectId}');
    if (kIsWeb) {
      try {
        await FirebaseAuth.instance.setPersistence(Persistence.LOCAL);
      } catch (_) {}
    }
    unawaited(PushNotificationService.initialize().catchError((e) {
      if (kDebugMode) debugPrint('RettBase Push Init: $e');
    }));
  } catch (e) {
    debugPrint('Firebase Init Fehler: $e');
  }
  // Update-Check: immer einrichten (auch wenn Firebase fehlschlägt)
  WidgetsBinding.instance.addPostFrameCallback((_) {
    firebase_sw.registerFirebaseMessagingSwDeferred();
  });

  runApp(kIsWeb ? const RettBaseApp() : const _AppWithTokenRefreshOnResume());
}

final _navigatorKey = GlobalKey<NavigatorState>();

/// Wrapper für Native: Token bei App-Resume erneuern (FCM-Token-Rotation).
class _AppWithTokenRefreshOnResume extends StatefulWidget {
  const _AppWithTokenRefreshOnResume();

  @override
  State<_AppWithTokenRefreshOnResume> createState() => _AppWithTokenRefreshOnResumeState();
}

class _AppWithTokenRefreshOnResumeState extends State<_AppWithTokenRefreshOnResume> {
  late final AppLifecycleListener _lifecycleListener;

  @override
  void initState() {
    super.initState();
    _lifecycleListener = AppLifecycleListener(
      onResume: () => unawaited(PushNotificationService.retrySaveTokenIfNeeded()),
    );
  }

  @override
  void dispose() {
    _lifecycleListener.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => const RettBaseApp();
}

class RettBaseApp extends StatelessWidget {
  const RettBaseApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: _navigatorKey,
      debugShowCheckedModeBanner: false,
      title: 'RettBase',
      theme: AppTheme.light,
      locale: const Locale('de'),
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [
        Locale('de'),
        Locale('en'),
      ],
      home: const RettBaseHome(),
    );
  }
}

class RettBaseHome extends StatefulWidget {
  const RettBaseHome({super.key});

  @override
  State<RettBaseHome> createState() => _RettBaseHomeState();
}

class _RettBaseHomeState extends State<RettBaseHome> {
  double _progress = 0.0;
  /// Kunden-ID-Formular nur wenn wirklich keine Company gespeichert.
  bool _showCompanyIdForm = false;
  String? _companyIdHint;
  String _initialCompanyId = '';
  final _companyIdController = TextEditingController();
  final _companyIdFocusNode = FocusNode();
  bool _companyIdLoading = false;
  String? _companyIdError;

  @override
  void dispose() {
    _companyIdController.dispose();
    _companyIdFocusNode.dispose();
    super.dispose();
  }

  void _setProgress(double value) {
    final p = value.clamp(0.0, 1.0);
    if (kIsWeb) splash_loader.updateProgress(p);
    if (mounted) setState(() => _progress = p);
  }

  void _showCompanyId({String? hint, String initialId = ''}) {
    if (!mounted) return;
    if (kIsWeb) splash_loader.removeLoader();
    setState(() {
      _showCompanyIdForm = true;
      _companyIdHint = hint;
      _initialCompanyId = initialId;
      _companyIdController.text = initialId;
      _companyIdError = null;
    });
  }

  void _hideCompanyIdAndContinue() {
    if (!mounted) return;
    setState(() {
      _showCompanyIdForm = false;
      _companyIdHint = null;
      _companyIdError = null;
      _progress = 0.0;
    });
    _initAppAfterCompanyId();
  }

  @override
  void initState() {
    super.initState();
    _initApp();
  }

  /// Nach Kunden-ID-Eingabe: kundeExists bereits validiert – nur Auth + Web-Check, dann Login/Dashboard.
  Future<void> _initAppAfterCompanyId() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final companyId = prefs.getString('rettbase_company_id') ??
          prefs.getString('rettbase_subdomain') ?? '';
      if (companyId.isEmpty) {
        if (mounted) _showCompanyId();
        return;
      }
      _setProgress(0.2);
      final authFuture = FirebaseAuth.instance
          .authStateChanges()
          .handleError((e) {
            if (kDebugMode) debugPrint('RettBase authStateChanges: $e');
          })
          .first
          .then<User?>((u) => u)
          .catchError((_) => null);
      final results = await Future.wait([authFuture]);
      final user = results[0] as User?;
      if (!mounted) return;
      _setProgress(1.0);
      if (user != null) {
        if (!kIsWeb) unawaited(PushNotificationService().saveToken(companyId, user!.uid));
        _navigateTo(DashboardScreen(companyId: companyId));
      } else {
        _navigateTo(LoginScreen(companyId: companyId));
      }
    } catch (e, s) {
      if (kDebugMode) debugPrint('RettBase _initAppAfterCompanyId Fehler: $e\n$s');
      if (!mounted) return;
      _initApp();
    }
  }

  Future<void> _initApp() async {
    try {
      await _initAppImpl();
    } catch (e, s) {
      if (kDebugMode) debugPrint('RettBase _initApp Fehler: $e\n$s');
      if (!mounted) return;
      try {
        final prefs = await SharedPreferences.getInstance();
        final companyId = prefs.getString('rettbase_company_id') ??
            prefs.getString('rettbase_subdomain') ?? '';
        if (companyId.isNotEmpty && mounted) {
          _setProgress(1.0);
          final user = FirebaseAuth.instance.currentUser;
          if (user != null) {
            if (!kIsWeb) unawaited(PushNotificationService().saveToken(companyId, user.uid));
            _navigateTo(DashboardScreen(companyId: companyId));
          } else {
            _navigateTo(LoginScreen(companyId: companyId));
          }
          return;
        }
      } catch (_) {}
      if (mounted) _showCompanyId();
    }
  }

  Future<void> _submitCompanyId() async {
    final raw = _companyIdController.text.trim();
    final kundenId = raw.isEmpty ? '' : raw.toLowerCase().replaceAll(RegExp(r'[^a-z0-9\-]'), '');
    if (kundenId.isEmpty) {
      setState(() => _companyIdError = 'Bitte eine gültige Kunden-ID eingeben.');
      return;
    }

    setState(() {
      _companyIdLoading = true;
      _companyIdError = null;
    });

    try {
      final res = await FirebaseFunctions.instanceFor(region: 'europe-west1')
          .httpsCallable('kundeExists')
          .call<Map<String, dynamic>>({'companyId': kundenId});
      final exists = res.data['exists'] == true;

      if (!exists) {
        if (mounted) {
          setState(() {
            _companyIdLoading = false;
            _companyIdError = 'Diese Kunden-ID existiert nicht. Bitte prüfen Sie die Eingabe.';
          });
        }
        return;
      }

      final docId = (res.data['docId'] as String?)?.trim().toLowerCase() ?? kundenId;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('rettbase_company_configured', true);
      await prefs.setString('rettbase_company_id', docId);
      await prefs.setString('rettbase_subdomain', kundenId);

      if (!mounted) return;
      _hideCompanyIdAndContinue();
    } on FirebaseFunctionsException catch (e) {
      if (mounted) {
        setState(() {
          _companyIdLoading = false;
          _companyIdError = e.code == 'resource-exhausted'
              ? 'Zu viele Anfragen. Bitte später erneut versuchen.'
              : 'Kunde konnte nicht überprüft werden. Bitte prüfen Sie Ihre Verbindung.';
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _companyIdLoading = false;
          _companyIdError = 'Kunde konnte nicht überprüft werden. Bitte prüfen Sie Ihre Verbindung.';
        });
      }
    }
  }

  void _navigateTo(Widget page) {
    if (kIsWeb) splash_loader.removeLoader();
    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        pageBuilder: (_, __, ___) => page,
        transitionDuration: const Duration(milliseconds: 150),
        transitionsBuilder: (_, a, __, c) =>
            FadeTransition(opacity: a, child: c),
      ),
    );
  }

  Future<void> _initAppImpl() async {
    final prefs = await SharedPreferences.getInstance();

    final companyConfigured = prefs.getBool('rettbase_company_configured') ?? false;
    var companyId = prefs.getString('rettbase_company_id') ??
        prefs.getString('rettbase_subdomain') ??
        '';

    if (!companyConfigured || companyId.isEmpty) {
      if (!mounted) return;
      // Fortschrittsbalken erst vollständig laufen lassen, dann Kunden-ID – kein Abbruch dazwischen
      _setProgress(0.3);
      await Future.delayed(const Duration(milliseconds: 400));
      if (!mounted) return;
      _setProgress(0.7);
      await Future.delayed(const Duration(milliseconds: 300));
      if (!mounted) return;
      _setProgress(1.0);
      await Future.delayed(const Duration(milliseconds: 200));
      if (!mounted) return;
      _showCompanyId();
      return;
    }

    if (!mounted) return;
    _setProgress(0.1);

    final cid = companyId.trim().toLowerCase();
    _setProgress(0.2);

    final kundeFuture = FirebaseFunctions.instanceFor(region: 'europe-west1')
        .httpsCallable('kundeExists')
        .call<Map<String, dynamic>>({'companyId': cid});
    final authFuture = FirebaseAuth.instance
        .authStateChanges()
        .handleError((e) {
          if (kDebugMode) debugPrint('RettBase authStateChanges: $e');
        })
        .first
        .then<User?>((u) => u)
        .catchError((_) => null);

    final futures = <Future>[kundeFuture, authFuture];

    dynamic kundeRes;
    User? user;
    try {
      final results = await Future.wait(futures);
      kundeRes = results[0];
      user = results[1] as User?;
      _setProgress(0.85);
    } catch (e) {
      if (kDebugMode) debugPrint('RettBase kundeExists Fehler: $e');
      if (!mounted) return;
      // Bei Netzwerkfehler: mit gespeicherter Company-ID fortfahren (optimistisch)
      user = await FirebaseAuth.instance.authStateChanges().first;
      _setProgress(1.0);
      if (user != null) {
        if (!kIsWeb) unawaited(PushNotificationService().saveToken(companyId, user!.uid));
        _navigateTo(DashboardScreen(companyId: companyId));
      } else {
        _navigateTo(LoginScreen(companyId: companyId));
      }
      return;
    }
    if (!mounted) return;

    try {
      final res = kundeRes as dynamic;
      final data = res.data;
      if (data != null) {
        final exists = data['exists'] == true;
        final docId = (data['docId'] as String?)?.trim().toLowerCase();
        if (exists && docId != null && docId.isNotEmpty && docId != cid) {
          companyId = docId;
          unawaited(prefs.setString('rettbase_company_id', docId));
        } else if (!exists) {
          if (!mounted) return;
          _showCompanyId(
            hint: 'Diese Kunden-ID wurde nicht gefunden. Bitte erneut eingeben.',
            initialId: cid,
          );
          return;
        }
      }
    } catch (_) {}

    if (!mounted) return;
    _setProgress(1.0);

    if (user != null) {
      debugPrint('RettBase: Bereits angemeldet (uid=${user.uid}) – springe direkt ins Dashboard');
      if (!kIsWeb) unawaited(PushNotificationService().saveToken(companyId, user!.uid));
      _navigateTo(DashboardScreen(companyId: companyId));
    } else {
      _navigateTo(LoginScreen(companyId: companyId));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_showCompanyIdForm) {
      return _buildCompanyIdForm(context);
    }
    // Web: HTML-Loader sichtbar – kein Flutter-SplashScreen (verhindert Flackern beim Übergang)
    if (kIsWeb) {
      return const ColoredBox(color: AppTheme.headerBg);
    }
    return SplashScreen(progress: _progress);
  }

  Widget _buildCompanyIdForm(BuildContext context) {
    const logoHeight = 90.0; // Konstant (kein Wechsel bei Tastatur-Fokus)
    final viewInsets = MediaQuery.of(context).viewInsets;
    final keyboardVisible = viewInsets.bottom > 0;
    return Scaffold(
      backgroundColor: AppTheme.headerBg,
      resizeToAvoidBottomInset: true,
      body: SafeArea(
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: EdgeInsets.only(
            left: Responsive.horizontalPadding(context),
            right: Responsive.horizontalPadding(context),
            top: keyboardVisible ? 12 : 20,
            bottom: keyboardVisible ? viewInsets.bottom + 16 : 20,
          ),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 400),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Image.asset(
                  'img/rettbase_splash.png',
                  height: logoHeight,
                  fit: BoxFit.contain,
                ),
                SizedBox(height: keyboardVisible ? 20 : 48),
                  if (_companyIdHint != null) ...[
                    Text(
                      _companyIdHint!,
                      style: TextStyle(
                        color: Colors.amber.shade200,
                        fontSize: 13,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 16),
                  ],
                  TextField(
                    controller: _companyIdController,
                    focusNode: _companyIdFocusNode,
                    textInputAction: TextInputAction.done,
                    keyboardType: TextInputType.text,
                    autocorrect: false,
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'[a-zA-Z0-9\-_]')),
                    ],
                    style: const TextStyle(color: Colors.white, fontSize: 16),
                    decoration: InputDecoration(
                      hintText: 'Kunden-ID eingeben',
                      hintStyle: TextStyle(color: Colors.white.withOpacity(0.4)),
                      floatingLabelBehavior: FloatingLabelBehavior.never,
                      errorText: _companyIdError,
                      errorStyle: TextStyle(color: Colors.red.shade300, fontSize: 13),
                      errorMaxLines: 2,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(
                          color: _companyIdError != null ? Colors.red.shade400 : Colors.transparent,
                        ),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(
                          color: _companyIdError != null ? Colors.red.shade400 : AppTheme.primary,
                          width: 1.5,
                        ),
                      ),
                      filled: true,
                      fillColor: const Color(0xFF2D3139),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
                    ),
                    onSubmitted: (_) => _submitCompanyId(),
                  ),
                  SizedBox(height: keyboardVisible ? 20 : 32),
                  FilledButton(
                    onPressed: _companyIdLoading ? null : _submitCompanyId,
                    style: FilledButton.styleFrom(
                      backgroundColor: AppTheme.primary,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 18),
                      elevation: 0,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: _companyIdLoading
                        ? const SizedBox(
                            height: 24,
                            width: 24,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : const Text('Weiter', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
