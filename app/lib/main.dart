import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb, kDebugMode;
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'firebase_options.dart';
import 'services/push_notification_service.dart';
import 'app_config.dart';
import 'theme/app_theme.dart';
import 'screens/splash_screen.dart';
import 'screens/company_id_screen.dart';
import 'screens/login_screen.dart';
import 'screens/dashboard_screen.dart';
import 'utils/service_worker_update_stub.dart'
    if (dart.library.html) 'utils/service_worker_update_web.dart' as sw_update;
import 'utils/firebase_sw_register_stub.dart'
    if (dart.library.html) 'utils/firebase_sw_register_web.dart' as firebase_sw;
import 'utils/web_version_check.dart';
import 'utils/reload_web.dart' as rw;

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Web: Service-Worker auf Updates prüfen → automatischer Reload bei neuem Build
  sw_update.initServiceWorkerUpdateListener();

  if (kIsWeb) {
    initWebVersionCheck(_reloadWeb);  // Automatisch neu laden bei neuer Version (kein Banner)
  }

  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    debugPrint('RettBase Firebase: project=${Firebase.app().options.projectId}');
    await _initAppCheck();
    unawaited(PushNotificationService.initialize());
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

/// App Check aktivieren – schützt Cloud Functions (kundeExists, resolveLoginInfo) vor Enumerations-Angriffen.
/// Firebase Console: App Check Enforcement für Cloud Functions aktivieren, wenn bereit.
Future<void> _initAppCheck() async {
  try {
    final webKey = AppConfig.appCheckRecaptchaSiteKey;
    await FirebaseAppCheck.instance.activate(
      webProvider: (kIsWeb && webKey != null && webKey.isNotEmpty)
          ? ReCaptchaV3Provider(webKey)
          : null,
      androidProvider: kDebugMode ? AndroidProvider.debug : AndroidProvider.playIntegrity,
      appleProvider: kDebugMode ? AppleProvider.debug : AppleProvider.appAttest,
    );
    debugPrint('RettBase App Check: aktiv');
  } catch (e) {
    debugPrint('RettBase App Check Init Fehler: $e');
  }
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
  @override
  void initState() {
    super.initState();
    _initApp();
  }

  Future<void> _initApp() async {
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
    dynamic user;
    try {
      final kundeFuture = FirebaseFunctions.instanceFor(region: 'europe-west1')
          .httpsCallable('kundeExists')
          .call<Map<String, dynamic>>({'companyId': cid});
      final authFuture = FirebaseAuth.instance.authStateChanges().first;

      final results = await Future.wait([
        kundeFuture,
        authFuture,
        Future.delayed(const Duration(milliseconds: 400)),
      ]);
      kundeRes = results[0];
      user = results[1];
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
      final exists = res.data['exists'] == true;
      final docId = (res.data['docId'] as String?)?.trim().toLowerCase();
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
    } catch (_) {}

    if (!mounted) return;
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
