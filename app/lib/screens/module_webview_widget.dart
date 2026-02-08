import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import '../theme/app_theme.dart';
import 'package:url_launcher/url_launcher.dart';
import '../app_config.dart';
import '../models/app_module.dart';

/// Zeigt ein Modul in der Web-App (mit Auth-Bridge)
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
  late final WebViewController _controller;
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _initWebView();
  }

  String _fullUrl(String path) {
    final base = 'https://${widget.companyId}.${AppConfig.rootDomain}';
    final p = path.startsWith('/') ? path : '/$path';
    return '$base$p';
  }

  void _initWebView() {
    final url = _fullUrl(widget.module.url);

    final needsAuth = widget.loginEmail != null &&
        widget.loginPassword != null &&
        widget.loginEmail!.isNotEmpty &&
        widget.loginPassword!.isNotEmpty;

    _controller = WebViewController()
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

    if (needsAuth) {
      final html = _authBridgeHtml(widget.loginEmail!, widget.loginPassword!, url);
      final baseUrl = 'https://${widget.companyId}.${AppConfig.rootDomain}/';
      _controller.loadHtmlString(html, baseUrl: baseUrl);
    } else {
      _controller.loadRequest(Uri.parse(url));
    }
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

    return Stack(
      children: [
        WebViewWidget(controller: _controller),
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
