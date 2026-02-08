import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../models/fahrtenbuch_model.dart';
import '../models/fahrtenbuch_vorlage.dart';
import '../models/fleet_model.dart';
import '../models/mitarbeiter_model.dart';
import '../services/fahrtenbuch_service.dart';
import '../services/mitarbeiter_service.dart';
import '../services/auth_service.dart';
import '../services/schicht_status_service.dart';
import '../services/schichtanmeldung_service.dart';

/// Fahrtenbuch – digitales Fahrtenbuch
class FahrtenbuchScreen extends StatefulWidget {
  final String companyId;
  final VoidCallback onBack;
  final FahrtenbuchVorlage? initialVorlage;
  final FahrtenbuchEintrag? initialEintrag;

  const FahrtenbuchScreen({
    super.key,
    required this.companyId,
    required this.onBack,
    this.initialVorlage,
    this.initialEintrag,
  });

  @override
  State<FahrtenbuchScreen> createState() => _FahrtenbuchScreenState();
}

class _FahrtenbuchScreenState extends State<FahrtenbuchScreen> {
  final _service = FahrtenbuchService();
  final _mitarbeiterService = MitarbeiterService();
  final _authService = AuthService();
  DateTime _filterVon = DateTime.now();
  DateTime _filterBis = DateTime.now();
  bool _useDateFilter = false;
  bool _formOpenedFromVorlage = false;
  FahrtenbuchUebersichtItem? _selectedFahrzeug; // null = Übersicht, gesetzt = Einträge dieses Fahrzeugs

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybeOpenForm());
  }

  Future<void> _maybeOpenForm() async {
    if (!mounted || _formOpenedFromVorlage) return;
    _formOpenedFromVorlage = true;
    if (widget.initialEintrag != null) {
      _openEintragForm(eintrag: widget.initialEintrag, vorlage: null);
      return;
    }
    var vorlage = widget.initialVorlage;
    if (vorlage == null) {
      var aktiveSchicht = await SchichtStatusService().getAktiveSchicht(widget.companyId);
      if (aktiveSchicht == null) {
        final normId = widget.companyId.trim().toLowerCase();
        if (normId != widget.companyId) {
          aktiveSchicht = await SchichtStatusService().getAktiveSchicht(normId);
        }
      }
      if (aktiveSchicht != null && mounted) {
        vorlage = await SchichtanmeldungService().buildFahrtenbuchVorlageFromAnmeldung(
          widget.companyId, aktiveSchicht, _service);
        if (vorlage == null && widget.companyId.trim().toLowerCase() != widget.companyId) {
          vorlage = await SchichtanmeldungService().buildFahrtenbuchVorlageFromAnmeldung(
            widget.companyId.trim().toLowerCase(), aktiveSchicht, _service);
        }
      }
    }
    if (mounted) _openEintragForm(vorlage: vorlage);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.surfaceBg,
      appBar: AppTheme.buildModuleAppBar(
        title: _selectedFahrzeug?.displayLabel ?? 'Fahrtenbücher',
        onBack: () {
          if (_selectedFahrzeug != null) {
            setState(() => _selectedFahrzeug = null);
          } else {
            widget.onBack();
          }
        },
      ),
      body: const Center(child: CircularProgressIndicator(color: AppTheme.primary)),
    );
  }

  Widget _buildUebersicht() {
    return FutureBuilder<List<FahrtenbuchUebersichtItem>>(
      future: _service.loadFahrtenbuecherUebersicht(widget.companyId),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator(color: AppTheme.primary));
        }
        final list = snap.data ?? [];
        if (list.isEmpty) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.directions_car_outlined, size: 64, color: Colors.grey[400]),
                const SizedBox(height: 16),
                Text(
                  'Keine Fahrtenbücher vorhanden.',
                  style: TextStyle(color: Colors.grey[600]),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  'Das Fahrtenbuch wird beim ersten Eintrag über die Schichtanmeldung erstellt.',
                  style: TextStyle(color: Colors.grey[500], fontSize: 13),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          );
        }
        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: list.length,
          itemBuilder: (_, i) {
            final item = list[i];
            return Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: ListTile(
                leading: CircleAvatar(
                  backgroundColor: AppTheme.primary.withOpacity(0.15),
                  child: Icon(Icons.directions_car, color: AppTheme.primary),
                ),
                title: Text(item.displayLabel, style: const TextStyle(fontWeight: FontWeight.w600)),
                subtitle: Text('${item.anzahl} Einträge'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => setState(() => _selectedFahrzeug = item),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildFahrzeugEintraege() {
    final item = _selectedFahrzeug!;
    final key = item.vehicleKey;
    return StreamBuilder<List<FahrtenbuchEintrag>>(
      stream: _service.streamEintraegeFuerFahrzeug(widget.companyId, key),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting && !snap.hasData) {
          return const Center(child: CircularProgressIndicator(color: AppTheme.primary));
        }
        final list = snap.data ?? [];
        if (list.isEmpty) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.description_outlined, size: 64, color: Colors.grey[400]),
                const SizedBox(height: 16),
                Text('Keine Einträge für dieses Fahrzeug.', style: TextStyle(color: Colors.grey[600])),
              ],
            ),
          );
        }
        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: list.length,
          itemBuilder: (_, i) => _buildEintragCard(list[i]),
        );
      },
    );
  }

  Widget _buildDateFilter() {
    return Container(
      padding: const EdgeInsets.all(12),
      color: Colors.white,
      child: Row(
        children: [
          Expanded(
            child: OutlinedButton.icon(
              icon: const Icon(Icons.calendar_today, size: 18),
              label: Text('${_filterVon.day.toString().padLeft(2, '0')}.${_filterVon.month.toString().padLeft(2, '0')}.${_filterVon.year}'),
              onPressed: () async {
                final d = await showDatePicker(
                  context: context,
                  initialDate: _filterVon,
                  firstDate: DateTime(2020),
                  lastDate: DateTime.now().add(const Duration(days: 365)),
                );
                if (d != null) setState(() => _filterVon = d);
              },
            ),
          ),
          const Padding(padding: EdgeInsets.symmetric(horizontal: 8), child: Text('–')),
          Expanded(
            child: OutlinedButton.icon(
              icon: const Icon(Icons.calendar_today, size: 18),
              label: Text('${_filterBis.day.toString().padLeft(2, '0')}.${_filterBis.month.toString().padLeft(2, '0')}.${_filterBis.year}'),
              onPressed: () async {
                final d = await showDatePicker(
                  context: context,
                  initialDate: _filterBis,
                  firstDate: DateTime(2020),
                  lastDate: DateTime.now().add(const Duration(days: 365)),
                );
                if (d != null) setState(() => _filterBis = d);
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEintragCard(FahrtenbuchEintrag e) {
    final datumStr = e.datum != null
        ? '${e.datum!.day.toString().padLeft(2, '0')}.${e.datum!.month.toString().padLeft(2, '0')}.${e.datum!.year}'
        : '–';
    final alarmEnde = [e.alarm, e.ende].where((x) => x != null && x.toString().trim().isNotEmpty).join(' – ');
    final fahrzeug = e.fahrzeugkennung ?? e.kennzeichen ?? '–';
    final ziel = e.transportziel ?? e.einsatzort ?? e.einsatzart ?? '';

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        onTap: () => _openEintragForm(eintrag: e, vorlage: null),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(datumStr, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                  if (alarmEnde.isNotEmpty) ...[
                    const SizedBox(width: 8),
                    Text(alarmEnde, style: TextStyle(color: Colors.grey[700], fontSize: 13)),
                  ],
                  const Spacer(),
                  if (e.gesamtKm != null)
                    Text('${e.gesamtKm} km', style: TextStyle(color: AppTheme.primary, fontWeight: FontWeight.w500, fontSize: 13)),
                ],
              ),
              const SizedBox(height: 4),
              Text(fahrzeug, style: TextStyle(color: Colors.grey[700], fontSize: 13)),
              if (e.nameFahrer != null && e.nameFahrer!.trim().isNotEmpty)
                Text('Fahrer: ${e.nameFahrer}', style: TextStyle(color: Colors.grey[600], fontSize: 12)),
              if (ziel.isNotEmpty)
                Text(ziel, style: TextStyle(color: Colors.grey[600], fontSize: 12), maxLines: 1, overflow: TextOverflow.ellipsis),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _openEintragForm({FahrtenbuchEintrag? eintrag, FahrtenbuchVorlage? vorlage}) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (ctx) => _FahrtenbuchFormScreen(
          companyId: widget.companyId,
          eintrag: eintrag,
          vorlage: vorlage,
          fahrtenbuchService: _service,
          mitarbeiterService: _mitarbeiterService,
          currentUserUid: _authService.currentUser?.uid ?? '',
          onSave: () {
            Navigator.of(ctx).pop();
            widget.onBack();
          },
          onCancel: () {
            Navigator.of(ctx).pop();
            widget.onBack();
          },
        ),
      ),
    );
  }
}

class _FahrtenbuchFormScreen extends StatefulWidget {
  final String companyId;
  final FahrtenbuchEintrag? eintrag;
  final FahrtenbuchVorlage? vorlage;
  final FahrtenbuchService fahrtenbuchService;
  final MitarbeiterService mitarbeiterService;
  final String currentUserUid;
  final VoidCallback onSave;
  final VoidCallback onCancel;

  const _FahrtenbuchFormScreen({
    required this.companyId,
    this.eintrag,
    this.vorlage,
    required this.fahrtenbuchService,
    required this.mitarbeiterService,
    required this.currentUserUid,
    required this.onSave,
    required this.onCancel,
  });

  @override
  State<_FahrtenbuchFormScreen> createState() => _FahrtenbuchFormScreenState();
}

class _FahrtenbuchFormScreenState extends State<_FahrtenbuchFormScreen> {
  final _formKey = GlobalKey<FormState>();
  List<Fahrzeug> _fahrzeuge = [];
  List<String> _mitarbeiterNamen = [];
  String? _selectedFahrzeugId;
  // Vorlage-Namen sofort nutzbar, damit Dropdowns beim ersten Build schon Werte anzeigen
  List<String> _vorlageNamen = [];
  String? _selectedFahrer;
  String? _selectedBeifahrer;
  late TextEditingController _fahrzeugkennungCtrl;
  late TextEditingController _kennzeichenCtrl;
  late TextEditingController _nameFahrerCtrl;
  late TextEditingController _nameBeifahrerCtrl;
  late TextEditingController _praktikantCtrl;
  late TextEditingController _datumCtrl;
  late TextEditingController _alarmCtrl;
  late TextEditingController _endeCtrl;
  FocusNode? _alarmFocusNode;
  FocusNode? _endeFocusNode;
  late TextEditingController _einsatzartCtrl;
  late TextEditingController _einsatzortCtrl;
  late TextEditingController _transportzielCtrl;
  late TextEditingController _einsatznummerCtrl;
  late TextEditingController _kmAnfangCtrl;
  late TextEditingController _kmEndeCtrl;
  late TextEditingController _besetztKmCtrl;
  final TextEditingController _mitarbeiterSuchCtrl = TextEditingController();
  bool _sonderrechteAnfahrt = false;
  bool _sonderrechteTransport = false;
  bool _transportschein = false;
  bool _loading = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final e = widget.eintrag;
    final v = widget.vorlage;
    final fzRuf = e?.fahrzeugkennung ?? v?.fahrzeugRufname ?? '';
    final kz = e?.kennzeichen ?? v?.kennzeichen ?? '';
    final nF = e?.nameFahrer ?? v?.nameFahrer ?? '';
    final nB = e?.nameBeifahrer ?? v?.nameBeifahrer ?? '';
    _fahrzeugkennungCtrl = TextEditingController(text: fzRuf);
    _kennzeichenCtrl = TextEditingController(text: kz);
    _nameFahrerCtrl = TextEditingController(text: nF);
    _nameBeifahrerCtrl = TextEditingController(text: nB);
    if (v != null) {
      _selectedFahrzeugId = (fzRuf.isNotEmpty || (v.fahrzeugId.isNotEmpty && v.fahrzeugId != 'alle')) ? '__vorlage__' : null;
      _selectedFahrer = nF.trim().isEmpty ? null : nF.trim();
      _selectedBeifahrer = nB.trim().isEmpty ? null : nB.trim();
    }
    _praktikantCtrl = TextEditingController(text: e?.praktikantAzubi ?? '');
    final datum = e?.datum ?? v?.datum ?? DateTime.now();
    _datumCtrl = TextEditingController(
      text: '${datum.day.toString().padLeft(2, '0')}.${datum.month.toString().padLeft(2, '0')}.${datum.year}',
    );
    _alarmCtrl = TextEditingController(text: e?.alarm ?? '');
    _endeCtrl = TextEditingController(text: e?.ende ?? '');
    _alarmFocusNode = FocusNode();
    _endeFocusNode = FocusNode();
    _alarmFocusNode!.addListener(_onAlarmFocusChanged);
    _endeFocusNode!.addListener(_onEndeFocusChanged);
    _einsatzartCtrl = TextEditingController(text: e?.einsatzart ?? '');
    _einsatzortCtrl = TextEditingController(text: e?.einsatzort ?? '');
    _transportzielCtrl = TextEditingController(text: e?.transportziel ?? '');
    _einsatznummerCtrl = TextEditingController(text: e?.einsatznummer ?? '');
    _kmAnfangCtrl = TextEditingController(text: e?.kmAnfang?.toString() ?? v?.kmAnfang?.toString() ?? '');
    _kmEndeCtrl = TextEditingController(text: e?.kmEnde?.toString() ?? '');
    _besetztKmCtrl = TextEditingController(text: e?.besetztKm?.toString() ?? '');
    final sr = (e?.sonderrechteAnfahrtTransport ?? '').toLowerCase();
    _sonderrechteAnfahrt = sr.contains('anfahrt') && sr.contains('ja');
    _sonderrechteTransport = sr.contains('transport') && sr.contains('ja');
    _transportschein = e?.transportschein ?? false;
    _kmAnfangCtrl.addListener(() => setState(() {}));
    _kmEndeCtrl.addListener(() => setState(() {}));
    _mitarbeiterSuchCtrl.addListener(() => setState(() {}));
    if (v != null) {
      final fa = v.fahrerOptionen;
      final be = v.beifahrerOptionen;
      _vorlageNamen = [
        ...(fa ?? const <String>[]),
        ...(be ?? const <String>[]),
        if (v.nameFahrer != null && v.nameFahrer!.trim().isNotEmpty) v.nameFahrer!,
        if (v.nameBeifahrer != null && v.nameBeifahrer!.trim().isNotEmpty) v.nameBeifahrer!,
      ].where((n) => n.trim().isNotEmpty).toSet().toList();
    }
    _loadData();
  }

  void _onAlarmFocusChanged() {
    if (_alarmFocusNode?.hasFocus == false) {
      final t = _formatTimeInput(_alarmCtrl.text.trim());
      if (t.isNotEmpty) {
        _alarmCtrl.text = t;
        _alarmCtrl.selection = TextSelection.collapsed(offset: t.length);
      }
    }
  }

  void _onEndeFocusChanged() {
    if (_endeFocusNode?.hasFocus == false) {
      final t = _formatTimeInput(_endeCtrl.text.trim());
      if (t.isNotEmpty) {
        _endeCtrl.text = t;
        _endeCtrl.selection = TextSelection.collapsed(offset: t.length);
      }
    }
  }

  Future<void> _showMitarbeiterPicker({
    required String label,
    required String? currentValue,
    required String emptyOption,
    required void Function(String?) onSelected,
  }) async {
    if (!mounted) return;
    final result = await showGeneralDialog<String?>(
      context: context,
      barrierDismissible: false,
      barrierLabel: label,
      barrierColor: Colors.black54,
      transitionDuration: const Duration(milliseconds: 200),
      pageBuilder: (ctx, animation, secondaryAnimation) => Align(
        alignment: Alignment.topCenter,
        child: Material(
          color: Colors.transparent,
          child: SafeArea(
            child: _MitarbeiterPickerSheet(
              emptyOption: emptyOption,
              filteredNames: _filteredMitarbeiterNamen(),
            ),
          ),
        ),
      ),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && result != null) {
        onSelected(result.isEmpty ? null : result);
      }
    });
  }

  List<String> _filteredMitarbeiterNamen() {
    final names = List<String>.from(_mitarbeiterNamen);
    for (final n in _vorlageNamen) {
      if (n.trim().isNotEmpty && !names.contains(n)) names.add(n);
    }
    final valF = _selectedFahrer ?? _nameFahrerCtrl.text.trim();
    if (valF.isNotEmpty && !names.contains(valF)) names.add(valF);
    final valB = _selectedBeifahrer ?? _nameBeifahrerCtrl.text.trim();
    if (valB.isNotEmpty && !names.contains(valB)) names.add(valB);
    final q = _mitarbeiterSuchCtrl.text.trim().toLowerCase();
    List<String> result;
    if (q.isNotEmpty) {
      result = names.where((n) => n.toLowerCase().contains(q)).toList();
      for (final v in [valF, valB]) {
        if (v.isNotEmpty && !result.contains(v)) result.add(v);
      }
    } else {
      result = names;
    }
    result.sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return result;
  }

  Future<void> _loadData() async {
    final vorlage = widget.vorlage;
    final cid = widget.companyId;
    try {
      final results = await Future.wait<dynamic>([
        widget.fahrtenbuchService.loadFahrzeuge(cid),
        widget.mitarbeiterService.streamMitarbeiter(cid).first,
        SchichtanmeldungService().loadSchichtplanMitarbeiter(cid),
      ]);
      final fz = results[0] as List<Fahrzeug>;
      final ma = results[1] as List<Mitarbeiter>;
      final schichtplan = results[2] as List<SchichtplanMitarbeiter>;
      final namenSet = <String>{};
      for (final m in ma) {
        final n = m.displayName.trim();
        if (n.isNotEmpty) namenSet.add(n);
      }
      for (final m in schichtplan) {
        final n = m.displayName.trim();
        if (n.isNotEmpty) namenSet.add(n);
      }
      var namen = namenSet.toList();
      for (final n in _vorlageNamen) {
        if (n.trim().isNotEmpty && !namen.contains(n)) namen.add(n);
      }
      if (vorlage != null) {
        final fa = vorlage.fahrerOptionen;
        final be = vorlage.beifahrerOptionen;
        for (final n in [...(fa ?? const <String>[]), ...(be ?? const <String>[])]) {
          if (n.trim().isNotEmpty && !namen.contains(n)) namen.add(n);
        }
      }
      namen.sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));

      var selectedFzId = _selectedFahrzeugId;
      var selectedFahrer = _selectedFahrer;
      var selectedBeifahrer = _selectedBeifahrer;

      final fzMatch = widget.eintrag?.fahrzeugkennung ?? vorlage?.fahrzeugRufname ?? vorlage?.fahrzeugId;
      final kzVorhanden = (widget.eintrag?.kennzeichen ?? vorlage?.kennzeichen)?.trim().isNotEmpty == true;
      if (fzMatch != null && fzMatch.isNotEmpty && fz.isNotEmpty) {
        for (final f in fz) {
          final ruf = (f.rufname ?? f.id ?? '').toString().trim();
          final id = (f.id ?? '').toString().trim();
          if (ruf == fzMatch.trim() || id == fzMatch.trim()) {
            selectedFzId = f.id;
            _fahrzeugkennungCtrl.text = f.rufname ?? f.id ?? '';
            final kz = f.kennzeichen?.trim().isNotEmpty == true ? f.kennzeichen : null;
            _kennzeichenCtrl.text = kz ?? widget.eintrag?.kennzeichen ?? vorlage?.kennzeichen ?? _kennzeichenCtrl.text;
            break;
          }
        }
        if (selectedFzId == null && kzVorhanden) {
          final gesuchtKz = (widget.eintrag?.kennzeichen ?? vorlage?.kennzeichen ?? '').trim();
          for (final f in fz) {
            if ((f.kennzeichen ?? '').trim() == gesuchtKz) {
              selectedFzId = f.id;
              _fahrzeugkennungCtrl.text = f.rufname ?? f.id ?? '';
              _kennzeichenCtrl.text = f.kennzeichen ?? gesuchtKz;
              break;
            }
          }
        }
      }
      if (selectedFzId == null && vorlage != null && (vorlage.fahrzeugRufname.trim().isNotEmpty || vorlage.fahrzeugId.trim().isNotEmpty)) {
        selectedFzId = '__vorlage__';
        _fahrzeugkennungCtrl.text = vorlage.fahrzeugRufname.trim().isNotEmpty ? vorlage.fahrzeugRufname : vorlage.fahrzeugId;
        if (vorlage.kennzeichen != null && vorlage.kennzeichen!.trim().isNotEmpty) {
          _kennzeichenCtrl.text = vorlage.kennzeichen!;
        }
      }
      if (vorlage?.kennzeichen != null && vorlage!.kennzeichen!.trim().isNotEmpty && _kennzeichenCtrl.text.trim().isEmpty) {
        _kennzeichenCtrl.text = vorlage.kennzeichen!;
      }
      if (vorlage?.nameFahrer != null && vorlage!.nameFahrer!.trim().isNotEmpty) {
        selectedFahrer = vorlage.nameFahrer!.trim();
        _nameFahrerCtrl.text = selectedFahrer;
      }
      if (vorlage?.nameBeifahrer != null && vorlage!.nameBeifahrer!.trim().isNotEmpty) {
        selectedBeifahrer = vorlage.nameBeifahrer!.trim();
        _nameBeifahrerCtrl.text = selectedBeifahrer;
      }

      if (mounted) {
        setState(() {
          _fahrzeuge = fz;
          _mitarbeiterNamen = namen;
          _selectedFahrzeugId = selectedFzId;
          _selectedFahrer = selectedFahrer;
          _selectedBeifahrer = selectedBeifahrer;
          _loading = false;
        });
        if (widget.eintrag == null && _kmAnfangCtrl.text.trim().isEmpty && _fahrzeugkennungCtrl.text.trim().isNotEmpty) {
          _fillKmAnfangFromLastTrip();
        }
      }
    } catch (_) {
      if (mounted) {
        if (vorlage != null) {
          _selectedFahrzeugId = vorlage.fahrzeugRufname.trim().isNotEmpty || vorlage.fahrzeugId.trim().isNotEmpty ? '__vorlage__' : null;
          if (_selectedFahrzeugId == '__vorlage__') {
            _fahrzeugkennungCtrl.text = vorlage.fahrzeugRufname.trim().isNotEmpty ? vorlage.fahrzeugRufname : vorlage.fahrzeugId;
            if (vorlage.kennzeichen != null && vorlage.kennzeichen!.trim().isNotEmpty) {
              _kennzeichenCtrl.text = vorlage.kennzeichen!;
            }
          }
          if (vorlage.nameFahrer != null && vorlage.nameFahrer!.trim().isNotEmpty) {
            _selectedFahrer = vorlage.nameFahrer!.trim();
            _nameFahrerCtrl.text = _selectedFahrer!;
          }
          if (vorlage.nameBeifahrer != null && vorlage.nameBeifahrer!.trim().isNotEmpty) {
            _selectedBeifahrer = vorlage.nameBeifahrer!.trim();
            _nameBeifahrerCtrl.text = _selectedBeifahrer!;
          }
        }
        setState(() => _loading = false);
      }
    }
  }

  /// Km Anfang aus dem Ende der letzten Fahrt/Korrektur dieses Fahrzeugs vorbelegen (bei neuem Eintrag)
  Future<void> _fillKmAnfangFromLastTrip() async {
    final ruf = _fahrzeugkennungCtrl.text.trim();
    final kz = _kennzeichenCtrl.text.trim();
    if ((ruf.isEmpty && kz.isEmpty) || widget.eintrag != null) return;
    final km = await widget.fahrtenbuchService.getLetzterKmEndeByKennzeichenOderRufname(
      widget.companyId,
      kz.isNotEmpty ? kz : null,
      fahrzeugRufnameAlternativ: ruf.isNotEmpty ? ruf : null,
    );
    if (mounted && km != null) {
      setState(() => _kmAnfangCtrl.text = km.toString());
    }
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

  Future<void> _pickDate() async {
    final d = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (d != null) {
      _datumCtrl.text = '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.${d.year}';
    }
  }

  @override
  void dispose() {
    _fahrzeugkennungCtrl.dispose();
    _kennzeichenCtrl.dispose();
    _nameFahrerCtrl.dispose();
    _nameBeifahrerCtrl.dispose();
    _praktikantCtrl.dispose();
    _datumCtrl.dispose();
    _alarmFocusNode?.removeListener(_onAlarmFocusChanged);
    _endeFocusNode?.removeListener(_onEndeFocusChanged);
    _alarmFocusNode?.dispose();
    _endeFocusNode?.dispose();
    _alarmCtrl.dispose();
    _endeCtrl.dispose();
    _einsatzartCtrl.dispose();
    _einsatzortCtrl.dispose();
    _transportzielCtrl.dispose();
    _einsatznummerCtrl.dispose();
    _kmAnfangCtrl.dispose();
    _kmEndeCtrl.dispose();
    _besetztKmCtrl.dispose();
    _mitarbeiterSuchCtrl.dispose();
    super.dispose();
  }

  Future<void> _confirmDelete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Eintrag löschen'),
        content: const Text('Möchten Sie diesen Fahrtenbuch-Eintrag wirklich löschen?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Abbrechen')),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Löschen'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _saving = true);
    try {
      await widget.fahrtenbuchService.deleteEintrag(widget.companyId, widget.eintrag!.id);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Eintrag gelöscht.')));
        widget.onSave();
      }
    } catch (err) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Fehler: $err')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final datum = _parseDate(_datumCtrl.text.trim());
    if (datum == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Bitte gültiges Datum eingeben (TT.MM.JJJJ).')));
      return;
    }
    final kmAnfang = int.tryParse(_kmAnfangCtrl.text.trim());
    final kmEnde = int.tryParse(_kmEndeCtrl.text.trim());
    int? gesamtKm;
    if (kmAnfang != null && kmEnde != null && kmEnde >= kmAnfang) {
      gesamtKm = kmEnde - kmAnfang;
    } else if (kmAnfang != null && kmEnde != null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Km Ende muss >= Km Anfang sein.')));
      return;
    }
    final besetztKm = int.tryParse(_besetztKmCtrl.text.trim());

    setState(() => _saving = true);
    try {
      final uid = widget.currentUserUid;
      final alarmRaw = _alarmCtrl.text.trim();
      final endeRaw = _endeCtrl.text.trim();
      final alarm = alarmRaw.isEmpty ? null : (_formatTimeInput(alarmRaw).isNotEmpty ? _formatTimeInput(alarmRaw) : alarmRaw);
      final ende = endeRaw.isEmpty ? null : (_formatTimeInput(endeRaw).isNotEmpty ? _formatTimeInput(endeRaw) : endeRaw);
      final e = FahrtenbuchEintrag(
        id: widget.eintrag?.id ?? '',
        fahrzeugkennung: _fahrzeugkennungCtrl.text.trim().isEmpty ? null : _fahrzeugkennungCtrl.text.trim(),
        kennzeichen: _kennzeichenCtrl.text.trim().isEmpty ? null : _kennzeichenCtrl.text.trim(),
        nameFahrer: () {
          final val = _selectedFahrer ?? _nameFahrerCtrl.text.trim();
          return val.isEmpty ? null : val;
        }(),
        nameBeifahrer: () {
          final val = _selectedBeifahrer ?? _nameBeifahrerCtrl.text.trim();
          return val.isEmpty ? null : val;
        }(),
        praktikantAzubi: _praktikantCtrl.text.trim().isEmpty ? null : _praktikantCtrl.text.trim(),
        datum: datum,
        alarm: alarm,
        ende: ende,
        einsatzart: _einsatzartCtrl.text.trim().isEmpty ? null : _einsatzartCtrl.text.trim(),
        transportschein: _transportschein,
        einsatzort: _einsatzortCtrl.text.trim().isEmpty ? null : _einsatzortCtrl.text.trim(),
        transportziel: _transportzielCtrl.text.trim().isEmpty ? null : _transportzielCtrl.text.trim(),
        einsatznummer: _einsatznummerCtrl.text.trim().isEmpty ? null : _einsatznummerCtrl.text.trim(),
        kmAnfang: kmAnfang,
        kmEnde: kmEnde,
        gesamtKm: gesamtKm,
        besetztKm: besetztKm,
        sonderrechteAnfahrtTransport: 'Anfahrt: ${_sonderrechteAnfahrt ? 'ja' : 'nein'}, Transport: ${_sonderrechteTransport ? 'ja' : 'nein'}',
      );

      if (widget.eintrag != null) {
        await widget.fahrtenbuchService.updateEintrag(widget.companyId, widget.eintrag!.id, e);
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Eintrag aktualisiert.')));
      } else {
        await widget.fahrtenbuchService.createEintrag(widget.companyId, e, uid);
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Fahrtenbucheintrag hinzugefügt.')));
      }
      widget.onSave();
    } catch (err) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Fehler: $err')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  DateTime? _parseDate(String s) {
    final parts = s.split('.');
    if (parts.length != 3) return null;
    final d = int.tryParse(parts[0]);
    final m = int.tryParse(parts[1]);
    final y = int.tryParse(parts[2]);
    if (d == null || m == null || y == null || m < 1 || m > 12 || d < 1 || d > 31) return null;
    try {
      return DateTime(y, m, d);
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppTheme.buildModuleAppBar(
        title: widget.eintrag == null ? 'Neuer Fahrtenbucheintrag' : 'Fahrtenbucheintrag bearbeiten',
        onBack: widget.onCancel,
        leadingIcon: Icons.close,
        actions: [
          TextButton(onPressed: widget.onCancel, child: const Text('Abbrechen')),
          FilledButton(
            onPressed: _saving ? null : _save,
            style: FilledButton.styleFrom(backgroundColor: AppTheme.primary),
            child: _saving
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Text('Speichern'),
          ),
          const SizedBox(width: 16),
        ],
      ),
      body: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TextFormField(
                      controller: _einsatznummerCtrl,
                      decoration: const InputDecoration(labelText: 'Einsatz-Nr. / Zweck der Fahrt *'),
                      validator: (v) => (v ?? '').trim().isEmpty ? 'Pflichtfeld' : null,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _einsatzortCtrl,
                      decoration: const InputDecoration(labelText: 'Einsatzort *'),
                      validator: (v) => (v ?? '').trim().isEmpty ? 'Pflichtfeld' : null,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _transportzielCtrl,
                      decoration: const InputDecoration(labelText: 'Transportziel *'),
                      validator: (v) => (v ?? '').trim().isEmpty ? 'Pflichtfeld' : null,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _kmAnfangCtrl,
                      decoration: const InputDecoration(labelText: 'Km Anfang'),
                      keyboardType: TextInputType.number,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _kmEndeCtrl,
                      decoration: const InputDecoration(labelText: 'Km Ende *'),
                      keyboardType: TextInputType.number,
                      validator: (v) {
                        if ((v ?? '').trim().isEmpty) return 'Pflichtfeld';
                        if (int.tryParse(v!.trim()) == null) return 'Ungültige Zahl';
                        return null;
                      },
                    ),
                    const SizedBox(height: 12),
                    InputDecorator(
                      decoration: const InputDecoration(labelText: 'Gesamt KM'),
                      child: Text(
                        () {
                          final a = int.tryParse(_kmAnfangCtrl.text.trim());
                          final e = int.tryParse(_kmEndeCtrl.text.trim());
                          if (a != null && e != null && e >= a) return '${e - a}';
                          return '–';
                        }(),
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onSurface,
                          fontSize: 16,
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _besetztKmCtrl,
                      decoration: const InputDecoration(labelText: 'Besetzt-KM (manuell)'),
                      keyboardType: TextInputType.number,
                    ),
                    const SizedBox(height: 12),
                    SwitchListTile(
                      title: const Text('Sonderrechte Anfahrt'),
                      value: _sonderrechteAnfahrt,
                      onChanged: (v) => setState(() => _sonderrechteAnfahrt = v),
                    ),
                    SwitchListTile(
                      title: const Text('Sonderrechte Transport'),
                      value: _sonderrechteTransport,
                      onChanged: (v) => setState(() => _sonderrechteTransport = v),
                    ),
                    const SizedBox(height: 24),
                    // 8. Transport, dann Fahrzeug & Besatzung
                    const Text('Transport', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _datumCtrl,
                      decoration: const InputDecoration(labelText: 'Datum (TT.MM.JJJJ)'),
                      readOnly: true,
                      onTap: _pickDate,
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: TextFormField(
                            controller: _alarmCtrl,
                            focusNode: _alarmFocusNode,
                            decoration: const InputDecoration(
                              labelText: 'Beginn der Fahrt',
                              hintText: 'z.B. 0900 oder 09:00',
                            ),
                            keyboardType: TextInputType.datetime,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextFormField(
                            controller: _endeCtrl,
                            focusNode: _endeFocusNode,
                            decoration: const InputDecoration(
                              labelText: 'Ende der Fahrt',
                              hintText: 'z.B. 1030 oder 10:30',
                            ),
                            keyboardType: TextInputType.datetime,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _einsatzartCtrl,
                      decoration: const InputDecoration(labelText: 'Einsatzart'),
                    ),
                    const SizedBox(height: 12),
                    SwitchListTile(
                      title: const Text('Transportschein'),
                      value: _transportschein,
                      onChanged: (v) => setState(() => _transportschein = v),
                    ),
                    const SizedBox(height: 24),
                    const Text('Fahrzeug & Besatzung', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 12),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: _fahrzeuge.isNotEmpty
                              ? DropdownButtonFormField<String>(
                                  value: _selectedFahrzeugId,
                                  decoration: const InputDecoration(labelText: 'Fahrzeugkennung'),
                                  items: () {
                                    final items = <DropdownMenuItem<String>>[
                                      const DropdownMenuItem(value: null, child: Text('– Manuell –')),
                                      ..._fahrzeuge.map((f) => DropdownMenuItem(
                                            value: f.id,
                                            child: Text('${f.rufname ?? f.id}${f.kennzeichen != null && f.kennzeichen!.isNotEmpty ? ' (${f.kennzeichen})' : ''}'),
                                          )),
                                    ];
                                    final vorlageRuf = widget.vorlage?.fahrzeugRufname ?? '';
                                    if (vorlageRuf.isNotEmpty) {
                                      items.insert(1, DropdownMenuItem(value: '__vorlage__', child: Text(vorlageRuf)));
                                    }
                                    return items;
                                  }(),
                                  onChanged: (v) {
                                    setState(() {
                                      _selectedFahrzeugId = v;
                                      if (v == null) {
                                        _fahrzeugkennungCtrl.clear();
                                        _kennzeichenCtrl.clear();
                                      } else if (v == '__vorlage__') {
                                        _fahrzeugkennungCtrl.text = widget.vorlage?.fahrzeugRufname ?? '';
                                        _kennzeichenCtrl.text = widget.vorlage?.kennzeichen ?? '';
                                      } else {
                                        final f = _fahrzeuge.firstWhere((x) => x.id == v);
                                        _fahrzeugkennungCtrl.text = f.rufname ?? f.id;
                                        _kennzeichenCtrl.text = f.kennzeichen ?? '';
                                      }
                                    });
                                    if (v != null && v != '__vorlage__' && widget.eintrag == null) {
                                      _fillKmAnfangFromLastTrip();
                                    }
                                  },
                                )
                              : TextFormField(
                                  controller: _fahrzeugkennungCtrl,
                                  decoration: const InputDecoration(labelText: 'Fahrzeugkennung'),
                                ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextFormField(
                            controller: _kennzeichenCtrl,
                            decoration: const InputDecoration(labelText: 'Kennzeichen'),
                            readOnly: true,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              TextFormField(
                                controller: _nameFahrerCtrl,
                                readOnly: true,
                                decoration: const InputDecoration(
                                  labelText: 'Name Fahrer *',
                                  hintText: '– Bitte wählen –',
                                  suffixIcon: Icon(Icons.arrow_drop_down),
                                ),
                                validator: (v) => (v ?? '').trim().isEmpty ? 'Bitte Fahrer auswählen' : null,
                                onTap: () async {
                                  await _showMitarbeiterPicker(
                                    label: 'Fahrer',
                                    currentValue: _selectedFahrer ?? (_nameFahrerCtrl.text.trim().isEmpty ? null : _nameFahrerCtrl.text.trim()),
                                    emptyOption: '– Bitte wählen –',
                                    onSelected: (v) {
                                      setState(() {
                                        _selectedFahrer = v;
                                        _nameFahrerCtrl.text = v ?? '';
                                      });
                                    },
                                  );
                                },
                              ),
                              const SizedBox(height: 12),
                              TextFormField(
                                controller: _nameBeifahrerCtrl,
                                readOnly: true,
                                decoration: const InputDecoration(
                                  labelText: 'Name Beifahrer (optional)',
                                  hintText: '– Keiner –',
                                  suffixIcon: Icon(Icons.arrow_drop_down),
                                ),
                                onTap: () async {
                                  await _showMitarbeiterPicker(
                                    label: 'Beifahrer',
                                    currentValue: _selectedBeifahrer ?? (_nameBeifahrerCtrl.text.trim().isEmpty ? null : _nameBeifahrerCtrl.text.trim()),
                                    emptyOption: '– Keiner –',
                                    onSelected: (v) {
                                      setState(() {
                                        _selectedBeifahrer = v;
                                        _nameBeifahrerCtrl.text = v ?? '';
                                      });
                                    },
                                  );
                                },
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        Padding(
                          padding: const EdgeInsets.only(top: 20),
                          child: Tooltip(
                            message: 'Fahrer und Beifahrer tauschen',
                            child: IconButton(
                              icon: const Icon(Icons.swap_vert),
                              onPressed: () {
                                setState(() {
                                  final fahrer = _selectedFahrer ?? _nameFahrerCtrl.text.trim();
                                  final beifahrer = _selectedBeifahrer ?? _nameBeifahrerCtrl.text.trim();
                                  _selectedFahrer = beifahrer.isEmpty ? null : beifahrer;
                                  _selectedBeifahrer = fahrer.isEmpty ? null : fahrer;
                                  _nameFahrerCtrl.text = beifahrer;
                                  _nameBeifahrerCtrl.text = fahrer;
                                });
                              },
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _praktikantCtrl,
                      decoration: const InputDecoration(labelText: 'Praktikant/Azubi'),
                    ),
                    if (widget.eintrag != null) ...[
                      const SizedBox(height: 24),
                      OutlinedButton.icon(
                        icon: const Icon(Icons.delete, color: Colors.red, size: 20),
                        label: const Text('Eintrag löschen', style: TextStyle(color: Colors.red)),
                        onPressed: _saving ? null : _confirmDelete,
                      ),
                    ],
                  ],
                ),
              ),
            ),
    );
  }
}

/// Eigenständiges Sheet für Mitarbeiter-Auswahl – Controller-Lebenszyklus
/// liegt im Modal, vermeidet „TextEditingController used after disposed“.
class _MitarbeiterPickerSheet extends StatefulWidget {
  final String emptyOption;
  final List<String> filteredNames;

  const _MitarbeiterPickerSheet({
    required this.emptyOption,
    required this.filteredNames,
  });

  @override
  State<_MitarbeiterPickerSheet> createState() => _MitarbeiterPickerSheetState();
}

class _MitarbeiterPickerSheetState extends State<_MitarbeiterPickerSheet> {
  late final TextEditingController _searchCtrl;

  @override
  void initState() {
    super.initState();
    _searchCtrl = TextEditingController();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.7),
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor,
        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(12)),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.2), blurRadius: 8, offset: const Offset(0, 4)),
        ],
      ),
      child: ValueListenableBuilder<TextEditingValue>(
        valueListenable: _searchCtrl,
        builder: (context, value, _) {
          final q = value.text.trim().toLowerCase();
          final filtered = q.isEmpty
              ? widget.filteredNames
              : (widget.filteredNames
                    .where((n) => n.toLowerCase().contains(q))
                    .toList()
                  ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase())));
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: TextField(
                  controller: _searchCtrl,
                  autofocus: true,
                  decoration: const InputDecoration(
                    labelText: 'Mitarbeiter suchen',
                    hintText: 'Name eingeben...',
                    prefixIcon: Icon(Icons.search),
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
              Expanded(
                child: ListView.builder(
                  itemCount: filtered.length + 2,
                  itemBuilder: (_, i) {
                    if (i == 0) {
                      return ListTile(
                        leading: const Icon(Icons.close),
                        title: Text('Abbrechen', style: TextStyle(color: Colors.grey[600])),
                        onTap: () => Navigator.pop(context, null),
                      );
                    }
                    if (i == 1) {
                      return ListTile(
                        title: Text(widget.emptyOption, style: TextStyle(color: Colors.grey[600])),
                        onTap: () => Navigator.pop(context, ''),
                      );
                    }
                    final n = filtered[i - 2];
                    return ListTile(
                      title: Text(n),
                      onTap: () => Navigator.pop(context, n),
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
