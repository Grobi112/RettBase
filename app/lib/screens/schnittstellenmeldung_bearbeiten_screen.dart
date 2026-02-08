import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme/app_theme.dart';
import '../models/schnittstellenmeldung_model.dart';
import '../services/schnittstellenmeldung_service.dart';
import 'schnittstellenmeldung_druck_screen.dart';

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

/// Schnittstellenmeldung bearbeiten
class SchnittstellenmeldungBearbeitenScreen extends StatefulWidget {
  final String companyId;
  final Schnittstellenmeldung meldung;
  final VoidCallback onBack;

  const SchnittstellenmeldungBearbeitenScreen({
    super.key,
    required this.companyId,
    required this.meldung,
    required this.onBack,
  });

  @override
  State<SchnittstellenmeldungBearbeitenScreen> createState() => _SchnittstellenmeldungBearbeitenScreenState();
}

class _SchnittstellenmeldungBearbeitenScreenState extends State<SchnittstellenmeldungBearbeitenScreen> {
  final _service = SchnittstellenmeldungService();

  late final TextEditingController _datumCtrl;
  late final TextEditingController _uhrzeitCtrl;
  final _uhrzeitFocusNode = FocusNode();
  late final TextEditingController _einsatznummerCtrl;
  late final TextEditingController _leitstelleCtrl;
  late final TextEditingController _fbNummerCtrl;
  late final TextEditingController _schnPersonalCtrl;
  late final TextEditingController _rtwMzfCtrl;
  late final TextEditingController _nefCtrl;
  late final TextEditingController _besatzungCtrl;
  late final TextEditingController _arztCtrl;
  late final TextEditingController _vorkommnisCtrl;

  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final m = widget.meldung;
    _datumCtrl = TextEditingController(text: m.datum != null ? _formatDate(m.datum!) : '');
    _uhrzeitCtrl = TextEditingController(text: m.uhrzeit ?? '');
    _uhrzeitFocusNode.addListener(_onUhrzeitFocusChanged);
    _einsatznummerCtrl = TextEditingController(text: m.einsatznummer ?? '');
    _leitstelleCtrl = TextEditingController(text: m.leitstelle ?? '');
    _fbNummerCtrl = TextEditingController(text: m.fbNummer ?? '');
    _schnPersonalCtrl = TextEditingController(text: m.schnPersonal ?? '');
    _rtwMzfCtrl = TextEditingController(text: m.rtwMzf ?? '');
    _nefCtrl = TextEditingController(text: m.nef ?? '');
    _besatzungCtrl = TextEditingController(text: m.besatzung ?? '');
    _arztCtrl = TextEditingController(text: m.arzt ?? '');
    _vorkommnisCtrl = TextEditingController(text: m.vorkommnis);
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

    final datum = _parseDatum(_datumCtrl.text.trim()) ?? widget.meldung.datum ?? DateTime.now();

    final m = Schnittstellenmeldung(
      id: widget.meldung.id,
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
      companyId: widget.meldung.companyId,
      createdBy: widget.meldung.createdBy,
      createdByName: widget.meldung.createdByName,
      createdAt: widget.meldung.createdAt,
    );

    setState(() => _saving = true);
    try {
      await _service.update(widget.companyId, m);
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Änderungen gespeichert.')),
        );
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

  void _drucken() {
    final m = Schnittstellenmeldung(
      id: widget.meldung.id,
      datum: _parseDatum(_datumCtrl.text.trim()) ?? widget.meldung.datum,
      uhrzeit: _uhrzeitCtrl.text.trim().isNotEmpty ? _uhrzeitCtrl.text.trim() : null,
      einsatznummer: _einsatznummerCtrl.text.trim().isNotEmpty ? _einsatznummerCtrl.text.trim() : null,
      leitstelle: _leitstelleCtrl.text.trim().isNotEmpty ? _leitstelleCtrl.text.trim() : null,
      fbNummer: _fbNummerCtrl.text.trim().isNotEmpty ? _fbNummerCtrl.text.trim() : null,
      schnPersonal: _schnPersonalCtrl.text.trim().isNotEmpty ? _schnPersonalCtrl.text.trim() : null,
      rtwMzf: _rtwMzfCtrl.text.trim().isNotEmpty ? _rtwMzfCtrl.text.trim() : null,
      nef: _nefCtrl.text.trim().isNotEmpty ? _nefCtrl.text.trim() : null,
      besatzung: _besatzungCtrl.text.trim().isNotEmpty ? _besatzungCtrl.text.trim() : null,
      arzt: _arztCtrl.text.trim().isNotEmpty ? _arztCtrl.text.trim() : null,
      vorkommnis: _vorkommnisCtrl.text.trim(),
      companyId: widget.meldung.companyId,
      createdBy: widget.meldung.createdBy,
      createdByName: widget.meldung.createdByName,
      createdAt: widget.meldung.createdAt,
    );
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => SchnittstellenmeldungDruckScreen(
          meldung: m,
          onBack: () => Navigator.of(context).pop(),
        ),
      ),
    );
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.surfaceBg,
      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: AppTheme.primary,
        elevation: 1,
        leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: widget.onBack),
        title: Text('Schnittstellenmeldung bearbeiten', style: TextStyle(color: AppTheme.primary, fontWeight: FontWeight.w600)),
        actions: [
          IconButton(
            icon: const Icon(Icons.print),
            tooltip: 'Drucken',
            onPressed: _drucken,
          ),
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
