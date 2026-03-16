import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme/app_theme.dart';
import '../services/auth_service.dart';
import '../services/auth_data_service.dart';
import '../services/einsatzprotokoll_nfs_service.dart';
import '../services/alarmierung_nfs_service.dart';
import 'einsatzprotokoll_nfs_einstellungen_screen.dart';

String _formatDate(DateTime d) =>
    '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.${d.year}';

String _formatTime(TimeOfDay t) =>
    '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

/// Parst "HH:mm" oder "HH:mm:ss" zu TimeOfDay.
TimeOfDay? _parseTime(String? s) {
  if (s == null || s.trim().isEmpty) return null;
  final parts = s.trim().split(RegExp(r'[:\s]'));
  if (parts.isEmpty) return null;
  final h = int.tryParse(parts[0]);
  final m = parts.length >= 2 ? int.tryParse(parts[1]) : 0;
  if (h == null || h < 0 || h > 23) return null;
  return TimeOfDay(hour: h, minute: (m ?? 0).clamp(0, 59));
}

/// Parst "DD.MM.YYYY" zu DateTime.
DateTime? _parseDate(String? s) {
  if (s == null || s.trim().isEmpty) return null;
  final parts = s.trim().split('.');
  if (parts.length != 3) return null;
  final d = int.tryParse(parts[0]);
  final m = int.tryParse(parts[1]);
  final y = int.tryParse(parts[2]);
  if (d == null || m == null || y == null) return null;
  if (m < 1 || m > 12 || d < 1 || d > 31) return null;
  try {
    return DateTime(y, m, d);
  } catch (_) {
    return null;
  }
}

/// Einsatzdauer aus Alarmierungszeit und Einsatzende (HH.MM)
String _formatEinsatzdauer(TimeOfDay? alarm, TimeOfDay? ende) {
  if (alarm == null || ende == null) return '-';
  int alarmMin = alarm.hour * 60 + alarm.minute;
  int endeMin = ende.hour * 60 + ende.minute;
  int diff = endeMin - alarmMin;
  if (diff < 0) diff += 24 * 60;
  int h = diff ~/ 60;
  int m = diff % 60;
  return '$h.${m.toString().padLeft(2, '0')}';
}

/// Gelbe Füllung für leere Pflichtfelder; wird weiß bei ausgefüllt
const _pflichtfeldGelb = Color(0xFFFFF9C4); // Amber 100

const _inputDecoration = InputDecoration(
  filled: true,
  fillColor: Colors.white,
  border: OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(10))),
  enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(10)), borderSide: BorderSide(color: AppTheme.border)),
  focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(10)), borderSide: BorderSide(color: AppTheme.primary, width: 1.5)),
  contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 14),
);

const _einsatznachbesprechungOptions = <(String?, String)>[
  (null, 'bitte auswählen ...'),
  ('ja', 'ja'),
  ('nein', 'nein'),
  ('sonstiges', 'sonstiges'),
];

const _weitereBetreuungOptions = <(String?, String)>[
  (null, 'bitte auswählen ...'),
  ('angehoerige', 'Angehörige'),
  ('freunde_nachbarn', 'Freunde / Nachbarn'),
  ('sonstige_fachdienste', 'sonstige Fachdienste'),
  ('sonstiges', 'sonstiges'),
];

const _einsatzindikationOptions = <(String?, String)>[
  (null, 'bitte auswählen ...'),
  ('utn', 'ÜTN - Überbringen Todesnachricht'),
  ('haeuslicher_todesfall', 'häuslicher Todesfall / akute Erkrankung'),
  ('frustrane_reanimation', 'frustrane Reanimation'),
  ('suizid', 'Suizid'),
  ('verkehrsunfall', 'Verkehrsunfall'),
  ('arbeitsunfall', 'Arbeitsunfall'),
  ('schuleinsatz', 'Schuleinsatz'),
  ('brand_explosion_unwetter', 'Brand / Explosion / Unwetter'),
  ('gewalt_verbrechen', 'Gewalttat / Verbrechen'),
  ('grosse_einsatzlage', 'Große Einsatzlage'),
  ('ploetzlicher_kindstod', 'plötzlicher Kindstod'),
  ('sonstiges', 'sonstiges'),
];

/// Einsatzprotokoll Notfallseelsorge – Formular mit 4 Bereichen
class EinsatzprotokollNfsScreen extends StatefulWidget {
  final String companyId;
  final String? title;
  final VoidCallback onBack;
  final String? mitarbeiterId;

  const EinsatzprotokollNfsScreen({
    super.key,
    required this.companyId,
    this.title,
    required this.onBack,
    this.mitarbeiterId,
  });

  @override
  State<EinsatzprotokollNfsScreen> createState() => _EinsatzprotokollNfsScreenState();
}

class _EinsatzprotokollNfsScreenState extends State<EinsatzprotokollNfsScreen> {
  final _authService = AuthService();
  final _authDataService = AuthDataService();
  final _nfsService = EinsatzprotokollNfsService();
  final _alarmierungNfsService = AlarmierungNfsService();
  bool _saving = false;
  String? _userRole;
  List<Map<String, dynamic>> _abgeschlosseneEinsaetze = [];
  StreamSubscription<List<Map<String, dynamic>>>? _abgeschlosseneEinsaetzeSub;
  String? _selectedEinsatzId; // null = nicht gewählt, "manual" = manuell, sonst doc id

  String? get _einsatzdauerForSave {
    final d = _formatEinsatzdauer(_alarmierungszeit, _einsatzendeTime);
    return d == '-' ? null : d;
  }

  bool get _canAccessEinstellungen {
    final r = (_userRole ?? '').toLowerCase().trim();
    return r == 'admin' || r == 'koordinator' || r == 'superadmin';
  }

  final _laufendeNrCtrl = TextEditingController(text: '–');
  final _nameCtrl = TextEditingController();
  DateTime? _einsatzDatum;
  final _einsatzNrCtrl = TextEditingController();
  TimeOfDay? _alarmierungszeit;
  TimeOfDay? _eintreffenTime;
  TimeOfDay? _abfahrtTime;
  TimeOfDay? _einsatzendeTime;

  bool _alarmierungKoordinator = false;
  bool _alarmierungSonstige = false;
  String? _einsatzindikation;
  bool _einsatzOeffentlich = false;
  bool _einsatzPrivat = false;
  bool _nfsNachalarmiertJa = false;
  bool _nfsNachalarmiertNein = false;
  final _nfsNachalarmiertNamenCtrl = TextEditingController();
  final _gefahreneKmCtrl = TextEditingController();

  final _situationVorOrtCtrl = TextEditingController();
  final _meineRolleAufgabeCtrl = TextEditingController();
  final _verlaufBegleitungCtrl = TextEditingController();
  final _situationAmEndeCtrl = TextEditingController();
  String? _weitereBetreuungDurch;
  final _weitereBetreuungSonstigesCtrl = TextEditingController();

  bool _weitereDiensteJa = false;
  bool _weitereDiensteNein = false;
  final _weitereDiensteNamenCtrl = TextEditingController();

  final _fallbesprechungCtrl = TextEditingController();
  String? _einsatznachbesprechungGewuenscht;
  final _einsatznachbesprechungSonstigesCtrl = TextEditingController();

  bool _einsatzdatenExpanded = false;
  bool _einsatzberichtExpanded = false;
  bool _einsatzverlaufExpanded = false;
  bool _sonstigesExpanded = false;

  @override
  void initState() {
    super.initState();
    _loadAuth();
    _loadLaufendeNrPreview();
    _abgeschlosseneEinsaetzeSub = (widget.mitarbeiterId != null && widget.mitarbeiterId!.isNotEmpty
            ? _alarmierungNfsService.streamAbgeschlosseneEinsaetzeForMitarbeiter(
                widget.companyId,
                widget.mitarbeiterId!,
              )
            : _alarmierungNfsService.streamAbgeschlosseneEinsaetze(widget.companyId))
        .listen((list) {
      if (mounted) setState(() {
        _abgeschlosseneEinsaetze = list;
        if (_selectedEinsatzId != null && _selectedEinsatzId != 'manual') {
          final found = list.any((e) => (e['id'] ?? '').toString() == _selectedEinsatzId);
          if (!found) _selectedEinsatzId = null;
        }
      });
    });
  }

  @override
  void dispose() {
    _abgeschlosseneEinsaetzeSub?.cancel();
    _laufendeNrCtrl.dispose();
    _nameCtrl.dispose();
    _einsatzNrCtrl.dispose();
    _nfsNachalarmiertNamenCtrl.dispose();
    _gefahreneKmCtrl.dispose();
    _situationVorOrtCtrl.dispose();
    _meineRolleAufgabeCtrl.dispose();
    _verlaufBegleitungCtrl.dispose();
    _situationAmEndeCtrl.dispose();
    _weitereBetreuungSonstigesCtrl.dispose();
    _weitereDiensteNamenCtrl.dispose();
    _fallbesprechungCtrl.dispose();
    _einsatznachbesprechungSonstigesCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadAuth() async {
    final user = _authService.currentUser;
    if (user == null) return;
    final auth = await _authDataService.getAuthData(user.uid, user.email ?? '', widget.companyId);
    if (mounted) {
      setState(() {
        _nameCtrl.text = _formatNameVornameZuerst(auth.displayName);
        _userRole = auth.role;
      });
    }
  }

  /// Laufende-Interne-Nr: Wird beim Erstellen des Protokolls vergeben.
  /// Bei Einsatz-Auswahl: aus laufendeNr des Einsatzes (nicht einsatzNr!).
  /// Einzelperson: laufendeNr; mehrere: laufendeNr-1, laufendeNr-2, …
  Future<void> _loadLaufendeNrPreview() async {
    if (!mounted) return;
    try {
      String nr;
      if (_selectedEinsatzId != null && _selectedEinsatzId != 'manual') {
        final e = _abgeschlosseneEinsaetze.firstWhere(
          (x) => (x['id'] ?? '').toString() == _selectedEinsatzId,
          orElse: () => <String, dynamic>{},
        );
        if (e.isNotEmpty) {
          final base = (e['laufendeNr'] ?? '').toString().trim();
          final ids = (e['alarmierteMitarbeiterIds'] as List?)?.map((x) => x.toString()).toList() ?? [];
          final mid = widget.mitarbeiterId;
          if (base.isNotEmpty && mid != null && ids.length > 1) {
            final idx = ids.indexOf(mid);
            nr = idx >= 0 ? '$base-${idx + 1}' : base;
          } else if (base.isNotEmpty) {
            nr = base;
          } else {
            nr = await _nfsService.getNextLaufendeInterneNrPreview(widget.companyId);
          }
        } else {
          nr = await _nfsService.getNextLaufendeInterneNrPreview(widget.companyId);
        }
      } else {
        nr = await _nfsService.getNextLaufendeInterneNrPreview(widget.companyId);
      }
      if (mounted) setState(() => _laufendeNrCtrl.text = nr);
    } catch (_) {
      if (mounted) setState(() => _laufendeNrCtrl.text = '–');
    }
  }

  void _openEinstellungen() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => EinsatzprotokollNfsEinstellungenScreen(
          companyId: widget.companyId,
          userRole: _userRole,
          onBack: () => Navigator.of(context).pop(),
        ),
      ),
    );
  }

  /// "Nachname, Vorname" → "Vorname Nachname"
  String _formatNameVornameZuerst(String? displayName) {
    if (displayName == null || displayName.isEmpty) return '';
    final parts = displayName.split(',');
    if (parts.length >= 2) {
      final nachname = parts[0].trim();
      final vorname = parts[1].trim();
      if (vorname.isNotEmpty && nachname.isNotEmpty) return '$vorname $nachname';
    }
    return displayName;
  }

  Future<void> _pickDatum() async {
    final d = await showDatePicker(
      context: context,
      initialDate: _einsatzDatum ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (d != null) setState(() => _einsatzDatum = d);
  }

  Future<void> _speichern() async {
    var valid = true;
    valid = valid && _nameCtrl.text.trim().isNotEmpty;
    valid = valid && (_alarmierungKoordinator || _alarmierungSonstige);
    valid = valid && _einsatzDatum != null;
    valid = valid && _einsatzNrCtrl.text.trim().isNotEmpty;
    valid = valid && _alarmierungszeit != null;
    valid = valid && _eintreffenTime != null;
    valid = valid && _abfahrtTime != null;
    valid = valid && _einsatzendeTime != null;
    valid = valid && (_einsatzindikation != null && _einsatzindikation!.trim().isNotEmpty);
    valid = valid && (_einsatzOeffentlich || _einsatzPrivat);
    valid = valid && (_nfsNachalarmiertJa || _nfsNachalarmiertNein);
    valid = valid && (!_nfsNachalarmiertJa || _nfsNachalarmiertNamenCtrl.text.trim().isNotEmpty);

    if (!valid) {
      if (mounted) {
        await showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Text('Hinweis', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.red)),
            content: const Text('Es wurden nicht alle Pflichtfelder ausgefüllt. Bitte ausfüllen.'),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('OK'),
              ),
            ],
          ),
        );
      }
      return;
    }

    setState(() => _saving = true);
    try {
      final user = _authService.currentUser;
      String? creatorName;
      if (user != null) {
        final auth = await _authDataService.getAuthData(user.uid, user.email ?? '', widget.companyId);
        creatorName = auth.displayName;
      }

      final data = <String, dynamic>{
        'name': _nameCtrl.text.trim(),
        'alarmierungKoordinator': _alarmierungKoordinator,
        'alarmierungSonstige': _alarmierungSonstige,
        'einsatzDatum': _einsatzDatum != null ? _formatDate(_einsatzDatum!) : null,
        'einsatzNr': _einsatzNrCtrl.text.trim(),
        'alarmierungszeit': _alarmierungszeit != null ? _formatTime(_alarmierungszeit!) : null,
        'eintreffenTime': _eintreffenTime != null ? _formatTime(_eintreffenTime!) : null,
        'abfahrtTime': _abfahrtTime != null ? _formatTime(_abfahrtTime!) : null,
        'einsatzendeTime': _einsatzendeTime != null ? _formatTime(_einsatzendeTime!) : null,
        'einsatzdauer': _einsatzdauerForSave,
        'gefahreneKm': _gefahreneKmCtrl.text.trim().isEmpty ? null : _gefahreneKmCtrl.text.trim(),
        'einsatzindikation': _einsatzindikation,
        'einsatzOeffentlich': _einsatzOeffentlich,
        'einsatzPrivat': _einsatzPrivat,
        'nfsNachalarmiertJa': _nfsNachalarmiertJa,
        'nfsNachalarmiertNein': _nfsNachalarmiertNein,
        'nfsNachalarmiertNamen': _nfsNachalarmiertJa ? _nfsNachalarmiertNamenCtrl.text.trim() : null,
        'situationVorOrt': _situationVorOrtCtrl.text.trim().isEmpty ? null : _situationVorOrtCtrl.text.trim(),
        'meineRolleAufgabe': _meineRolleAufgabeCtrl.text.trim().isEmpty ? null : _meineRolleAufgabeCtrl.text.trim(),
        'verlaufBegleitung': _verlaufBegleitungCtrl.text.trim().isEmpty ? null : _verlaufBegleitungCtrl.text.trim(),
        'situationAmEnde': _situationAmEndeCtrl.text.trim().isEmpty ? null : _situationAmEndeCtrl.text.trim(),
        'weitereBetreuungDurch': _weitereBetreuungDurch,
        'weitereBetreuungSonstiges': _weitereBetreuungDurch == 'sonstiges' ? _weitereBetreuungSonstigesCtrl.text.trim() : null,
        'weitereDiensteJa': _weitereDiensteJa,
        'weitereDiensteNein': _weitereDiensteNein,
        'weitereDiensteNamen': _weitereDiensteJa ? _weitereDiensteNamenCtrl.text.trim() : null,
        'fallbesprechung': _fallbesprechungCtrl.text.trim().isEmpty ? null : _fallbesprechungCtrl.text.trim(),
        'einsatznachbesprechungGewuenscht': _einsatznachbesprechungGewuenscht,
        'einsatznachbesprechungSonstiges': _einsatznachbesprechungGewuenscht == 'sonstiges' ? _einsatznachbesprechungSonstigesCtrl.text.trim() : null,
      };

      // Laufende-Interne-Nr: aus laufendeNr des Einsatzes (nicht einsatzNr!)
      String? laufendeNrOverride;
      if (_selectedEinsatzId != null && _selectedEinsatzId != 'manual') {
        Map<String, dynamic>? e;
        for (final x in _abgeschlosseneEinsaetze) {
          if ((x['id'] ?? '').toString() == _selectedEinsatzId) {
            e = x;
            break;
          }
        }
        if (e != null) {
          final base = (e['laufendeNr'] ?? '').toString().trim();
          final ids = (e['alarmierteMitarbeiterIds'] as List?)?.map((x) => x.toString()).toList() ?? [];
          final mid = widget.mitarbeiterId;
          if (base.isNotEmpty && mid != null && ids.length > 1) {
            final idx = ids.indexOf(mid);
            laufendeNrOverride = idx >= 0 ? '$base-${idx + 1}' : base;
          } else if (base.isNotEmpty) {
            laufendeNrOverride = base;
          }
        }
      }

      final result = await _nfsService.create(
        widget.companyId,
        data,
        creatorUid: user?.uid,
        creatorName: creatorName,
        laufendeNrOverride: laufendeNrOverride,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Protokoll ${result.laufendeInterneNr} gespeichert.')),
        );
        _resetForm();
        _loadLaufendeNrPreview();
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
    setState(() {
      _selectedEinsatzId = null;
      _einsatzDatum = null;
      _einsatzNrCtrl.clear();
      _alarmierungszeit = null;
      _eintreffenTime = null;
      _abfahrtTime = null;
      _einsatzendeTime = null;
      _gefahreneKmCtrl.clear();
      _alarmierungKoordinator = false;
      _alarmierungSonstige = false;
      _einsatzindikation = null;
      _einsatzOeffentlich = false;
      _einsatzPrivat = false;
      _nfsNachalarmiertJa = false;
      _nfsNachalarmiertNein = false;
      _nfsNachalarmiertNamenCtrl.clear();
      _situationVorOrtCtrl.clear();
      _meineRolleAufgabeCtrl.clear();
      _verlaufBegleitungCtrl.clear();
      _situationAmEndeCtrl.clear();
      _weitereBetreuungDurch = null;
      _weitereBetreuungSonstigesCtrl.clear();
      _weitereDiensteJa = false;
      _weitereDiensteNein = false;
      _weitereDiensteNamenCtrl.clear();
      _fallbesprechungCtrl.clear();
      _einsatznachbesprechungGewuenscht = null;
      _einsatznachbesprechungSonstigesCtrl.clear();
    });
  }

  Future<void> _pickUhrzeit(ValueChanged<TimeOfDay> onPicked, {TimeOfDay? initial}) async {
    final start = initial ?? TimeOfDay.now();
    final t = await showTimePicker(
      context: context,
      initialTime: start,
      initialEntryMode: TimePickerEntryMode.input,
      builder: (context, child) {
        return MediaQuery(
          data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true),
          child: child!,
        );
      },
    );
    if (t != null) {
      setState(() => onPicked(t));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.surfaceBg,
      appBar: AppTheme.buildModuleAppBar(
        title: widget.title ?? 'Einsatzprotokoll Notfallseelsorge',
        onBack: widget.onBack,
        actions: _canAccessEinstellungen
            ? [
                IconButton(
                  icon: const Icon(Icons.settings),
                  onPressed: _openEinstellungen,
                  tooltip: 'Einstellungen',
                ),
              ]
            : null,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _buildSection(
            title: 'Einsatzdaten',
            expanded: _einsatzdatenExpanded,
            onExpansionChanged: (v) => setState(() => _einsatzdatenExpanded = v),
            child: _buildEinsatzdatenContent(),
          ),
          const SizedBox(height: 16),
          _buildSection(
            title: 'Einsatzbericht',
            expanded: _einsatzberichtExpanded,
            onExpansionChanged: (v) => setState(() => _einsatzberichtExpanded = v),
            child: _buildEinsatzberichtContent(),
          ),
          const SizedBox(height: 16),
          _buildSection(
            title: 'Einsatzverlauf',
            expanded: _einsatzverlaufExpanded,
            onExpansionChanged: (v) => setState(() => _einsatzverlaufExpanded = v),
            child: _buildEinsatzverlaufContent(),
          ),
          const SizedBox(height: 16),
          _buildSection(
            title: 'Sonstiges',
            expanded: _sonstigesExpanded,
            onExpansionChanged: (v) => setState(() => _sonstigesExpanded = v),
            child: _buildSonstigesContent(),
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _saving ? null : _speichern,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
              child: _saving ? const Text('Wird gespeichert...') : const Text('Protokoll absenden'),
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _buildEinsatzberichtContent() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _field(_situationVorOrtCtrl, 'Situation vor Ort', maxLines: 4),
          _field(_meineRolleAufgabeCtrl, 'Meine Rolle / Aufgabe', maxLines: 4),
        ],
      ),
    );
  }

  Widget _buildEinsatzverlaufContent() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _field(_verlaufBegleitungCtrl, 'Verlauf der Begleitung', maxLines: 4),
          const SizedBox(height: 16),
          DropdownButtonFormField<String?>(
            value: _weitereBetreuungDurch,
            isExpanded: true,
            decoration: _inputDecoration.copyWith(labelText: 'Weitere Betreuung durch:'),
            items: _weitereBetreuungOptions
                .map((e) => DropdownMenuItem<String?>(value: e.$1, child: Text(e.$2, overflow: TextOverflow.ellipsis, maxLines: 1)))
                .toList(),
            onChanged: (v) => setState(() => _weitereBetreuungDurch = v),
          ),
          if (_weitereBetreuungDurch == 'sonstiges') ...[
            const SizedBox(height: 12),
            _field(_weitereBetreuungSonstigesCtrl, 'Bitte angeben', maxLines: 2),
          ],
          const SizedBox(height: 16),
          _field(_situationAmEndeCtrl, 'Situation am Ende vor Ort', maxLines: 4),
          const SizedBox(height: 16),
          Text('Wurden weitere Dienste in den Einsatz einbezogen?', style: TextStyle(fontSize: 13, color: Colors.grey.shade700)),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  _checkboxRow('Ja', _weitereDiensteJa, (v) => setState(() {
                    _weitereDiensteJa = v;
                    if (v) _weitereDiensteNein = false;
                  })),
                  _checkboxRow('Nein', _weitereDiensteNein, (v) => setState(() {
                    _weitereDiensteNein = v;
                    if (v) _weitereDiensteJa = false;
                  })),
                ],
              ),
              if (_weitereDiensteJa) ...[
                const SizedBox(width: 16),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: TextField(
                      controller: _weitereDiensteNamenCtrl,
                      maxLines: 2,
                      decoration: _inputDecoration.copyWith(
                        hintText: 'Namen der Dienste',
                        alignLabelWithHint: true,
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSonstigesContent() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _field(_fallbesprechungCtrl, 'Was ist interessant für eine Fallbesprechung?', maxLines: 4),
          const SizedBox(height: 16),
          DropdownButtonFormField<String?>(
            value: _einsatznachbesprechungGewuenscht,
            isExpanded: true,
            decoration: _inputDecoration.copyWith(
              labelText: 'Ist eine gesonderte Einsatznachbesprechung gewünscht?',
            ),
            items: _einsatznachbesprechungOptions
                .map((e) => DropdownMenuItem<String?>(value: e.$1, child: Text(e.$2, overflow: TextOverflow.ellipsis, maxLines: 1)))
                .toList(),
            onChanged: (v) => setState(() => _einsatznachbesprechungGewuenscht = v),
          ),
          if (_einsatznachbesprechungGewuenscht == 'sonstiges') ...[
            const SizedBox(height: 12),
            _field(_einsatznachbesprechungSonstigesCtrl, 'Bitte angeben', maxLines: 2),
          ],
        ],
      ),
    );
  }

  Widget _buildSection({
    required String title,
    required bool expanded,
    required ValueChanged<bool> onExpansionChanged,
    required Widget child,
  }) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          initiallyExpanded: expanded,
          onExpansionChanged: onExpansionChanged,
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
          title: Text(
            title,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: Colors.white,
            ),
          ),
          children: [
            Container(
              color: Theme.of(context).colorScheme.surface,
              child: child,
            ),
          ],
        ),
      ),
    );
  }

  void _applyEinsatzSelection(Map<String, dynamic> e) {
    // Einsatz-Nr = vom Koordinator bei „Neuer Einsatz“ manuell hinterlegt (nicht laufendeNr!)
    final einsatzNr = (e['einsatzNr'] ?? '').toString().trim();
    _einsatzNrCtrl.text = einsatzNr;

    // Einsatzindikation aus Alarmierung übernehmen
    final indikation = (e['einsatzindikation'] as String?)?.trim();
    _einsatzindikation = (indikation != null && indikation.isNotEmpty) ? indikation : null;

    // Datum aus Einsatz übernehmen
    final datumStr = (e['einsatzDatum'] ?? '').toString();
    _einsatzDatum = _parseDate(datumStr);

    // Statuszeiten: aus alarmierteMitarbeiterZeiten (Status 3→Alarmierung, 4→Eintreffen, 7→Abfahrt, 2→Einsatzende)
    Map<String, dynamic>? z;
    final zeiten = e['alarmierteMitarbeiterZeiten'];
    final mid = widget.mitarbeiterId;
    if (zeiten is Map) {
      if (mid != null) {
        z = zeiten[mid] as Map<String, dynamic>?;
        if (z == null) {
          for (final entry in zeiten.entries) {
            if (entry.key.toString() == mid && entry.value is Map) {
              z = Map<String, dynamic>.from(entry.value as Map);
              break;
            }
          }
        }
      }
      if (z == null) {
        // Kein mitarbeiterId: erste alarmierte Kraft verwenden
        final ids = (e['alarmierteMitarbeiterIds'] as List?)?.map((x) => x.toString()).toList() ?? [];
        for (final id in ids) {
          if (id.isNotEmpty) {
            final zeitenMap = zeiten[id];
            if (zeitenMap is Map && zeitenMap.isNotEmpty) {
              z = Map<String, dynamic>.from(zeitenMap);
              break;
            }
          }
        }
      }
    }
    if (z != null && z.isNotEmpty) {
      _alarmierungszeit = _parseTime((z['uhrzeitEinsatzUebernommen'] ?? '').toString());
      _eintreffenTime = _parseTime((z['uhrzeitAnEinsatzort'] ?? '').toString());
      _abfahrtTime = _parseTime((z['uhrzeitAbfahrt'] ?? '').toString());
      _einsatzendeTime = _parseTime((z['uhrzeitZuHause'] ?? '').toString());
    } else {
      // Fallback: Zeiten auf Einsatz-Ebene (vom Koordinator gesetzt)
      _alarmierungszeit = _parseTime((e['uhrzeitEinsatzUebernommen'] ?? '').toString());
      _eintreffenTime = _parseTime((e['uhrzeitAnEinsatzort'] ?? '').toString());
      _abfahrtTime = _parseTime((e['uhrzeitAbfahrt'] ?? '').toString());
      _einsatzendeTime = _parseTime((e['uhrzeitZuHause'] ?? '').toString());
    }
  }

  void _applyFromList(String? v) {
    if (v == null || !mounted) return;
    for (final x in _abgeschlosseneEinsaetze) {
      if ((x['id'] ?? '').toString() == v) {
        setState(() => _applyEinsatzSelection(x));
        return;
      }
    }
  }

  void _clearEinsatzSelection() {
    _einsatzNrCtrl.clear();
    _einsatzDatum = null;
    _alarmierungszeit = null;
    _eintreffenTime = null;
    _abfahrtTime = null;
    _einsatzendeTime = null;
    _einsatzindikation = null;
  }

  Widget _buildEinsatzNrField({bool required = true}) {
    final hasDropdown = _abgeschlosseneEinsaetze.isNotEmpty;
    if (!hasDropdown) {
      return _field(_einsatzNrCtrl, 'Einsatz-Nr.', required: required);
    }
    final dropdownValue = _selectedEinsatzId ?? '';
    final items = <DropdownMenuItem<String>>[
      const DropdownMenuItem(value: '', child: Text('bitte auswählen ...')),
      ..._abgeschlosseneEinsaetze.map((e) {
        final id = (e['id'] ?? '').toString();
        // Einsatz-Nr = Koordinator-Eingabe; laufendeNr NICHT hier anzeigen
        final einsatzNr = (e['einsatzNr'] ?? '').toString();
        final datum = (e['einsatzDatum'] ?? '').toString();
        final label = einsatzNr.isNotEmpty ? '$einsatzNr${datum.isNotEmpty ? ' ($datum)' : ''}' : (datum.isNotEmpty ? 'Einsatz $datum' : id);
        return DropdownMenuItem<String>(
          value: id,
          child: Text(label, overflow: TextOverflow.ellipsis, maxLines: 1),
        );
      }),
      const DropdownMenuItem(value: 'manual', child: Text('Manuell eingeben')),
    ];
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DropdownButtonFormField<String>(
            value: dropdownValue,
            isExpanded: true,
            decoration: _inputDecoration.copyWith(
              labelText: 'Einsatz-Nr.',
              fillColor: required && _einsatzNrCtrl.text.trim().isEmpty ? _pflichtfeldGelb : Colors.white,
            ),
            items: items,
            onChanged: (v) async {
              setState(() => _selectedEinsatzId = v);
              if (v == null || v.isEmpty) {
                setState(() => _clearEinsatzSelection());
              } else if (v == 'manual') {
                setState(() => _clearEinsatzSelection());
              } else {
                // Frische Daten vom Server laden (inkl. alarmierteMitarbeiterZeiten)
                final docId = v.toString();
                try {
                  final e = await _alarmierungNfsService.get(widget.companyId, docId);
                  if (mounted && e != null) {
                    setState(() => _applyEinsatzSelection(e));
                  } else {
                    _applyFromList(v);
                  }
                } catch (_) {
                  _applyFromList(v);
                }
              }
              if (mounted) _loadLaufendeNrPreview();
            },
          ),
          if (_selectedEinsatzId == 'manual') ...[
            const SizedBox(height: 8),
            _field(_einsatzNrCtrl, 'Einsatz-Nr. (manuell)', required: required),
          ],
        ],
      ),
    );
  }

  Widget _field(TextEditingController ctrl, String label, {List<TextInputFormatter>? inputFormatters, String? hintText, bool required = false, int maxLines = 1}) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: TextField(
          controller: ctrl,
          inputFormatters: inputFormatters,
          maxLines: maxLines,
          onChanged: required ? (_) => setState(() {}) : null,
          decoration: _inputDecoration.copyWith(
            labelText: label,
            hintText: hintText,
            alignLabelWithHint: maxLines > 1,
            fillColor: required && ctrl.text.trim().isEmpty ? _pflichtfeldGelb : Colors.white,
          ),
        ),
      );

  Widget _einsatzdauerField() => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: InputDecorator(
      decoration: _inputDecoration.copyWith(
        labelText: 'Einsatzdauer (HH.MM)',
        fillColor: Colors.grey.shade100,
      ),
      child: Text(_formatEinsatzdauer(_alarmierungszeit, _einsatzendeTime)),
    ),
  );

  Widget _uhrzeitField(String label, TimeOfDay? value, ValueChanged<TimeOfDay> onPicked, {bool required = false, VoidCallback? onPick}) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: InkWell(
          onTap: onPick ?? () => _pickUhrzeit(onPicked),
          child: InputDecorator(
            decoration: _inputDecoration.copyWith(
              labelText: label,
              fillColor: required && value == null ? _pflichtfeldGelb : Colors.white,
            ),
            child: Text(value != null ? _formatTime(value) : 'Uhrzeit eingeben'),
          ),
        ),
      );

  Widget _fieldReadOnly(TextEditingController ctrl, String label, {bool required = false, bool enabled = true}) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: TextField(
          controller: ctrl,
          readOnly: true,
          enabled: enabled,
          decoration: _inputDecoration.copyWith(
            labelText: label,
            fillColor: required && ctrl.text.trim().isEmpty ? _pflichtfeldGelb : Colors.grey.shade100,
          ),
        ),
      );

  Widget _checkboxRow(String label, bool value, ValueChanged<bool> onChanged, {bool required = false, bool groupFulfilled = true}) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 24,
              height: 24,
              child: Checkbox(
                value: value,
                onChanged: (v) => onChanged(v ?? false),
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                fillColor: (required && !groupFulfilled)
                    ? WidgetStateProperty.resolveWith((states) => states.contains(WidgetState.selected) ? null : _pflichtfeldGelb)
                    : null,
              ),
            ),
            const SizedBox(width: 8),
            Flexible(child: Text(label, style: const TextStyle(fontSize: 14), overflow: TextOverflow.ellipsis)),
          ],
        ),
      );

  Widget _buildEinsatzdatenContent() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isNarrow = constraints.maxWidth < 600;
        return Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (isNarrow) ...[
                _fieldReadOnly(_laufendeNrCtrl, 'Laufende interne Nr.', required: false, enabled: false),
                _fieldReadOnly(_nameCtrl, 'Vor- und Nachname', required: true),
                const SizedBox(height: 4),
                Text('Alarmierung durch:', style: TextStyle(fontSize: 13, color: Colors.grey.shade700)),
                _checkboxRow('Koordinator', _alarmierungKoordinator, (v) => setState(() => _alarmierungKoordinator = v), required: true, groupFulfilled: _alarmierungKoordinator || _alarmierungSonstige),
                _checkboxRow('sonstige', _alarmierungSonstige, (v) => setState(() => _alarmierungSonstige = v), required: true, groupFulfilled: _alarmierungKoordinator || _alarmierungSonstige),
                const SizedBox(height: 12),
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: InkWell(
                    onTap: _pickDatum,
                    child: InputDecorator(
                      decoration: _inputDecoration.copyWith(
                        labelText: 'Einsatz-Datum',
                        fillColor: _einsatzDatum == null ? _pflichtfeldGelb : Colors.white,
                      ),
                      child: Text(_einsatzDatum != null ? _formatDate(_einsatzDatum!) : 'Datum wählen'),
                    ),
                  ),
                ),
                _buildEinsatzNrField(required: true),
                _uhrzeitField('Alarmierungszeit (HH:MM)', _alarmierungszeit, (t) => _alarmierungszeit = t, required: true, onPick: () => _pickUhrzeit((t) => _alarmierungszeit = t, initial: _alarmierungszeit)),
                _uhrzeitField('Eintreffen vor Ort (HH:MM)', _eintreffenTime, (t) => _eintreffenTime = t, required: true, onPick: () => _pickUhrzeit((t) => _eintreffenTime = t, initial: _eintreffenTime)),
                _uhrzeitField('Abfahrt vom Einsatzort (HH:MM)', _abfahrtTime, (t) => _abfahrtTime = t, required: true, onPick: () => _pickUhrzeit((t) => _abfahrtTime = t, initial: _abfahrtTime)),
                _uhrzeitField('Einsatzende (HH:MM)', _einsatzendeTime, (t) => _einsatzendeTime = t, required: true, onPick: () => _pickUhrzeit((t) => _einsatzendeTime = t, initial: _einsatzendeTime)),
                _einsatzdauerField(),
                _field(_gefahreneKmCtrl, 'Gefahrene KM (bitte nur ganze KM angeben)', inputFormatters: [FilteringTextInputFormatter.digitsOnly], required: true),
                const SizedBox(height: 16),
                DropdownButtonFormField<String?>(
                  value: _einsatzindikation,
                  isExpanded: true,
                  decoration: _inputDecoration.copyWith(
                    labelText: 'Einsatzindikation',
                    fillColor: (_einsatzindikation == null || (_einsatzindikation ?? '').trim().isEmpty) ? _pflichtfeldGelb : Colors.white,
                  ),
                  items: _einsatzindikationOptions
                      .map((e) => DropdownMenuItem<String?>(value: e.$1, child: Text(e.$2, overflow: TextOverflow.ellipsis, maxLines: 1)))
                      .toList(),
                  onChanged: (v) => setState(() => _einsatzindikation = v),
                ),
                const SizedBox(height: 16),
                Text('Einsatz im:', style: TextStyle(fontSize: 13, color: Colors.grey.shade700)),
                _checkboxRow('öffentlichen Bereich', _einsatzOeffentlich, (v) => setState(() => _einsatzOeffentlich = v), required: true, groupFulfilled: _einsatzOeffentlich || _einsatzPrivat),
                _checkboxRow('privaten Bereich', _einsatzPrivat, (v) => setState(() => _einsatzPrivat = v), required: true, groupFulfilled: _einsatzOeffentlich || _einsatzPrivat),
                const SizedBox(height: 16),
                Text('Wurden NFS nachalarmiert?', style: TextStyle(fontSize: 13, color: Colors.grey.shade700)),
                _checkboxRow('Ja', _nfsNachalarmiertJa, (v) => setState(() {
                  _nfsNachalarmiertJa = v;
                  if (v) _nfsNachalarmiertNein = false;
                }), required: true, groupFulfilled: _nfsNachalarmiertJa || _nfsNachalarmiertNein),
                _checkboxRow('Nein', _nfsNachalarmiertNein, (v) => setState(() {
                  _nfsNachalarmiertNein = v;
                  if (v) _nfsNachalarmiertJa = false;
                }), required: true, groupFulfilled: _nfsNachalarmiertJa || _nfsNachalarmiertNein),
                if (_nfsNachalarmiertJa) ...[
                  const SizedBox(height: 8),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Namen der nachalarmierten NFS eingeben', style: TextStyle(fontSize: 13, color: Colors.grey.shade700)),
                        const SizedBox(height: 4),
                        TextField(
                          controller: _nfsNachalarmiertNamenCtrl,
                          maxLines: 2,
                          decoration: _inputDecoration.copyWith(
                            labelText: null,
                            hintText: null,
                            alignLabelWithHint: true,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ] else
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _fieldReadOnly(_laufendeNrCtrl, 'Laufende interne Nr.', required: false, enabled: false),
                          _fieldReadOnly(_nameCtrl, 'Vor- und Nachname', required: true),
                          const SizedBox(height: 4),
                          Text('Alarmierung durch:', style: TextStyle(fontSize: 13, color: Colors.grey.shade700)),
                          _checkboxRow('Koordinator', _alarmierungKoordinator, (v) => setState(() => _alarmierungKoordinator = v), required: true, groupFulfilled: _alarmierungKoordinator || _alarmierungSonstige),
                          _checkboxRow('sonstige', _alarmierungSonstige, (v) => setState(() => _alarmierungSonstige = v), required: true, groupFulfilled: _alarmierungKoordinator || _alarmierungSonstige),
                          const SizedBox(height: 16),
                          DropdownButtonFormField<String?>(
                            value: _einsatzindikation,
                            isExpanded: true,
                            decoration: _inputDecoration.copyWith(
                              labelText: 'Einsatzindikation',
                              fillColor: (_einsatzindikation == null || (_einsatzindikation ?? '').trim().isEmpty) ? _pflichtfeldGelb : Colors.white,
                            ),
                            items: _einsatzindikationOptions
                                .map((e) => DropdownMenuItem<String?>(value: e.$1, child: Text(e.$2, overflow: TextOverflow.ellipsis, maxLines: 1)))
                                .toList(),
                            onChanged: (v) => setState(() => _einsatzindikation = v),
                          ),
                          const SizedBox(height: 16),
                          Text('Einsatz im:', style: TextStyle(fontSize: 13, color: Colors.grey.shade700)),
                          _checkboxRow('öffentlichen Bereich', _einsatzOeffentlich, (v) => setState(() => _einsatzOeffentlich = v), required: true, groupFulfilled: _einsatzOeffentlich || _einsatzPrivat),
                          _checkboxRow('privaten Bereich', _einsatzPrivat, (v) => setState(() => _einsatzPrivat = v), required: true, groupFulfilled: _einsatzOeffentlich || _einsatzPrivat),
                          const SizedBox(height: 16),
                          Text('Wurden NFS nachalarmiert?', style: TextStyle(fontSize: 13, color: Colors.grey.shade700)),
                          _checkboxRow('Ja', _nfsNachalarmiertJa, (v) => setState(() {
                            _nfsNachalarmiertJa = v;
                            if (v) _nfsNachalarmiertNein = false;
                          }), required: true, groupFulfilled: _nfsNachalarmiertJa || _nfsNachalarmiertNein),
                          _checkboxRow('Nein', _nfsNachalarmiertNein, (v) => setState(() {
                            _nfsNachalarmiertNein = v;
                            if (v) _nfsNachalarmiertJa = false;
                          }), required: true, groupFulfilled: _nfsNachalarmiertJa || _nfsNachalarmiertNein),
                          if (_nfsNachalarmiertJa) ...[
                            const SizedBox(height: 8),
                            Padding(
                              padding: const EdgeInsets.only(bottom: 12),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('Namen der nachalarmierten NFS eingeben', style: TextStyle(fontSize: 13, color: Colors.grey.shade700)),
                                  const SizedBox(height: 4),
                                  TextField(
                                    controller: _nfsNachalarmiertNamenCtrl,
                                    maxLines: 2,
                                    decoration: _inputDecoration.copyWith(
                                      labelText: null,
                                      hintText: null,
                                      alignLabelWithHint: true,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(width: 24),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: InkWell(
                              onTap: _pickDatum,
                              child: InputDecorator(
                                decoration: _inputDecoration.copyWith(
                                  labelText: 'Einsatz-Datum',
                                  fillColor: _einsatzDatum == null ? _pflichtfeldGelb : Colors.white,
                                ),
                                child: Text(_einsatzDatum != null ? _formatDate(_einsatzDatum!) : 'Datum wählen'),
                              ),
                            ),
                          ),
                          _buildEinsatzNrField(required: true),
                          _uhrzeitField('Alarmierungszeit (HH:MM)', _alarmierungszeit, (t) => _alarmierungszeit = t, required: true, onPick: () => _pickUhrzeit((t) => _alarmierungszeit = t, initial: _alarmierungszeit)),
                          _uhrzeitField('Eintreffen vor Ort (HH:MM)', _eintreffenTime, (t) => _eintreffenTime = t, required: true, onPick: () => _pickUhrzeit((t) => _eintreffenTime = t, initial: _eintreffenTime)),
                          _uhrzeitField('Abfahrt vom Einsatzort (HH:MM)', _abfahrtTime, (t) => _abfahrtTime = t, required: true, onPick: () => _pickUhrzeit((t) => _abfahrtTime = t, initial: _abfahrtTime)),
                          _uhrzeitField('Einsatzende (HH:MM)', _einsatzendeTime, (t) => _einsatzendeTime = t, required: true, onPick: () => _pickUhrzeit((t) => _einsatzendeTime = t, initial: _einsatzendeTime)),
                          _einsatzdauerField(),
                          _field(_gefahreneKmCtrl, 'Gefahrene KM (bitte nur ganze KM angeben)', inputFormatters: [FilteringTextInputFormatter.digitsOnly], required: true),
                        ],
                      ),
                    ),
                  ],
                ),
            ],
          ),
        );
      },
    );
  }
}
