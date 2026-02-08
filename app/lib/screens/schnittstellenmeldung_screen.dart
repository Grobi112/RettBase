import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme/app_theme.dart';
import '../models/schnittstellenmeldung_model.dart';
import '../services/schnittstellenmeldung_service.dart';
import '../services/auth_data_service.dart';
import '../services/auth_service.dart';
import '../services/schnittstellenmeldung_config_service.dart';
import '../services/email_service.dart';
import 'schnittstellenmeldung_einstellungen_screen.dart';
import 'schnittstellenmeldung_uebersicht_screen.dart';

String _formatDate(DateTime d) {
  return '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.${d.year}';
}

/// Formatiert manuelle Uhrzeit-Eingabe (z.B. "0900" → "09:00", "930" → "09:30")
String _formatTimeInput(String s) {
  final digits = s.replaceAll(RegExp(r'[^\d]'), '');
  if (digits.isEmpty) return '';
  if (digits.length == 1) return '0$digits:00';
  if (digits.length == 2) {
    final h = (int.tryParse(digits) ?? 0).clamp(0, 23);
    return '${h.toString().padLeft(2, '0')}:00';
  }
  if (digits.length == 3) {
    final h = (int.tryParse(digits[0]) ?? 0).clamp(0, 9);
    final m = (int.tryParse(digits.substring(1)) ?? 0).clamp(0, 59);
    return '0$h:${m.toString().padLeft(2, '0')}';
  }
  final h = (int.tryParse(digits.substring(0, 2)) ?? 0).clamp(0, 23);
  final m = (int.tryParse(digits.substring(2, 4)) ?? 0).clamp(0, 59);
  return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}';
}

/// Rollen mit Zugriff auf Einstellungen (QM-Beauftragter E-Mails)
const _settingsRoles = ['superadmin', 'admin', 'geschaeftsfuehrung', 'rettungsdienstleitung'];

/// Schnittstellenmeldung – Formular zum Erfassen
class SchnittstellenmeldungScreen extends StatefulWidget {
  final String companyId;
  final String? userRole;
  final VoidCallback onBack;

  const SchnittstellenmeldungScreen({
    super.key,
    required this.companyId,
    this.userRole,
    required this.onBack,
  });

  @override
  State<SchnittstellenmeldungScreen> createState() => _SchnittstellenmeldungScreenState();
}

class _SchnittstellenmeldungScreenState extends State<SchnittstellenmeldungScreen> {
  final _service = SchnittstellenmeldungService();
  final _authService = AuthService();
  final _authDataService = AuthDataService();
  final _configService = SchnittstellenmeldungConfigService();
  final _emailService = EmailService();

  final _datumCtrl = TextEditingController();
  final _uhrzeitCtrl = TextEditingController();
  final _uhrzeitFocusNode = FocusNode();
  final _einsatznummerCtrl = TextEditingController();
  final _leitstelleCtrl = TextEditingController();
  final _fbNummerCtrl = TextEditingController();
  final _schnPersonalCtrl = TextEditingController();
  final _rtwMzfCtrl = TextEditingController();
  final _nefCtrl = TextEditingController();
  final _besatzungCtrl = TextEditingController();
  final _arztCtrl = TextEditingController();
  final _vorkommnisCtrl = TextEditingController();

  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _datumCtrl.text = _formatDate(DateTime.now());
    _uhrzeitCtrl.text = '';
    _uhrzeitFocusNode.addListener(_onUhrzeitFocusChanged);
  }

  void _onUhrzeitFocusChanged() {
    if (_uhrzeitFocusNode.hasFocus == false) {
      final t = _formatTimeInput(_uhrzeitCtrl.text.trim());
      if (t.isNotEmpty) {
        _uhrzeitCtrl.text = t;
        _uhrzeitCtrl.selection = TextSelection.collapsed(offset: t.length);
      }
    }
  }

  @override
  void dispose() {
    _uhrzeitFocusNode.removeListener(_onUhrzeitFocusChanged);
    _uhrzeitFocusNode.dispose();
    _datumCtrl.dispose();
    _uhrzeitCtrl.dispose();
    _einsatznummerCtrl.dispose();
    _leitstelleCtrl.dispose();
    _fbNummerCtrl.dispose();
    _schnPersonalCtrl.dispose();
    _rtwMzfCtrl.dispose();
    _nefCtrl.dispose();
    _besatzungCtrl.dispose();
    _arztCtrl.dispose();
    _vorkommnisCtrl.dispose();
    super.dispose();
  }

  Future<void> _sendQmBenachrichtigung() async {
    try {
      final emails = await _configService.loadQmEmails(widget.companyId);
      final subject = 'Neue Schnittstellenmeldung eingegangen';
      const body = 'Hallo,\n\nes ist eine neue Schnittstellenmeldung eingegangen. Diese kann in der Übersicht eingesehen werden.\n\nDein RettBase';
      for (final email in emails) {
        if (EmailService.isValidEmail(email)) {
          await _emailService.sendExternalEmail(
            widget.companyId,
            email,
            'QM-Beauftragter',
            subject,
            body,
            fromEmailOverride: 'noreply@rettbase.de',
            fromNameOverride: 'RettBase',
          );
        }
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('E-Mail-Benachrichtigung an QM-Beauftragten fehlgeschlagen.')),
        );
      }
    }
  }

  DateTime? _parseDatum(String s) {
    final parts = s.trim().split('.');
    if (parts.length != 3) return null;
    final d = int.tryParse(parts[0]);
    final m = int.tryParse(parts[1]);
    final y = int.tryParse(parts[2]);
    if (d == null || m == null || y == null) return null;
    return DateTime(y, m, d);
  }

  Future<void> _speichern() async {
    final vorkommnis = _vorkommnisCtrl.text.trim();
    if (vorkommnis.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Bitte Vorkommnis angeben.')),
      );
      return;
    }

    final user = _authService.currentUser;
    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Nicht angemeldet.')),
      );
      return;
    }

    final authData = await _authDataService.getAuthData(user.uid, user.email ?? '', widget.companyId);
    final displayName = authData.displayName ?? user.email ?? 'Unbekannt';

    final datum = _parseDatum(_datumCtrl.text.trim()) ?? DateTime.now();

    final m = Schnittstellenmeldung(
      id: '',
      datum: datum,
      uhrzeit: _uhrzeitCtrl.text.trim().isNotEmpty ? _uhrzeitCtrl.text.trim() : null,
      einsatznummer: _einsatznummerCtrl.text.trim().isNotEmpty ? _einsatznummerCtrl.text.trim() : null,
      leitstelle: _leitstelleCtrl.text.trim().isNotEmpty ? _leitstelleCtrl.text.trim() : null,
      fbNummer: _fbNummerCtrl.text.trim().isNotEmpty ? _fbNummerCtrl.text.trim() : null,
      schnPersonal: _schnPersonalCtrl.text.trim().isNotEmpty ? _schnPersonalCtrl.text.trim() : null,
      rtwMzf: _rtwMzfCtrl.text.trim().isNotEmpty ? _rtwMzfCtrl.text.trim() : null,
      nef: _nefCtrl.text.trim().isNotEmpty ? _nefCtrl.text.trim() : null,
      besatzung: _besatzungCtrl.text.trim().isNotEmpty ? _besatzungCtrl.text.trim() : null,
      arzt: _arztCtrl.text.trim().isNotEmpty ? _arztCtrl.text.trim() : null,
      vorkommnis: vorkommnis,
      companyId: widget.companyId,
      createdBy: user.uid,
      createdByName: displayName,
      createdAt: DateTime.now(),
    );

    setState(() => _saving = true);
    try {
      await _service.create(widget.companyId, m, user.uid, displayName);
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Schnittstellenmeldung gespeichert.')),
        );
        _vorkommnisCtrl.clear();
        _sendQmBenachrichtigung();
      }
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Fehler: $e')),
        );
      }
    }
  }

  Widget _buildField(TextEditingController ctrl, String label, {String? hint, int maxLines = 1}) {
    return TextFormField(
      controller: ctrl,
      maxLines: maxLines,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        border: const OutlineInputBorder(),
        filled: true,
        fillColor: Colors.white,
      ),
    );
  }

  Widget _buildTimeField(TextEditingController ctrl) {
    return TextFormField(
      controller: ctrl,
      focusNode: _uhrzeitFocusNode,
      keyboardType: TextInputType.datetime,
      inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[\d:]'))],
      decoration: const InputDecoration(
        labelText: 'Uhrzeit (HH:MM)',
        border: OutlineInputBorder(),
        filled: true,
        fillColor: Colors.white,
      ),
    );
  }

  bool get _canEditSettings {
    final r = (widget.userRole ?? '').toLowerCase().trim();
    return _settingsRoles.contains(r);
  }

  void _openEinstellungen() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => SchnittstellenmeldungEinstellungenScreen(
          companyId: widget.companyId,
          onBack: () => Navigator.of(context).pop(),
        ),
      ),
    );
  }

  void _openUebersicht() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => SchnittstellenmeldungUebersichtScreen(
          companyId: widget.companyId,
          onBack: () => Navigator.of(context).pop(),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.surfaceBg,
      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: AppTheme.primary,
        elevation: 1,
        leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: widget.onBack),
        title: Text('Schnittstellenmeldung', style: TextStyle(color: AppTheme.primary, fontWeight: FontWeight.w600)),
        actions: [
          if (_canEditSettings) ...[
            IconButton(
              icon: const Icon(Icons.list),
              tooltip: 'Übersicht',
              onPressed: _openUebersicht,
            ),
            IconButton(
              icon: const Icon(Icons.settings),
              tooltip: 'Einstellungen',
              onPressed: _openEinstellungen,
            ),
          ],
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    children: [
                      _buildField(_datumCtrl, 'Datum', hint: 'TT.MM.JJJJ'),
                      const SizedBox(height: 16),
                      _buildField(_einsatznummerCtrl, 'Einsatznummer'),
                      const SizedBox(height: 16),
                      _buildField(_fbNummerCtrl, 'FB-Nummer'),
                      const SizedBox(height: 16),
                      _buildField(_rtwMzfCtrl, 'RTW/MZF'),
                      const SizedBox(height: 16),
                      _buildField(_besatzungCtrl, 'Besatzung'),
                    ],
                  ),
                ),
                const SizedBox(width: 20),
                Expanded(
                  child: Column(
                    children: [
                      _buildTimeField(_uhrzeitCtrl),
                      const SizedBox(height: 16),
                      _buildField(_leitstelleCtrl, 'Leitstelle'),
                      const SizedBox(height: 16),
                      _buildField(_schnPersonalCtrl, 'Schn. Personal'),
                      const SizedBox(height: 16),
                      _buildField(_nefCtrl, 'NEF'),
                      const SizedBox(height: 16),
                      _buildField(_arztCtrl, 'Arzt'),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            _buildField(_vorkommnisCtrl, 'Vorkommnis', hint: 'Beschreiben Sie das Vorkommnis...', maxLines: 6),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: _saving ? null : _speichern,
              icon: _saving
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.save),
              label: Text(_saving ? 'Wird gespeichert…' : 'Speichern'),
              style: FilledButton.styleFrom(
                backgroundColor: Colors.green[700],
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
