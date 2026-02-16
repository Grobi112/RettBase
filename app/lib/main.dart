import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:firebase_core/firebase_core.dart';
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
    initWebVersionCheck(_showWebUpdateBanner);
  }

  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    debugPrint('RettBase Firebase: project=${Firebase.app().options.projectId}');
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

void _showWebUpdateBanner() {
  final ctx = _navigatorKey.currentContext;
  if (ctx == null || !ctx.mounted) return;
  ScaffoldMessenger.of(ctx).clearMaterialBanners();
  ScaffoldMessenger.of(ctx).showMaterialBanner(
    MaterialBanner(
      content: const Text('Neue Version verfügbar'),
      backgroundColor: AppTheme.primary,
      contentTextStyle: const TextStyle(color: Colors.white),
      actions: [
        TextButton(
          onPressed: () {
            ScaffoldMessenger.of(ctx).clearMaterialBanners();
            if (ctx.mounted) _reloadWeb();
          },
          child: const Text('Jetzt neu laden', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
        ),
      ],
    ),
  );
}

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
    final kundeFuture = FirebaseFunctions.instanceFor(region: 'europe-west1')
        .httpsCallable('kundeExists')
        .call<Map<String, dynamic>>({'companyId': cid});
    final authFuture = FirebaseAuth.instance.authStateChanges().first;

    final results = await Future.wait([
      kundeFuture,
      authFuture,
      Future.delayed(const Duration(milliseconds: 400)),
    ]);
    if (!mounted) return;

    try {
      final res = results[0] as dynamic;
      final exists = res.data['exists'] == true;
      final docId = (res.data['docId'] as String?)?.trim().toLowerCase();
      if (exists && docId != null && docId.isNotEmpty && docId != cid) {
        companyId = docId;
        unawaited(prefs.setString('rettbase_company_id', docId));
      }
    } catch (_) {}

    final user = results[1] as dynamic;
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
