import 'dart:html' as html;
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_functions/cloud_functions.dart';
import '../app_config.dart';
import '../theme/app_theme.dart';

/// Auf Web: Modul-URL mit Auth-Bridge (Custom-Token) für zentrale App-Hostung.
/// Ermöglicht iframe-Auth auch wenn Flutter-App und Modul unterschiedliche Origins haben.
Widget buildModuleIframe(String companyId, String modulePath) {
  return _ModuleAuthBridgeIframe(
    companyId: companyId,
    modulePath: modulePath,
  );
}

class _ModuleAuthBridgeIframe extends StatefulWidget {
  final String companyId;
  final String modulePath;

  const _ModuleAuthBridgeIframe({
    required this.companyId,
    required this.modulePath,
  });

  @override
  State<_ModuleAuthBridgeIframe> createState() => _ModuleAuthBridgeIframeState();
}

class _ModuleAuthBridgeIframeState extends State<_ModuleAuthBridgeIframe> {
  String? _iframeUrl;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadAuthAndBuildUrl();
  }

  Future<void> _loadAuthAndBuildUrl() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        if (mounted) setState(() => _error = 'Nicht angemeldet.');
        return;
      }
      final idToken = await user.getIdToken();
      if (idToken == null || idToken.isEmpty) {
        if (mounted) setState(() => _error = 'Token konnte nicht geladen werden.');
        return;
      }
      final callable = FirebaseFunctions.instanceFor(region: 'europe-west1').httpsCallable('exchangeToken');
      final result = await callable.call<Map<String, dynamic>>({'idToken': idToken});
      final customToken = result.data['customToken'] as String?;
      if (customToken == null || customToken.isEmpty) {
        if (mounted) setState(() => _error = 'Auth-Fehler.');
        return;
      }
      final base = 'https://${widget.companyId}.${AppConfig.rootDomain}';
      final redirect = '/${widget.modulePath.startsWith('/') ? widget.modulePath.substring(1) : widget.modulePath}';
      final authUrl = '$base/auth-callback.html?token=${Uri.encodeComponent(customToken)}&redirect=${Uri.encodeComponent(redirect)}';
      if (mounted) setState(() {
        _iframeUrl = authUrl;
        _error = null;
      });
    } catch (e) {
      if (mounted) setState(() => _error = 'Auth fehlgeschlagen: $e');
    }
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
              Text(_error!, textAlign: TextAlign.center),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: () {
                  setState(() => _error = null);
                  _loadAuthAndBuildUrl();
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
    if (_iframeUrl == null) {
      return const Center(child: CircularProgressIndicator(color: AppTheme.primary));
    }
    final url = _iframeUrl!;
    return HtmlElementView.fromTagName(
      tagName: 'iframe',
      onElementCreated: (el) {
        final iframe = el as html.IFrameElement;
        iframe.src = url;
        iframe.style.width = '100%';
        iframe.style.height = '100%';
        iframe.style.border = 'none';
      },
    );
  }
}
