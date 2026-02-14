import 'dart:async';
import 'package:flutter/material.dart';
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

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Web: Service-Worker auf Updates prüfen → automatischer Reload bei neuem Build
  sw_update.initServiceWorkerUpdateListener();

  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    debugPrint('RettBase Firebase: project=${Firebase.app().options.projectId}');
    unawaited(PushNotificationService.initialize());
  } catch (e) {
    debugPrint('Firebase Init Fehler: $e');
    // App trotzdem starten – läuft mit eingeschränkter Funktionalität
  }

  runApp(const RettBaseApp());
}

class RettBaseApp extends StatelessWidget {
  const RettBaseApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
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
        MaterialPageRoute(
          builder: (_) => const CompanyIdScreen(),
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
        MaterialPageRoute(
          builder: (_) => DashboardScreen(companyId: companyId),
        ),
      );
    } else {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => LoginScreen(companyId: companyId),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return const SplashScreen();
  }
}
