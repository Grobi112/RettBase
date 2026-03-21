import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart'
    show kIsWeb, kDebugMode, defaultTargetPlatform, TargetPlatform;
import 'dart:ui' show PlatformDispatcher;
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'firebase_options.dart';
import 'services/push_notification_service.dart';
import 'services/background_push_handler.dart' as bg_push;
import 'services/app_update_service.dart';
import 'services/chat_offline_queue.dart';
import 'theme/app_theme.dart';
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
/// Stumme Chats: Badge-Update überspringen (Cloud Function sendet idealerweise keinen Push).
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  final data = message.data;
  if (data == null) return;

  // Android-Alarm: Data-only FCM → hier lokale Notification (Kanal/Ton aus App), sichtbar + hörbar.
  if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
    final t = (data['type'] as String? ?? '');
    if (t == 'alarm') {
      try {
        await bg_push.initBackgroundNotifications();
        await bg_push.showAlarmNotificationFromBackground(message);
      } catch (_) {}
      return;
    }
  }

  if ((data['type'] as String? ?? '') != 'chat') return;
  final companyId = (data['companyId'] as String? ?? '').trim();
  final chatId = (data['chatId'] as String? ?? '').trim();
  if (companyId.isEmpty || chatId.isEmpty) return;

  // Stummschaltung prüfen – wenn Chat stumm, kein Badge-Update
  try {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      final prefs = await FirebaseFirestore.instance
          .collection('kunden')
          .doc(companyId)
          .collection('chatPrefs')
          .doc(user.uid)
          .get();
      final muted = (prefs.data()?['mutedChatIds'] as List?)?.map((e) => e.toString().trim()).where((s) => s.isNotEmpty).toList() ?? [];
      if (muted.contains(chatId)) return; // Stumm – nichts tun
    }
  } catch (_) {}

  final badgeStr = data['totalUnread'] ?? data['badge'];
  if (badgeStr != null && badgeStr.toString().isNotEmpty) {
    final badge = int.tryParse(badgeStr.toString());
    if (badge != null && badge >= 0) {
      await PushNotificationService.updateBadge(badge);
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
    if (!kIsWeb) {
      unawaited(ChatOfflineQueue.init().catchError((e) {
        if (kDebugMode) debugPrint('RettBase ChatOfflineQueue Init: $e');
      }));
    }
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
      await _initAppImpl(context);
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

  Future<void> _initAppImpl(BuildContext context) async {
    // APK-Update: erst nach erstem Frame + Root-Navigator – sonst fehlt oft der Overlay/Context
    // und der Dialog erscheint nicht (Splash/Home-Context zu früh).
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      final done = Completer<void>();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        unawaited((() async {
          try {
            final navCtx = _navigatorKey.currentContext;
            final ctx = (navCtx != null && navCtx.mounted) ? navCtx : context;
            if (ctx.mounted) {
              await maybePromptAndroidApkUpdate(ctx);
            }
          } catch (e, st) {
            if (kDebugMode) debugPrint('RettBase APK-Update Rahmen: $e\n$st');
          } finally {
            if (!done.isCompleted) done.complete();
          }
        })());
      });
      await done.future;
    }

    final prefs = await SharedPreferences.getInstance();

    final companyConfigured = prefs.getBool('rettbase_company_configured') ?? false;
    var companyId = prefs.getString('rettbase_company_id') ??
        prefs.getString('rettbase_subdomain') ??
        '';

    if (!companyConfigured || companyId.isEmpty) {
      if (!mounted) return;
      _setProgress(1.0);
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
    final viewInsets = MediaQuery.of(context).viewInsets;
    final keyboardVisible = viewInsets.bottom > 0;
    return Scaffold(
      resizeToAvoidBottomInset: true,
      body: SizedBox.expand(
        child: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                AppTheme.navyLight,
                AppTheme.navy,
                AppTheme.navyDark,
              ],
              stops: [0.0, 0.55, 1.0],
            ),
          ),
          child: SafeArea(
            child: SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: EdgeInsets.only(
                left: Responsive.horizontalPadding(context),
                right: Responsive.horizontalPadding(context),
                top: keyboardVisible ? 12 : 24,
                bottom: keyboardVisible ? viewInsets.bottom + 16 : 24,
              ),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 400),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Image.asset(
                        'img/rettbase-logo.png',
                        height: keyboardVisible ? 56 : 80,
                        fit: BoxFit.contain,
                      ),
                      SizedBox(height: keyboardVisible ? 20 : 36),
                      if (_companyIdHint != null) ...[
                        Text(
                          _companyIdHint!,
                          style: TextStyle(color: Colors.amber.shade200, fontSize: 13),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 16),
                      ],
                      Container(
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(20),
                          border: Border(
                            top: BorderSide(
                              color: AppTheme.primary.withValues(alpha: 0.6),
                              width: 1.5,
                            ),
                          ),
                        ),
                        padding: const EdgeInsets.fromLTRB(20, 24, 20, 24),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
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
                                labelText: 'Kunden-ID',
                                labelStyle: TextStyle(color: Colors.white.withValues(alpha: 0.55)),
                                floatingLabelStyle: const TextStyle(color: AppTheme.skyBlue, fontSize: 13),
                                floatingLabelBehavior: FloatingLabelBehavior.auto,
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                                enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: BorderSide(
                                    color: _companyIdError != null ? AppTheme.errorVivid : Colors.transparent,
                                  ),
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: BorderSide(
                                    color: _companyIdError != null ? AppTheme.errorVivid : AppTheme.primary,
                                    width: 1.5,
                                  ),
                                ),
                                filled: true,
                                fillColor: AppTheme.navyLight,
                                contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
                              ),
                              onSubmitted: (_) => _submitCompanyId(),
                            ),
                            const SizedBox(height: 16),
                            AnimatedSize(
                              duration: const Duration(milliseconds: 200),
                              curve: Curves.easeInOut,
                              child: _companyIdError != null
                                  ? Container(
                                      margin: const EdgeInsets.only(bottom: 16),
                                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                                      decoration: BoxDecoration(
                                        color: AppTheme.errorVivid.withValues(alpha: 0.12),
                                        borderRadius: BorderRadius.circular(10),
                                        border: Border.all(
                                          color: AppTheme.errorVivid.withValues(alpha: 0.35),
                                        ),
                                      ),
                                      child: Row(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          const Padding(
                                            padding: EdgeInsets.only(top: 1),
                                            child: Icon(Icons.error_outline_rounded, color: AppTheme.errorLight, size: 18),
                                          ),
                                          const SizedBox(width: 10),
                                          Expanded(
                                            child: Text(
                                              _companyIdError!,
                                              style: const TextStyle(color: AppTheme.errorLight, fontSize: 13, height: 1.4),
                                            ),
                                          ),
                                        ],
                                      ),
                                    )
                                  : const SizedBox.shrink(),
                            ),
                            FilledButton(
                              onPressed: _companyIdLoading ? null : _submitCompanyId,
                              style: FilledButton.styleFrom(
                                backgroundColor: AppTheme.primary,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(vertical: 18),
                                elevation: 0,
                                shape: const StadiumBorder(),
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
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
