import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../app_config.dart';
import '../theme/app_theme.dart';
import 'login_screen.dart';

/// Unternehmen auswählen – Kunden-ID eingeben (z.B. admin für admin.rettbase.de).
class CompanyIdScreen extends StatefulWidget {
  const CompanyIdScreen({super.key});

  @override
  State<CompanyIdScreen> createState() => _CompanyIdScreenState();
}

class _CompanyIdScreenState extends State<CompanyIdScreen> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  String _normalizeKundenId(String value) {
    return value.trim().toLowerCase().replaceAll(RegExp(r'[^a-z0-9\-]'), '');
  }

  Future<void> _saveAndContinue() async {
    final raw = _controller.text.trim();
    final kundenId = raw.isEmpty ? AppConfig.defaultKundenId : _normalizeKundenId(raw);
    if (kundenId.isEmpty) {
      setState(() {
        _error = 'Bitte eine gültige Kunden-ID eingeben.';
      });
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final res = await FirebaseFunctions.instanceFor(region: 'europe-west1')
          .httpsCallable('kundeExists')
          .call<Map<String, dynamic>>({'companyId': kundenId});
      final exists = res.data['exists'] == true;

      if (!exists) {
        if (mounted) {
          setState(() {
            _loading = false;
            _error = 'Diese Kunden-ID existiert nicht. Bitte prüfen Sie die Eingabe.';
          });
        }
        return;
      }

      // docId = Firestore-Dokument-ID (kann von kundenId abweichen, wenn Kunden-ID geändert wurde)
      final docId = (res.data['docId'] as String?)?.trim().toLowerCase() ?? kundenId;

      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('rettbase_company_configured', true);
      await prefs.setString('rettbase_company_id', docId);
      await prefs.setString('rettbase_subdomain', kundenId);

      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => LoginScreen(companyId: docId),
        ),
      );
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = 'Kunde konnte nicht überprüft werden. Bitte prüfen Sie Ihre Verbindung.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.headerBg,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: EdgeInsets.symmetric(
              horizontal: Responsive.horizontalPadding(context),
              vertical: 20,
            ),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 400),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Image.asset(
                    'img/rettbase_splash.png',
                    height: Responsive.isCompact(context) ? 100 : 140,
                    fit: BoxFit.contain,
                  ),
                  const SizedBox(height: 48),
                  Text(
                    'Kunden-ID',
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.9),
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _controller,
                    focusNode: _focusNode,
                    textInputAction: TextInputAction.done,
                    keyboardType: TextInputType.text,
                    autocorrect: false,
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'[a-zA-Z0-9\-_]')),
                    ],
                    style: const TextStyle(color: Colors.white, fontSize: 16),
                    decoration: InputDecoration(
                      hintText: 'z.B. admin',
                      hintStyle: TextStyle(color: Colors.white.withOpacity(0.4)),
                      errorText: _error,
                      errorStyle: TextStyle(color: Colors.red.shade300, fontSize: 13),
                      errorMaxLines: 2,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(
                          color: _error != null ? Colors.red.shade400 : Colors.transparent,
                        ),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(
                          color: _error != null ? Colors.red.shade400 : AppTheme.primary,
                          width: 1.5,
                        ),
                      ),
                      filled: true,
                      fillColor: const Color(0xFF2D3139),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
                    ),
                    onSubmitted: (_) => _saveAndContinue(),
                  ),
                  const SizedBox(height: 32),
                  FilledButton(
                    onPressed: _loading ? null : _saveAndContinue,
                    style: FilledButton.styleFrom(
                      backgroundColor: AppTheme.primary,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 18),
                      elevation: 0,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: _loading
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
          ),
        ),
      ),
    );
  }
}
