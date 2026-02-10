import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import '../app_config.dart';
import '../services/auth_service.dart';
import 'company_id_screen.dart';
import 'login_screen.dart';

/// Zeigt die RettBase-Webseite in einer WebView (Android/iOS).
/// Auf der Web-Plattform wird die URL im Browser geöffnet (WebView wird dort nicht unterstützt).
class WebViewScreen extends StatefulWidget {
  final String companyId;
  final String? loginEmail;
  final String? loginPassword;

  const WebViewScreen({
    super.key,
    required this.companyId,
    this.loginEmail,
    this.loginPassword,
  });

  @override
  State<WebViewScreen> createState() => _WebViewScreenState();
}

class _WebViewScreenState extends State<WebViewScreen> {
  WebViewController? _controller;
  bool _isLoading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    if (!kIsWeb) _initWebView();
    else _isLoading = false;
  }

  String _buildAuthBridgeHtml(String email, String password, String companyId) {
    final escapedEmail = jsonEncode(email);
    final escapedPassword = jsonEncode(password);
    final redirectUrl = 'https://$companyId.${AppConfig.rootDomain}/dashboard.html';
    return '''
<!DOCTYPE html>
<html>
<head><meta charset="UTF-8"><meta name="viewport" content="width=device-width,initial-scale=1"></head>
<body style="margin:0;display:flex;align-items:center;justify-content:center;min-height:100vh;font-family:sans-serif;background:#f5f5f5">
<div id="msg" style="text-align:center;padding:24px">Melde an…</div>
<script src="https://www.gstatic.com/firebasejs/11.0.1/firebase-app-compat.js"></script>
<script src="https://www.gstatic.com/firebasejs/11.0.1/firebase-auth-compat.js"></script>
<script>
var config = {
  apiKey: "AIzaSyCl67Qcs2Z655Y0507NG6o9WCL4twr65uc",
  authDomain: "rettbase-app.firebaseapp.com",
  projectId: "rettbase-app",
  storageBucket: "rettbase-app.firebasestorage.app",
  messagingSenderId: "339125193380",
  appId: "1:339125193380:web:350966b45a875fae8eb431"
};
firebase.initializeApp(config);
var auth = firebase.auth();
auth.signInWithEmailAndPassword($escapedEmail, $escapedPassword)
  .then(function() {
    window.location.replace("$redirectUrl");
  })
  .catch(function(err) {
    document.getElementById("msg").innerHTML = "<p style='color:red'>Fehler: " + (err.message || err.code) + "</p>";
  });
</script>
</body>
</html>''';
  }

  void _initWebView() {
    final ctrl = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.white)
      ..enableZoom(true)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (_) => setState(() {
            _isLoading = true;
            _errorMessage = null;
          }),
          onPageFinished: (_) {
            setState(() => _isLoading = false);
          },
          onWebResourceError: (error) => setState(() {
            _isLoading = false;
            _errorMessage = '${error.description} (${error.errorCode})';
          }),
          onNavigationRequest: (request) async {
            final uri = Uri.tryParse(request.url);
            if (uri == null) return NavigationDecision.navigate;

            if (uri.scheme == 'mailto' || uri.scheme == 'tel') {
              if (await canLaunchUrl(uri)) {
                await launchUrl(uri, mode: LaunchMode.externalApplication);
              }
              return NavigationDecision.prevent;
            }

            if (uri.path.endsWith('.pdf') || request.url.contains('download')) {
              if (await canLaunchUrl(uri)) {
                await launchUrl(uri, mode: LaunchMode.externalApplication);
              }
              return NavigationDecision.prevent;
            }

            return NavigationDecision.navigate;
          },
        ),
      );

    if (widget.loginEmail != null &&
        widget.loginPassword != null &&
        widget.loginEmail!.isNotEmpty &&
        widget.loginPassword!.isNotEmpty) {
      final html = _buildAuthBridgeHtml(
        widget.loginEmail!,
        widget.loginPassword!,
        widget.companyId,
      );
      final baseUrl = 'https://${widget.companyId}.${AppConfig.rootDomain}/';
      ctrl.loadHtmlString(html, baseUrl: baseUrl);
    } else {
      final url = AppConfig.getBaseUrl(widget.companyId);
      ctrl.loadRequest(Uri.parse(url));
    }
    setState(() => _controller = ctrl);
  }

  @override
  Widget build(BuildContext context) {
    // Web-Plattform: WebView wird nicht unterstützt → RettBase im Browser öffnen
    if (kIsWeb) {
      final url = AppConfig.getBaseUrl(widget.companyId);
      return Scaffold(
        appBar: AppBar(
          backgroundColor: const Color(0xFFE63946),
          foregroundColor: Colors.white,
          title: Text('RettBase – ${widget.companyId}.${AppConfig.rootDomain}'),
        ),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.open_in_browser, size: 64, color: Colors.grey[400]),
                const SizedBox(height: 16),
                Text(
                  'RettBase im Browser öffnen',
                  style: Theme.of(context).textTheme.titleLarge,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  'Die Webseite wird in einer neuen Registerkarte geöffnet.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey[600]),
                ),
                const SizedBox(height: 24),
                FilledButton.icon(
                  onPressed: () => launchUrl(Uri.parse(url), mode: LaunchMode.platformDefault),
                  icon: const Icon(Icons.open_in_new),
                  label: const Text('Jetzt öffnen'),
                  style: FilledButton.styleFrom(backgroundColor: const Color(0xFFE63946)),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        if (_controller != null && await _controller!.canGoBack()) {
          _controller!.goBack();
        } else {
          if (context.mounted) _showExitDialog();
        }
      },
      child: Scaffold(
        appBar: AppBar(
          backgroundColor: const Color(0xFFE63946),
          foregroundColor: Colors.white,
          title: Text('RettBase – ${widget.companyId}.${AppConfig.rootDomain}'),
          actions: [
            IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: _controller != null ? () => _controller!.reload() : null,
              tooltip: 'Aktualisieren',
            ),
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert),
              onSelected: (value) {
                if (value == 'change') {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const CompanyIdScreen(),
                    ),
                  );
                } else if (value == 'reload' && _controller != null) {
                  _controller!.reload();
                } else if (value == 'logout') {
                  _showLogoutDialog();
                }
              },
              itemBuilder: (_) => [
                const PopupMenuItem(
                  value: 'reload',
                  child: ListTile(
                    leading: Icon(Icons.refresh),
                    title: Text('Seite neu laden'),
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
                const PopupMenuItem(
                  value: 'change',
                  child: ListTile(
                    leading: Icon(Icons.business),
                    title: Text('Unternehmen wechseln'),
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
                const PopupMenuItem(
                  value: 'logout',
                  child: ListTile(
                    leading: Icon(Icons.logout),
                    title: Text('Abmelden'),
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
              ],
            ),
          ],
        ),
        body: _controller == null
            ? const Center(
                child: CircularProgressIndicator(color: Color(0xFFE63946)),
              )
            : Stack(
                children: [
                  if (_errorMessage != null)
                    Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.error_outline, size: 64, color: Colors.grey[400]),
                            const SizedBox(height: 16),
                            Text(
                              'Verbindungsfehler',
                              style: Theme.of(context).textTheme.titleLarge,
                            ),
                            const SizedBox(height: 8),
                            Text(
                              _errorMessage!,
                              textAlign: TextAlign.center,
                              style: TextStyle(color: Colors.grey[600]),
                            ),
                            const SizedBox(height: 24),
                            FilledButton.icon(
                              onPressed: () {
                                setState(() => _errorMessage = null);
                                _controller!.reload();
                              },
                              icon: const Icon(Icons.refresh),
                              label: const Text('Erneut versuchen'),
                              style: FilledButton.styleFrom(
                                backgroundColor: const Color(0xFFE63946),
                              ),
                            ),
                          ],
                        ),
                      ),
                    )
                  else
                    WebViewWidget(controller: _controller!),
                  if (_isLoading && _errorMessage == null)
                    Container(
                      color: Colors.white,
                      child: const Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            CircularProgressIndicator(color: Color(0xFFE63946)),
                            SizedBox(height: 16),
                            Text('Lade RettBase…'),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
      ),
    );
  }

  void _showLogoutDialog() {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Abmelden?'),
        content: const Text(
          'Sie werden abgemeldet und zur Anmeldung weitergeleitet.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Abbrechen'),
          ),
          FilledButton(
            onPressed: () async {
              Navigator.of(dialogContext).pop();
              await AuthService().logout();
              if (!mounted) return;
              Navigator.of(context).pushAndRemoveUntil(
                MaterialPageRoute(
                  builder: (_) => LoginScreen(companyId: widget.companyId),
                ),
                (route) => false,
              );
            },
            style: FilledButton.styleFrom(backgroundColor: const Color(0xFFE63946)),
            child: const Text('Abmelden'),
          ),
        ],
      ),
    );
  }

  void _showExitDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('RettBase beenden?'),
        content: const Text(
          'Möchtest du die App wirklich schließen?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Abbrechen'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.of(context).pop();
              SystemNavigator.pop();
            },
            style: FilledButton.styleFrom(backgroundColor: const Color(0xFFE63946)),
            child: const Text('Beenden'),
          ),
        ],
      ),
    );
  }
}
