import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import '../app_config.dart';
import '../models/app_module.dart';
import '../theme/app_theme.dart';
// Iframe nur auf Web (gleicher Kontext → Auth/Cookies), Stub sonst.
import 'module_iframe_web.dart' if (dart.library.io) 'module_iframe_stub.dart' as module_iframe;

/// Zeigt ein Web-Modul (z. B. Mitgliederverwaltung, Modul-/Menü-Verwaltung) in der App.
/// - Native (Android/iOS): WebView mit optionaler Auth-Bridge.
/// - Web: iframe-Einbettung (gleicher Kontext wie die App → Auth/Cookies, Zugriff auf richtige Datenbank).
/// Alle Modul-URLs laufen über diese Komponente; Zugriff auf Firestore/Auth wie in der nativen App (rett-fe0fa).
class ModuleWebViewWidget extends StatefulWidget {
  final AppModule module;
  final String companyId;
  final String? loginEmail;
  final String? loginPassword;

  const ModuleWebViewWidget({
    super.key,
    required this.module,
    required this.companyId,
    this.loginEmail,
    this.loginPassword,
  });

  @override
  State<ModuleWebViewWidget> createState() => _ModuleWebViewWidgetState();
}

class _ModuleWebViewWidgetState extends State<ModuleWebViewWidget> {
  WebViewController? _controller;
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    if (!kIsWeb) _initWebView();
    else _isLoading = false;
  }

  String _fullUrl(String path) {
    final base = 'https://${widget.companyId}.${AppConfig.rootDomain}';
    final p = path.startsWith('/') ? path : '/$path';
    return '$base$p';
  }

  /// Auth-Callback-URL für native WebView (Chat etc.) – gleicher Flow wie Web-iframe.
  Future<String> _buildAuthCallbackUrl() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        if (mounted) setState(() => _error = 'Nicht angemeldet.');
        return '';
      }
      // Force refresh – verhindert "Token ungültig oder abgelaufen"
      final idToken = await user.getIdToken(true);
      if (idToken == null || idToken.isEmpty) {
        if (mounted) setState(() => _error = 'Token konnte nicht geladen werden.');
        return '';
      }
      final callable = FirebaseFunctions.instanceFor(region: 'europe-west1').httpsCallable('exchangeToken');
      final result = await callable.call<Map<String, dynamic>>({'idToken': idToken});
      final customToken = result.data['customToken'] as String?;
      if (customToken == null || customToken.isEmpty) {
        if (mounted) setState(() => _error = 'Auth-Fehler.');
        return '';
      }
      final base = 'https://${widget.companyId}.${AppConfig.rootDomain}';
      final redirect = '/${widget.module.url.startsWith('/') ? widget.module.url.substring(1) : widget.module.url}';
      return '$base/auth-callback.html?token=${Uri.encodeComponent(customToken)}&redirect=${Uri.encodeComponent(redirect)}';
    } catch (e) {
      if (mounted) setState(() => _error = 'Auth fehlgeschlagen: $e');
      return '';
    }
  }

  Future<void> _initWebView() async {
    String url;
    final needsEmailPassword = widget.loginEmail != null &&
        widget.loginPassword != null &&
        widget.loginEmail!.isNotEmpty &&
        widget.loginPassword!.isNotEmpty;

    if (needsEmailPassword) {
      url = _fullUrl(widget.module.url);
    } else if (widget.module.url.isNotEmpty) {
      url = await _buildAuthCallbackUrl();
      if (url.isEmpty && mounted) return;
    } else {
      url = _fullUrl(widget.module.url);
    }
    if (!mounted) return;

    final ctrl = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.white)
      ..enableZoom(true)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (_) => setState(() {
            _isLoading = true;
            _error = null;
          }),
          onPageFinished: (_) => setState(() => _isLoading = false),
          onWebResourceError: (e) => setState(() {
            _isLoading = false;
            _error = '${e.description} (${e.errorCode})';
          }),
          onNavigationRequest: (req) async {
            final uri = Uri.tryParse(req.url);
            if (uri == null) return NavigationDecision.navigate;
            if (uri.scheme == 'mailto' || uri.scheme == 'tel') {
              if (await canLaunchUrl(uri)) await launchUrl(uri, mode: LaunchMode.externalApplication);
              return NavigationDecision.prevent;
            }
            if (uri.path.endsWith('.pdf') || req.url.contains('download')) {
              if (await canLaunchUrl(uri)) await launchUrl(uri, mode: LaunchMode.externalApplication);
              return NavigationDecision.prevent;
            }
            return NavigationDecision.navigate;
          },
        ),
      );

    if (needsEmailPassword) {
      final html = _authBridgeHtml(widget.loginEmail!, widget.loginPassword!, url);
      final baseUrl = 'https://${widget.companyId}.${AppConfig.rootDomain}/';
      ctrl.loadHtmlString(html, baseUrl: baseUrl);
    } else {
      ctrl.loadRequest(Uri.parse(url));
    }
    if (mounted) setState(() => _controller = ctrl);
  }

  String _authBridgeHtml(String email, String password, String redirectUrl) {
    final e = jsonEncode(email);
    final p = jsonEncode(password);
    final r = jsonEncode(redirectUrl);
    return '''
<!DOCTYPE html><html><head><meta charset="UTF-8"></head>
<body style="margin:0;display:flex;align-items:center;justify-content:center;min-height:100vh;font-family:sans-serif">
<div id="msg">Melde an…</div>
<script src="https://www.gstatic.com/firebasejs/11.0.1/firebase-app-compat.js"></script>
<script src="https://www.gstatic.com/firebasejs/11.0.1/firebase-auth-compat.js"></script>
<script>
firebase.initializeApp({apiKey:"AIzaSyCBpI6-cT5PDbRzjNPsx_k03np4JK8AJtA",authDomain:"rett-fe0fa.firebaseapp.com",projectId:"rett-fe0fa",storageBucket:"rett-fe0fa.firebasestorage.app",messagingSenderId:"740721219821",appId:"1:740721219821:web:a8e7f8070f875866ccd4e4"});
firebase.auth().signInWithEmailAndPassword($e,$p).then(function(){window.location.replace($r);}).catch(function(err){document.getElementById("msg").innerHTML="<p style=color:red>Fehler: "+(err.message||err.code)+"</p>";});
</script></body></html>''';
  }

  @override
  Widget build(BuildContext context) {
    // Web-Plattform: Modul im iframe einbetten (gleicher Browser-Kontext → Auth/Cookies, Daten werden geladen)
    if (kIsWeb) {
      return SizedBox.expand(
        child: module_iframe.buildModuleIframe(widget.companyId, widget.module.url),
      );
    }

    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.error_outline, size: 48, color: Colors.grey[400]),
              const SizedBox(height: 16),
              Text('Verbindungsfehler', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              Text(_error!, textAlign: TextAlign.center, style: TextStyle(color: Colors.grey[600])),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: () {
                  setState(() => _error = null);
                  _initWebView();
                },
                icon: const Icon(Icons.refresh),
                label: const Text('Erneut versuchen'),
                style: FilledButton.styleFrom(backgroundColor: AppTheme.primary),
              ),
            ],
          ),
        ),
      );
    }

    if (_controller == null) {
      return const Center(child: CircularProgressIndicator(color: Color(0xFFE63946)));
    }

    return Stack(
      children: [
        WebViewWidget(controller: _controller!),
        if (_isLoading)
          Container(
            color: Colors.white,
            child: const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(color: Color(0xFFE63946)),
                  SizedBox(height: 16),
                  Text('Lade…'),
                ],
              ),
            ),
          ),
      ],
    );
  }
}
