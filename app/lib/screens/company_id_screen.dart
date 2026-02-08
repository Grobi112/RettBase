import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../app_config.dart';
import '../theme/app_theme.dart';
import 'login_screen.dart';

/// Unternehmen / Subdomain auswählen oder eingeben.
class CompanyIdScreen extends StatefulWidget {
  const CompanyIdScreen({super.key});

  @override
  State<CompanyIdScreen> createState() => _CompanyIdScreenState();
}

class _CompanyIdScreenState extends State<CompanyIdScreen> {
  final _controller = TextEditingController(text: AppConfig.defaultSubdomain);
  final _focusNode = FocusNode();
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  String _normalizeSubdomain(String value) {
    return value.trim().toLowerCase().replaceAll(RegExp(r'[^a-z0-9\-]'), '');
  }

  Future<void> _saveAndContinue() async {
    final raw = _controller.text.trim();
    final subdomain = raw.isEmpty ? AppConfig.defaultSubdomain : _normalizeSubdomain(raw);
    if (subdomain.isEmpty) {
      setState(() {
        _error = 'Bitte eine gültige Subdomain eingeben.';
      });
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('rettbase_company_configured', true);
      await prefs.setString('rettbase_company_id', subdomain);
      await prefs.setString('rettbase_subdomain', subdomain);

      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => LoginScreen(companyId: subdomain),
        ),
      );
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = 'Fehler beim Speichern: $e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.surfaceBg,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 48),
              Center(
                child: Image.asset(
                  'img/rettbase.png',
                  height: 72,
                  fit: BoxFit.contain,
                ),
              ),
              const SizedBox(height: 24),
              Text(
                'Unternehmen auswählen',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: AppTheme.textPrimary,
                    ),
              ),
              const SizedBox(height: 8),
              Text(
                'Gib die Subdomain deines RettBase-Kontos ein.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: AppTheme.textSecondary,
                  fontSize: 15,
                ),
              ),
              const SizedBox(height: 32),
              TextField(
                controller: _controller,
                focusNode: _focusNode,
                textInputAction: TextInputAction.done,
                keyboardType: TextInputType.text,
                autocorrect: false,
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[a-zA-Z0-9\-_\.]')),
                ],
                decoration: InputDecoration(
                  labelText: 'Subdomain',
                  hintText: 'z.B. admin',
                  suffixText: '.${AppConfig.rootDomain}',
                  errorText: _error,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                onSubmitted: (_) => _saveAndContinue(),
              ),
              const SizedBox(height: 16),
              ...AppConfig.knownSubdomains.map((s) => Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: OutlinedButton(
                      onPressed: _loading
                          ? null
                          : () {
                              _controller.text = s;
                              setState(() => _error = null);
                            },
                      child: Text('$s.${AppConfig.rootDomain}'),
                    ),
                  )),
              const SizedBox(height: 24),
              FilledButton(
                onPressed: _loading ? null : _saveAndContinue,
                style: FilledButton.styleFrom(
                  backgroundColor: AppTheme.primary,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                child: _loading
                    ? const SizedBox(
                        height: 24,
                        width: 24,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Text('Weiter'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
