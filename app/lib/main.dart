import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb, kDebugMode;
import 'dart:ui' show PlatformDispatcher;
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'firebase_options.dart';
import 'services/push_notification_service.dart';
import 'theme/app_theme.dart';
import 'screens/splash_screen.dart';
import 'screens/company_id_screen.dart';
import 'screens/login_screen.dart';
import 'screens/dashboard_screen.dart';
import 'utils/service_worker_update_stub.dart'
    if (dart.library.html) 'utils/service_worker_update_web.dart' as sw_update;
import 'utils/firebase_sw_register_stub.dart'
    if (dart.library.html) 'utils/firebase_sw_register_web.dart' as firebase_sw;
import 'utils/reload_web.dart' as rw;
import 'utils/web_version_check.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

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

  runApp(const RettBaseApp());
}

final _navigatorKey = GlobalKey<NavigatorState>();

void _reloadWeb() => rw.reload();

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
  @override
  void initState() {
    super.initState();
    _initApp();
  }

  Future<void> _initApp() async {
    try {
      await _initAppImpl();
    } catch (e, s) {
      if (kDebugMode) debugPrint('RettBase _initApp Fehler: $e\n$s');
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        PageRouteBuilder(
          pageBuilder: (_, __, ___) => const CompanyIdScreen(),
          transitionDuration: Duration.zero,
        ),
      );
    }
  }

  Future<void> _initAppImpl() async {
    final prefs = await SharedPreferences.getInstance();
    final companyConfigured = prefs.getBool('rettbase_company_configured') ?? false;
    var companyId = prefs.getString('rettbase_company_id') ??
        prefs.getString('rettbase_subdomain') ??
        '';

    if (!companyConfigured || companyId.isEmpty) {
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        PageRouteBuilder(
          pageBuilder: (_, __, ___) => const CompanyIdScreen(),
          transitionDuration: Duration.zero,
        ),
      );
      return;
    }

    final cid = companyId.trim().toLowerCase();
    dynamic kundeRes;
    User? user;
    try {
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

      final results = await Future.wait([kundeFuture, authFuture]);
      kundeRes = results[0];
      user = results[1] as User?;
    } catch (e) {
      // kundeExists fehlgeschlagen (Netzwerk, 404, Rate-Limit) → Kunden-ID neu eingeben
      if (kDebugMode) debugPrint('RettBase kundeExists Fehler: $e');
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        PageRouteBuilder(
          pageBuilder: (_, __, ___) => CompanyIdScreen(
            initialCompanyId: cid,
            retryHint: 'Die Prüfung ist fehlgeschlagen. Bitte Kunden-ID erneut eingeben.',
          ),
          transitionDuration: Duration.zero,
        ),
      );
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
          // Kunde existiert nicht mehr → Kunden-ID neu eingeben
          if (!mounted) return;
          Navigator.of(context).pushReplacement(
            PageRouteBuilder(
              pageBuilder: (_, __, ___) => CompanyIdScreen(
                initialCompanyId: cid,
                retryHint: 'Diese Kunden-ID wurde nicht gefunden. Bitte erneut eingeben.',
              ),
              transitionDuration: Duration.zero,
            ),
          );
          return;
        }
      }
    } catch (_) {}

    if (!mounted) return;

    // Web: Einmalige Versionsprüfung im Ladefenster – Update ggf. sofort, keine Prüfung mehr in der Session
    if (kIsWeb) {
      await runWebVersionCheckOnce(_reloadWeb);
      if (!mounted) return;
    }

    if (user != null) {
      debugPrint('RettBase: Bereits angemeldet (uid=${user.uid}) – springe direkt ins Dashboard');
      Navigator.of(context).pushReplacement(
        PageRouteBuilder(
          pageBuilder: (_, __, ___) => DashboardScreen(companyId: companyId),
          transitionDuration: Duration.zero,
        ),
      );
    } else {
      Navigator.of(context).pushReplacement(
        PageRouteBuilder(
          pageBuilder: (_, __, ___) => LoginScreen(companyId: companyId),
          transitionDuration: Duration.zero,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return const SplashScreen();
  }
}
