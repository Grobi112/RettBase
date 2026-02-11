import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../app_config.dart';
import '../theme/app_theme.dart';
import '../services/login_service.dart';
import 'company_id_screen.dart';
import 'dashboard_screen.dart';

/// Kunden-ID für Firestore/Rollen konsistent kleinschreiben (z. B. "Admin" → "admin").
String _normalizeCompanyId(String companyId) =>
    companyId.trim().toLowerCase();

/// Login – einziger Einstieg für Web-App und Native App.
/// Nutzt [LoginService.resolveLoginEmail] (112+admin sowie alle anderen Kunden, gleiche Logik).
/// RettBase-Design, Logo, E-Mail/Personalnummer + Passwort.
class LoginScreen extends StatefulWidget {
  final String companyId;

  const LoginScreen({
    super.key,
    required this.companyId,
  });

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _loginService = LoginService();
  final _userController = TextEditingController();
  final _passwordController = TextEditingController();
  final _userFocus = FocusNode();
  final _passwordFocus = FocusNode();
  bool _obscurePassword = true;
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _userController.dispose();
    _passwordController.dispose();
    _userFocus.dispose();
    _passwordFocus.dispose();
    super.dispose();
  }

  String _translateAuthError(String? message, {String? code, String? resolvedEmail}) {
    if (code != null && code.isNotEmpty) {
      switch (code) {
        case 'user-not-found':
        case 'invalid-credential':
          return 'Passwort falsch oder Konto existiert nicht. Bei Personalnummer-Login wird das Konto beim ersten Login automatisch angelegt.';
        case 'wrong-password':
          return 'Falsches Passwort.';
        case 'too-many-requests':
          return 'Zu viele Versuche. Bitte später erneut versuchen.';
        case 'network-request-failed':
          return 'Keine Verbindung. Bitte prüfen Sie Ihr Netzwerk.';
        case 'user-disabled':
          return 'Dieses Konto wurde deaktiviert.';
      }
    }
    if (message == null || message.isEmpty) return 'Anmeldung fehlgeschlagen.';
    if (message.contains('malformed') || message.contains('invalid-credential')) {
      return 'Anmeldedaten ungültig. Bitte prüfen Sie E-Mail/Personalnummer und Passwort.';
    }
    if (message.contains('user-not-found')) return 'Kein Konto mit diesen Daten gefunden.';
    if (message.contains('wrong-password')) return 'Falsches Passwort.';
    if (message.contains('too-many-requests')) return 'Zu viele Versuche. Bitte später erneut versuchen.';
    if (message.contains('network')) return 'Keine Verbindung. Bitte prüfen Sie Ihr Netzwerk.';
    if (message.contains('expired')) return 'Anmeldedaten abgelaufen. Bitte erneut anmelden.';
    return message;
  }

  Future<void> _login() async {
    final userInput = _userController.text.trim();
    final password = _passwordController.text;

    if (userInput.isEmpty) {
      setState(() => _error = 'Bitte E-Mail oder Personalnummer eingeben.');
      _userFocus.requestFocus();
      return;
    }
    if (password.isEmpty) {
      setState(() => _error = 'Bitte Passwort eingeben.');
      _passwordFocus.requestFocus();
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    String resolvedEmail = '';
    String? mitarbeiterDocPath;
    String? effectiveCompanyId;
    try {
      final info = await _loginService.resolveLoginInfo(userInput, widget.companyId);
      resolvedEmail = info.email;
      mitarbeiterDocPath = info.mitarbeiterDocPath;
      effectiveCompanyId = info.effectiveCompanyId?.trim().toLowerCase();
      final dashboardCompanyId = (effectiveCompanyId != null && effectiveCompanyId.isNotEmpty)
          ? effectiveCompanyId
          : _normalizeCompanyId(widget.companyId);
      debugPrint('RettBase Login: Anmeldung mit E-Mail=$resolvedEmail (Company-ID=$dashboardCompanyId)');
      await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: resolvedEmail,
        password: password,
      );
      if (!mounted) return;
      if (effectiveCompanyId != null && effectiveCompanyId != _normalizeCompanyId(widget.companyId)) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('rettbase_company_id', effectiveCompanyId!);
      }
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => DashboardScreen(companyId: dashboardCompanyId),
        ),
      );
    } on FirebaseAuthException catch (e) {
      if (e.code == 'invalid-credential' || e.code == 'user-not-found') {
        try {
          debugPrint('RettBase Login: Account nicht vorhanden – erstelle Firebase Auth Nutzer für $resolvedEmail');
          final userCredential = await FirebaseAuth.instance.createUserWithEmailAndPassword(
            email: resolvedEmail,
            password: password,
          );
          if (mitarbeiterDocPath != null) {
            final updates = <String, dynamic>{
              'uid': userCredential.user!.uid,
              'updatedAt': FieldValue.serverTimestamp(),
            };
            if (resolvedEmail.endsWith('.${AppConfig.rootDomain}')) {
              updates['pseudoEmail'] = resolvedEmail;
              updates['email'] = resolvedEmail;
            }
            await FirebaseFirestore.instance.doc(mitarbeiterDocPath).set(updates, SetOptions(merge: true));
          }
          if (!mounted) return;
          final companyId = effectiveCompanyId != null && effectiveCompanyId.isNotEmpty
              ? effectiveCompanyId!
              : _normalizeCompanyId(widget.companyId);
          if (effectiveCompanyId != null && effectiveCompanyId != _normalizeCompanyId(widget.companyId)) {
            final prefs = await SharedPreferences.getInstance();
            await prefs.setString('rettbase_company_id', effectiveCompanyId!);
          }
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(
              builder: (_) => DashboardScreen(companyId: companyId),
            ),
          );
        } on FirebaseAuthException catch (createE) {
          if (!mounted) return;
          if (createE.code == 'email-already-in-use') {
            setState(() {
              _loading = false;
              _error = 'Passwort falsch. Bitte prüfen Sie Ihr Passwort.';
            });
          } else {
            setState(() {
              _loading = false;
              _error = _translateAuthError(createE.message, code: createE.code, resolvedEmail: resolvedEmail);
            });
          }
        }
      } else {
        if (!mounted) return;
        setState(() {
          _loading = false;
          _error = _translateAuthError(e.message, code: e.code, resolvedEmail: resolvedEmail.isNotEmpty ? resolvedEmail : null);
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = _translateAuthError(e.toString());
      });
    }
  }

  void _switchCompany() {
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => const CompanyIdScreen(),
      ),
    );
  }

  void _forgotPassword() async {
    final email = await showDialog<String>(
      context: context,
      builder: (ctx) {
        final ctrl = TextEditingController();
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text('Passwort vergessen?'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Geben Sie Ihre E-Mail-Adresse ein. Wir senden Ihnen einen Link zum Zurücksetzen des Passworts.',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: AppTheme.textSecondary),
              ),
              const SizedBox(height: 20),
              TextField(
                controller: ctrl,
                keyboardType: TextInputType.emailAddress,
                autocorrect: false,
                decoration: InputDecoration(
                  hintText: 'ihre@email.de',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  filled: true,
                  fillColor: const Color(0xFFF8FAFC),
                ),
                autofocus: true,
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Abbrechen')),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(ctrl.text.trim()),
              style: FilledButton.styleFrom(
                backgroundColor: AppTheme.primary,
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: const Text('Senden'),
            ),
          ],
        );
      },
    );
    if (email == null || email.isEmpty) return;
    try {
      await FirebaseAuth.instance.sendPasswordResetEmail(email: email);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('E-Mail zum Zurücksetzen wurde gesendet.'),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Fehler: $e'),
            behavior: SnackBarBehavior.floating,
            backgroundColor: Colors.red.shade700,
          ),
        );
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
                    'img/rettbase.png',
                    height: 64,
                    fit: BoxFit.contain,
                  ),
                  const SizedBox(height: 48),
                  Text(
                    'E-Mail oder Personalnummer',
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.9),
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _userController,
                    focusNode: _userFocus,
                    keyboardType: TextInputType.text,
                    autocorrect: false,
                    textInputAction: TextInputAction.next,
                    style: const TextStyle(color: Colors.white, fontSize: 16),
                    decoration: InputDecoration(
                      hintText: 'z.B. 112 oder deine@email.de',
                      hintStyle: TextStyle(color: Colors.white.withOpacity(0.4)),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(color: AppTheme.primary, width: 1.5),
                      ),
                      filled: true,
                      fillColor: const Color(0xFF2D3139),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
                    ),
                    onSubmitted: (_) => _passwordFocus.requestFocus(),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    'Passwort',
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.9),
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _passwordController,
                    focusNode: _passwordFocus,
                    obscureText: _obscurePassword,
                    textInputAction: TextInputAction.done,
                    style: const TextStyle(color: Colors.white, fontSize: 16),
                    decoration: InputDecoration(
                      hintText: 'Passwort eingeben',
                      hintStyle: TextStyle(color: Colors.white.withOpacity(0.4)),
                      suffixIcon: IconButton(
                        icon: Icon(
                          _obscurePassword ? Icons.visibility_rounded : Icons.visibility_off_rounded,
                          color: Colors.white.withOpacity(0.5),
                          size: 22,
                        ),
                        onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                      ),
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
                    onSubmitted: (_) => _login(),
                  ),
                  const SizedBox(height: 32),
                  FilledButton(
                    onPressed: _loading ? null : _login,
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
                        : const Text('Login', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                  ),
                  const SizedBox(height: 20),
                  Center(
                    child: TextButton(
                      onPressed: _loading ? null : _forgotPassword,
                      style: TextButton.styleFrom(foregroundColor: AppTheme.primary),
                      child: const Text('Passwort vergessen?', style: TextStyle(fontSize: 14)),
                    ),
                  ),
                  const SizedBox(height: 24),
                  Center(
                    child: TextButton.icon(
                      onPressed: _loading ? null : _switchCompany,
                      icon: Icon(Icons.business_rounded, size: 18, color: Colors.white.withOpacity(0.9)),
                      label: Text(
                        'Unternehmen wechseln',
                        style: TextStyle(color: Colors.white.withOpacity(0.9), fontSize: 14),
                      ),
                    ),
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
