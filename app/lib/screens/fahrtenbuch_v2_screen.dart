import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../models/fahrtenbuch_v2_model.dart';
import '../models/fahrtenbuch_v2_vorlage.dart';
import '../models/fleet_model.dart';
import '../models/mitarbeiter_model.dart';
import '../services/fahrtenbuch_v2_service.dart';
import '../services/fahrtenbuch_service.dart';
import '../services/mitarbeiter_service.dart';
import '../services/auth_service.dart';
import '../services/auth_data_service.dart';
import '../services/schichtanmeldung_service.dart';
import '../services/schicht_status_service.dart';
import '../utils/fahrtenbuch_permissions.dart';
import 'fahrtenbuch_v2_uebersicht_screen.dart';

/// Fahrtenbuch V2 – Übersicht + Formular
class FahrtenbuchV2Screen extends StatefulWidget {
  final String companyId;
  final VoidCallback onBack;
  final FahrtenbuchV2Vorlage? initialVorlage;
  final FahrtenbuchV2Eintrag? initialEintrag;
  final String? userRole;

  const FahrtenbuchV2Screen({
    super.key,
    required this.companyId,
    required this.onBack,
    this.initialVorlage,
    this.initialEintrag,
    this.userRole,
  });

  @override
  State<FahrtenbuchV2Screen> createState() => _FahrtenbuchV2ScreenState();
}

class _FahrtenbuchV2ScreenState extends State<FahrtenbuchV2Screen> {
  final _service = FahrtenbuchV2Service();
  bool _formOpening = true;
  FahrtenbuchV2Vorlage? _loadedVorlage;

  @override
  void initState() {
    super.initState();
    // Wie V1: Vorlage laden bevor Menü angezeigt wird – garantiert Kennzeichen-Vorauswahl
    _loadedVorlage = widget.initialVorlage;
    if (widget.initialEintrag != null) {
      _formOpening = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() => _formOpening = false);
        _openEintragForm(eintrag: widget.initialEintrag, vorlage: null);
      });
    } else if (widget.initialVorlage == null) {
      // Vorlage blockierend laden (wie V1) – dann Menü anzeigen
      _formOpening = true;
      WidgetsBinding.instance.addPostFrameCallback((_) => _loadVorlageThenShowMenu());
    } else {
      // Vorlage bereits übergeben (z.B. von Schichtanmeldung) – Menü sofort anzeigen
      _formOpening = false;
    }
  }

  /// Vorlage laden bevor Menü erscheint – exakt wie V1 (blockierend)
  Future<void> _loadVorlageThenShowMenu() async {
    if (!mounted || widget.initialEintrag != null) return;
    var vorlage = widget.initialVorlage;
    if (vorlage == null) {
      vorlage = await _loadVorlageSync();
    }
    if (mounted) {
      setState(() {
        _loadedVorlage = vorlage;
        _formOpening = false;
      });
    }
  }

  /// Aktive Schicht laden – gleiche Logik wie SchichtanmeldungScreen (Fahrer + Beifahrer)
  Future<SchichtanmeldungEintrag?> _getAktiveSchichtWieSchichtanmeldung(String companyId) async {
    final user = AuthService().currentUser;
    if (user == null) return null;
    final email = user.email ?? '';
    final uid = user.uid;
    final schichtService = SchichtanmeldungService();
    SchichtplanMitarbeiter? mitarbeiter;
    if (email.isNotEmpty) mitarbeiter = await schichtService.findMitarbeiterByEmail(companyId, email);
    if (mitarbeiter == null && uid.isNotEmpty) mitarbeiter = await schichtService.findMitarbeiterByUid(companyId, uid);
    if (mitarbeiter == null) return null;
    return schichtService.getAktiveSchichtanmeldung(companyId, mitarbeiter.id);
  }

  @override
  Widget build(BuildContext context) {
    if (_formOpening) {
      return Scaffold(
        backgroundColor: AppTheme.surfaceBg,
        appBar: AppTheme.buildModuleAppBar(title: 'Fahrtenbuch-Menü', onBack: widget.onBack),
        body: const Center(child: CircularProgressIndicator(color: AppTheme.primary)),
      );
    }
    return FahrtenbuchV2UebersichtScreen(
      companyId: widget.companyId,
      title: 'Fahrtenbuch-Menü',
      onBack: widget.onBack,
      onAddTap: (v) => _openEintragForm(vorlage: v ?? widget.initialVorlage ?? _loadedVorlage),
      service: _service,
      userRole: widget.userRole,
      initialVorlage: widget.initialVorlage ?? _loadedVorlage,
    );
  }

  /// Vorlage laden – gleiche Logik wie V1 (SchichtStatusService + buildFahrtenbuchV2VorlageFromAnmeldung)
  Future<FahrtenbuchV2Vorlage?> _loadVorlageSync() async {
    var vorlage = widget.initialVorlage ?? _loadedVorlage;
    if (vorlage != null) return vorlage;
    final cidsToTry = <String>[
      widget.companyId,
      widget.companyId.trim().toLowerCase(),
      widget.companyId.trim(),
    ];
    final user = AuthService().currentUser;
    if (user != null) {
      final authData = await AuthDataService().getAuthData(
        user.uid, user.email ?? '', widget.companyId,
      );
      final authCid = (authData.companyId ?? '').trim();
      if (authCid.isNotEmpty && !cidsToTry.contains(authCid)) {
        cidsToTry.add(authCid);
        cidsToTry.add(authCid.toLowerCase());
      }
    }
    SchichtanmeldungEintrag? aktiveSchicht;
    for (final cid in cidsToTry) {
      if (cid.isEmpty) continue;
      aktiveSchicht = await _getAktiveSchichtWieSchichtanmeldung(cid);
      if (aktiveSchicht != null) break;
      aktiveSchicht = await SchichtStatusService().getAktiveSchicht(cid);
      if (aktiveSchicht != null) break;
    }
    if (aktiveSchicht == null) return null;
    for (final cid in cidsToTry) {
      if (cid.isEmpty) continue;
      vorlage = await SchichtanmeldungService().buildFahrtenbuchV2VorlageFromAnmeldung(
        cid, aktiveSchicht!, FahrtenbuchService(), _service,
      );
      if (vorlage != null) return vorlage;
    }
    return null;
  }

  void _openEintragForm({
    FahrtenbuchV2Eintrag? eintrag,
    FahrtenbuchV2Vorlage? vorlage,
  }) {
    final v = vorlage ?? widget.initialVorlage ?? _loadedVorlage;
    final uid = AuthService().currentUser?.uid ?? '';
    final canEdit = eintrag == null
        ? true
        : FahrtenbuchPermissions.canEdit(
            userRole: widget.userRole,
            userId: uid,
            createdBy: eintrag.createdBy,
          );
    Navigator.of(context).push(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (ctx) => _FahrtenbuchV2FormScreen(
          companyId: widget.companyId,
          eintrag: eintrag,
          vorlage: v,
          service: _service,
          currentUserUid: uid,
          canEdit: canEdit,
          onSave: () {
            Navigator.of(ctx).pop();
            widget.onBack();
          },
          onCancel: () => Navigator.of(ctx).pop(),
        ),
      ),
    );
  }
}

class _FahrtenbuchV2FormScreen extends StatefulWidget {
  final String companyId;
  final FahrtenbuchV2Eintrag? eintrag;
  final FahrtenbuchV2Vorlage? vorlage;
  final FahrtenbuchV2Service service;
  final String currentUserUid;
  final bool canEdit;
  final VoidCallback onSave;
  final VoidCallback onCancel;

  const _FahrtenbuchV2FormScreen({
    required this.companyId,
    this.eintrag,
    this.vorlage,
    required this.service,
    required this.currentUserUid,
    this.canEdit = true,
    required this.onSave,
    required this.onCancel,
  });

  @override
  State<_FahrtenbuchV2FormScreen> createState() => _FahrtenbuchV2FormScreenState();
}

class _FahrtenbuchV2FormScreenState extends State<_FahrtenbuchV2FormScreen> {
  final _formKey = GlobalKey<FormState>();
  String? _selectedFahrzeugId;
  String? _selectedFahrer;
  String? _fahrerDropdownValue; // Wert aus Dropdown oder '__manual__'
  List<Fahrzeug> _fahrzeuge = [];
  FahrtenbuchV2Vorlage? _vorlage; // Kann nachgeladen werden, wenn widget.vorlage null
  late TextEditingController _fahrzeugkennungCtrl;
  late TextEditingController _kennzeichenCtrl;
  late VoidCallback _fieldListener;
  late TextEditingController _datumCtrl;
  late TextEditingController _fahrzeitVonCtrl;
  late TextEditingController _fahrzeitBisCtrl;
  late TextEditingController _fahrtVonCtrl;
  late TextEditingController _zielCtrl;
  late TextEditingController _grundCtrl;
  late TextEditingController _kmAnfangCtrl;
  late TextEditingController _kmEndeCtrl;
  late TextEditingController _kmDienstlichCtrl;
  late TextEditingController _kmWohnortCtrl;
  late TextEditingController _kmPrivatCtrl;
  late TextEditingController _nameFahrerCtrl;
  late TextEditingController _kostenBetragCtrl;
  late TextEditingController _kostenArtCtrl;
  bool _saving = false;
  final FocusNode _fahrzeitVonFocus = FocusNode();
  final FocusNode _fahrzeitBisFocus = FocusNode();
  final FocusNode _kmDienstlichFocus = FocusNode();
  final FocusNode _kmWohnortFocus = FocusNode();
  final FocusNode _kmPrivatFocus = FocusNode();
  late VoidCallback _kmDienstlichFocusListener;
  late VoidCallback _kmWohnortFocusListener;
  late VoidCallback _kmPrivatFocusListener;

  FahrtenbuchV2Vorlage? get _effectiveVorlage => _vorlage ?? widget.vorlage;

  /// Gesamt-KM aus Fahrtbeginn und Fahrtende
  int? _getGesamtKm() {
    final anfang = int.tryParse(_kmAnfangCtrl.text.trim());
    final ende = int.tryParse(_kmEndeCtrl.text.trim());
    if (anfang == null || ende == null || ende < anfang) return null;
    return ende - anfang;
  }

  /// KM in ein Feld eintragen, andere leeren – nur eine Option möglich
  void _setKmZuordnung(String which) {
    final gesamt = _getGesamtKm();
    if (gesamt == null) return;
    setState(() {
      _kmDienstlichCtrl.text = which == 'dienstl' ? gesamt.toString() : '';
      _kmWohnortCtrl.text = which == 'wohnort' ? gesamt.toString() : '';
      _kmPrivatCtrl.text = which == 'privat' ? gesamt.toString() : '';
    });
  }

  void _onFahrzeitVonFocusChanged() {
    if (_fahrzeitVonFocus.hasFocus == false) {
      final t = _formatTimeInput(_fahrzeitVonCtrl.text.trim());
      if (t.isNotEmpty) {
        _fahrzeitVonCtrl.text = t;
        _fahrzeitVonCtrl.selection = TextSelection.collapsed(offset: t.length);
      }
    }
  }

  void _onFahrzeitBisFocusChanged() {
    if (_fahrzeitBisFocus.hasFocus == false) {
      final t = _formatTimeInput(_fahrzeitBisCtrl.text.trim());
      if (t.isNotEmpty) {
        _fahrzeitBisCtrl.text = t;
        _fahrzeitBisCtrl.selection = TextSelection.collapsed(offset: t.length);
      }
    }
  }

  /// Bei Änderung von KM-Anfang/Ende: Standard = KM dienstl. automatisch eintragen + Plausibilitätsprüfung
  void _onKmAnfangEndeChanged() {
    final gesamt = _getGesamtKm();
    if (gesamt != null) {
      final d = _kmDienstlichCtrl.text.trim();
      final w = _kmWohnortCtrl.text.trim();
      final p = _kmPrivatCtrl.text.trim();
      final which = d.isNotEmpty ? 'dienstl' : (w.isNotEmpty ? 'wohnort' : (p.isNotEmpty ? 'privat' : 'dienstl'));
      _setKmZuordnung(which);
    }
    // Plausibilitätsprüfung sofort anzeigen (KM Ende >= KM Anfang)
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _formKey.currentState?.validate();
    });
  }

  @override
  void initState() {
    super.initState();
    _vorlage = widget.vorlage;
    final e = widget.eintrag;
    final v = _effectiveVorlage;
    final fzRuf = e?.fahrzeugkennung ?? v?.fahrzeugRufname ?? '';
    final kz = e?.kennzeichen ?? v?.kennzeichen ?? '';
    _fahrzeugkennungCtrl = TextEditingController(text: fzRuf);
    _kennzeichenCtrl = TextEditingController(text: kz);
    if (v != null && (fzRuf.isNotEmpty || (v.fahrzeugId.isNotEmpty && v.fahrzeugId != 'alle'))) {
      _selectedFahrzeugId = '__vorlage__';
    }
    if (v != null && v.nameFahrer != null && v.nameFahrer!.trim().isNotEmpty) {
      _selectedFahrer = v.nameFahrer!.trim();
      _fahrerDropdownValue = v.fahrerOptionen.any((n) => n.trim() == _selectedFahrer) ? _selectedFahrer : null;
    }
    _datumCtrl = TextEditingController(
      text: e?.datum != null ? _fmtDate(e!.datum!) : (v != null ? _fmtDate(v.datum) : _fmtDate(DateTime.now())),
    );
    _fahrzeitVonCtrl = TextEditingController(text: e?.fahrzeitVon ?? '');
    _fahrzeitBisCtrl = TextEditingController(text: e?.fahrzeitBis ?? '');
    _fahrtVonCtrl = TextEditingController(text: e?.fahrtVon ?? '');
    _zielCtrl = TextEditingController(text: e?.ziel ?? '');
    _grundCtrl = TextEditingController(text: e?.grundDerFahrt ?? '');
    _kmAnfangCtrl = TextEditingController(text: e?.kmAnfang?.toString() ?? v?.kmAnfang?.toString() ?? '');
    _kmEndeCtrl = TextEditingController(text: e?.kmEnde?.toString() ?? '');
    _kmDienstlichCtrl = TextEditingController(text: e?.kmDienstlich?.toString() ?? '');
    _kmWohnortCtrl = TextEditingController(text: e?.kmWohnortArbeit?.toString() ?? '');
    _kmPrivatCtrl = TextEditingController(text: e?.kmPrivat?.toString() ?? '');
    _nameFahrerCtrl = TextEditingController(text: e?.nameFahrer ?? v?.nameFahrer ?? '');
    _kostenBetragCtrl = TextEditingController(text: e?.kostenBetrag?.toString() ?? '');
    _kostenArtCtrl = TextEditingController(text: e?.kostenArt ?? '');
    _addFieldListeners();
    _fahrzeugkennungCtrl.addListener(_fieldListener);
    _fahrzeitVonFocus.addListener(_onFahrzeitVonFocusChanged);
    _fahrzeitBisFocus.addListener(_onFahrzeitBisFocusChanged);
    _kmAnfangCtrl.addListener(_onKmAnfangEndeChanged);
    _kmEndeCtrl.addListener(_onKmAnfangEndeChanged);
    _kmDienstlichFocusListener = () {
      if (_kmDienstlichFocus.hasFocus) _setKmZuordnung('dienstl');
    };
    _kmWohnortFocusListener = () {
      if (_kmWohnortFocus.hasFocus) _setKmZuordnung('wohnort');
    };
    _kmPrivatFocusListener = () {
      if (_kmPrivatFocus.hasFocus) _setKmZuordnung('privat');
    };
    _kmDienstlichFocus.addListener(_kmDienstlichFocusListener);
    _kmWohnortFocus.addListener(_kmWohnortFocusListener);
    _kmPrivatFocus.addListener(_kmPrivatFocusListener);
    // Formular sofort anzeigen, Daten im Hintergrund laden (kein Blockieren)
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadData();
      // Vorlage nachladen wenn fehlend oder fahrerOptionen leer (z.B. Minimal-Vorlage von Schichtanmeldung)
      if ((widget.vorlage == null && widget.eintrag == null) ||
          (widget.vorlage != null && widget.eintrag == null && (widget.vorlage!.fahrerOptionen.isEmpty))) {
        _loadVorlageFromAktiveSchicht();
      }
    });
  }

  /// Vorlage aus aktiver Schicht nachladen, wenn nicht übergeben (wie V1-Fallback)
  Future<void> _loadVorlageFromAktiveSchicht() async {
    final schichtService = SchichtanmeldungService();
    final user = AuthService().currentUser;
    if (user == null) return;
    final cidsToTry = <String>[
      widget.companyId,
      widget.companyId.trim().toLowerCase(),
      widget.companyId.trim(),
    ];
    final authData = await AuthDataService().getAuthData(user.uid, user.email ?? '', widget.companyId);
    final authCid = (authData.companyId ?? '').trim();
    if (authCid.isNotEmpty && !cidsToTry.contains(authCid)) {
      cidsToTry.add(authCid);
      cidsToTry.add(authCid.toLowerCase());
    }
    SchichtanmeldungEintrag? aktiveSchicht;
    for (final cid in cidsToTry) {
      if (cid.isEmpty) continue;
      var m = await schichtService.findMitarbeiterByEmail(cid, user.email ?? '');
      if (m == null) m = await schichtService.findMitarbeiterByUid(cid, user.uid);
      if (m != null) aktiveSchicht = await schichtService.getAktiveSchichtanmeldung(cid, m.id);
      if (aktiveSchicht == null) aktiveSchicht = await SchichtStatusService().getAktiveSchicht(cid);
      if (aktiveSchicht != null) break;
    }
    if (aktiveSchicht == null || !mounted) return;
    for (final cid in cidsToTry) {
      if (cid.isEmpty) continue;
      final v = await schichtService.buildFahrtenbuchV2VorlageFromAnmeldung(
        cid, aktiveSchicht!, FahrtenbuchService(), widget.service,
      );
      if (v != null && mounted) {
        setState(() {
          _vorlage = v;
          if (_selectedFahrzeugId == null &&
              (v.fahrzeugRufname.trim().isNotEmpty || (v.fahrzeugId.isNotEmpty && v.fahrzeugId != 'alle'))) {
            _selectedFahrzeugId = '__vorlage__';
          }
          if (v.nameFahrer != null && v.nameFahrer!.trim().isNotEmpty) {
            _selectedFahrer = v.nameFahrer!.trim();
            _fahrerDropdownValue = v.fahrerOptionen.any((n) => n.trim() == _selectedFahrer) ? _selectedFahrer : null;
            _nameFahrerCtrl.text = _selectedFahrer!;
          }
          if (v.kmAnfang != null && _kmAnfangCtrl.text.trim().isEmpty) {
            _kmAnfangCtrl.text = v.kmAnfang.toString();
          }
        });
        break;
      }
    }
  }

  void _addFieldListeners() {
    _fieldListener = () => setState(() {});
    _fahrzeitVonCtrl.addListener(_fieldListener);
    _fahrzeitBisCtrl.addListener(_fieldListener);
    _fahrtVonCtrl.addListener(_fieldListener);
    _zielCtrl.addListener(_fieldListener);
    _grundCtrl.addListener(_fieldListener);
    _kmAnfangCtrl.addListener(_fieldListener);
    _kmEndeCtrl.addListener(_fieldListener);
    _nameFahrerCtrl.addListener(_fieldListener);
  }

  String _fmtDate(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.${d.year}';

  @override
  void dispose() {
    _fahrzeugkennungCtrl.removeListener(_fieldListener);
    _fahrzeugkennungCtrl.dispose();
    _kennzeichenCtrl.dispose();
    _fahrzeitVonCtrl.removeListener(_fieldListener);
    _fahrzeitBisCtrl.removeListener(_fieldListener);
    _fahrtVonCtrl.removeListener(_fieldListener);
    _zielCtrl.removeListener(_fieldListener);
    _grundCtrl.removeListener(_fieldListener);
    _kmAnfangCtrl.removeListener(_fieldListener);
    _kmAnfangCtrl.removeListener(_onKmAnfangEndeChanged);
    _kmEndeCtrl.removeListener(_fieldListener);
    _kmEndeCtrl.removeListener(_onKmAnfangEndeChanged);
    _fahrzeitVonFocus.removeListener(_onFahrzeitVonFocusChanged);
    _fahrzeitBisFocus.removeListener(_onFahrzeitBisFocusChanged);
    _kmDienstlichFocus.removeListener(_kmDienstlichFocusListener);
    _kmWohnortFocus.removeListener(_kmWohnortFocusListener);
    _kmPrivatFocus.removeListener(_kmPrivatFocusListener);
    _fahrzeitVonFocus.dispose();
    _fahrzeitBisFocus.dispose();
    _kmDienstlichFocus.dispose();
    _kmWohnortFocus.dispose();
    _kmPrivatFocus.dispose();
    _datumCtrl.dispose();
    _fahrzeitVonCtrl.dispose();
    _fahrzeitBisCtrl.dispose();
    _fahrtVonCtrl.dispose();
    _zielCtrl.dispose();
    _grundCtrl.dispose();
    _kmAnfangCtrl.dispose();
    _kmEndeCtrl.dispose();
    _kmDienstlichCtrl.dispose();
    _kmWohnortCtrl.dispose();
    _kmPrivatCtrl.dispose();
    _nameFahrerCtrl.dispose();
    _kostenBetragCtrl.dispose();
    _kostenArtCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    // Formular ist bereits sichtbar – Daten im Hintergrund laden
    try {
      final results = await Future.wait([
        widget.service.loadFahrzeuge(widget.companyId),
        MitarbeiterService().streamMitarbeiter(widget.companyId).first,
      ]);
      final fz = results[0] as List<Fahrzeug>;
      final ma = results[1] as List<Mitarbeiter>;
      final namen = ma.map((m) => m.displayName.trim()).where((n) => n.isNotEmpty).toSet().toList();
      if (_effectiveVorlage != null) {
        for (final n in _effectiveVorlage!.fahrerOptionen) {
          if (n.trim().isNotEmpty && !namen.contains(n)) namen.add(n);
        }
      }
      namen.sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));

      var selectedFzId = _selectedFahrzeugId;
      var selectedFahrer = _selectedFahrer;
      final v = _effectiveVorlage;
      // Exakt wie V1: fzMatch = Rufname oder fahrzeugId, dann ruf/id matchen, dann kennzeichen
      final fzMatch = widget.eintrag?.fahrzeugkennung ?? v?.fahrzeugRufname ?? v?.fahrzeugId;
      final kzVorhanden = (widget.eintrag?.kennzeichen ?? v?.kennzeichen)?.trim().isNotEmpty == true;
      if (fzMatch != null && fzMatch.isNotEmpty && fz.isNotEmpty) {
        for (final f in fz) {
          final ruf = (f.rufname ?? f.id ?? '').toString().trim();
          final id = (f.id ?? '').toString().trim();
          if (ruf == fzMatch.trim() || id == fzMatch.trim()) {
            selectedFzId = f.id;
            _fahrzeugkennungCtrl.text = f.rufname ?? f.id ?? '';
            _kennzeichenCtrl.text = (f.kennzeichen ?? '').trim().isNotEmpty ? (f.kennzeichen ?? '') : (widget.eintrag?.kennzeichen ?? v?.kennzeichen ?? _kennzeichenCtrl.text);
            break;
          }
        }
        if (selectedFzId == null && kzVorhanden) {
          final gesuchtKz = (widget.eintrag?.kennzeichen ?? v?.kennzeichen ?? '').trim();
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
      if (selectedFzId == null && v != null && (v.fahrzeugRufname.trim().isNotEmpty || v.fahrzeugId.trim().isNotEmpty)) {
        selectedFzId = '__vorlage__';
        _fahrzeugkennungCtrl.text = v.fahrzeugRufname.trim().isNotEmpty ? v.fahrzeugRufname : v.fahrzeugId;
        if ((v.kennzeichen ?? '').trim().isNotEmpty) _kennzeichenCtrl.text = v.kennzeichen!;
      } else if (selectedFzId == null && widget.eintrag != null) {
        final fzMatchRaw = widget.eintrag?.fahrzeugkennung ?? widget.eintrag?.kennzeichen;
        final fzMatch = (fzMatchRaw ?? '').toString().trim().toLowerCase();
        if (fzMatch.isNotEmpty && fz.isNotEmpty) {
          for (final f in fz) {
            final ruf = ((f.rufname ?? f.id) ?? '').toString().trim().toLowerCase();
            final id = f.id.toString().trim().toLowerCase();
            final kz = (f.kennzeichen ?? '').trim().toLowerCase();
            if (ruf == fzMatch || id == fzMatch || kz == fzMatch) {
              selectedFzId = f.id;
              break;
            }
          }
        }
      }
      if (v != null && v.nameFahrer != null && v.nameFahrer!.trim().isNotEmpty) {
        selectedFahrer = v.nameFahrer!.trim();
        _nameFahrerCtrl.text = selectedFahrer;
        if (v.fahrerOptionen.any((n) => n.trim() == selectedFahrer)) {
          _fahrerDropdownValue = selectedFahrer;
        }
      }
      // Sofort anzeigen – KM-Stand im Hintergrund nachladen
      if (mounted) {
        setState(() {
          _fahrzeuge = fz;
          _selectedFahrzeugId = selectedFzId;
          _selectedFahrer = selectedFahrer;
        });
      }
      if (widget.eintrag == null && _kmAnfangCtrl.text.trim().isEmpty && mounted) {
        final selFz = selectedFzId != null && selectedFzId != '__vorlage__'
            ? fz.where((f) => f.id == selectedFzId).firstOrNull
            : null;
        int? km;
        if (selFz != null) {
          km = await widget.service.getLetzterKmEnde(widget.companyId, (selFz.kennzeichen ?? '').trim().isNotEmpty ? selFz.kennzeichen : (selFz.rufname ?? selFz.id));
        } else if (selectedFzId == '__vorlage__' && v?.kmAnfang != null) {
          km = v!.kmAnfang;
        }
        if (km != null && mounted) setState(() => _kmAnfangCtrl.text = km.toString());
      }
    } catch (_) {
      if (mounted) {
        final vorlage = _effectiveVorlage;
        if (vorlage != null && (vorlage.fahrzeugRufname.trim().isNotEmpty || vorlage.fahrzeugId.trim().isNotEmpty)) {
          setState(() => _selectedFahrzeugId = '__vorlage__');
        } else {
          setState(() {});
        }
      }
    }
  }

  String? _getKennzeichen() {
    if (_selectedFahrzeugId == '__vorlage__' && _effectiveVorlage != null && (_effectiveVorlage!.kennzeichen ?? '').trim().isNotEmpty) {
      return _effectiveVorlage!.kennzeichen!.trim();
    }
    final f = _selectedFahrzeugId != null ? _fahrzeuge.where((x) => x.id == _selectedFahrzeugId).firstOrNull : null;
    if (f != null && (f.kennzeichen ?? '').trim().isNotEmpty) return f.kennzeichen!.trim();
    if (widget.eintrag != null && (widget.eintrag!.kennzeichen ?? '').trim().isNotEmpty) return widget.eintrag!.kennzeichen!.trim();
    return null;
  }

  String? _getFahrzeugkennung() {
    if (_selectedFahrzeugId == '__vorlage__' && _effectiveVorlage != null) return _effectiveVorlage!.fahrzeugRufname.trim();
    final f = _selectedFahrzeugId != null ? _fahrzeuge.where((x) => x.id == _selectedFahrzeugId).firstOrNull : null;
    if (f != null) return (f.rufname ?? f.id).trim();
    if (widget.eintrag != null && (widget.eintrag!.fahrzeugkennung ?? '').trim().isNotEmpty) return widget.eintrag!.fahrzeugkennung!.trim();
    return null;
  }

  String _formatVorlageLabel() {
    final v = _effectiveVorlage!;
    final kz = (v.kennzeichen ?? '').trim();
    final ruf = v.fahrzeugRufname.trim();
    if (kz.isNotEmpty && ruf.isNotEmpty) return '$kz ($ruf)';
    return ruf.isNotEmpty ? ruf : v.fahrzeugId;
  }

  static const _yellowBg = Color(0xFFFFF9C4);

  InputDecoration _pflichtfeldDecoration(String labelText, {required bool hasValue}) => InputDecoration(
    labelText: labelText,
    filled: true,
    fillColor: hasValue ? Colors.white : _yellowBg,
    border: const OutlineInputBorder(),
  );

  /// Fahrer ist Pflicht, wenn nicht aus Schichtanmeldung vorausgefüllt
  bool get _isFahrerPflicht {
    if (_effectiveVorlage?.nameFahrer != null && _effectiveVorlage!.nameFahrer!.trim().isNotEmpty) return false;
    return true;
  }

  /// Anzeigeformat: "Kennzeichen (Fahrzeugkennung)" oder nur "Fahrzeugkennung" wenn kein Kennzeichen
  String _formatFahrzeugLabel(Fahrzeug f) {
    final kz = (f.kennzeichen ?? '').trim();
    final ruf = (f.rufname ?? f.id).trim();
    if (kz.isNotEmpty && ruf.isNotEmpty) return '$kz ($ruf)';
    return ruf.isNotEmpty ? ruf : f.id;
  }

  /// Formatiert Uhrzeit-Eingabe beim Verlassen des Feldes (z.B. "0900" → "09:00")
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

  String _formatTime(String s) => _formatTimeInput(s);

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

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final datum = _parseDate(_datumCtrl.text.trim());
    if (datum == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Bitte gültiges Datum (TT.MM.JJJJ).')));
      return;
    }
    final kmAnfang = int.tryParse(_kmAnfangCtrl.text.trim());
    final kmEnde = int.tryParse(_kmEndeCtrl.text.trim());
    if (kmEnde != null && kmAnfang != null && kmEnde < kmAnfang) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('KM Ende muss >= KM Anfang sein.')));
      return;
    }
    setState(() => _saving = true);
    try {
      final von = _fahrzeitVonCtrl.text.trim().isEmpty ? null : _formatTime(_fahrzeitVonCtrl.text.trim());
      final bis = _fahrzeitBisCtrl.text.trim().isEmpty ? null : _formatTime(_fahrzeitBisCtrl.text.trim());
      final e = FahrtenbuchV2Eintrag(
        id: widget.eintrag?.id ?? '',
        datum: datum,
        fahrzeitVon: von,
        fahrzeitBis: bis,
        fahrtVon: _fahrtVonCtrl.text.trim().isEmpty ? null : _fahrtVonCtrl.text.trim(),
        ziel: _zielCtrl.text.trim().isEmpty ? null : _zielCtrl.text.trim(),
        grundDerFahrt: _grundCtrl.text.trim().isEmpty ? null : _grundCtrl.text.trim(),
        kmAnfang: kmAnfang,
        kmEnde: kmEnde,
        kmDienstlich: int.tryParse(_kmDienstlichCtrl.text.trim()),
        kmWohnortArbeit: int.tryParse(_kmWohnortCtrl.text.trim()),
        kmPrivat: int.tryParse(_kmPrivatCtrl.text.trim()),
        nameFahrer: _nameFahrerCtrl.text.trim().isEmpty ? null : _nameFahrerCtrl.text.trim(),
        kostenBetrag: num.tryParse(_kostenBetragCtrl.text.trim().replaceAll(',', '.')),
        kostenArt: _kostenArtCtrl.text.trim().isEmpty ? null : _kostenArtCtrl.text.trim(),
        fahrzeugkennung: _getFahrzeugkennung(),
        kennzeichen: _getKennzeichen(),
        createdBy: widget.currentUserUid,
      );
      if (widget.eintrag != null) {
        await widget.service.updateEintrag(widget.companyId, widget.eintrag!.id, e);
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Eintrag aktualisiert.')));
      } else {
        await widget.service.createEintrag(widget.companyId, e, widget.currentUserUid);
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Eintrag hinzugefügt.')));
      }
      widget.onSave();
    } catch (err) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Fehler: $err')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppTheme.buildModuleAppBar(
        title: widget.eintrag == null
            ? 'Neuer Fahrtenbucheintrag'
            : (widget.canEdit ? 'Eintrag bearbeiten' : 'Eintrag anzeigen'),
        onBack: widget.onCancel,
        leadingIcon: Icons.close,
        actions: widget.canEdit
            ? [
                FilledButton(
                  onPressed: _saving ? null : _save,
                  style: FilledButton.styleFrom(backgroundColor: AppTheme.primary),
                  child: _saving
                      ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Text('Speichern'),
                ),
                const SizedBox(width: 16),
              ]
            : null,
      ),
      body: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: IgnorePointer(
                ignoring: !widget.canEdit,
                child: Form(
                  key: _formKey,
                  autovalidateMode: AutovalidateMode.onUserInteraction,
                  child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _buildKennzeichenField(),
                    const SizedBox(height: 12),
                    _buildFahrerField(),
                    const SizedBox(height: 12),
                    _buildDateField(),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: TextFormField(
                            controller: _fahrzeitVonCtrl,
                            focusNode: _fahrzeitVonFocus,
                            decoration: _pflichtfeldDecoration('Fahrzeit von (HH:mm)', hasValue: _fahrzeitVonCtrl.text.trim().isNotEmpty),
                            keyboardType: TextInputType.datetime,
                            validator: (v) => (v ?? '').trim().isEmpty ? 'Pflichtfeld' : null,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextFormField(
                            controller: _fahrzeitBisCtrl,
                            focusNode: _fahrzeitBisFocus,
                            decoration: _pflichtfeldDecoration('Fahrzeit bis (HH:mm)', hasValue: _fahrzeitBisCtrl.text.trim().isNotEmpty),
                            keyboardType: TextInputType.datetime,
                            validator: (v) => (v ?? '').trim().isEmpty ? 'Pflichtfeld' : null,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _fahrtVonCtrl,
                      decoration: _pflichtfeldDecoration('Fahrt von', hasValue: _fahrtVonCtrl.text.trim().isNotEmpty),
                      validator: (v) => (v ?? '').trim().isEmpty ? 'Pflichtfeld' : null,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _zielCtrl,
                      decoration: _pflichtfeldDecoration('Fahrt-Ziel', hasValue: _zielCtrl.text.trim().isNotEmpty),
                      validator: (v) => (v ?? '').trim().isEmpty ? 'Pflichtfeld' : null,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _grundCtrl,
                      decoration: _pflichtfeldDecoration('Grund der Fahrt', hasValue: _grundCtrl.text.trim().isNotEmpty),
                      validator: (v) => (v ?? '').trim().isEmpty ? 'Pflichtfeld' : null,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _kmAnfangCtrl,
                      decoration: _pflichtfeldDecoration('KM-Stand Fahrtbeginn', hasValue: _kmAnfangCtrl.text.trim().isNotEmpty),
                      keyboardType: TextInputType.number,
                      validator: (v) {
                        if ((v ?? '').trim().isEmpty) return 'Pflichtfeld';
                        final kmAnfang = int.tryParse(v!.trim());
                        if (kmAnfang == null) return 'Ungültige Zahl';
                        final kmEnde = int.tryParse(_kmEndeCtrl.text.trim());
                        if (kmEnde != null && kmAnfang > kmEnde) {
                          return 'KM-Stand Fahrtbeginn darf nicht über KM-Stand Fahrtende liegen';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _kmEndeCtrl,
                      decoration: _pflichtfeldDecoration('KM-Stand Fahrtende', hasValue: _kmEndeCtrl.text.trim().isNotEmpty),
                      keyboardType: TextInputType.number,
                      validator: (v) {
                        if ((v ?? '').trim().isEmpty) return 'Pflichtfeld';
                        final kmEnde = int.tryParse(v!.trim());
                        if (kmEnde == null) return 'Ungültige Zahl';
                        final kmAnfang = int.tryParse(_kmAnfangCtrl.text.trim());
                        if (kmAnfang != null && kmEnde < kmAnfang) {
                          return 'KM-Stand Fahrtende darf nicht unter KM-Stand Fahrtbeginn liegen';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: TextFormField(
                            controller: _kmDienstlichCtrl,
                            focusNode: _kmDienstlichFocus,
                            decoration: const InputDecoration(labelText: 'KM dienstl.'),
                            keyboardType: TextInputType.number,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextFormField(
                            controller: _kmWohnortCtrl,
                            focusNode: _kmWohnortFocus,
                            decoration: const InputDecoration(labelText: 'KM Wohn.-Arb.'),
                            keyboardType: TextInputType.number,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextFormField(
                            controller: _kmPrivatCtrl,
                            focusNode: _kmPrivatFocus,
                            decoration: const InputDecoration(labelText: 'KM privat'),
                            keyboardType: TextInputType.number,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(child: TextFormField(controller: _kostenBetragCtrl, decoration: const InputDecoration(labelText: 'Kosten (Betrag)'), keyboardType: const TextInputType.numberWithOptions(decimal: true))),
                        const SizedBox(width: 12),
                        Expanded(child: TextFormField(controller: _kostenArtCtrl, decoration: const InputDecoration(labelText: 'Art der Kosten'))),
                      ],
                    ),
                  ],
                ),
                ),
              ),
            ),
    );
  }

  /// Kennzeichen: Dropdown mit Vorauswahl – exakt wie V1
  Widget _buildKennzeichenField() {
    final list = _fahrzeuge;
    final v = _effectiveVorlage;
    final vorlageRuf = v?.fahrzeugRufname ?? '';

    // Items: Platzhalter + Schicht-Fahrzeug (wenn vorlageRuf) + Flotte – wie V1
    final items = <DropdownMenuItem<String>>[
      DropdownMenuItem(value: '', child: Text('— Fahrzeug wählen —', overflow: TextOverflow.ellipsis, maxLines: 1)),
    ];
    if (vorlageRuf.isNotEmpty) {
      items.insert(1, DropdownMenuItem(
        value: '__vorlage__',
        child: Text(_formatVorlageLabel(), overflow: TextOverflow.ellipsis, maxLines: 1),
      ));
    }
    items.addAll(list.map((f) => DropdownMenuItem(value: f.id, child: Text(_formatFahrzeugLabel(f), overflow: TextOverflow.ellipsis, maxLines: 1))));

    final selectedId = _selectedFahrzeugId != null &&
        (list.any((f) => f.id == _selectedFahrzeugId) || _selectedFahrzeugId == '__vorlage__')
        ? _selectedFahrzeugId!
        : '';
    return DropdownButtonFormField<String>(
      key: ValueKey('kennzeichen_${_selectedFahrzeugId ?? "empty"}'),
      value: selectedId.isNotEmpty ? selectedId : '',
      isExpanded: true,
      decoration: InputDecoration(
        labelText: 'Kennzeichen',
        hintText: 'Fahrzeug wählen',
        filled: true,
        fillColor: selectedId.isNotEmpty ? Colors.white : _yellowBg,
        border: const OutlineInputBorder(),
      ),
      items: items,
      validator: widget.eintrag == null ? (v) => (v == null || v.isEmpty) ? 'Fahrzeug erforderlich' : null : null,
      onChanged: (val) async {
        if (val == null || val.isEmpty) return;
        setState(() => _selectedFahrzeugId = val);
        final f = list.where((x) => x.id == val).firstOrNull;
        if (widget.eintrag == null && _kmAnfangCtrl.text.trim().isEmpty) {
          if (f != null) {
            final km = await widget.service.getLetzterKmEnde(
              widget.companyId,
              (f.kennzeichen ?? '').trim().isNotEmpty ? f.kennzeichen : (f.rufname ?? f.id),
            );
            if (km != null && mounted) setState(() => _kmAnfangCtrl.text = km.toString());
          } else if (val == '__vorlage__' && _effectiveVorlage != null && _effectiveVorlage!.kmAnfang != null) {
            if (mounted) setState(() => _kmAnfangCtrl.text = _effectiveVorlage!.kmAnfang.toString());
          }
        }
      },
    );
  }

  /// Fahrer: Dropdown mit Fahrer + Beifahrer aus Schicht, "Manuell eingeben" öffnet Namensfeld
  Widget _buildFahrerField() {
    final hasOptionen = _effectiveVorlage?.fahrerOptionen.isNotEmpty == true;
    final optionen = _effectiveVorlage?.fahrerOptionen ?? [];
    final isManuell = _fahrerDropdownValue == '__manual__';

    if (!hasOptionen) {
      return TextFormField(
        controller: _nameFahrerCtrl,
        decoration: _isFahrerPflicht
            ? _pflichtfeldDecoration('Fahrer (Name)', hasValue: _nameFahrerCtrl.text.trim().isNotEmpty)
            : const InputDecoration(labelText: 'Fahrer (Name)', border: OutlineInputBorder()),
        validator: _isFahrerPflicht ? (v) => (v ?? '').trim().isEmpty ? 'Pflichtfeld' : null : null,
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DropdownButtonFormField<String>(
          value: () {
            final t = _nameFahrerCtrl.text.trim();
            if (optionen.contains(t)) return t;
            if (isManuell || (t.isNotEmpty && !optionen.contains(t))) return '__manual__';
            return _fahrerDropdownValue;
          }(),
          isExpanded: true,
          decoration: InputDecoration(
            labelText: 'Fahrer (aus Schicht wählen)',
            filled: true,
            fillColor: (_fahrerDropdownValue != null && _fahrerDropdownValue != '__manual__') || (isManuell && _nameFahrerCtrl.text.trim().isNotEmpty) ? Colors.white : _yellowBg,
            border: const OutlineInputBorder(),
          ),
          items: [
            const DropdownMenuItem(value: null, child: Text('— Bitte wählen —', overflow: TextOverflow.ellipsis, maxLines: 1)),
            ...optionen.map((n) => DropdownMenuItem(value: n, child: Text(n, overflow: TextOverflow.ellipsis, maxLines: 1))),
            const DropdownMenuItem(value: '__manual__', child: Text('Manuell eingeben', overflow: TextOverflow.ellipsis, maxLines: 1)),
          ],
          validator: (v) {
            if (v == null) return 'Bitte wählen';
            if (v == '__manual__' && _nameFahrerCtrl.text.trim().isEmpty) return 'Bitte Namen eingeben';
            return null;
          },
          onChanged: (v) {
            setState(() {
              _fahrerDropdownValue = v;
              if (v != null && v != '__manual__') {
                _nameFahrerCtrl.text = v;
              } else if (v == '__manual__') {
                _nameFahrerCtrl.clear();
              }
            });
          },
        ),
        if (isManuell) ...[
          const SizedBox(height: 12),
          TextFormField(
            controller: _nameFahrerCtrl,
            decoration: _pflichtfeldDecoration('Fahrer (Name)', hasValue: _nameFahrerCtrl.text.trim().isNotEmpty),
            validator: (val) => (val ?? '').trim().isEmpty ? 'Pflichtfeld' : null,
            onChanged: (_) => setState(() {}),
          ),
        ],
      ],
    );
  }

  Widget _buildDateField() {
    return InkWell(
      onTap: () async {
        final d = await showDatePicker(
          context: context,
          initialDate: _parseDate(_datumCtrl.text) ?? DateTime.now(),
          firstDate: DateTime(2020),
          lastDate: DateTime.now().add(const Duration(days: 365)),
        );
        if (d != null) _datumCtrl.text = _fmtDate(d);
      },
      child: InputDecorator(
        decoration: const InputDecoration(labelText: 'Datum'),
        child: Text(_datumCtrl.text.isEmpty ? 'TT.MM.JJJJ' : _datumCtrl.text),
      ),
    );
  }
}
