import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme/app_theme.dart';
import '../models/uebergriffsmeldung_model.dart';
import '../services/uebergriffsmeldung_service.dart';
import '../services/uebergriffsmeldung_config_service.dart';
import '../services/auth_data_service.dart';
import '../services/auth_service.dart';
import '../services/email_service.dart';
import '../utils/device_utils.dart';
import '../widgets/signature_pad.dart';
import 'uebergriffsmeldung_einstellungen_screen.dart';
import 'uebergriffsmeldung_uebersicht_screen.dart';

String _formatDate(DateTime d) =>
    '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.${d.year}';

class _DatumInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final digits = newValue.text.replaceAll(RegExp(r'[^\d]'), '');
    if (digits.length == 8) {
      final formatted = '${digits.substring(0, 2)}.${digits.substring(2, 4)}.${digits.substring(4, 8)}';
      return TextEditingValue(
        text: formatted,
        selection: TextSelection.collapsed(offset: formatted.length),
      );
    }
    return newValue;
  }
}

DateTime? _parseDatum(String s) {
  final t = s.trim();
  if (t.isEmpty) return null;
  final parts = t.split('.');
  if (parts.length != 3) return null;
  final tag = int.tryParse(parts[0]);
  final monat = int.tryParse(parts[1]);
  final jahr = int.tryParse(parts[2]);
  if (tag == null || monat == null || jahr == null) return null;
  if (jahr < 2000 || jahr > 2100) return null;
  if (monat < 1 || monat > 12) return null;
  if (tag < 1 || tag > 31) return null;
  try {
    return DateTime(jahr, monat, tag);
  } catch (_) {
    return null;
  }
}

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

const _settingsRoles = ['superadmin', 'admin', 'geschaeftsfuehrung', 'rettungsdienstleitung'];

/// Uebergriffsmeldung – Formular zum Erfassen von Uebergriffen/Sachbeschaedigungen
class UebergriffsmeldungScreen extends StatefulWidget {
  final String companyId;
  final String? userRole;
  final VoidCallback onBack;

  const UebergriffsmeldungScreen({
    super.key,
    required this.companyId,
    this.userRole,
    required this.onBack,
  });

  @override
  State<UebergriffsmeldungScreen> createState() => _UebergriffsmeldungScreenState();
}

class _UebergriffsmeldungScreenState extends State<UebergriffsmeldungScreen> {
  final _service = UebergriffsmeldungService();
  final _configService = UebergriffsmeldungConfigService();
  final _authService = AuthService();
  final _authDataService = AuthDataService();
  final _emailService = EmailService();

  final _ortCtrl = TextEditingController();
  final _datumCtrl = TextEditingController();
  final _uhrzeitCtrl = TextEditingController();
  final _uhrzeitFocusNode = FocusNode();
  final _beleidigungCtrl = TextEditingController();
  final _bedrohungCtrl = TextEditingController();
  final _bedrohungBeschreibungCtrl = TextEditingController();
  final _sachbeschaedigungCtrl = TextEditingController();
  final _koerperlicheGewaltCtrl = TextEditingController();
  final _koerperlicheGewaltBeschreibungCtrl = TextEditingController();
  final _sonstigesCtrl = TextEditingController();
  final _zeugenKollegenCtrl = TextEditingController();
  final _zeugenAndereCtrl = TextEditingController();
  final _tatverdaechtigWahrnehmungCtrl = TextEditingController();
  final _auffaelligkeitenAllgemeinCtrl = TextEditingController();
  final _beschreibungCtrl = TextEditingController();
  final _weitereHinweiseCtrl = TextEditingController();

  bool? _einsatzZusammenhang;
  bool? _polizeilichRegistriert;
  int _anzahlTatverdaechtige = 1;
  String? _artDesUebergriffs; // null=bitte wählen, beleidigung, bedrohung, koerperliche_gewalt, sonstiges
  final List<_TatverdaechtigeCtrls> _tatverdaechtigeCtrls = [];
  final _signatureKey = GlobalKey<SignaturePadState>();

  String _currentUserDisplayName = '';
  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _uhrzeitFocusNode.addListener(_onUhrzeitFocusChanged);
    _ensureTatverdaechtigeCount();
    _load();
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

  Future<void> _pickDatum() async {
    final initial = _parseDatum(_datumCtrl.text.trim()) ?? DateTime.now();
    final d = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (d != null) {
      setState(() => _datumCtrl.text = _formatDate(d));
    }
  }

  void _ensureTatverdaechtigeCount() {
    while (_tatverdaechtigeCtrls.length < _anzahlTatverdaechtige) {
      _tatverdaechtigeCtrls.add(_TatverdaechtigeCtrls());
    }
    while (_tatverdaechtigeCtrls.length > _anzahlTatverdaechtige) {
      final c = _tatverdaechtigeCtrls.removeLast();
      c.dispose();
    }
  }

  bool get _canEditSettings {
    final r = (widget.userRole ?? '').toLowerCase().trim();
    return _settingsRoles.contains(r);
  }

  void _openUebersicht() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => UebergriffsmeldungUebersichtScreen(
          companyId: widget.companyId,
          onBack: () => Navigator.of(context).pop(),
        ),
      ),
    );
  }

  void _openEinstellungen() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => UebergriffsmeldungEinstellungenScreen(
          companyId: widget.companyId,
          onBack: () => Navigator.of(context).pop(),
        ),
      ),
    );
  }

  Future<void> _sendQmBenachrichtigung() async {
    try {
      final emails = await _configService.loadQmEmails(widget.companyId);
      const subject = 'Neue Übergriffsmeldung eingegangen';
      const body = 'Hallo,\n\nes wurde eine neue Übergriffsmeldung eingereicht. Bitte logge dich ein, um sie zu lesen und zu bearbeiten.\n\nDein RettBase';
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

  Future<void> _load() async {
    final user = _authService.currentUser;
    String displayName = '';
    if (user != null) {
      final authData = await _authDataService.getAuthData(user.uid, user.email ?? '', widget.companyId);
      displayName = authData.displayName ?? user.email?.split('@').first ?? '';
    }
    if (mounted) {
      setState(() {
        _currentUserDisplayName = displayName;
        _loading = false;
      });
    }
  }

  @override
  void dispose() {
    _uhrzeitFocusNode.removeListener(_onUhrzeitFocusChanged);
    _uhrzeitFocusNode.dispose();
    _ortCtrl.dispose();
    _datumCtrl.dispose();
    _uhrzeitCtrl.dispose();
    _beleidigungCtrl.dispose();
    _bedrohungCtrl.dispose();
    _bedrohungBeschreibungCtrl.dispose();
    _sachbeschaedigungCtrl.dispose();
    _koerperlicheGewaltCtrl.dispose();
    _koerperlicheGewaltBeschreibungCtrl.dispose();
    _sonstigesCtrl.dispose();
    _zeugenKollegenCtrl.dispose();
    _zeugenAndereCtrl.dispose();
    _tatverdaechtigWahrnehmungCtrl.dispose();
    _auffaelligkeitenAllgemeinCtrl.dispose();
    _beschreibungCtrl.dispose();
    _weitereHinweiseCtrl.dispose();
    for (final c in _tatverdaechtigeCtrls) c.dispose();
    super.dispose();
  }

  Future<void> _speichern() async {
    final beschreibung = _beschreibungCtrl.text.trim();
    if (beschreibung.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Bitte beschreiben Sie den Vorfall.')),
      );
      return;
    }
    final isSimulator = await isSimulatorOrEmulator();
    if (!isSimulator && !_signatureKey.currentState!.hasContent) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Bitte unterschreiben Sie.')),
      );
      return;
    }

    final user = _authService.currentUser;
    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Nicht angemeldet.')));
      return;
    }

    final melderName = _currentUserDisplayName;

    final datumStr = _datumCtrl.text.trim();
    if (datumStr.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Bitte Datum eingeben.')),
      );
      return;
    }
    final parsed = _parseDatum(datumStr);
    if (parsed == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Bitte Datum im Format TT.MM.JJJJ eingeben (z.B. 07.02.2026).')),
      );
      return;
    }
    final datum = parsed;
    final datumFormatted = _formatDate(datum);

    final personen = _tatverdaechtigeCtrls.map((c) => TatverdaechtigePerson(
          persoenlicheDaten: c.persoenlicheDaten.text.trim().isEmpty ? null : c.persoenlicheDaten.text.trim(),
          auffaelligkeiten: c.auffaelligkeiten.text.trim().isEmpty ? null : c.auffaelligkeiten.text.trim(),
          artDesUebergriffs: c.artDesUebergriffs.text.trim().isEmpty ? null : c.artDesUebergriffs.text.trim(),
        )).toList();

    final m = Uebergriffsmeldung(
      id: '',
      einsatzZusammenhang: _einsatzZusammenhang,
      melderName: melderName.isEmpty ? null : melderName,
      ort: _ortCtrl.text.trim().isEmpty ? null : _ortCtrl.text.trim(),
      datumUhrzeit: _uhrzeitCtrl.text.trim().isEmpty ? datumFormatted : '$datumFormatted ${_uhrzeitCtrl.text.trim()}',
      beleidigungWortlaut: _beleidigungCtrl.text.trim().isEmpty ? null : _beleidigungCtrl.text.trim(),
      bedrohung: _bedrohungCtrl.text.trim().isEmpty ? null : _bedrohungCtrl.text.trim(),
      bedrohungBeschreibung: _bedrohungBeschreibungCtrl.text.trim().isEmpty ? null : _bedrohungBeschreibungCtrl.text.trim(),
      sachbeschaedigung: _sachbeschaedigungCtrl.text.trim().isEmpty ? null : _sachbeschaedigungCtrl.text.trim(),
      koerperlicheGewalt: _koerperlicheGewaltCtrl.text.trim().isEmpty ? null : _koerperlicheGewaltCtrl.text.trim(),
      koerperlicheGewaltBeschreibung: _koerperlicheGewaltBeschreibungCtrl.text.trim().isEmpty ? null : _koerperlicheGewaltBeschreibungCtrl.text.trim(),
      sonstiges: _sonstigesCtrl.text.trim().isEmpty ? null : _sonstigesCtrl.text.trim(),
      polizeilichRegistriert: _polizeilichRegistriert,
      zeugenKollegen: _zeugenKollegenCtrl.text.trim().isEmpty ? null : _zeugenKollegenCtrl.text.trim(),
      zeugenAndere: _zeugenAndereCtrl.text.trim().isEmpty ? null : _zeugenAndereCtrl.text.trim(),
      anzahlTatverdaechtige: _anzahlTatverdaechtige,
      tatverdaechtigWahrnehmung: _tatverdaechtigWahrnehmungCtrl.text.trim().isEmpty ? null : _tatverdaechtigWahrnehmungCtrl.text.trim(),
      auffaelligkeitenAllgemein: _auffaelligkeitenAllgemeinCtrl.text.trim().isEmpty ? null : _auffaelligkeitenAllgemeinCtrl.text.trim(),
      tatverdaechtigePersonen: personen,
      beschreibung: beschreibung,
      weitereHinweise: _weitereHinweiseCtrl.text.trim().isEmpty ? null : _weitereHinweiseCtrl.text.trim(),
      createdBy: user.uid,
      createdByName: melderName.isEmpty ? _currentUserDisplayName : melderName,
      createdAt: DateTime.now(),
    );

    setState(() => _saving = true);
    try {
      final docId = await _service.create(widget.companyId, m, user.uid, melderName.isEmpty ? _currentUserDisplayName : melderName);
      final signatureBytes = await _signatureKey.currentState?.captureImage();
      if (signatureBytes != null && signatureBytes.isNotEmpty) {
        final url = await _service.uploadUnterschrift(widget.companyId, docId, signatureBytes);
        await _service.updateUnterschriftUrl(widget.companyId, docId, url);
      }
      _sendQmBenachrichtigung();
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Uebergriffsmeldung gespeichert.')));
        widget.onBack();
      }
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Fehler: $e')));
      }
    }
  }

  static const _inputDecoration = InputDecoration(
    labelStyle: TextStyle(color: AppTheme.textSecondary),
    filled: true,
    fillColor: Colors.white,
    border: OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(10))),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.all(Radius.circular(10)),
      borderSide: BorderSide(color: AppTheme.border),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.all(Radius.circular(10)),
      borderSide: const BorderSide(color: AppTheme.primary, width: 1.5),
    ),
    contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 14),
  );

  Widget _sectionCard({
    required String title,
    IconData icon = Icons.folder_outlined,
    required List<Widget> children,
  }) =>
      Card(
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: Colors.grey.shade200)),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(icon, size: 20, color: AppTheme.primary),
                  const SizedBox(width: 10),
                  Text(
                    title,
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: AppTheme.textPrimary),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              ...children,
            ],
          ),
        ),
      );

  Widget _infoText(String text) => Container(
        padding: const EdgeInsets.all(14),
        margin: const EdgeInsets.only(bottom: 20),
        decoration: BoxDecoration(
          color: AppTheme.primary.withOpacity(0.06),
          borderRadius: BorderRadius.circular(10),
          border: Border(left: BorderSide(color: AppTheme.primary, width: 4)),
        ),
        child: Text(text, style: TextStyle(fontSize: 14, height: 1.5, color: AppTheme.textSecondary)),
      );

  Widget _field(TextEditingController ctrl, String label, {int maxLines = 1, String? hint}) => Padding(
        padding: const EdgeInsets.only(bottom: 20),
        child: TextField(
          controller: ctrl,
          maxLines: maxLines,
          decoration: _inputDecoration.copyWith(
            labelText: label,
            hintText: hint,
            alignLabelWithHint: maxLines > 1,
          ),
        ),
      );

  Widget _dropdownBool(String label, bool? value, ValueChanged<bool?> onChanged) => Padding(
        padding: const EdgeInsets.only(bottom: 20),
        child: DropdownButtonFormField<bool>(
          value: value,
          decoration: _inputDecoration.copyWith(labelText: label),
          hint: const Text('Bitte wählen'),
          borderRadius: BorderRadius.circular(10),
          items: const [
            DropdownMenuItem(value: true, child: Text('Ja')),
            DropdownMenuItem(value: false, child: Text('Nein')),
          ],
          onChanged: onChanged,
        ),
      );

  Widget _readOnlyField(String label, String value) => Padding(
        padding: const EdgeInsets.only(bottom: 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: TextStyle(fontSize: 12, color: AppTheme.textSecondary, fontWeight: FontWeight.w500),
            ),
            const SizedBox(height: 6),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: BoxDecoration(
                color: Colors.grey.shade50,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppTheme.border),
              ),
              child: Text(value.isEmpty ? '-' : value, style: TextStyle(fontSize: 16, color: AppTheme.textPrimary)),
            ),
          ],
        ),
      );

  Widget _dropdownAnzahlTatverdaechtige() => Padding(
        padding: const EdgeInsets.only(bottom: 20),
        child: DropdownButtonFormField<int>(
          value: _anzahlTatverdaechtige,
          decoration: _inputDecoration.copyWith(labelText: 'Wie viele Personen sind tatverdächtig?'),
          borderRadius: BorderRadius.circular(10),
          items: List.generate(10, (i) => DropdownMenuItem(value: i + 1, child: Text('${i + 1}'))),
          onChanged: (v) {
            if (v != null) {
              setState(() {
                _anzahlTatverdaechtige = v;
                _ensureTatverdaechtigeCount();
              });
            }
          },
        ),
      );

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(
        backgroundColor: AppTheme.surfaceBg,
        appBar: AppTheme.buildModuleAppBar(
          title: 'Übergriff',
          onBack: widget.onBack,
          actions: [
            if (_canEditSettings) ...[
              IconButton(icon: const Icon(Icons.list), tooltip: 'Übersicht', onPressed: _openUebersicht),
              IconButton(icon: const Icon(Icons.settings), tooltip: 'Einstellungen', onPressed: _openEinstellungen),
            ],
          ],
        ),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      backgroundColor: AppTheme.surfaceBg,
      appBar: AppTheme.buildModuleAppBar(
        title: 'Übergriff',
        onBack: widget.onBack,
        actions: [
          if (_canEditSettings) ...[
            IconButton(icon: const Icon(Icons.list), tooltip: 'Übersicht', onPressed: _openUebersicht),
            IconButton(icon: const Icon(Icons.settings), tooltip: 'Einstellungen', onPressed: _openEinstellungen),
          ],
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 8),
            // EINSATZDATEN
            _sectionCard(
              title: 'Einsatzdaten',
              icon: Icons.assignment_outlined,
              children: [
                _dropdownBool(
                  'Hat der Übergriff/die Sachbeschädigung im Zusammenhang mit einem Einsatz stattgefunden?',
                  _einsatzZusammenhang,
                  (v) => setState(() => _einsatzZusammenhang = v),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // PERSÖNLICHE DATEN
            _sectionCard(
              title: 'Persönliche Daten',
              icon: Icons.person_outline,
              children: [
                _readOnlyField('Nachname, Vorname', _currentUserDisplayName),
              ],
            ),
            const SizedBox(height: 16),

            // ORT UND ZEITPUNKT
            _sectionCard(
              title: 'Ort und Zeitpunkt',
              icon: Icons.location_on_outlined,
              children: [
                _infoText(
                  'Da sich der Ort und Zeitpunkt des Übergriffs/der Sachbeschädigung nicht immer unmittelbar mit dem Einsatzort decken, ist hier eine persönliche Eingabe durch die/den Meldenden erforderlich.',
                ),
                _field(_ortCtrl, 'Ort des Übergriffs/der Sachbeschädigung', maxLines: 3),
                Padding(
                  padding: const EdgeInsets.only(bottom: 20),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _datumCtrl,
                          keyboardType: TextInputType.datetime,
                          inputFormatters: [
                            FilteringTextInputFormatter.allow(RegExp(r'[\d.]')),
                            _DatumInputFormatter(),
                          ],
                          decoration: _inputDecoration.copyWith(
                            labelText: 'Datum (TT.MM.JJJJ)',
                            hintText: 'z.B. 07.02.2026',
                            suffixIcon: IconButton(
                              icon: const Icon(Icons.calendar_today),
                              onPressed: _pickDatum,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: TextField(
                          controller: _uhrzeitCtrl,
                          focusNode: _uhrzeitFocusNode,
                          keyboardType: TextInputType.datetime,
                          inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[\d:]'))],
                          decoration: _inputDecoration.copyWith(
                            labelText: 'Uhrzeit (HH:MM)',
                            hintText: 'z.B. 09:00',
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // ARTEN DES ÜBERGRIFFS
            _sectionCard(
              title: 'Arten des Übergriffs',
              icon: Icons.list_alt,
              children: [
                Padding(
                  padding: const EdgeInsets.only(bottom: 20),
                  child: DropdownButtonFormField<String>(
                    value: _artDesUebergriffs,
                    decoration: _inputDecoration.copyWith(labelText: 'Art des Übergriffs'),
                    hint: const Text('bitte wählen ...'),
                    borderRadius: BorderRadius.circular(10),
                    items: const [
                      DropdownMenuItem(value: 'beleidigung', child: Text('Beleidigung')),
                      DropdownMenuItem(value: 'bedrohung', child: Text('Bedrohung')),
                      DropdownMenuItem(value: 'koerperliche_gewalt', child: Text('Körperliche Gewalt')),
                      DropdownMenuItem(value: 'sonstiges', child: Text('Sonstiges')),
                    ],
                    onChanged: (v) => setState(() => _artDesUebergriffs = v),
                  ),
                ),
                if (_artDesUebergriffs == 'beleidigung')
                  _field(_beleidigungCtrl, 'Genauer Wortlaut der Beleidigung', maxLines: 4),
                if (_artDesUebergriffs == 'bedrohung') ...[
                  _field(_bedrohungBeschreibungCtrl, 'Beschreibung der Bedrohung', maxLines: 4),
                  _field(_sachbeschaedigungCtrl, 'Was wurde beschädigt? (RTW, Kleidung, etc.)', maxLines: 4),
                ],
                if (_artDesUebergriffs == 'koerperliche_gewalt')
                  _field(_koerperlicheGewaltBeschreibungCtrl, 'Beschreibung der körperlichen Gewalt', maxLines: 4),
                if (_artDesUebergriffs == 'sonstiges')
                  _field(_sonstigesCtrl, 'Sonstiges', maxLines: 4),
              ],
            ),
            const SizedBox(height: 16),

            // WEITERE ANGABEN
            _sectionCard(
              title: 'Weitere Angaben',
              icon: Icons.info_outline,
              children: [
                _dropdownBool('Wurde der Vorfall polizeilich registriert?', _polizeilichRegistriert, (v) => setState(() => _polizeilichRegistriert = v)),
                _field(_zeugenKollegenCtrl, 'Gibt es Kolleginnen bzw. Kollegen als Zeugen?', maxLines: 4),
                _field(_zeugenAndereCtrl, 'Gibt es andere Personen als Zeugen? (Angabe mit Kontaktdaten)', maxLines: 4),
              ],
            ),
            const SizedBox(height: 16),

            // TATVERDÄCHTIGE
            _sectionCard(
              title: 'Tatverdächtige',
              icon: Icons.people_outline,
              children: [
                _dropdownAnzahlTatverdaechtige(),
                _field(_tatverdaechtigWahrnehmungCtrl, 'Wer ist aus Ihrer Wahrnehmung tatverdächtig?', maxLines: 4),
                _field(_auffaelligkeitenAllgemeinCtrl, 'Auffälligkeiten, die zum Übergriff geführt haben können'),
                ...List.generate(_anzahlTatverdaechtige, (i) {
                  final c = _tatverdaechtigeCtrls[i];
                  return Padding(
                    padding: const EdgeInsets.only(top: 24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.person_outline, size: 18, color: AppTheme.textSecondary),
                            const SizedBox(width: 8),
                            Text(
                              'Tatverdächtige Person ${i + 1}',
                              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: AppTheme.textPrimary),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        _field(c.persoenlicheDaten, 'Persönliche Daten (Name, Anschrift, Geburtsdatum)', maxLines: 4),
                        _field(c.auffaelligkeiten, 'Auffälligkeiten, die zum Übergriff geführt haben können'),
                        _field(c.artDesUebergriffs, 'Art des Übergriffs/der Sachbeschädigung'),
                      ],
                    ),
                  );
                }),
              ],
            ),
            const SizedBox(height: 16),

            // ÜBERGRIFF/SACHBESCHÄDIGUNG
            _sectionCard(
              title: 'Übergriff / Sachbeschädigung',
              icon: Icons.description_outlined,
              children: [
                _infoText(
                  'Bitte beschreiben Sie möglichst genau, wie es zu dem Übergriff/der Sachbeschädigung gekommen ist; was ist konkret passiert? Wo befand sich die oder der Tatverdächtige? Wie war der Handlungsablauf?',
                ),
                _field(_beschreibungCtrl, 'Beschreibung des Vorfalls', maxLines: 6),
                _field(_weitereHinweiseCtrl, 'Weitere Hinweise', maxLines: 4),
              ],
            ),
            const SizedBox(height: 16),

            // UNTERSCHRIFT
            _sectionCard(
              title: 'Unterschrift',
              icon: Icons.draw_outlined,
              children: [
                SignaturePad(key: _signatureKey, height: 160),
              ],
            ),

            const SizedBox(height: 28),
            FilledButton.icon(
              onPressed: _saving ? null : _speichern,
              icon: _saving
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.save_outlined),
              label: Text(_saving ? 'Wird gespeichert…' : 'Speichern'),
              style: FilledButton.styleFrom(
                backgroundColor: AppTheme.primary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                elevation: 0,
              ),
            ),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }
}

class _TatverdaechtigeCtrls {
  final TextEditingController persoenlicheDaten = TextEditingController();
  final TextEditingController auffaelligkeiten = TextEditingController();
  final TextEditingController artDesUebergriffs = TextEditingController();

  void dispose() {
    persoenlicheDaten.dispose();
    auffaelligkeiten.dispose();
    artDesUebergriffs.dispose();
  }
}
