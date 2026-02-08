import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme/app_theme.dart';
import '../models/uebergriffsmeldung_model.dart';
import '../services/uebergriffsmeldung_service.dart';
import '../utils/device_utils.dart';
import '../widgets/signature_pad.dart';
import 'uebergriffsmeldung_druck_screen.dart';

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

/// Uebergriffsmeldung bearbeiten
class UebergriffsmeldungBearbeitenScreen extends StatefulWidget {
  final String companyId;
  final Uebergriffsmeldung meldung;
  final VoidCallback onBack;

  const UebergriffsmeldungBearbeitenScreen({
    super.key,
    required this.companyId,
    required this.meldung,
    required this.onBack,
  });

  @override
  State<UebergriffsmeldungBearbeitenScreen> createState() => _UebergriffsmeldungBearbeitenScreenState();
}

class _UebergriffsmeldungBearbeitenScreenState extends State<UebergriffsmeldungBearbeitenScreen> {
  final _service = UebergriffsmeldungService();
  late final TextEditingController _ortCtrl;
  late final TextEditingController _datumCtrl;
  late final TextEditingController _uhrzeitCtrl;
  final _uhrzeitFocusNode = FocusNode();
  late final TextEditingController _beleidigungCtrl;
  late final TextEditingController _bedrohungCtrl;
  late final TextEditingController _bedrohungBeschreibungCtrl;
  late final TextEditingController _sachbeschaedigungCtrl;
  late final TextEditingController _koerperlicheGewaltCtrl;
  late final TextEditingController _koerperlicheGewaltBeschreibungCtrl;
  late final TextEditingController _sonstigesCtrl;
  late final TextEditingController _zeugenKollegenCtrl;
  late final TextEditingController _zeugenAndereCtrl;
  late final TextEditingController _tatverdaechtigWahrnehmungCtrl;
  late final TextEditingController _auffaelligkeitenAllgemeinCtrl;
  late final TextEditingController _beschreibungCtrl;
  late final TextEditingController _weitereHinweiseCtrl;

  late bool? _einsatzZusammenhang;
  late bool? _polizeilichRegistriert;
  late int _anzahlTatverdaechtige;
  late String? _artDesUebergriffs; // null=bitte wählen, beleidigung, bedrohung, koerperliche_gewalt, sonstiges
  final List<_TatverdaechtigeCtrls> _tatverdaechtigeCtrls = [];
  final _signatureKey = GlobalKey<SignaturePadState>();

  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final m = widget.meldung;
    final datumUhrzeit = (m.datumUhrzeit ?? '').trim();
    final parts = datumUhrzeit.split(' ');
    final datumStr = parts.isNotEmpty ? parts[0] : '';
    final uhrzeitStr = parts.length > 1 ? parts[1] : '';

    _ortCtrl = TextEditingController(text: m.ort ?? '');
    _datumCtrl = TextEditingController(text: datumStr);
    _uhrzeitCtrl = TextEditingController(text: uhrzeitStr);
    _beleidigungCtrl = TextEditingController(text: m.beleidigungWortlaut ?? '');
    _bedrohungCtrl = TextEditingController(text: m.bedrohung ?? '');
    _bedrohungBeschreibungCtrl = TextEditingController(text: m.bedrohungBeschreibung ?? '');
    _sachbeschaedigungCtrl = TextEditingController(text: m.sachbeschaedigung ?? '');
    _koerperlicheGewaltCtrl = TextEditingController(text: m.koerperlicheGewalt ?? '');
    _koerperlicheGewaltBeschreibungCtrl = TextEditingController(text: m.koerperlicheGewaltBeschreibung ?? '');
    _sonstigesCtrl = TextEditingController(text: m.sonstiges ?? '');
    _zeugenKollegenCtrl = TextEditingController(text: m.zeugenKollegen ?? '');
    _zeugenAndereCtrl = TextEditingController(text: m.zeugenAndere ?? '');
    _tatverdaechtigWahrnehmungCtrl = TextEditingController(text: m.tatverdaechtigWahrnehmung ?? '');
    _auffaelligkeitenAllgemeinCtrl = TextEditingController(text: m.auffaelligkeitenAllgemein ?? '');
    _beschreibungCtrl = TextEditingController(text: m.beschreibung ?? '');
    _weitereHinweiseCtrl = TextEditingController(text: m.weitereHinweise ?? '');

    _einsatzZusammenhang = m.einsatzZusammenhang;
    _polizeilichRegistriert = m.polizeilichRegistriert;
    _anzahlTatverdaechtige = m.anzahlTatverdaechtige > 0 ? m.anzahlTatverdaechtige : 1;
    _artDesUebergriffs = _inferArtDesUebergriffs(m);

    for (var i = 0; i < _anzahlTatverdaechtige; i++) {
      final c = _TatverdaechtigeCtrls();
      if (i < m.tatverdaechtigePersonen.length) {
        final p = m.tatverdaechtigePersonen[i];
        c.persoenlicheDaten.text = p.persoenlicheDaten ?? '';
        c.auffaelligkeiten.text = p.auffaelligkeiten ?? '';
        c.artDesUebergriffs.text = p.artDesUebergriffs ?? '';
      }
      _tatverdaechtigeCtrls.add(c);
    }
    _uhrzeitFocusNode.addListener(_onUhrzeitFocusChanged);
  }

  static String? _inferArtDesUebergriffs(Uebergriffsmeldung m) {
    if ((m.beleidigungWortlaut ?? '').trim().isNotEmpty) return 'beleidigung';
    if ((m.bedrohungBeschreibung ?? '').trim().isNotEmpty || (m.sachbeschaedigung ?? '').trim().isNotEmpty) return 'bedrohung';
    if ((m.koerperlicheGewaltBeschreibung ?? '').trim().isNotEmpty) return 'koerperliche_gewalt';
    if ((m.sonstiges ?? '').trim().isNotEmpty) return 'sonstiges';
    return null;
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

  void _ensureTatverdaechtigeCount() {
    while (_tatverdaechtigeCtrls.length < _anzahlTatverdaechtige) {
      _tatverdaechtigeCtrls.add(_TatverdaechtigeCtrls());
    }
    while (_tatverdaechtigeCtrls.length > _anzahlTatverdaechtige) {
      final c = _tatverdaechtigeCtrls.removeLast();
      c.dispose();
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
    if (d != null) setState(() => _datumCtrl.text = _formatDate(d));
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
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Bitte beschreiben Sie den Vorfall.')));
      return;
    }
    final isSimulator = await isSimulatorOrEmulator();
    if (!isSimulator && !_signatureKey.currentState!.hasContent && widget.meldung.unterschriftUrl == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Bitte unterschreiben Sie.')));
      return;
    }

    final datumStr = _datumCtrl.text.trim();
    if (datumStr.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Bitte Datum eingeben.')));
      return;
    }
    final parsed = _parseDatum(datumStr);
    if (parsed == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Bitte Datum im Format TT.MM.JJJJ eingeben (z.B. 07.02.2026).')),
      );
      return;
    }
    final datumFormatted = _formatDate(parsed);

    final personen = _tatverdaechtigeCtrls.map((c) => TatverdaechtigePerson(
          persoenlicheDaten: c.persoenlicheDaten.text.trim().isEmpty ? null : c.persoenlicheDaten.text.trim(),
          auffaelligkeiten: c.auffaelligkeiten.text.trim().isEmpty ? null : c.auffaelligkeiten.text.trim(),
          artDesUebergriffs: c.artDesUebergriffs.text.trim().isEmpty ? null : c.artDesUebergriffs.text.trim(),
        )).toList();

    String? unterschriftUrl = widget.meldung.unterschriftUrl;
    final signatureBytes = await _signatureKey.currentState?.captureImage();
    if (signatureBytes != null && signatureBytes.isNotEmpty) {
      unterschriftUrl = await _service.uploadUnterschrift(widget.companyId, widget.meldung.id, signatureBytes);
    }

    final m = Uebergriffsmeldung(
      id: widget.meldung.id,
      einsatzZusammenhang: _einsatzZusammenhang,
      melderName: widget.meldung.melderName,
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
      unterschriftUrl: unterschriftUrl,
      createdBy: widget.meldung.createdBy,
      createdByName: widget.meldung.createdByName,
      createdAt: widget.meldung.createdAt,
    );

    setState(() => _saving = true);
    try {
      await _service.update(widget.companyId, m);
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Aenderungen gespeichert.')));
      }
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Fehler: $e')));
      }
    }
  }

  void _drucken() {
    final m = Uebergriffsmeldung(
      id: widget.meldung.id,
      einsatzZusammenhang: _einsatzZusammenhang,
      melderName: widget.meldung.melderName,
      ort: _ortCtrl.text.trim().isEmpty ? null : _ortCtrl.text.trim(),
      datumUhrzeit: _uhrzeitCtrl.text.trim().isEmpty ? _datumCtrl.text.trim() : '${_datumCtrl.text.trim()} ${_uhrzeitCtrl.text.trim()}',
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
      tatverdaechtigePersonen: _tatverdaechtigeCtrls.map((c) => TatverdaechtigePerson(
            persoenlicheDaten: c.persoenlicheDaten.text.trim().isEmpty ? null : c.persoenlicheDaten.text.trim(),
            auffaelligkeiten: c.auffaelligkeiten.text.trim().isEmpty ? null : c.auffaelligkeiten.text.trim(),
            artDesUebergriffs: c.artDesUebergriffs.text.trim().isEmpty ? null : c.artDesUebergriffs.text.trim(),
          )).toList(),
      beschreibung: _beschreibungCtrl.text.trim(),
      weitereHinweise: _weitereHinweiseCtrl.text.trim().isEmpty ? null : _weitereHinweiseCtrl.text.trim(),
      unterschriftUrl: widget.meldung.unterschriftUrl,
      createdBy: widget.meldung.createdBy,
      createdByName: widget.meldung.createdByName,
      createdAt: widget.meldung.createdAt,
    );
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => UebergriffsmeldungDruckScreen(meldung: m, onBack: () => Navigator.of(context).pop()),
      ),
    );
  }

  static const _inputDecoration = InputDecoration(
    labelStyle: TextStyle(color: AppTheme.textSecondary),
    filled: true,
    fillColor: Colors.white,
    border: OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(10))),
    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(10)), borderSide: BorderSide(color: AppTheme.border)),
    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(10)), borderSide: BorderSide(color: AppTheme.primary, width: 1.5)),
    contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 14),
  );

  Widget _sectionCard({required String title, IconData icon = Icons.folder_outlined, required List<Widget> children}) =>
      Card(
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: Colors.grey.shade200)),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [Icon(icon, size: 20, color: AppTheme.primary), const SizedBox(width: 10), Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: AppTheme.textPrimary))]),
              const SizedBox(height: 20),
              ...children,
            ],
          ),
        ),
      );

  Widget _infoText(String text) => Container(
        padding: const EdgeInsets.all(14),
        margin: const EdgeInsets.only(bottom: 20),
        decoration: BoxDecoration(color: AppTheme.primary.withOpacity(0.06), borderRadius: BorderRadius.circular(10), border: Border(left: BorderSide(color: AppTheme.primary, width: 4))),
        child: Text(text, style: TextStyle(fontSize: 14, height: 1.5, color: AppTheme.textSecondary)),
      );

  Widget _field(TextEditingController ctrl, String label, {int maxLines = 1}) => Padding(
        padding: const EdgeInsets.only(bottom: 20),
        child: TextField(controller: ctrl, maxLines: maxLines, decoration: _inputDecoration.copyWith(labelText: label, alignLabelWithHint: maxLines > 1)),
      );

  Widget _dropdownBool(String label, bool? value, ValueChanged<bool?> onChanged) => Padding(
        padding: const EdgeInsets.only(bottom: 20),
        child: DropdownButtonFormField<bool>(
          value: value,
          decoration: _inputDecoration.copyWith(labelText: label),
          hint: const Text('Bitte waehlen'),
          borderRadius: BorderRadius.circular(10),
          items: const [DropdownMenuItem(value: true, child: Text('Ja')), DropdownMenuItem(value: false, child: Text('Nein'))],
          onChanged: onChanged,
        ),
      );

  Widget _dropdownAnzahl() => Padding(
        padding: const EdgeInsets.only(bottom: 20),
        child: DropdownButtonFormField<int>(
          value: _anzahlTatverdaechtige,
          decoration: _inputDecoration.copyWith(labelText: 'Wie viele Personen sind tatverdaechtig?'),
          borderRadius: BorderRadius.circular(10),
          items: List.generate(10, (i) => DropdownMenuItem(value: i + 1, child: Text('${i + 1}'))),
          onChanged: (v) {
            if (v != null) setState(() { _anzahlTatverdaechtige = v; _ensureTatverdaechtigeCount(); });
          },
        ),
      );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.surfaceBg,
      appBar: AppTheme.buildModuleAppBar(
        title: 'Übergriffsmeldung bearbeiten',
        onBack: widget.onBack,
        actions: [IconButton(icon: const Icon(Icons.print), tooltip: 'Drucken', onPressed: _drucken)],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _sectionCard(title: 'Einsatzdaten', icon: Icons.assignment_outlined, children: [
              _dropdownBool('Hat der Uebergriff/die Sachbeschaedigung im Zusammenhang mit einem Einsatz stattgefunden?', _einsatzZusammenhang, (v) => setState(() => _einsatzZusammenhang = v)),
            ]),
            const SizedBox(height: 16),
            _sectionCard(title: 'Persoenliche Daten', icon: Icons.person_outline, children: [
              Padding(padding: const EdgeInsets.only(bottom: 20), child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                decoration: BoxDecoration(color: Colors.grey.shade50, borderRadius: BorderRadius.circular(10), border: Border.all(color: AppTheme.border)),
                child: Text(widget.meldung.melderName ?? '-', style: TextStyle(fontSize: 16, color: AppTheme.textPrimary)),
              )),
            ]),
            const SizedBox(height: 16),
            _sectionCard(title: 'Ort und Zeitpunkt', icon: Icons.location_on_outlined, children: [
              _infoText('Da sich der Ort und Zeitpunkt des Uebergriffs/der Sachbeschaedigung nicht immer unmittelbar mit dem Einsatzort decken, ist hier eine persoenliche Eingabe durch die/den Meldenden erforderlich.'),
              _field(_ortCtrl, 'Ort des Uebergriffs/der Sachbeschaedigung', maxLines: 3),
              Padding(padding: const EdgeInsets.only(bottom: 20), child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Expanded(child: TextField(controller: _datumCtrl, keyboardType: TextInputType.datetime, inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[\d.]')), _DatumInputFormatter()], decoration: _inputDecoration.copyWith(labelText: 'Datum (TT.MM.JJJJ)', hintText: 'z.B. 07.02.2026', suffixIcon: IconButton(icon: const Icon(Icons.calendar_today), onPressed: _pickDatum)))),
                const SizedBox(width: 16),
                Expanded(child: TextField(controller: _uhrzeitCtrl, focusNode: _uhrzeitFocusNode, keyboardType: TextInputType.datetime, inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[\d:]'))], decoration: _inputDecoration.copyWith(labelText: 'Uhrzeit (HH:MM)', hintText: 'z.B. 09:00'))),
              ])),
            ]),
            const SizedBox(height: 16),
            _sectionCard(title: 'Arten des Übergriffs', icon: Icons.list_alt, children: [
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
            ]),
            const SizedBox(height: 16),
            _sectionCard(title: 'Weitere Angaben', icon: Icons.info_outline, children: [
              _dropdownBool('Wurde der Vorfall polizeilich registriert?', _polizeilichRegistriert, (v) => setState(() => _polizeilichRegistriert = v)),
              _field(_zeugenKollegenCtrl, 'Gibt es Kolleginnen bzw. Kollegen als Zeugen?', maxLines: 4),
              _field(_zeugenAndereCtrl, 'Gibt es andere Personen als Zeugen?', maxLines: 4),
            ]),
            const SizedBox(height: 16),
            _sectionCard(title: 'Tatverdaechtige', icon: Icons.people_outline, children: [
              _dropdownAnzahl(),
              _field(_tatverdaechtigWahrnehmungCtrl, 'Wer ist aus Ihrer Wahrnehmung tatverdaechtig?', maxLines: 4),
              _field(_auffaelligkeitenAllgemeinCtrl, 'Auffaelligkeiten, die zum Uebergriff gefuehrt haben koennen'),
              ...List.generate(_anzahlTatverdaechtige, (i) {
                final c = _tatverdaechtigeCtrls[i];
                return Padding(padding: const EdgeInsets.only(top: 24), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [Icon(Icons.person_outline, size: 18, color: AppTheme.textSecondary), const SizedBox(width: 8), Text('Tatverdaechtige Person ${i + 1}', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: AppTheme.textPrimary))]),
                  const SizedBox(height: 16),
                  _field(c.persoenlicheDaten, 'Persoenliche Daten', maxLines: 4),
                  _field(c.auffaelligkeiten, 'Auffaelligkeiten'),
                  _field(c.artDesUebergriffs, 'Art des Uebergriffs'),
                ]));
              }),
            ]),
            const SizedBox(height: 16),
            _sectionCard(title: 'Uebergriff / Sachbeschaedigung', icon: Icons.description_outlined, children: [
              _infoText('Bitte beschreiben Sie moeglichst genau, wie es zu dem Uebergriff/der Sachbeschaedigung gekommen ist.'),
              _field(_beschreibungCtrl, 'Beschreibung des Vorfalls', maxLines: 6),
              _field(_weitereHinweiseCtrl, 'Weitere Hinweise', maxLines: 4),
            ]),
            const SizedBox(height: 16),
            _sectionCard(title: 'Unterschrift', icon: Icons.draw_outlined, children: [
              SignaturePad(key: _signatureKey, height: 160),
            ]),
            const SizedBox(height: 28),
            FilledButton.icon(
              onPressed: _saving ? null : _speichern,
              icon: _saving ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Icon(Icons.save_outlined),
              label: Text(_saving ? 'Wird gespeichert...' : 'Speichern'),
              style: FilledButton.styleFrom(backgroundColor: AppTheme.primary, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 16), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)), elevation: 0),
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
