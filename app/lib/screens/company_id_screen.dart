import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../app_config.dart';
import '../theme/app_theme.dart';
import 'login_screen.dart';

/// Unternehmen auswählen – Kunden-ID eingeben (z.B. admin für admin.rettbase.de).
class CompanyIdScreen extends StatefulWidget {
  /// Vorausgefüllte Kunden-ID (z.B. wenn vorheriger Check fehlgeschlagen ist).
  final String? initialCompanyId;
  /// Hinweis, warum der Screen gezeigt wird (z.B. nach Fehler).
  final String? retryHint;

  const CompanyIdScreen({
    super.key,
    this.initialCompanyId,
    this.retryHint,
  });

  @override
  State<CompanyIdScreen> createState() => _CompanyIdScreenState();
}

class _CompanyIdScreenState extends State<CompanyIdScreen> {
  late final TextEditingController _controller;
  final _focusNode = FocusNode();
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialCompanyId ?? '');
  }

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
    final kundenId = raw.isEmpty ? '' : _normalizeKundenId(raw);
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
    } on FirebaseFunctionsException catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = e.code == 'resource-exhausted'
              ? 'Zu viele Anfragen. Bitte später erneut versuchen.'
              : 'Kunde konnte nicht überprüft werden. Bitte prüfen Sie Ihre Verbindung.';
        });
      }
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
                      if (widget.retryHint != null) ...[
                        Text(
                          widget.retryHint!,
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
                                labelText: 'Kunden-ID',
                                labelStyle: TextStyle(color: Colors.white.withValues(alpha: 0.55)),
                                floatingLabelStyle: const TextStyle(color: AppTheme.skyBlue, fontSize: 13),
                                floatingLabelBehavior: FloatingLabelBehavior.auto,
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                                enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: BorderSide(
                                    color: _error != null ? AppTheme.errorVivid : Colors.transparent,
                                  ),
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: BorderSide(
                                    color: _error != null ? AppTheme.errorVivid : AppTheme.primary,
                                    width: 1.5,
                                  ),
                                ),
                                filled: true,
                                fillColor: AppTheme.navyLight,
                                contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
                              ),
                              onSubmitted: (_) => _saveAndContinue(),
                            ),
                            const SizedBox(height: 16),
                            AnimatedSize(
                              duration: const Duration(milliseconds: 200),
                              curve: Curves.easeInOut,
                              child: _error != null
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
                                              _error!,
                                              style: const TextStyle(color: AppTheme.errorLight, fontSize: 13, height: 1.4),
                                            ),
                                          ),
                                        ],
                                      ),
                                    )
                                  : const SizedBox.shrink(),
                            ),
                            FilledButton(
                              onPressed: _loading ? null : _saveAndContinue,
                              style: FilledButton.styleFrom(
                                backgroundColor: AppTheme.primary,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(vertical: 18),
                                elevation: 0,
                                shape: const StadiumBorder(),
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
