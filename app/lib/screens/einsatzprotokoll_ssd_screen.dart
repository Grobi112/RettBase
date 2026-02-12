import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:pointer_interceptor/pointer_interceptor.dart';
import '../theme/app_theme.dart';
import '../services/einsatzprotokoll_ssd_service.dart';
import '../services/auth_service.dart';
import '../services/auth_data_service.dart';
import '../widgets/sketch_canvas.dart';
import '../widgets/signature_pad.dart';

String _formatDate(DateTime d) =>
    '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.${d.year}';

String _formatZeitstempel(DateTime d) =>
    '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

const _inputDecoration = InputDecoration(
  filled: true,
  fillColor: Colors.white,
  border: OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(10))),
  enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(10)), borderSide: BorderSide(color: AppTheme.border)),
  focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(10)), borderSide: BorderSide(color: AppTheme.primary, width: 1.5)),
  contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 14),
);

/// Einsatzprotokoll des Schulsanitätsdienstes – Formular
class EinsatzprotokollSsdScreen extends StatefulWidget {
  final String companyId;
  final VoidCallback onBack;

  const EinsatzprotokollSsdScreen({super.key, required this.companyId, required this.onBack});

  @override
  State<EinsatzprotokollSsdScreen> createState() => _EinsatzprotokollSsdScreenState();
}

class _EinsatzprotokollSsdScreenState extends State<EinsatzprotokollSsdScreen> {
  final _service = EinsatzprotokollSsdService();
  final _authService = AuthService();
  final _authDataService = AuthDataService();
  final _formKey = GlobalKey<FormState>();
  final _sketchKey = GlobalKey<SketchCanvasState>();
  final _signatureKey1 = GlobalKey<SignaturePadState>();
  final _signatureKey2 = GlobalKey<SignaturePadState>();

  final _protokollNrCtrl = TextEditingController();
  final _vornameErkrankterCtrl = TextEditingController();
  final _nameErkrankterCtrl = TextEditingController();
  final _geburtsdatumCtrl = TextEditingController();
  final _klasseCtrl = TextEditingController();

  final _vornameHelfer1Ctrl = TextEditingController();
  final _nameHelfer1Ctrl = TextEditingController();
  final _vornameHelfer2Ctrl = TextEditingController();
  final _nameHelfer2Ctrl = TextEditingController();
  DateTime? _datumEinsatz;
  final _uhrzeitCtrl = TextEditingController();
  final _einsatzortCtrl = TextEditingController();

  bool _erkrankung = false;
  bool _unfall = false;
  final _artErkrankungCtrl = TextEditingController();
  final _unfallOrtCtrl = TextEditingController();
  bool _sportunterricht = false;
  bool _sonstigerUnterricht = false;
  bool _pause = false;
  bool _schulweg = false;
  bool _sonstigesAktivitaet = false;
  final _schilderungCtrl = TextEditingController();

  String? _schmerzen; // keine, starke, mittelstarke
  bool _atmungSpontan = false;
  bool _atmungHyperventilation = false;
  bool _atmungAtemnot = false;
  final _pulsCtrl = TextEditingController();
  final _spo2Ctrl = TextEditingController();
  final _blutdruckCtrl = TextEditingController();
  bool _verletzungPrellung = false;
  bool _verletzungBruch = false;
  bool _verletzungWunde = false;
  bool _verletzungSonstiges = false;
  final _beschwerdenCtrl = TextEditingController();

  bool _massnahmeBetreuung = false;
  bool _massnahmePflaster = false;
  bool _massnahmeVerband = false;
  bool _massnahmeKuehlung = false;
  bool _massnahmeSonstiges = false;
  final _massnahmeSonstigesTextCtrl = TextEditingController();
  bool _elternBenachrichtigt = false;
  bool _elternbriefMitgegeben = false;
  bool _arztbesuchEmpfohlen = false;
  bool _notruf = false;
  final _notrufZeitstempelCtrl = TextEditingController();
  final _elternBenachrichtigtZeitstempelCtrl = TextEditingController();
  bool _sekretariatInformiert = false;
  bool _schulleitungInformiert = false;
  bool _lehrerInformiert = false;
  bool _leiterSSDInformiert = false;

  bool _saving = false;
  bool _loading = true;
  String? _nextProtokollNr;
  Uint8List? _sketchImageBytes;
  bool _rettungstechnischeDatenExpanded = true;
  bool _patientendatenExpanded = true;
  bool _angabenErkrankungVerletzungExpanded = true;
  bool _erstbefundExpanded = true;
  bool _getroffeneMassnahmenExpanded = true;
  bool _einsatzabschlussExpanded = true;
  Uint8List? _unterschriftBytes1;
  Uint8List? _unterschriftBytes2;

  @override
  void initState() {
    super.initState();
    _datumEinsatz = DateTime.now();
    _uhrzeitCtrl.text = '${DateTime.now().hour.toString().padLeft(2, '0')}:${DateTime.now().minute.toString().padLeft(2, '0')}';
    _loadNextNr();
  }

  Future<void> _loadNextNr() async {
    try {
      final snap = await _service.streamProtokolle(widget.companyId).first;
      final count = snap.length;
      setState(() {
        _nextProtokollNr = '${count + 1}';
        _protokollNrCtrl.text = _nextProtokollNr ?? '';
        _loading = false;
      });
    } catch (_) {
      setState(() {
        _nextProtokollNr = '1';
        _protokollNrCtrl.text = '1';
        _loading = false;
      });
    }
  }

  @override
  void dispose() {
    _protokollNrCtrl.dispose();
    _vornameErkrankterCtrl.dispose();
    _nameErkrankterCtrl.dispose();
    _geburtsdatumCtrl.dispose();
    _klasseCtrl.dispose();
    _vornameHelfer1Ctrl.dispose();
    _nameHelfer1Ctrl.dispose();
    _vornameHelfer2Ctrl.dispose();
    _nameHelfer2Ctrl.dispose();
    _uhrzeitCtrl.dispose();
    _einsatzortCtrl.dispose();
    _artErkrankungCtrl.dispose();
    _unfallOrtCtrl.dispose();
    _schilderungCtrl.dispose();
    _pulsCtrl.dispose();
    _spo2Ctrl.dispose();
    _blutdruckCtrl.dispose();
    _beschwerdenCtrl.dispose();
    _massnahmeSonstigesTextCtrl.dispose();
    _notrufZeitstempelCtrl.dispose();
    _elternBenachrichtigtZeitstempelCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickDatum() async {
    final d = await showDatePicker(
      context: context,
      initialDate: _datumEinsatz ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (d != null) setState(() => _datumEinsatz = d);
  }

  Future<void> _speichern() async {
    final schilderung = _schilderungCtrl.text.trim();
    if (schilderung.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Bitte Schilderung des Unfalls/der Erkrankung ausfüllen.')),
      );
      return;
    }
    if (!_sekretariatInformiert && !_schulleitungInformiert && !_lehrerInformiert && !_leiterSSDInformiert) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Bitte mindestens eine Person ankreuzen (Sekretariat, Schulleitung, Lehrer oder Leiter SSD).')),
      );
      return;
    }

    setState(() => _saving = true);
    try {
      final user = _authService.currentUser;
      String? creatorName;
      if (user != null) {
        final authData = await _authDataService.getAuthData(user.uid, user.email ?? '', widget.companyId);
        creatorName = authData.displayName;
      }

      final data = <String, dynamic>{
        'protokollNr': _protokollNrCtrl.text.trim().isEmpty ? null : _protokollNrCtrl.text.trim(),
        'vornameErkrankter': _vornameErkrankterCtrl.text.trim().isEmpty ? null : _vornameErkrankterCtrl.text.trim(),
        'nameErkrankter': _nameErkrankterCtrl.text.trim().isEmpty ? null : _nameErkrankterCtrl.text.trim(),
        'geburtsdatum': _geburtsdatumCtrl.text.trim().isEmpty ? null : _geburtsdatumCtrl.text.trim(),
        'klasse': _klasseCtrl.text.trim().isEmpty ? null : _klasseCtrl.text.trim(),
        'vornameHelfer1': _vornameHelfer1Ctrl.text.trim().isEmpty ? null : _vornameHelfer1Ctrl.text.trim(),
        'nameHelfer1': _nameHelfer1Ctrl.text.trim().isEmpty ? null : _nameHelfer1Ctrl.text.trim(),
        'vornameHelfer2': _vornameHelfer2Ctrl.text.trim().isEmpty ? null : _vornameHelfer2Ctrl.text.trim(),
        'nameHelfer2': _nameHelfer2Ctrl.text.trim().isEmpty ? null : _nameHelfer2Ctrl.text.trim(),
        'datumEinsatz': _datumEinsatz != null ? _formatDate(_datumEinsatz!) : null,
        'uhrzeit': _uhrzeitCtrl.text.trim().isEmpty ? null : _uhrzeitCtrl.text.trim(),
        'einsatzort': _einsatzortCtrl.text.trim().isEmpty ? null : _einsatzortCtrl.text.trim(),
        'erkrankung': _erkrankung,
        'unfall': _unfall,
        'artErkrankung': _artErkrankungCtrl.text.trim().isEmpty ? null : _artErkrankungCtrl.text.trim(),
        'unfallOrt': _unfallOrtCtrl.text.trim().isEmpty ? null : _unfallOrtCtrl.text.trim(),
        'sportunterricht': _sportunterricht,
        'sonstigerUnterricht': _sonstigerUnterricht,
        'pause': _pause,
        'schulweg': _schulweg,
        'sonstigesAktivitaet': _sonstigesAktivitaet,
        'schilderung': schilderung,
        'schmerzen': _schmerzen,
        'atmungSpontan': _atmungSpontan,
        'atmungHyperventilation': _atmungHyperventilation,
        'atmungAtemnot': _atmungAtemnot,
        'puls': _pulsCtrl.text.trim().isEmpty ? null : _pulsCtrl.text.trim(),
        'spo2': _spo2Ctrl.text.trim().isEmpty ? null : _spo2Ctrl.text.trim(),
        'blutdruck': _blutdruckCtrl.text.trim().isEmpty ? null : _blutdruckCtrl.text.trim(),
        'verletzungPrellung': _verletzungPrellung,
        'verletzungBruch': _verletzungBruch,
        'verletzungWunde': _verletzungWunde,
        'verletzungSonstiges': _verletzungSonstiges,
        'beschwerden': _beschwerdenCtrl.text.trim().isEmpty ? null : _beschwerdenCtrl.text.trim(),
        'massnahmeBetreuung': _massnahmeBetreuung,
        'massnahmePflaster': _massnahmePflaster,
        'massnahmeVerband': _massnahmeVerband,
        'massnahmeKuehlung': _massnahmeKuehlung,
        'massnahmeSonstiges': _massnahmeSonstiges,
        'massnahmeSonstigesText': _massnahmeSonstigesTextCtrl.text.trim().isEmpty ? null : _massnahmeSonstigesTextCtrl.text.trim(),
        'elternBenachrichtigt': _elternBenachrichtigt,
        'elternbriefMitgegeben': _elternbriefMitgegeben,
        'arztbesuchEmpfohlen': _arztbesuchEmpfohlen,
        'notruf': _notruf,
        'notrufZeitstempel': _notrufZeitstempelCtrl.text.trim().isEmpty ? null : _notrufZeitstempelCtrl.text.trim(),
        'elternBenachrichtigtZeitstempel': _elternBenachrichtigtZeitstempelCtrl.text.trim().isEmpty ? null : _elternBenachrichtigtZeitstempelCtrl.text.trim(),
        'sekretariatInformiert': _sekretariatInformiert,
        'schulleitungInformiert': _schulleitungInformiert,
        'lehrerInformiert': _lehrerInformiert,
        'leiterSSDInformiert': _leiterSSDInformiert,
      };

      final docId = await _service.create(
        widget.companyId,
        data,
        user?.uid,
        creatorName,
      );

      // Körper-Skizze hochladen falls vorhanden
      if (_sketchImageBytes != null && _sketchImageBytes!.isNotEmpty) {
        final url = await _service.uploadKoerperSkizze(widget.companyId, docId, _sketchImageBytes!);
        if (url != null) {
          await _service.updateKoerperSkizzeUrl(widget.companyId, docId, url);
        }
      }

      // Unterschriften hochladen falls vorhanden
      if (_unterschriftBytes1 != null && _unterschriftBytes1!.isNotEmpty) {
        final url = await _service.uploadUnterschrift(widget.companyId, docId, _unterschriftBytes1!, 1);
        if (url != null) await _service.updateUnterschriftUrl(widget.companyId, docId, url, 1);
      }
      if (_unterschriftBytes2 != null && _unterschriftBytes2!.isNotEmpty) {
        final url = await _service.uploadUnterschrift(widget.companyId, docId, _unterschriftBytes2!, 2);
        if (url != null) await _service.updateUnterschriftUrl(widget.companyId, docId, url, 2);
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Einsatzprotokoll gespeichert.')));
        _resetForm();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Fehler: $e')));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _resetForm() {
    final nextNr = (int.tryParse(_protokollNrCtrl.text) ?? 0) + 1;
    setState(() {
      _protokollNrCtrl.text = '$nextNr';
      _vornameErkrankterCtrl.clear();
      _nameErkrankterCtrl.clear();
      _geburtsdatumCtrl.clear();
      _klasseCtrl.clear();
      _vornameHelfer1Ctrl.clear();
      _nameHelfer1Ctrl.clear();
      _vornameHelfer2Ctrl.clear();
      _nameHelfer2Ctrl.clear();
      _datumEinsatz = DateTime.now();
      _uhrzeitCtrl.text = '${DateTime.now().hour.toString().padLeft(2, '0')}:${DateTime.now().minute.toString().padLeft(2, '0')}';
      _einsatzortCtrl.clear();
      _erkrankung = false;
      _unfall = false;
      _artErkrankungCtrl.clear();
      _unfallOrtCtrl.clear();
      _sportunterricht = false;
      _sonstigerUnterricht = false;
      _pause = false;
      _schulweg = false;
      _sonstigesAktivitaet = false;
      _schilderungCtrl.clear();
      _schmerzen = null;
      _atmungSpontan = false;
      _atmungHyperventilation = false;
      _atmungAtemnot = false;
      _pulsCtrl.clear();
      _spo2Ctrl.clear();
      _blutdruckCtrl.clear();
      _verletzungPrellung = false;
      _verletzungBruch = false;
      _verletzungWunde = false;
      _verletzungSonstiges = false;
      _beschwerdenCtrl.clear();
      _sketchImageBytes = null;
      _unterschriftBytes1 = null;
      _unterschriftBytes2 = null;
      _massnahmeBetreuung = false;
      _massnahmePflaster = false;
      _massnahmeVerband = false;
      _massnahmeKuehlung = false;
      _massnahmeSonstiges = false;
      _massnahmeSonstigesTextCtrl.clear();
      _elternBenachrichtigt = false;
      _elternbriefMitgegeben = false;
      _arztbesuchEmpfohlen = false;
      _notruf = false;
      _notrufZeitstempelCtrl.clear();
      _elternBenachrichtigtZeitstempelCtrl.clear();
      _sekretariatInformiert = false;
      _schulleitungInformiert = false;
      _lehrerInformiert = false;
      _leiterSSDInformiert = false;
    });
  }

  Widget _sectionHeader(String title) => Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        color: Colors.grey.shade300,
        child: Text(title, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: Colors.grey.shade800)),
      );

  Widget _field(TextEditingController ctrl, String label, {int maxLines = 1}) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: TextField(
          controller: ctrl,
          maxLines: maxLines,
          decoration: _inputDecoration.copyWith(labelText: label, alignLabelWithHint: maxLines > 1),
        ),
      );

  Widget _checkboxRow(String label, bool value, ValueChanged<bool> onChanged) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 24,
              height: 24,
              child: Checkbox(value: value, onChanged: (v) => onChanged(v ?? false), materialTapTargetSize: MaterialTapTargetSize.shrinkWrap),
            ),
            const SizedBox(width: 8),
            Flexible(child: Text(label, style: const TextStyle(fontSize: 14), overflow: TextOverflow.ellipsis)),
          ],
        ),
      );

  Widget _checkboxRowMitZeitstempel(String label, bool value, TextEditingController zeitstempelCtrl, String zeitstempelLabel, ValueChanged<bool> onChanged) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: 24,
                  height: 24,
                  child: Checkbox(value: value, onChanged: (v) => onChanged(v ?? false), materialTapTargetSize: MaterialTapTargetSize.shrinkWrap),
                ),
                const SizedBox(width: 8),
                Flexible(child: Text(label, style: const TextStyle(fontSize: 14), overflow: TextOverflow.ellipsis)),
              ],
            ),
            if (value) ...[
              const SizedBox(height: 6),
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: TextField(
                  controller: zeitstempelCtrl,
                  decoration: _inputDecoration.copyWith(labelText: zeitstempelLabel),
                ),
              ),
            ],
          ],
        ),
      );

  Widget _radioRow(String label, String? groupValue, String value, ValueChanged<String?> onChanged) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Row(
          children: [
            SizedBox(
              width: 24,
              height: 24,
              child: Radio<String>(value: value, groupValue: groupValue, onChanged: (v) => onChanged(v), materialTapTargetSize: MaterialTapTargetSize.shrinkWrap),
            ),
            const SizedBox(width: 8),
            Text(label, style: const TextStyle(fontSize: 14)),
          ],
        ),
      );

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(
        backgroundColor: AppTheme.surfaceBg,
        appBar: AppTheme.buildModuleAppBar(title: 'Einsatzprotokoll Schulsanitätsdienst', onBack: widget.onBack),
        body: const Center(child: CircularProgressIndicator(color: AppTheme.primary)),
      );
    }

    return Scaffold(
      backgroundColor: AppTheme.surfaceBg,
      appBar: AppTheme.buildModuleAppBar(title: 'Einsatzprotokoll Schulsanitätsdienst', onBack: widget.onBack),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // Rettungstechnische Daten (ausklappbar)
            Card(
              elevation: 0,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: Colors.grey.shade200)),
              child: Theme(
                data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
                child: ExpansionTile(
                  initiallyExpanded: _rettungstechnischeDatenExpanded,
                  onExpansionChanged: (v) => setState(() => _rettungstechnischeDatenExpanded = v),
                  tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  childrenPadding: EdgeInsets.zero,
                  collapsedBackgroundColor: AppTheme.primary,
                  backgroundColor: AppTheme.primary,
                  textColor: Colors.white,
                  collapsedTextColor: Colors.white,
                  iconColor: Colors.white,
                  collapsedIconColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  collapsedShape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  title: Text('Rettungstechnische Daten', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Colors.white)),
                  children: [
                    Container(
                      color: Theme.of(context).colorScheme.surface,
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _field(_protokollNrCtrl, 'Protokoll Nr. / Einsatz-Nr.'),
                          const SizedBox(height: 16),
                          _buildSchulsanitaeterCard(),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Patientendaten (ausklappbar)
            Card(
              elevation: 0,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: Colors.grey.shade200)),
              child: Theme(
                data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
                child: ExpansionTile(
                  initiallyExpanded: _patientendatenExpanded,
                  onExpansionChanged: (v) => setState(() => _patientendatenExpanded = v),
                  tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  childrenPadding: EdgeInsets.zero,
                  collapsedBackgroundColor: AppTheme.primary,
                  backgroundColor: AppTheme.primary,
                  textColor: Colors.white,
                  collapsedTextColor: Colors.white,
                  iconColor: Colors.white,
                  collapsedIconColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  collapsedShape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  title: Text('Patientendaten', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Colors.white)),
                  children: [
                    Container(
                      color: Theme.of(context).colorScheme.surface,
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(child: _field(_vornameErkrankterCtrl, 'Vorname')),
                              const SizedBox(width: 12),
                              Expanded(child: _field(_nameErkrankterCtrl, 'Name')),
                            ],
                          ),
                          Row(
                            children: [
                              Expanded(child: _field(_geburtsdatumCtrl, 'Geburtsdatum')),
                              const SizedBox(width: 12),
                              Expanded(child: _field(_klasseCtrl, 'Klasse')),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Angaben zur Erkrankung/Verletzung (ausklappbar)
            Card(
              elevation: 0,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: Colors.grey.shade200)),
              child: Theme(
                data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
                child: ExpansionTile(
                  initiallyExpanded: _angabenErkrankungVerletzungExpanded,
                  onExpansionChanged: (v) => setState(() => _angabenErkrankungVerletzungExpanded = v),
                  tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  childrenPadding: EdgeInsets.zero,
                  collapsedBackgroundColor: AppTheme.primary,
                  backgroundColor: AppTheme.primary,
                  textColor: Colors.white,
                  collapsedTextColor: Colors.white,
                  iconColor: Colors.white,
                  collapsedIconColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  collapsedShape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  title: Text('Angaben zur Erkrankung/Verletzung', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Colors.white)),
                  children: [
                    Container(
                      color: Theme.of(context).colorScheme.surface,
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text('Art des Vorfalls:', style: TextStyle(fontSize: 13, color: Colors.grey.shade700)),
                                    _checkboxRow('Erkrankung', _erkrankung, (v) => setState(() => _erkrankung = v)),
                                    _checkboxRow('Unfall', _unfall, (v) => setState(() => _unfall = v)),
                                    if (_erkrankung) _field(_artErkrankungCtrl, 'Art der Erkrankung'),
                                    if (_unfall) _field(_unfallOrtCtrl, 'Wo genau ist der Unfall passiert?'),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 24),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text('Was hat der Verletzte zum Unfallzeitpunkt gemacht:', style: TextStyle(fontSize: 13, color: Colors.grey.shade700)),
                                    _checkboxRow('Sportunterricht', _sportunterricht, (v) => setState(() => _sportunterricht = v)),
                                    _checkboxRow('Sonstiger Unterricht', _sonstigerUnterricht, (v) => setState(() => _sonstigerUnterricht = v)),
                                    _checkboxRow('Pause', _pause, (v) => setState(() => _pause = v)),
                                    _checkboxRow('Schulweg', _schulweg, (v) => setState(() => _schulweg = v)),
                                    _checkboxRow('Sonstiges', _sonstigesAktivitaet, (v) => setState(() => _sonstigesAktivitaet = v)),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          _field(_schilderungCtrl, 'Schilderung des Unfalls oder der Erkrankung *', maxLines: 4),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Erstbefund (ausklappbar)
            Card(
              elevation: 0,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: Colors.grey.shade200)),
              child: Theme(
                data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
                child: ExpansionTile(
                  initiallyExpanded: _erstbefundExpanded,
                  onExpansionChanged: (v) => setState(() => _erstbefundExpanded = v),
                  tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  childrenPadding: EdgeInsets.zero,
                  collapsedBackgroundColor: AppTheme.primary,
                  backgroundColor: AppTheme.primary,
                  textColor: Colors.white,
                  collapsedTextColor: Colors.white,
                  iconColor: Colors.white,
                  collapsedIconColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  collapsedShape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  title: Text('Erstbefund', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Colors.white)),
                  children: [
                    Container(
                      color: Theme.of(context).colorScheme.surface,
                      padding: const EdgeInsets.all(16),
                      child: LayoutBuilder(
                      builder: (context, constraints) {
                        final isNarrow = constraints.maxWidth < 800;
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            isNarrow
                                ? Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      _buildSchmerzen(),
                                      const SizedBox(height: 8),
                                      _buildKoerperSkizze(),
                                      const SizedBox(height: 8),
                                      _buildVerletzung(),
                                      const SizedBox(height: 8),
                                      _buildAtmung(),
                                      const SizedBox(height: 8),
                                      Row(
                                        children: [
                                          Expanded(child: _field(_pulsCtrl, 'Puls')),
                                          const SizedBox(width: 8),
                                          Expanded(child: _field(_spo2Ctrl, 'Sauerstoffsättigung (SpO2)')),
                                          const SizedBox(width: 8),
                                          Expanded(child: _field(_blutdruckCtrl, 'Blutdruck (mm/Hg)')),
                                        ],
                                      ),
                                    ],
                                  )
                                : Row(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Expanded(
                                        flex: 1,
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            _buildSchmerzen(),
                                            const SizedBox(height: 8),
                                            _buildVerletzung(),
                                          ],
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        flex: 1,
                                        child: Center(
                                          child: SizedBox(width: 280, height: 280, child: _buildKoerperSkizze()),
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        flex: 1,
                                        child: Row(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Expanded(child: _buildAtmung()),
                                            const SizedBox(width: 8),
                                            Expanded(
                                              child: Column(
                                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                                children: [
                                                  _field(_pulsCtrl, 'Puls'),
                                                  const SizedBox(height: 8),
                                                  _field(_spo2Ctrl, 'Sauerstoffsättigung (SpO2)'),
                                                  const SizedBox(height: 8),
                                                  _field(_blutdruckCtrl, 'Blutdruck (mm/Hg)'),
                                                ],
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                            const SizedBox(height: 12),
                            _buildErstbefundRest(),
                          ],
                        );
                      },
                    ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Getroffene Maßnahmen (ausklappbar)
            Card(
              elevation: 0,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: Colors.grey.shade200)),
              child: Theme(
                data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
                child: ExpansionTile(
                  initiallyExpanded: _getroffeneMassnahmenExpanded,
                  onExpansionChanged: (v) => setState(() => _getroffeneMassnahmenExpanded = v),
                  tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  childrenPadding: EdgeInsets.zero,
                  collapsedBackgroundColor: AppTheme.primary,
                  backgroundColor: AppTheme.primary,
                  textColor: Colors.white,
                  collapsedTextColor: Colors.white,
                  iconColor: Colors.white,
                  collapsedIconColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  collapsedShape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  title: Text('Getroffene Maßnahmen', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Colors.white)),
                  children: [
                    Container(
                      color: Theme.of(context).colorScheme.surface,
                      padding: const EdgeInsets.all(16),
                      child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _checkboxRow('Betreuung', _massnahmeBetreuung, (v) => setState(() => _massnahmeBetreuung = v)),
                              _checkboxRow('Pflaster', _massnahmePflaster, (v) => setState(() => _massnahmePflaster = v)),
                              _checkboxRow('Verband', _massnahmeVerband, (v) => setState(() => _massnahmeVerband = v)),
                              _checkboxRow('Kühlung', _massnahmeKuehlung, (v) => setState(() => _massnahmeKuehlung = v)),
                              _checkboxRow('Sonstiges', _massnahmeSonstiges, (v) => setState(() => _massnahmeSonstiges = v)),
                              if (_massnahmeSonstiges) _field(_massnahmeSonstigesTextCtrl, 'Sonstiges – Angabe'),
                              _checkboxRow('Elternbrief mitgegeben', _elternbriefMitgegeben, (v) => setState(() => _elternbriefMitgegeben = v)),
                              _checkboxRow('Arztbesuch empfohlen', _arztbesuchEmpfohlen, (v) => setState(() => _arztbesuchEmpfohlen = v)),
                            ],
                          ),
                        ),
                        const SizedBox(width: 24),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _checkboxRowMitZeitstempel('Notruf', _notruf, _notrufZeitstempelCtrl, 'Notruf abgesetzt um', (v) {
                                setState(() {
                                  _notruf = v;
                                  if (v && _notrufZeitstempelCtrl.text.isEmpty) {
                                    _notrufZeitstempelCtrl.text = _formatZeitstempel(DateTime.now());
                                  }
                                });
                              }),
                              _checkboxRowMitZeitstempel('Eltern benachrichtigt', _elternBenachrichtigt, _elternBenachrichtigtZeitstempelCtrl, 'Eltern benachrichtigt um', (v) {
                                setState(() {
                                  _elternBenachrichtigt = v;
                                  if (v && _elternBenachrichtigtZeitstempelCtrl.text.isEmpty) {
                                    _elternBenachrichtigtZeitstempelCtrl.text = _formatZeitstempel(DateTime.now());
                                  }
                                });
                              }),
                              const SizedBox(height: 16),
                              Text('Mindestens eine Person muss informiert worden sein:', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.grey.shade700)),
                              const SizedBox(height: 6),
                              _checkboxRow('Sekretariat informiert', _sekretariatInformiert, (v) => setState(() => _sekretariatInformiert = v)),
                              _checkboxRow('Schulleitung informiert', _schulleitungInformiert, (v) => setState(() => _schulleitungInformiert = v)),
                              _checkboxRow('Lehrer informiert', _lehrerInformiert, (v) => setState(() => _lehrerInformiert = v)),
                              _checkboxRow('Leiter SSD informiert', _leiterSSDInformiert, (v) => setState(() => _leiterSSDInformiert = v)),
                            ],
                          ),
                        ),
                      ],
                    ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Einsatzabschluss (ausklappbar)
            Card(
              elevation: 0,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: Colors.grey.shade200)),
              child: Theme(
                data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
                child: ExpansionTile(
                  initiallyExpanded: _einsatzabschlussExpanded,
                  onExpansionChanged: (v) => setState(() => _einsatzabschlussExpanded = v),
                  tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  childrenPadding: EdgeInsets.zero,
                  collapsedBackgroundColor: AppTheme.primary,
                  backgroundColor: AppTheme.primary,
                  textColor: Colors.white,
                  collapsedTextColor: Colors.white,
                  iconColor: Colors.white,
                  collapsedIconColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  collapsedShape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  title: Text('Einsatzabschluss', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Colors.white)),
                  children: [
                    Container(
                      color: Theme.of(context).colorScheme.surface,
                      padding: const EdgeInsets.all(16),
                      child: _buildUnterschriftenfeld(),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),

            FilledButton(
              onPressed: _saving ? null : _speichern,
              style: FilledButton.styleFrom(backgroundColor: AppTheme.primary, padding: const EdgeInsets.symmetric(vertical: 16)),
              child: _saving
                  ? const SizedBox(height: 24, width: 24, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Text('Protokoll speichern'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSchulsanitaeterCard() {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: Colors.grey.shade200)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _sectionHeader('Schulsanitäter/in • Ersthelfer'),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(child: _field(_vornameHelfer1Ctrl, 'Vorname (Schulsanitäter/in 1)')),
                    const SizedBox(width: 12),
                    Expanded(child: _field(_nameHelfer1Ctrl, 'Name (Schulsanitäter/in 1)')),
                  ],
                ),
                Row(
                  children: [
                    Expanded(child: _field(_vornameHelfer2Ctrl, 'Vorname (Schulsanitäter/in 2)')),
                    const SizedBox(width: 12),
                    Expanded(child: _field(_nameHelfer2Ctrl, 'Name (Schulsanitäter/in 2)')),
                  ],
                ),
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: InkWell(
                          onTap: _pickDatum,
                          child: InputDecorator(
                            decoration: _inputDecoration.copyWith(labelText: 'Datum'),
                            child: Text(_datumEinsatz != null ? _formatDate(_datumEinsatz!) : 'Datum wählen'),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextField(
                          controller: _uhrzeitCtrl,
                          decoration: _inputDecoration.copyWith(labelText: 'Uhrzeit', hintText: 'HH:MM'),
                          keyboardType: TextInputType.datetime,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                _field(_einsatzortCtrl, 'Einsatzort'),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSchmerzen() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Schmerzen:', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.grey.shade700)),
        _checkboxRow('keine', _schmerzen == 'keine', (v) => setState(() => _schmerzen = v ? 'keine' : null)),
        _checkboxRow('starke', _schmerzen == 'starke', (v) => setState(() => _schmerzen = v ? 'starke' : null)),
        _checkboxRow('mittelstarke', _schmerzen == 'mittelstarke', (v) => setState(() => _schmerzen = v ? 'mittelstarke' : null)),
      ],
    );
  }

  Widget _buildAtmung() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Atmung:', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.grey.shade700)),
        _checkboxRow('spontan / frei', _atmungSpontan, (v) => setState(() => _atmungSpontan = v)),
        _checkboxRow('Hyperventilation', _atmungHyperventilation, (v) => setState(() => _atmungHyperventilation = v)),
        _checkboxRow('Atemnot', _atmungAtemnot, (v) => setState(() => _atmungAtemnot = v)),
      ],
    );
  }

  Widget _buildVerletzung() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Welche Verletzung liegt vermutlich vor:', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.grey.shade700)),
        _checkboxRow('Prellung, Zerrung', _verletzungPrellung, (v) => setState(() => _verletzungPrellung = v)),
        _checkboxRow('Knochenbruch', _verletzungBruch, (v) => setState(() => _verletzungBruch = v)),
        _checkboxRow('Wunde', _verletzungWunde, (v) => setState(() => _verletzungWunde = v)),
        _checkboxRow('Sonstiges', _verletzungSonstiges, (v) => setState(() => _verletzungSonstiges = v)),
      ],
    );
  }

  Widget _buildErstbefundRest() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _field(_beschwerdenCtrl, 'Der/die Erkrankte/Verletzte klagt über *', maxLines: 3),
      ],
    );
  }

  Widget _buildKoerperSkizze() {
    const size = 280.0;
    return GestureDetector(
      onTap: _openSketchEditor,
      child: _sketchImageBytes != null
          ? Image.memory(
              _sketchImageBytes!,
              fit: BoxFit.contain,
              width: size,
              height: size,
            )
          : Image.asset(
              'img/koerperfigur_vorlage.png',
              fit: BoxFit.contain,
              width: size,
              height: size,
            ),
    );
  }

  Widget _buildUnterschriftenfeld() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: _buildUnterschriftenfeldEinzel(1, 'Unterschrift Schulsanitäter/in 1', _unterschriftBytes1, _signatureKey1, (b) => _unterschriftBytes1 = b)),
        const SizedBox(width: 12),
        Expanded(child: _buildUnterschriftenfeldEinzel(2, 'Unterschrift Schulsanitäter/in 2', _unterschriftBytes2, _signatureKey2, (b) => _unterschriftBytes2 = b)),
      ],
    );
  }

  Widget _buildUnterschriftenfeldEinzel(
    int index,
    String label,
    Uint8List? bytes,
    GlobalKey<SignaturePadState> signatureKey,
    void Function(Uint8List?) onSaved,
  ) {
    return GestureDetector(
      onTap: () => _openUnterschriftEditor(index, signatureKey, bytes, onSaved),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.grey.shade50,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.grey.shade300),
        ),
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.grey.shade700)),
            const SizedBox(height: 8),
            SizedBox(
              height: 80,
              width: double.infinity,
              child: bytes != null && bytes.isNotEmpty
                  ? ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Image.memory(bytes, fit: BoxFit.contain),
                    )
                  : Container(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.grey.shade300),
                      ),
                      alignment: Alignment.center,
                      child: Text('Zum Eintragen tippen', style: TextStyle(fontSize: 14, color: Colors.grey.shade500)),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openUnterschriftEditor(
    int index,
    GlobalKey<SignaturePadState> signatureKey,
    Uint8List? initialBytes,
    void Function(Uint8List?) onSaved,
  ) async {
    final result = await showDialog<Uint8List?>(
      context: context,
      barrierDismissible: false,
      builder: (context) => _UnterschriftEditorDialog(
        signatureKey: signatureKey,
        initialImageBytes: initialBytes,
        title: 'Unterschrift Schulsanitäter/in $index',
      ),
    );
    if (result != null && mounted) {
      setState(() => onSaved(result.isEmpty ? null : result));
    }
  }

  Future<void> _openSketchEditor() async {
    final result = await showDialog<Uint8List?>(
      context: context,
      barrierDismissible: false,
      builder: (context) => _SketchEditorDialog(
        initialImageBytes: _sketchImageBytes,
        sketchKey: _sketchKey,
      ),
    );
    if (result != null && mounted) {
      setState(() => _sketchImageBytes = result.isEmpty ? null : result);
    }
  }
}

class _SketchEditorDialog extends StatefulWidget {
  final Uint8List? initialImageBytes;
  final GlobalKey<SketchCanvasState> sketchKey;

  const _SketchEditorDialog({this.initialImageBytes, required this.sketchKey});

  @override
  State<_SketchEditorDialog> createState() => _SketchEditorDialogState();
}

class _SketchEditorDialogState extends State<_SketchEditorDialog> {
  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 500, maxHeight: 600),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Verletzte Stelle markieren', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
              const SizedBox(height: 12),
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: SketchCanvas(
                    key: widget.sketchKey,
                    height: 400,
                    backgroundImage: 'img/koerperfigur_vorlage.png',
                    initialImageBytes: widget.initialImageBytes,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  if (widget.initialImageBytes != null)
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(Uint8List(0)),
                      child: const Text('Entfernen'),
                    ),
                  if (widget.initialImageBytes != null) const SizedBox(width: 8),
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Abbrechen'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: () async {
                      final bytes = await widget.sketchKey.currentState?.captureImage();
                      Navigator.of(context).pop(bytes);
                    },
                    child: const Text('Speichern'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _UnterschriftEditorDialog extends StatelessWidget {
  final GlobalKey<SignaturePadState> signatureKey;
  final Uint8List? initialImageBytes;
  final String title;

  const _UnterschriftEditorDialog({required this.signatureKey, this.initialImageBytes, required this.title});

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 500, maxHeight: 500),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(title, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              Text(
                'Mit Finger, Tabletstift oder Maus unterschreiben.',
                style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
              ),
              const SizedBox(height: 16),
              Expanded(
                child: PointerInterceptor(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: SignaturePad(key: signatureKey, height: 180),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  if (initialImageBytes != null)
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(Uint8List(0)),
                      child: const Text('Entfernen'),
                    ),
                  if (initialImageBytes != null) const SizedBox(width: 8),
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Abbrechen'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: () async {
                      final bytes = await signatureKey.currentState?.captureImage();
                      if (context.mounted) Navigator.of(context).pop(bytes ?? Uint8List(0));
                    },
                    child: const Text('Speichern'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
