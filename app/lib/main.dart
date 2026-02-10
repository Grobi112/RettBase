import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'firebase_options.dart';
import 'app_config.dart';
import 'theme/app_theme.dart';
import 'screens/splash_screen.dart';
import 'screens/company_id_screen.dart';
import 'screens/login_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    debugPrint('RettBase Firebase: project=${Firebase.app().options.projectId}');
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
    await Future.delayed(const Duration(milliseconds: 1500));
    if (!mounted) return;

    final prefs = await SharedPreferences.getInstance();
    // Kunden-ID nur einmal abfragen: nach dem ersten Eintrag direkt zum Login.
    final companyConfigured = prefs.getBool('rettbase_company_configured') ?? false;
    final companyId = prefs.getString('rettbase_company_id') ??
        prefs.getString('rettbase_subdomain') ??
        '';

    if (!mounted) return;

    if (!companyConfigured || companyId.isEmpty) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => const CompanyIdScreen(),
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
