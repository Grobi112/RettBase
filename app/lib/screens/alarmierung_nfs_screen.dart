import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import '../theme/app_theme.dart';
import '../utils/schichtplan_nfs_bereitschaftstyp_utils.dart';
import '../services/auth_service.dart';
import '../services/auth_data_service.dart';
import '../services/alarmierung_nfs_service.dart';
import '../services/gebaeudeadresse_service.dart';

String _formatDate(DateTime d) =>
    '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.${d.year}';

String _formatTime(TimeOfDay t) =>
    '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

DateTime? _parseDate(String? s) {
  if (s == null || s.trim().isEmpty) return null;
  final parts = s.trim().split('.');
  if (parts.length != 3) return null;
  final d = int.tryParse(parts[0]);
  final m = int.tryParse(parts[1]);
  final y = int.tryParse(parts[2]);
  if (d == null || m == null || y == null) return null;
  if (m < 1 || m > 12 || d < 1 || d > 31) return null;
  return DateTime(y, m, d);
}

TimeOfDay? _parseTime(String? s) {
  if (s == null || s.trim().isEmpty) return null;
  final parts = s.trim().split(':');
  if (parts.length < 2) return null;
  final h = int.tryParse(parts[0]);
  final m = int.tryParse(parts[1]);
  if (h == null || m == null || h < 0 || h > 23 || m < 0 || m > 59) return null;
  return TimeOfDay(hour: h, minute: m);
}

/// Extrahiert nur die Uhrzeit (HH:MM oder HH:MM:SS) aus datumUhrzeit-String (z.B. "14.03.2026 15:58:49")
String _timeFromDatumUhrzeit(String? s) {
  if (s == null || s.trim().isEmpty) return '';
  final parts = s.trim().split(' ');
  return parts.length >= 2 ? parts.last : '';
}

const _pflichtfeldGelb = Color(0xFFFFF9C4);

const _inputDecoration = InputDecoration(
  filled: true,
  fillColor: Colors.white,
  border: OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(10))),
  enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(10)), borderSide: BorderSide(color: AppTheme.border)),
  focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(10)), borderSide: BorderSide(color: AppTheme.primary, width: 1.5)),
  contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 14),
);

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

/// Einsatzverwaltung – Mitglieder-Status, Neue Alarmierung, Offene Einsätze
class AlarmierungNfsScreen extends StatefulWidget {
  final String companyId;
  final String? title;
  final String? userRole;
  final VoidCallback onBack;

  const AlarmierungNfsScreen({
    super.key,
    required this.companyId,
    this.title,
    this.userRole,
    required this.onBack,
  });

  @override
  State<AlarmierungNfsScreen> createState() => _AlarmierungNfsScreenState();
}

class _AlarmierungNfsScreenState extends State<AlarmierungNfsScreen>
    with SingleTickerProviderStateMixin {
  final _authService = AuthService();
  final _authDataService = AuthDataService();
  final _service = AlarmierungNfsService();
  final _gebaeudeAdresseService = GebaeudeAdresseService();
  List<GebaeudeAdresseVorschlag>? _adressVorschlaege;
  int _strasseAcKey = 0;

  late TabController _tabController;
  bool _saving = false;
  String? _userRole;

  final _laufendeNrCtrl = TextEditingController();
  final _einsatzNrCtrl = TextEditingController();
  DateTime? _einsatzDatum;
  TimeOfDay? _uhrzeitBeginn;
  TimeOfDay? _uhrzeitEinsatzUebernommen;
  TimeOfDay? _uhrzeitAnEinsatzort;
  TimeOfDay? _uhrzeitAbfahrt;
  TimeOfDay? _uhrzeitZuHause;
  final _nameBetroffenerCtrl = TextEditingController();
  final _strasseCtrl = TextEditingController();
  final _hausNrCtrl = TextEditingController();
  final _plzCtrl = TextEditingController();
  final _ortCtrl = TextEditingController();
  final _bemerkungenCtrl = TextEditingController();
  String? _einsatzindikation;

  List<Map<String, dynamic>> _alleMitarbeiter = [];
  List<Map<String, dynamic>> _verfuegbareMitarbeiter = [];
  List<Map<String, dynamic>> _mitgliederStatus = [];
  bool _loadingMitgliederStatus = false;
  final _selectedMitarbeiterIds = <String>{};
  bool _loadingMitarbeiter = false;
  final _kraefteSearchCtrl = TextEditingController();
  DateTime _statusDatum = DateTime.now();
  TimeOfDay _statusUhrzeit = TimeOfDay.now();

  bool get _canEdit {
    final r = (_userRole ?? '').toLowerCase().trim();
    return r == 'admin' || r == 'koordinator' || r == 'superadmin';
  }

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, initialIndex: 0, vsync: this);
    _einsatzDatum = DateTime.now();
    _uhrzeitBeginn = TimeOfDay.now();
    _loadLaufendeNrPreview();
    _kraefteSearchCtrl.addListener(() => setState(() {}));
    _loadAuth();
    _loadMitarbeiter();
    _loadMitgliederStatus();
    _gebaeudeAdresseService.loadCache().then((list) {
      if (mounted) setState(() => _adressVorschlaege = list);
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _refreshVerfuegbare());
  }

  Future<void> _loadLaufendeNrPreview() async {
    try {
      final nr = await _service.getNextLaufendeNrPreview(widget.companyId);
      if (mounted) {
        _laufendeNrCtrl.text = nr;
        setState(() {});
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    _tabController.dispose();
    _laufendeNrCtrl.dispose();
    _einsatzNrCtrl.dispose();
    _nameBetroffenerCtrl.dispose();
    _strasseCtrl.dispose();
    _hausNrCtrl.dispose();
    _plzCtrl.dispose();
    _ortCtrl.dispose();
    _bemerkungenCtrl.dispose();
    _kraefteSearchCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadAuth() async {
    final user = _authService.currentUser;
    if (user == null) return;
    final auth = await _authDataService.getAuthData(
      user.uid,
      user.email ?? '',
      widget.companyId,
    );
    if (mounted) setState(() => _userRole = auth.role);
  }

  Future<void> _loadMitgliederStatus() async {
    setState(() => _loadingMitgliederStatus = true);
    try {
      final dayId = _formatDate(_statusDatum);
      final stunde = _statusUhrzeit.hour;
      final list = await _service.loadMitgliederStatus(
        widget.companyId,
        dayId,
        stunde,
        forceServerRead: true,
      );
      if (mounted) setState(() {
        _mitgliederStatus = list;
        _loadingMitgliederStatus = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loadingMitgliederStatus = false);
    }
  }

  Future<void> _loadMitarbeiter() async {
    setState(() => _loadingMitarbeiter = true);
    try {
      final list = await _service.loadMitarbeiter(widget.companyId);
      if (mounted) setState(() {
        _alleMitarbeiter = list;
        _loadingMitarbeiter = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loadingMitarbeiter = false);
    }
  }

  Future<void> _refreshVerfuegbare() async {
    if (_einsatzDatum == null || _uhrzeitBeginn == null) {
      setState(() => _verfuegbareMitarbeiter = []);
      return;
    }
    final dayId = _formatDate(_einsatzDatum!);
    final stunde = _uhrzeitBeginn!.hour;
    try {
      final list = await _service.getVerfuegbareMitarbeiterMitDetails(
        widget.companyId,
        dayId,
        stunde,
        forceServerRead: true,
      );
      if (mounted) setState(() => _verfuegbareMitarbeiter = list);
    } catch (_) {
      if (mounted) setState(() => _verfuegbareMitarbeiter = []);
    }
  }

  Future<void> _pickDatum() async {
    final d = await showDatePicker(
      context: context,
      initialDate: _einsatzDatum ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (d != null) {
      setState(() => _einsatzDatum = d);
      await _refreshVerfuegbare();
    }
  }

  Future<void> _pickUhrzeit(
    ValueChanged<TimeOfDay> onPicked, {
    TimeOfDay? initial,
  }) async {
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
      if (identical(onPicked, (TimeOfDay t) => _uhrzeitBeginn = t)) {
        await _refreshVerfuegbare();
      }
    }
  }

  Widget _uhrzeitField(
    String label,
    TimeOfDay? value,
    ValueChanged<TimeOfDay> onPicked, {
    bool required = false,
    VoidCallback? onPick,
  }) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: InkWell(
          onTap: onPick ?? () => _pickUhrzeit(onPicked, initial: value),
          child: InputDecorator(
            decoration: _inputDecoration.copyWith(
              labelText: label,
              fillColor: required && value == null ? _pflichtfeldGelb : Colors.white,
            ),
            child: Text(value != null ? _formatTime(value) : 'Uhrzeit eingeben'),
          ),
        ),
      );

  Widget _field(
    TextEditingController ctrl,
    String label, {
    List<TextInputFormatter>? inputFormatters,
    bool required = false,
  }) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: TextField(
          controller: ctrl,
          onChanged: required ? (_) => setState(() {}) : null,
          inputFormatters: inputFormatters,
          decoration: _inputDecoration.copyWith(
            labelText: label,
            fillColor: required && ctrl.text.trim().isEmpty ? _pflichtfeldGelb : Colors.white,
          ),
        ),
      );

  Widget _bemerkungenField() => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: TextField(
          controller: _bemerkungenCtrl,
          maxLines: 5,
          decoration: _inputDecoration.copyWith(
            labelText: 'Bemerkungen',
            alignLabelWithHint: true,
          ),
        ),
      );

  Widget _buildStrasseAutocomplete() {
    final list = _adressVorschlaege ?? [];
    return RawAutocomplete<GebaeudeAdresseVorschlag>(
      key: ValueKey('strasse_ac_$_strasseAcKey'),
      optionsViewBuilder: (context, onSelected, options) {
        return Align(
          alignment: Alignment.topLeft,
          child: Material(
            elevation: 4,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 200),
              child: ListView.builder(
                padding: EdgeInsets.zero,
                shrinkWrap: true,
                itemCount: options.length,
                itemBuilder: (context, i) {
                  final o = options.elementAt(i);
                  return InkWell(
                    onTap: () => onSelected(o),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      child: Text(
                        o.displayLabel,
                        style: const TextStyle(fontSize: 14),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        );
      },
      optionsBuilder: (textEditingValue) {
        final q = textEditingValue.text.trim().toLowerCase();
        if (q.isEmpty || list.isEmpty) return const Iterable<GebaeudeAdresseVorschlag>.empty();
        final startsWith = list.where((o) => o.strasse.toLowerCase().startsWith(q));
        if (startsWith.length >= 25) return startsWith.take(25);
        final contains = list.where((o) => o.strasse.toLowerCase().contains(q) && !o.strasse.toLowerCase().startsWith(q));
        return [...startsWith, ...contains].take(25);
      },
      displayStringForOption: (o) => o.strasse,
      onSelected: (o) {
        setState(() {
          _strasseCtrl.text = o.strasse;
          _plzCtrl.text = o.plz;
          _ortCtrl.text = o.ort;
        });
      },
      fieldViewBuilder: (context, controller, focusNode, onFieldSubmitted) {
        final isEmpty = _strasseCtrl.text.trim().isEmpty;
        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: TextField(
            controller: controller,
            focusNode: focusNode,
            onChanged: (v) {
              _strasseCtrl.text = v;
              setState(() {});
            },
            decoration: _inputDecoration.copyWith(
              labelText: 'Straße',
              fillColor: isEmpty ? _pflichtfeldGelb : Colors.white,
            ),
          ),
        );
      },
    );
  }

  Future<void> _speichern() async {
    var valid = true;
    valid = valid && _einsatzNrCtrl.text.trim().isNotEmpty;
    valid = valid && _einsatzDatum != null;
    valid = valid && _uhrzeitBeginn != null;
    valid = valid && _nameBetroffenerCtrl.text.trim().isNotEmpty;
    valid = valid && _strasseCtrl.text.trim().isNotEmpty;
    valid = valid && _hausNrCtrl.text.trim().isNotEmpty;
    valid = valid && _ortCtrl.text.trim().isNotEmpty;
    valid = valid && _einsatzindikation != null && _einsatzindikation!.trim().isNotEmpty;
    valid = valid && _selectedMitarbeiterIds.isNotEmpty;

    if (!valid) {
      if (mounted) {
        await showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Text('Hinweis', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.red.shade700)),
            content: const Text(
              'Es wurden nicht alle Pflichtfelder ausgefüllt. '
              'Bitte füllen Sie alle Felder aus (inkl. Straße, Haus-Nr., Ort) und wählen Sie mindestens einen Mitarbeiter zur Alarmierung.',
            ),
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
        final auth = await _authDataService.getAuthData(
          user.uid,
          user.email ?? '',
          widget.companyId,
        );
        creatorName = auth.displayName;
      }

      final data = <String, dynamic>{
        'einsatzNr': _einsatzNrCtrl.text.trim(),
        'einsatzDatum': _formatDate(_einsatzDatum!),
        'uhrzeitBeginn': _formatTime(_uhrzeitBeginn!),
        'uhrzeitEinsatzUebernommen': _uhrzeitEinsatzUebernommen != null ? _formatTime(_uhrzeitEinsatzUebernommen!) : null,
        'uhrzeitAnEinsatzort': _uhrzeitAnEinsatzort != null ? _formatTime(_uhrzeitAnEinsatzort!) : null,
        'uhrzeitAbfahrt': _uhrzeitAbfahrt != null ? _formatTime(_uhrzeitAbfahrt!) : null,
        'uhrzeitZuHause': _uhrzeitZuHause != null ? _formatTime(_uhrzeitZuHause!) : null,
        'nameBetroffener': _nameBetroffenerCtrl.text.trim(),
        'strasse': _strasseCtrl.text.trim(),
        'hausNr': _hausNrCtrl.text.trim(),
        'plz': _plzCtrl.text.trim(),
        'ort': _ortCtrl.text.trim(),
        'einsatzindikation': _einsatzindikation,
        'bemerkungen': _bemerkungenCtrl.text.trim().isEmpty ? null : _bemerkungenCtrl.text.trim(),
        'alarmierteMitarbeiterIds': _selectedMitarbeiterIds.toList(),
      };

      final laufendeNr = _laufendeNrCtrl.text.trim();
      await _service.create(
        widget.companyId,
        data,
        creatorUid: user?.uid,
        creatorName: creatorName,
        laufendeNr: laufendeNr.isNotEmpty ? laufendeNr : null,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Einsatz ${_einsatzNrCtrl.text.trim()} erstellt. ${_selectedMitarbeiterIds.length} Kräfte alarmiert.')),
        );
        _resetForm();
        _tabController.animateTo(2); // Offene Einsätze
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Fehler: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _resetForm() {
    final now = DateTime.now();
    setState(() {
      _laufendeNrCtrl.clear();
      _einsatzNrCtrl.clear();
      _einsatzDatum = now;
      _uhrzeitBeginn = TimeOfDay(hour: now.hour, minute: now.minute);
      _uhrzeitEinsatzUebernommen = null;
      _uhrzeitAnEinsatzort = null;
      _uhrzeitAbfahrt = null;
      _uhrzeitZuHause = null;
      _nameBetroffenerCtrl.clear();
      _strasseCtrl.clear();
      _strasseAcKey++;
      _hausNrCtrl.clear();
      _plzCtrl.clear();
      _ortCtrl.clear();
      _bemerkungenCtrl.clear();
      _einsatzindikation = null;
      _selectedMitarbeiterIds.clear();
      _verfuegbareMitarbeiter = [];
      _kraefteSearchCtrl.clear();
    });
    _loadLaufendeNrPreview();
    _refreshVerfuegbare();
  }

  List<Map<String, dynamic>> _filterMitarbeiterBySearch(List<Map<String, dynamic>> list) {
    final q = _kraefteSearchCtrl.text.trim().toLowerCase();
    if (q.isEmpty) return list;
    return list.where((m) {
      final name = (m['displayName'] ?? '${m['vorname'] ?? ''} ${m['nachname'] ?? ''}').toString().toLowerCase();
      final vorname = (m['vorname'] ?? '').toString().toLowerCase();
      final nachname = (m['nachname'] ?? '').toString().toLowerCase();
      final ort = (m['ort'] ?? '').toString().toLowerCase();
      final telefon = (m['telefon'] ?? '').toString().toLowerCase();
      return name.contains(q) || vorname.contains(q) || nachname.contains(q) ||
          ort.contains(q) || telefon.contains(q);
    }).toList();
  }

  List<String> get _verfuegbareIds =>
      _verfuegbareMitarbeiter.map((m) => m['id'] as String? ?? '').where((s) => s.isNotEmpty).toList();

  Future<void> _launchTel(String number) async {
    final clean = number.replaceAll(RegExp(r'[\s\-\(\)]'), '');
    if (clean.isEmpty) return;
    final uri = Uri(scheme: 'tel', path: clean);
    try {
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else {
        await launchUrl(uri);
      }
    } catch (_) {}
  }

  Widget _buildMitarbeiterCheckbox(Map<String, dynamic> m, bool verfuegbar) {
    final id = m['id'] as String? ?? '';
    final name = m['displayName'] as String? ?? '${m['vorname']} ${m['nachname']}';
    final ort = (m['ort'] ?? '').toString().trim();
    final telefon = (m['telefon'] ?? '').toString().trim();
    final typName = (m['typName'] ?? '').toString().trim();
    final typColor = m['typColor'] as int?;
    final schichtColor = SchichtplanNfsBereitschaftstypUtils.colorForTypData(
      typColor: typColor,
      typName: typName,
    );
    final selected = _selectedMitarbeiterIds.contains(id);
    return InkWell(
      onTap: () {
        setState(() {
          if (selected) {
            _selectedMitarbeiterIds.remove(id);
          } else {
            _selectedMitarbeiterIds.add(id);
          }
        });
      },
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 24,
              height: 24,
              child: Checkbox(
                value: selected,
                onChanged: (v) {
                  setState(() {
                    if (v == true) {
                      _selectedMitarbeiterIds.add(id);
                    } else {
                      _selectedMitarbeiterIds.remove(id);
                    }
                  });
                },
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                shape: const CircleBorder(),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          name,
                          style: TextStyle(
                            fontWeight: verfuegbar ? FontWeight.w600 : FontWeight.normal,
                            fontSize: 15,
                          ),
                        ),
                      ),
                      if (verfuegbar)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: schichtColor.withOpacity(0.25),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: schichtColor.withOpacity(0.6), width: 1),
                          ),
                          child: Text(
                            typName.isNotEmpty ? typName : 'Verfügbar',
                            style: TextStyle(
                              fontSize: 12,
                              color: schichtColor,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                    ],
                  ),
                  if (verfuegbar && (ort.isNotEmpty || telefon.isNotEmpty)) ...[
                    const SizedBox(height: 4),
                    Wrap(
                      spacing: 12,
                      runSpacing: 4,
                      children: [
                        if (ort.isNotEmpty)
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.location_on, size: 14, color: Colors.grey.shade600),
                              const SizedBox(width: 4),
                              Text(ort, style: TextStyle(fontSize: 13, color: Colors.grey.shade700)),
                            ],
                          ),
                        if (telefon.isNotEmpty)
                          InkWell(
                            onTap: () => _launchTel(telefon),
                            borderRadius: BorderRadius.circular(4),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.phone, size: 14, color: AppTheme.primary),
                                const SizedBox(width: 4),
                                Text(telefon, style: TextStyle(fontSize: 13, color: AppTheme.primary, decoration: TextDecoration.underline)),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showEmSuchenSheet() async {
    if (_einsatzDatum == null || _uhrzeitBeginn == null) return;
    await _refreshVerfuegbare();
    if (!mounted) return;
    final selected = Set<String>.from(_selectedMitarbeiterIds);
    final result = await showDialog<Set<String>>(
      context: context,
      builder: (ctx) => _EmSuchenDialog(
        mitarbeiter: _alleMitarbeiter,
        verfuegbare: _verfuegbareMitarbeiter,
        initialSelected: selected,
        onZuteilen: () => Navigator.of(ctx).pop(selected),
        onAbbrechen: () => Navigator.of(ctx).pop(),
      ),
    );
    if (result != null && mounted) setState(() => _selectedMitarbeiterIds
      ..clear()
      ..addAll(result));
  }

  Widget _buildForm() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildEinsatzdatenCardWithAlarmierte(),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: _saving ? null : _speichern,
              style: FilledButton.styleFrom(
                backgroundColor: Colors.red.shade700,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
              child: _saving ? const Text('Wird gespeichert...') : const Text('Einsatz eröffnen und alarmieren'),
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _buildEinsatzdatenCard() {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Einsatzdaten',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: Colors.grey.shade800,
              ),
            ),
            const SizedBox(height: 16),
            _field(_einsatzNrCtrl, 'Einsatz-Nr.', required: true),
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: InkWell(
                onTap: _pickDatum,
                child: InputDecorator(
                  decoration: _inputDecoration.copyWith(
                    labelText: 'Einsatzdatum',
                    fillColor: _einsatzDatum == null ? _pflichtfeldGelb : Colors.white,
                  ),
                  child: Text(_einsatzDatum != null ? _formatDate(_einsatzDatum!) : 'Datum wählen'),
                ),
              ),
            ),
            _uhrzeitField(
              'Uhrzeit Beginn',
              _uhrzeitBeginn,
              (t) => setState(() => _uhrzeitBeginn = t),
              required: true,
              onPick: () => _pickUhrzeit((t) => _uhrzeitBeginn = t, initial: _uhrzeitBeginn),
            ),
            _uhrzeitField(
              'Einsatz übernommen',
              _uhrzeitEinsatzUebernommen,
              (t) => setState(() => _uhrzeitEinsatzUebernommen = t),
              required: false,
              onPick: () => _pickUhrzeit((t) => setState(() => _uhrzeitEinsatzUebernommen = t), initial: _uhrzeitEinsatzUebernommen),
            ),
            _uhrzeitField(
              'Am Einsatzort',
              _uhrzeitAnEinsatzort,
              (t) => setState(() => _uhrzeitAnEinsatzort = t),
              required: false,
              onPick: () => _pickUhrzeit((t) => _uhrzeitAnEinsatzort = t, initial: _uhrzeitAnEinsatzort),
            ),
            _uhrzeitField(
              'Einsatzstelle verlassen',
              _uhrzeitAbfahrt,
              (t) => setState(() => _uhrzeitAbfahrt = t),
              required: false,
              onPick: () => _pickUhrzeit((t) => _uhrzeitAbfahrt = t, initial: _uhrzeitAbfahrt),
            ),
            _uhrzeitField(
              'Einsatz beendet',
              _uhrzeitZuHause,
              (t) => setState(() => _uhrzeitZuHause = t),
              required: false,
              onPick: () => _pickUhrzeit((t) => _uhrzeitZuHause = t, initial: _uhrzeitZuHause),
            ),
            _field(_nameBetroffenerCtrl, 'Name des Betroffenen', required: true),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: _buildStrasseAutocomplete(),
                ),
                const SizedBox(width: 12),
                SizedBox(
                  width: 100,
                  child: _field(_hausNrCtrl, 'Haus-Nr.', required: true),
                ),
              ],
            ),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 100,
                  child: _field(_plzCtrl, 'PLZ', required: false),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _field(_ortCtrl, 'Ort', required: true),
                ),
              ],
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String?>(
              value: _einsatzindikation,
              isExpanded: true,
              decoration: _inputDecoration.copyWith(
                labelText: 'Einsatzindikation',
                fillColor: (_einsatzindikation == null || (_einsatzindikation ?? '').trim().isEmpty)
                    ? _pflichtfeldGelb
                    : Colors.white,
              ),
              items: _einsatzindikationOptions
                  .map((e) => DropdownMenuItem<String?>(
                        value: e.$1,
                        child: Text(e.$2, overflow: TextOverflow.ellipsis, maxLines: 1),
                      ))
                  .toList(),
              onChanged: (v) => setState(() => _einsatzindikation = v),
            ),
          ],
        ),
      ),
    );
  }

  /// Einsatzdaten-Card für „Neue Alarmierung“: Einsatzindikation + Alarmierte Mitarbeiter in einer Spalte.
  Widget _buildEinsatzdatenCardWithAlarmierte() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final narrow = constraints.maxWidth < 400;
        return Card(
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(color: Colors.grey.shade200),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Einsatzdaten',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey.shade800,
                  ),
                ),
                const SizedBox(height: 16),
                if (narrow)
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _field(_laufendeNrCtrl, 'Laufende-Nr.', required: false),
                      const SizedBox(height: 12),
                      _field(_einsatzNrCtrl, 'Einsatz-Nr.', required: true),
                    ],
                  )
                else
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        width: 140,
                        child: _field(_laufendeNrCtrl, 'Laufende-Nr.', required: false),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _field(_einsatzNrCtrl, 'Einsatz-Nr.', required: true),
                      ),
                    ],
                  ),
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: InkWell(
                onTap: _pickDatum,
                child: InputDecorator(
                  decoration: _inputDecoration.copyWith(
                    labelText: 'Einsatzdatum',
                    fillColor: _einsatzDatum == null ? _pflichtfeldGelb : Colors.white,
                  ),
                  child: Text(_einsatzDatum != null ? _formatDate(_einsatzDatum!) : 'Datum wählen'),
                ),
              ),
            ),
            _uhrzeitField(
              'Uhrzeit Beginn',
              _uhrzeitBeginn,
              (t) => setState(() => _uhrzeitBeginn = t),
              required: true,
              onPick: () => _pickUhrzeit((t) => _uhrzeitBeginn = t, initial: _uhrzeitBeginn),
            ),
            _field(_nameBetroffenerCtrl, 'Name des Betroffenen', required: true),
            if (narrow) ...[
              _buildStrasseAutocomplete(),
              const SizedBox(height: 12),
              _field(_hausNrCtrl, 'Haus-Nr.', required: true),
              const SizedBox(height: 12),
              _field(_plzCtrl, 'PLZ', required: false),
              const SizedBox(height: 12),
              _field(_ortCtrl, 'Ort', required: true),
            ] else ...[
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: _buildStrasseAutocomplete()),
                  const SizedBox(width: 12),
                  SizedBox(width: 100, child: _field(_hausNrCtrl, 'Haus-Nr.', required: true)),
                ],
              ),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(width: 100, child: _field(_plzCtrl, 'PLZ', required: false)),
                  const SizedBox(width: 12),
                  Expanded(child: _field(_ortCtrl, 'Ort', required: true)),
                ],
              ),
            ],
            const SizedBox(height: 16),
            DropdownButtonFormField<String?>(
              value: _einsatzindikation,
              isExpanded: true,
              decoration: _inputDecoration.copyWith(
                labelText: 'Einsatzindikation',
                fillColor: (_einsatzindikation == null || (_einsatzindikation ?? '').trim().isEmpty)
                    ? _pflichtfeldGelb
                    : Colors.white,
              ),
              items: _einsatzindikationOptions
                  .map((e) => DropdownMenuItem<String?>(
                        value: e.$1,
                        child: Text(e.$2, overflow: TextOverflow.ellipsis, maxLines: 1),
                      ))
                  .toList(),
              onChanged: (v) => setState(() => _einsatzindikation = v),
            ),
            const SizedBox(height: 16),
            _bemerkungenField(),
            const SizedBox(height: 20),
            _buildAlarmierteMitarbeiterSection(),
          ],
        ),
      ),
    );
      },
    );
  }

  Widget _buildAlarmierteMitarbeiterSection() {
    final zugeordnet = _selectedMitarbeiterIds.map((id) {
      for (final m in _verfuegbareMitarbeiter) {
        if ((m['id'] as String? ?? '') == id) return m;
      }
      for (final m in _alleMitarbeiter) {
        if ((m['id'] as String? ?? '') == id) return m;
      }
      return <String, dynamic>{'id': id, 'displayName': 'Unbekannt'};
    }).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Alarmierte Mitarbeiter',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Colors.grey.shade800),
        ),
        const SizedBox(height: 12),
        if (zugeordnet.isEmpty)
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.grey.shade50,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.grey.shade200),
            ),
            child: Text(
              'Keine Kräfte zugeordnet. Tippen Sie auf „weitere Mitarbeiter alarmieren“ um Mitglieder hinzuzufügen.',
              style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
            ),
          )
        else
          LayoutBuilder(
            builder: (context, listConstraints) {
              final narrow = listConstraints.maxWidth < 400;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: zugeordnet.map((m) {
                  final id = m['id'] as String? ?? '';
                  final name = m['displayName'] as String? ?? '${m['vorname']} ${m['nachname']}';
                  final typName = (m['typName'] ?? '').toString().trim();
                  final typColor = m['typColor'] as int?;
                  final isVerfuegbar = _verfuegbareIds.contains(id);
                  final schichtColor = isVerfuegbar && typName.isNotEmpty
                      ? SchichtplanNfsBereitschaftstypUtils.colorForTypData(typColor: typColor, typName: typName)
                      : Colors.grey;
                  final typBadge = typName.isNotEmpty
                      ? Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: schichtColor.withOpacity(0.25),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: schichtColor.withOpacity(0.6)),
                          ),
                          child: Text(typName, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: schichtColor)),
                        )
                      : const SizedBox.shrink();
                  final removeBtn = IconButton(
                    icon: const Icon(Icons.remove_circle_outline, size: 22),
                    color: Colors.red.shade400,
                    onPressed: () => setState(() => _selectedMitarbeiterIds.remove(id)),
                  );
                  if (narrow) {
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(Icons.person_outline, size: 20, color: Colors.grey.shade600),
                              const SizedBox(width: 8),
                              Expanded(child: Text(name, overflow: TextOverflow.ellipsis)),
                              removeBtn,
                            ],
                          ),
                          if (typName.isNotEmpty) ...[
                            const SizedBox(height: 6),
                            typBadge,
                          ],
                        ],
                      ),
                    );
                  }
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(
                      children: [
                        Icon(Icons.person_outline, size: 20, color: Colors.grey.shade600),
                        const SizedBox(width: 12),
                        Expanded(child: Text(name)),
                        typBadge,
                        const SizedBox(width: 8),
                        removeBtn,
                      ],
                    ),
                  );
                }).toList(),
              );
            },
          ),
        const SizedBox(height: 12),
        LayoutBuilder(
          builder: (context, constraints) {
            final narrow = constraints.maxWidth < 400;
            if (narrow) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  OutlinedButton.icon(
                    onPressed: _loadingMitarbeiter ? null : _showEmSuchenSheet,
                    icon: const Icon(Icons.search, size: 20),
                    label: const Text('weitere Mitarbeiter alarmieren'),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      alignment: Alignment.centerLeft,
                    ),
                  ),
                  const SizedBox(height: 8),
                  FilledButton.icon(
                    onPressed: _loadingMitarbeiter ? null : _showEmSuchenSheet,
                    icon: const Icon(Icons.add, size: 20),
                    label: const Text('Zuteilen'),
                    style: FilledButton.styleFrom(
                      backgroundColor: AppTheme.primary,
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                    ),
                  ),
                ],
              );
            }
            return Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _loadingMitarbeiter ? null : _showEmSuchenSheet,
                    icon: const Icon(Icons.search, size: 20),
                    label: const Text('weitere Mitarbeiter alarmieren'),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      alignment: Alignment.centerLeft,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                FilledButton.icon(
                  onPressed: _loadingMitarbeiter ? null : _showEmSuchenSheet,
                  icon: const Icon(Icons.add, size: 20),
                  label: const Text('Zuteilen'),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppTheme.primary,
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  ),
                ),
              ],
            );
          },
        ),
      ],
    );
  }

  static const _rot = Color(0xFFDC2626);
  static const _gelb = Color(0xFFF59E0B);
  static const _gruen = Color(0xFF10B981);

  String _formatNameMitOrt(Map<String, dynamic> m) {
    final vorname = (m['vorname'] ?? '').toString().trim();
    final nachname = (m['nachname'] ?? '').toString().trim();
    final ort = (m['ort'] ?? '').toString().trim();
    final name = vorname.isNotEmpty || nachname.isNotEmpty
        ? '$vorname $nachname'.trim()
        : (m['displayName'] ?? '').toString();
    return ort.isNotEmpty ? '$name ($ort)' : name;
  }

  Widget _buildMitgliederStatusGrid() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Mitglieder-Status',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w600,
            color: Colors.grey.shade800,
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: InkWell(
                onTap: () async {
                  final d = await showDatePicker(
                    context: context,
                    initialDate: _statusDatum,
                    firstDate: DateTime(2020),
                    lastDate: DateTime.now().add(const Duration(days: 365)),
                  );
                  if (d != null) {
                    setState(() => _statusDatum = d);
                    _loadMitgliederStatus();
                  }
                },
                child: InputDecorator(
                  decoration: _inputDecoration.copyWith(
                    labelText: 'Datum',
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  ),
                  child: Text(_formatDate(_statusDatum)),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: InkWell(
                onTap: () async {
                  final t = await showTimePicker(
                    context: context,
                    initialTime: _statusUhrzeit,
                    initialEntryMode: TimePickerEntryMode.input,
                    builder: (ctx, child) => MediaQuery(
                      data: MediaQuery.of(ctx).copyWith(alwaysUse24HourFormat: true),
                      child: child!,
                    ),
                  );
                  if (t != null) {
                    setState(() => _statusUhrzeit = t);
                    _loadMitgliederStatus();
                  }
                },
                child: InputDecorator(
                  decoration: _inputDecoration.copyWith(
                    labelText: 'Uhrzeit',
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  ),
                  child: Text(_formatTime(_statusUhrzeit)),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        if (_loadingMitgliederStatus)
          const Center(child: Padding(padding: EdgeInsets.all(24), child: CircularProgressIndicator()))
        else
          LayoutBuilder(
            builder: (context, constraints) {
              final crossAxisCount = constraints.maxWidth > 600 ? 4 : 1;
              final spacing = 8.0;
              final cellWidth = (constraints.maxWidth - (crossAxisCount - 1) * spacing) / crossAxisCount;
              final cellHeight = 32.0;
              final rowCount = (_mitgliederStatus.length / crossAxisCount).ceil();
              final gridHeight = (rowCount * (cellHeight + 4)).clamp(40.0, 400.0);
              return SizedBox(
                height: gridHeight,
                child: GridView.builder(
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: crossAxisCount,
                    mainAxisSpacing: 4,
                    crossAxisSpacing: spacing,
                    childAspectRatio: cellWidth / cellHeight,
                  ),
                  itemCount: _mitgliederStatus.length,
                itemBuilder: (context, i) {
                  final m = _mitgliederStatus[i];
                  final typName = (m['typName'] ?? '').toString().trim();
                  final typColor = m['typColor'] as int?;
                  final hasEintrag = typName.isNotEmpty;
                  final color = hasEintrag
                      ? SchichtplanNfsBereitschaftstypUtils.colorForTypData(
                          typColor: typColor,
                          typName: typName,
                        )
                      : _rot;
                  final label = hasEintrag ? typName : '–';
                  return Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: color.withOpacity(0.25),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: color.withOpacity(0.6), width: 1),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            _formatNameMitOrt(m),
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                            ),
                            overflow: TextOverflow.ellipsis,
                            maxLines: 1,
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                          decoration: BoxDecoration(
                            color: color.withOpacity(0.4),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            label,
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: color,
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                },
                ),
              );
            },
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.surfaceBg,
      appBar: AppTheme.buildModuleAppBar(
        title: widget.title ?? 'Einsatzverwaltung',
        onBack: widget.onBack,
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          tabs: const [
            Tab(text: 'Mitglieder-Status'),
            Tab(text: 'Neue Alarmierung'),
            Tab(text: 'Offene Einsätze'),
            Tab(text: 'Abgeschlossene Einsätze'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: _buildMitgliederStatusGrid(),
          ),
          SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: _buildForm(),
          ),
          _OffeneEinsaetzeTab(
            companyId: widget.companyId,
            canEdit: _canEdit,
            userRole: _userRole,
            service: _service,
            onRefresh: _loadMitarbeiter,
            onEinsatzAbgeschlossen: () => _tabController.animateTo(3),
          ),
          _AbgeschlosseneEinsaetzeTab(
            companyId: widget.companyId,
            service: _service,
            userRole: _userRole,
          ),
        ],
      ),
    );
  }
}

/// Dialog (zentriert): weitere Mitarbeiter alarmieren – Mitgliederliste auswählen und zuteilen
class _EmSuchenDialog extends StatefulWidget {
  final List<Map<String, dynamic>> mitarbeiter;
  final List<Map<String, dynamic>> verfuegbare;
  final Set<String> initialSelected;
  final VoidCallback onZuteilen;
  final VoidCallback onAbbrechen;

  const _EmSuchenDialog({
    required this.mitarbeiter,
    required this.verfuegbare,
    required this.initialSelected,
    required this.onZuteilen,
    required this.onAbbrechen,
  });

  @override
  State<_EmSuchenDialog> createState() => _EmSuchenDialogState();
}

class _EmSuchenDialogState extends State<_EmSuchenDialog> {
  final _searchCtrl = TextEditingController();
  late Set<String> _selected;

  @override
  void initState() {
    super.initState();
    _selected = Set.from(widget.initialSelected);
    _searchCtrl.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  List<Map<String, dynamic>> get _filtered {
    final q = _searchCtrl.text.trim().toLowerCase();
    if (q.isEmpty) return widget.mitarbeiter;
    return widget.mitarbeiter.where((m) {
      final name = (m['displayName'] ?? '${m['vorname']} ${m['nachname']}').toString().toLowerCase();
      return name.contains(q);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final verfuegbareIds = widget.verfuegbare.map((m) => m['id'] as String? ?? '').where((s) => s.isNotEmpty).toSet();
    final filtered = _filtered;
    return Dialog(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 480,
          maxHeight: MediaQuery.of(context).size.height * 0.8,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Einsatzkräfte zuordnen',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: Colors.grey.shade800),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _searchCtrl,
                    decoration: InputDecoration(
                      hintText: 'weitere Mitarbeiter alarmieren…',
                      prefixIcon: Padding(
                        padding: const EdgeInsets.only(left: 20),
                        child: const Icon(Icons.search),
                      ),
                      filled: true,
                      fillColor: Colors.grey.shade50,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    ),
                  ),
                  const SizedBox(height: 12),
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final narrow = constraints.maxWidth < 360;
                      if (narrow) {
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text('${_selected.length} ausgewählt', style: TextStyle(fontSize: 13, color: Colors.grey.shade600)),
                            const SizedBox(height: 8),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.end,
                              children: [
                                TextButton(
                                  onPressed: widget.onAbbrechen,
                                  child: const Text('Abbrechen'),
                                ),
                                const SizedBox(width: 8),
                                FilledButton.icon(
                                  onPressed: () {
                                    widget.initialSelected.clear();
                                    widget.initialSelected.addAll(_selected);
                                    widget.onZuteilen();
                                  },
                                  icon: const Icon(Icons.add, size: 20),
                                  label: const Text('Zuteilen'),
                                  style: FilledButton.styleFrom(backgroundColor: AppTheme.primary, padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12)),
                                ),
                              ],
                            ),
                          ],
                        );
                      }
                      return Row(
                        children: [
                          Text('${_selected.length} ausgewählt', style: TextStyle(fontSize: 13, color: Colors.grey.shade600)),
                          const Spacer(),
                          TextButton(
                            onPressed: widget.onAbbrechen,
                            child: const Text('Abbrechen'),
                          ),
                          const SizedBox(width: 8),
                          FilledButton.icon(
                            onPressed: () {
                              widget.initialSelected.clear();
                              widget.initialSelected.addAll(_selected);
                              widget.onZuteilen();
                            },
                            icon: const Icon(Icons.add, size: 20),
                            label: const Text('Zuteilen'),
                            style: FilledButton.styleFrom(backgroundColor: AppTheme.primary, padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12)),
                          ),
                        ],
                      );
                    },
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: filtered.length,
                itemBuilder: (ctx, i) {
                  final m = filtered[i];
                  final id = m['id'] as String? ?? '';
                  final name = m['displayName'] as String? ?? '${m['vorname']} ${m['nachname']}';
                  Map<String, dynamic>? vf;
                  for (final v in widget.verfuegbare) {
                    if ((v['id'] as String? ?? '') == id) { vf = v; break; }
                  }
                  final typName = (vf?['typName'] ?? m['typName'] ?? '').toString().trim();
                  final typColor = vf?['typColor'] as int? ?? m['typColor'] as int?;
                  final isVerfuegbar = verfuegbareIds.contains(id);
                  final selected = _selected.contains(id);
                  final color = isVerfuegbar && typName.isNotEmpty
                      ? SchichtplanNfsBereitschaftstypUtils.colorForTypData(typColor: typColor, typName: typName)
                      : Colors.grey;
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                    child: InkWell(
                      onTap: () => setState(() {
                        if (selected) _selected.remove(id);
                        else _selected.add(id);
                      }),
                      borderRadius: BorderRadius.circular(12),
                      child: Row(
                        children: [
                          SizedBox(
                            width: 24,
                            height: 24,
                            child: Checkbox(
                              value: selected,
                              onChanged: (v) => setState(() {
                                if (v == true) _selected.add(id);
                                else _selected.remove(id);
                              }),
                              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              shape: const CircleBorder(),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(child: Text(name, overflow: TextOverflow.ellipsis)),
                          if (typName.isNotEmpty)
                            Flexible(
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                  color: color.withOpacity(0.25),
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(color: color.withOpacity(0.6)),
                                ),
                                child: Text(typName, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: color), overflow: TextOverflow.ellipsis),
                              ),
                            ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Tab: Offene Einsätze – Liste und Bearbeitung für Admin/Koordinatoren
class _OffeneEinsaetzeTab extends StatelessWidget {
  final String companyId;
  final bool canEdit;
  final String? userRole;
  final AlarmierungNfsService service;
  final VoidCallback onRefresh;
  final VoidCallback? onEinsatzAbgeschlossen;

  const _OffeneEinsaetzeTab({
    required this.companyId,
    required this.canEdit,
    this.userRole,
    required this.service,
    required this.onRefresh,
    this.onEinsatzAbgeschlossen,
  });

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: service.streamEinsaetze(companyId),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        final list = snapshot.data ?? [];
        final offene = list.where((e) => (e['status'] ?? 'offen') == 'offen').toList();
        if (offene.isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                'Keine offenen Einsätze.',
                style: TextStyle(fontSize: 16, color: Colors.grey.shade600),
              ),
            ),
          );
        }
        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: offene.length,
          itemBuilder: (context, i) {
            final e = offene[i];
            final id = e['id'] as String? ?? '';
            final nr = e['einsatzNr'] as String? ?? '-';
            final datum = e['einsatzDatum'] as String? ?? '';
            final name = e['nameBetroffener'] as String? ?? '';
            final indikation = e['einsatzindikation'] as String? ?? '';
            final label = _einsatzindikationOptions
                .where((x) => x.$1 == indikation)
                .map((e) => e.$2)
                .firstOrNull ?? indikation;
            return Card(
              margin: const EdgeInsets.only(bottom: 12),
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(color: Colors.grey.shade200),
              ),
              child: InkWell(
                onTap: canEdit
                    ? () => _openBearbeiten(
                          context,
                          companyId,
                          id,
                          e,
                          service,
                          onRefresh,
                          userRole: userRole,
                          onEinsatzAbgeschlossen: onEinsatzAbgeschlossen,
                        )
                    : null,
                borderRadius: BorderRadius.circular(12),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            'Einsatz $nr',
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          if (canEdit) ...[
                            const Spacer(),
                            Icon(Icons.edit, size: 20, color: Colors.grey.shade600),
                          ],
                        ],
                      ),
                      if (datum.isNotEmpty) Text('$datum – $name', style: TextStyle(color: Colors.grey.shade600)),
                      if (label.isNotEmpty) Text(label, style: TextStyle(fontSize: 13, color: Colors.grey.shade700)),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}

/// Tab: Abgeschlossene Einsätze – Liste mit Suche nach Datum und Einsatz-Nr
class _AbgeschlosseneEinsaetzeTab extends StatefulWidget {
  final String companyId;
  final AlarmierungNfsService service;
  final String? userRole;

  const _AbgeschlosseneEinsaetzeTab({
    required this.companyId,
    required this.service,
    this.userRole,
  });

  @override
  State<_AbgeschlosseneEinsaetzeTab> createState() => _AbgeschlosseneEinsaetzeTabState();
}

class _AbgeschlosseneEinsaetzeTabState extends State<_AbgeschlosseneEinsaetzeTab> {
  final _einsatzNrSearchCtrl = TextEditingController();
  DateTime? _filterDatum;

  @override
  void initState() {
    super.initState();
    _einsatzNrSearchCtrl.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _einsatzNrSearchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: widget.service.streamEinsaetze(widget.companyId),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        final list = snapshot.data ?? [];
        final abgeschlossene = list.where((e) => (e['status'] ?? 'offen') == 'abgeschlossen').toList();

        final nrQuery = _einsatzNrSearchCtrl.text.trim().toLowerCase();
        var filtered = abgeschlossene;
        if (nrQuery.isNotEmpty) {
          filtered = filtered.where((e) {
            final nr = (e['einsatzNr'] ?? '').toString().toLowerCase();
            return nr.contains(nrQuery);
          }).toList();
        }
        if (_filterDatum != null) {
          final datumStr = _formatDate(_filterDatum!);
          filtered = filtered.where((e) {
            final eDatum = (e['einsatzDatum'] ?? '').toString();
            return eDatum == datumStr;
          }).toList();
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Filter',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Colors.grey.shade600,
                    ),
                  ),
                  const SizedBox(height: 8),
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final narrow = constraints.maxWidth < 400;
                      return narrow
                          ? Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                TextField(
                                  controller: _einsatzNrSearchCtrl,
                                  decoration: InputDecoration(
                                    hintText: 'Einsatz-Nr suchen…',
                                    prefixIcon: const Icon(Icons.search),
                                    filled: true,
                                    fillColor: Colors.grey.shade50,
                                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Row(
                                  children: [
                                    Expanded(
                                      child: InkWell(
                                        onTap: () async {
                                          final d = await showDatePicker(
                                            context: context,
                                            initialDate: _filterDatum ?? DateTime.now(),
                                            firstDate: DateTime(2020),
                                            lastDate: DateTime.now().add(const Duration(days: 365)),
                                          );
                                          if (d != null) setState(() => _filterDatum = d);
                                        },
                                        child: InputDecorator(
                                          decoration: InputDecoration(
                                            labelText: 'Datum',
                                            filled: true,
                                            fillColor: Colors.grey.shade50,
                                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                                            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                          ),
                                          child: Text(
                                            _filterDatum != null ? _formatDate(_filterDatum!) : 'Datum wählen',
                                            style: TextStyle(
                                              color: _filterDatum != null ? Colors.black87 : Colors.grey.shade600,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                    if (_filterDatum != null || _einsatzNrSearchCtrl.text.trim().isNotEmpty) ...[
                                      const SizedBox(width: 8),
                                      IconButton(
                                        icon: const Icon(Icons.clear_all),
                                        tooltip: 'Filter zurücksetzen',
                                        onPressed: () {
                                          setState(() {
                                            _filterDatum = null;
                                            _einsatzNrSearchCtrl.clear();
                                          });
                                        },
                                      ),
                                    ],
                                  ],
                                ),
                              ],
                            )
                          : Row(
                              children: [
                                Expanded(
                                  child: TextField(
                                    controller: _einsatzNrSearchCtrl,
                                    decoration: InputDecoration(
                                      hintText: 'Einsatz-Nr suchen…',
                                      prefixIcon: const Icon(Icons.search),
                                      filled: true,
                                      fillColor: Colors.grey.shade50,
                                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                SizedBox(
                                  width: 160,
                                  child: InkWell(
                                    onTap: () async {
                                      final d = await showDatePicker(
                                        context: context,
                                        initialDate: _filterDatum ?? DateTime.now(),
                                        firstDate: DateTime(2020),
                                        lastDate: DateTime.now().add(const Duration(days: 365)),
                                      );
                                      if (d != null) setState(() => _filterDatum = d);
                                    },
                                    child: InputDecorator(
                                      decoration: InputDecoration(
                                        labelText: 'Datum',
                                        filled: true,
                                        fillColor: Colors.grey.shade50,
                                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                      ),
                                      child: Text(
                                        _filterDatum != null ? _formatDate(_filterDatum!) : 'Datum wählen',
                                        style: TextStyle(
                                          color: _filterDatum != null ? Colors.black87 : Colors.grey.shade600,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                                if (_filterDatum != null || _einsatzNrSearchCtrl.text.trim().isNotEmpty) ...[
                                  const SizedBox(width: 8),
                                  IconButton(
                                    icon: const Icon(Icons.clear_all),
                                    tooltip: 'Filter zurücksetzen',
                                    onPressed: () {
                                      setState(() {
                                        _filterDatum = null;
                                        _einsatzNrSearchCtrl.clear();
                                      });
                                    },
                                  ),
                                ],
                              ],
                            );
                    },
                  ),
                ],
              ),
            ),
            Expanded(
              child: filtered.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(
                          abgeschlossene.isEmpty
                              ? 'Keine abgeschlossenen Einsätze.'
                              : 'Keine Einsätze gefunden.',
                          style: TextStyle(fontSize: 16, color: Colors.grey.shade600),
                        ),
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                      itemCount: filtered.length,
                      itemBuilder: (context, i) {
                        final e = filtered[i];
                        final id = e['id'] as String? ?? '';
                        final nr = e['einsatzNr'] as String? ?? '-';
                        final datum = e['einsatzDatum'] as String? ?? '';
                        final name = e['nameBetroffener'] as String? ?? '';
                        final indikation = e['einsatzindikation'] as String? ?? '';
                        final label = _einsatzindikationOptions
                            .where((x) => x.$1 == indikation)
                            .map((x) => x.$2)
                            .firstOrNull ?? indikation;
                        final isSuperadmin = (widget.userRole ?? '').toLowerCase().trim() == 'superadmin';
                        return Card(
                          margin: const EdgeInsets.only(bottom: 12),
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                            side: BorderSide(color: Colors.grey.shade200),
                          ),
                          child: InkWell(
                            onTap: () => _openBearbeiten(
                              context,
                              widget.companyId,
                              id,
                              e,
                              widget.service,
                              () => setState(() {}),
                              userRole: widget.userRole,
                            ),
                            borderRadius: BorderRadius.circular(12),
                            child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Text(
                                        'Einsatz $nr',
                                        style: const TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                      const Spacer(),
                                      Icon(Icons.visibility, size: 20, color: Colors.grey.shade600),
                                      if (isSuperadmin) ...[
                                        const SizedBox(width: 8),
                                        IconButton(
                                          icon: Icon(Icons.delete_outline, size: 22, color: Colors.red.shade700),
                                          tooltip: 'Einsatz löschen',
                                          onPressed: () => _confirmDeleteEinsatz(context, widget.companyId, id, nr, widget.service, () => setState(() {})),
                                        ),
                                      ],
                                    ],
                                  ),
                                  if (datum.isNotEmpty) Text('$datum – $name', style: TextStyle(color: Colors.grey.shade600)),
                                  if (label.isNotEmpty) Text(label, style: TextStyle(fontSize: 13, color: Colors.grey.shade700)),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        );
      },
    );
  }
}

Future<void> _confirmDeleteEinsatz(
  BuildContext context,
  String companyId,
  String docId,
  String nr,
  AlarmierungNfsService service,
  VoidCallback onRefresh,
) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Einsatz löschen?'),
      content: Text(
        'Einsatz $nr unwiderruflich löschen? Die Laufende-Nr. wird ggf. zurückgesetzt.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(false),
          child: const Text('Abbrechen'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: Colors.red),
          onPressed: () => Navigator.of(ctx).pop(true),
          child: const Text('Löschen'),
        ),
      ],
    ),
  );
  if (ok != true || !context.mounted) return;
  try {
    await service.deleteAbgeschlossenerEinsatz(companyId, docId);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Einsatz gelöscht. Laufende-Nr. ggf. zurückgesetzt.')),
      );
      onRefresh();
    }
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Fehler: $e'), backgroundColor: Colors.red),
      );
    }
  }
}

Future<void> _openBearbeiten(
  BuildContext context,
  String companyId,
  String docId,
  Map<String, dynamic> einsatz,
  AlarmierungNfsService service,
  VoidCallback onRefresh, {
  String? userRole,
  VoidCallback? onEinsatzAbgeschlossen,
}) async {
  await Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => _AlarmierungBearbeitenScreen(
        companyId: companyId,
        docId: docId,
        einsatz: einsatz,
        service: service,
        userRole: userRole,
        onEinsatzAbgeschlossen: onEinsatzAbgeschlossen,
      ),
    ),
  );
  onRefresh();
}

/// Bearbeitungs-Screen: vollständige Einsatzmaske + weitere Kräfte + Status
class _AlarmierungBearbeitenScreen extends StatefulWidget {
  final String companyId;
  final String docId;
  final Map<String, dynamic> einsatz;
  final AlarmierungNfsService service;
  final String? userRole;
  final VoidCallback? onEinsatzAbgeschlossen;

  const _AlarmierungBearbeitenScreen({
    required this.companyId,
    required this.docId,
    required this.einsatz,
    required this.service,
    this.userRole,
    this.onEinsatzAbgeschlossen,
  });

  @override
  State<_AlarmierungBearbeitenScreen> createState() =>
      _AlarmierungBearbeitenScreenState();
}

class _AlarmierungBearbeitenScreenState extends State<_AlarmierungBearbeitenScreen> {
  List<Map<String, dynamic>> _alleMitarbeiter = [];
  List<Map<String, dynamic>> _mitgliederStatus = [];
  List<Map<String, dynamic>> _verfuegbareMitarbeiter = [];
  final _selectedIds = <String>{};
  final _alarmierteMitarbeiterStatus = <String, int>{}; // id -> Status (2, 3, 4, 7)
  Map<String, dynamic>? _einsatzData; // Aktuelle Daten inkl. alarmierteMitarbeiterZeiten
  bool _loading = true;
  bool _saving = false;
  String? _currentUserName;
  StreamSubscription<Map<String, dynamic>?>? _einsatzStreamSubscription;
  DateTime? _lastStatusUpdateTime;

  /// Abgeschlossene Einsätze dürfen nur von Superadmin/Admin bearbeitet werden.
  bool get _canEdit {
    final r = (widget.userRole ?? '').toLowerCase().trim();
    final abgeschlossen = (widget.einsatz['status'] ?? 'offen') == 'abgeschlossen';
    if (abgeschlossen) return r == 'superadmin' || r == 'admin';
    return r == 'admin' || r == 'koordinator' || r == 'superadmin';
  }

  List<Map<String, dynamic>> _massnahmen = [];
  List<Map<String, dynamic>> _rueckmeldungen = [];

  final _einsatzNrCtrl = TextEditingController();
  DateTime? _einsatzDatum;
  TimeOfDay? _uhrzeitBeginn;
  final _nameBetroffenerCtrl = TextEditingController();
  final _strasseCtrl = TextEditingController();
  final _hausNrCtrl = TextEditingController();
  final _plzCtrl = TextEditingController();
  final _ortCtrl = TextEditingController();
  final _bemerkungenCtrl = TextEditingController();
  String? _einsatzindikation;

  @override
  void initState() {
    super.initState();
    _initFromEinsatz();
    _load();
    _einsatzStreamSubscription = widget.service
        .streamEinsatz(widget.companyId, widget.docId)
        .listen(_onEinsatzStreamUpdate);
  }

  void _onEinsatzStreamUpdate(Map<String, dynamic>? einsatzNeu) {
    if (!mounted || einsatzNeu == null) return;
    setState(() {
      _einsatzData = einsatzNeu;
      _lastStatusUpdateTime = DateTime.now();
      final alarmierteIds = (einsatzNeu['alarmierteMitarbeiterIds'] as List?)
          ?.map((x) => x.toString())
          .where((s) => s.isNotEmpty)
          .toSet();
      if (alarmierteIds != null) {
        _selectedIds
          ..clear()
          ..addAll(alarmierteIds);
      }
      final statusMap = einsatzNeu['alarmierteMitarbeiterStatus'];
      if (statusMap is Map) {
        _alarmierteMitarbeiterStatus.clear();
        for (final entry in statusMap.entries) {
          final k = entry.key?.toString();
          final v = entry.value;
          if (k != null && k.isNotEmpty) {
            final status = (v is num) ? v.toInt() : int.tryParse(v.toString());
            if (status != null && [2, 3, 4, 7].contains(status)) {
              _alarmierteMitarbeiterStatus[k] = status;
            }
          }
        }
      }
      _massnahmen = _parseMassnahmenRueckmeldungen(
        einsatzNeu['massnahmen'] ?? einsatzNeu['Massnahmen'],
      );
      _rueckmeldungen = _parseMassnahmenRueckmeldungen(
        einsatzNeu['rueckmeldungen'] ?? einsatzNeu['Rueckmeldungen'],
      );
    });
  }

  void _initFromEinsatz() {
    final e = widget.einsatz;
    _einsatzNrCtrl.text = (e['einsatzNr'] as String? ?? '').trim();
    _einsatzDatum = _parseDate(e['einsatzDatum'] as String?) ?? DateTime.now();
    _uhrzeitBeginn = _parseTime(e['uhrzeitBeginn'] as String?) ?? TimeOfDay.now();
    _nameBetroffenerCtrl.text = (e['nameBetroffener'] as String? ?? '').trim();
    _strasseCtrl.text = (e['strasse'] as String? ?? '').trim();
    _hausNrCtrl.text = (e['hausNr'] as String? ?? '').trim();
    _plzCtrl.text = (e['plz'] as String? ?? '').trim();
    _ortCtrl.text = (e['ort'] as String? ?? '').trim();
    _bemerkungenCtrl.text = (e['bemerkungen'] as String? ?? '').trim();
    _einsatzindikation = (e['einsatzindikation'] as String?)?.trim();
    if (_einsatzindikation != null && _einsatzindikation!.isEmpty) _einsatzindikation = null;
    _einsatzData = e;
    final alarmierte = (e['alarmierteMitarbeiterIds'] as List?)
            ?.map((x) => x.toString())
            .where((s) => s.isNotEmpty)
            .toSet() ??
        {};
    _selectedIds.addAll(alarmierte);
    final statusMap = e['alarmierteMitarbeiterStatus'];
    if (statusMap is Map) {
      for (final entry in statusMap.entries) {
        final k = entry.key?.toString();
        final v = entry.value;
        if (k != null && k.isNotEmpty) {
          final status = (v is num) ? v.toInt() : int.tryParse(v.toString());
          if (status != null && [2, 3, 4, 7].contains(status)) {
            _alarmierteMitarbeiterStatus[k] = status;
          }
        }
      }
    }
    _massnahmen = _parseMassnahmenRueckmeldungen(e['massnahmen'] ?? e['Massnahmen']);
    _rueckmeldungen = _parseMassnahmenRueckmeldungen(e['rueckmeldungen'] ?? e['Rueckmeldungen']);
  }

  @override
  void dispose() {
    _einsatzStreamSubscription?.cancel();
    _einsatzNrCtrl.dispose();
    _nameBetroffenerCtrl.dispose();
    _strasseCtrl.dispose();
    _hausNrCtrl.dispose();
    _plzCtrl.dispose();
    _ortCtrl.dispose();
    _bemerkungenCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final mitarbeiter = await widget.service.loadMitarbeiter(widget.companyId);
      final datum = _einsatzDatum ?? DateTime.now();
      final dayId = _formatDate(datum);
      final stunde = _uhrzeitBeginn?.hour ?? TimeOfDay.now().hour;
      final results = await Future.wait([
        widget.service.loadMitgliederStatus(widget.companyId, dayId, stunde, forceServerRead: true),
        widget.service.getVerfuegbareMitarbeiterMitDetails(widget.companyId, dayId, stunde),
        widget.service.get(widget.companyId, widget.docId),
        AuthService().currentUser != null
            ? AuthDataService().getAuthData(
                AuthService().currentUser!.uid,
                AuthService().currentUser!.email ?? '',
                widget.companyId,
              )
            : Future.value(null),
      ]);
      final status = results[0] as List<Map<String, dynamic>>;
      final verfuegbar = results[1] as List<Map<String, dynamic>>;
      final einsatzNeu = results[2] as Map<String, dynamic>?;
      final auth = results[3];
      if (mounted) setState(() {
        _alleMitarbeiter = mitarbeiter;
        _mitgliederStatus = status;
        _verfuegbareMitarbeiter = verfuegbar;
        _currentUserName = (auth is AuthData ? auth.displayName : null) ?? 'Unbekannt';
        if (einsatzNeu != null) {
          _einsatzData = einsatzNeu;
          final alarmierteIds = (einsatzNeu['alarmierteMitarbeiterIds'] as List?)
              ?.map((x) => x.toString())
              .where((s) => s.isNotEmpty)
              .toSet();
          if (alarmierteIds != null) {
            _selectedIds
              ..clear()
              ..addAll(alarmierteIds);
          }
          final statusMap = einsatzNeu['alarmierteMitarbeiterStatus'];
          if (statusMap is Map) {
            _alarmierteMitarbeiterStatus.clear();
            for (final entry in statusMap.entries) {
              final k = entry.key?.toString();
              final v = entry.value;
              if (k != null && k.isNotEmpty) {
                final status = (v is num) ? v.toInt() : int.tryParse(v.toString());
                if (status != null && [2, 3, 4, 7].contains(status)) {
                  _alarmierteMitarbeiterStatus[k] = status;
                }
              }
            }
          }
          _massnahmen = _parseMassnahmenRueckmeldungen(
            einsatzNeu['massnahmen'] ?? einsatzNeu['Massnahmen'],
          );
          _rueckmeldungen = _parseMassnahmenRueckmeldungen(
            einsatzNeu['rueckmeldungen'] ?? einsatzNeu['Rueckmeldungen'],
          );
        }
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  List<Map<String, dynamic>> _parseMassnahmenRueckmeldungen(dynamic raw) {
    if (raw == null) return [];
    List<dynamic> list;
    if (raw is List) {
      list = raw;
    } else if (raw is Iterable) {
      list = raw.toList();
    } else {
      return [];
    }
    final result = <Map<String, dynamic>>[];
    for (final x in list) {
      if (x is Map) {
        try {
          result.add(Map<String, dynamic>.from(x));
        } catch (_) {
          result.add(<String, dynamic>{});
        }
      }
    }
    return result;
  }

  Future<void> _pickDatum() async {
    final d = await showDatePicker(
      context: context,
      initialDate: _einsatzDatum ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (d != null) {
      setState(() => _einsatzDatum = d);
      _loadStatusOnly();
    }
  }

  Future<void> _pickUhrzeit(ValueChanged<TimeOfDay> onPicked, {TimeOfDay? initial}) async {
    final t = await showTimePicker(
      context: context,
      initialTime: initial ?? TimeOfDay.now(),
      initialEntryMode: TimePickerEntryMode.input,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true),
        child: child!,
      ),
    );
    if (t != null) {
      setState(() => onPicked(t));
      _loadStatusOnly();
    }
  }

  Future<void> _loadStatusOnly() async {
    final datum = _einsatzDatum ?? DateTime.now();
    final dayId = _formatDate(datum);
    final stunde = _uhrzeitBeginn?.hour ?? TimeOfDay.now().hour;
    try {
      final status = await widget.service.loadMitgliederStatus(
        widget.companyId,
        dayId,
        stunde,
        forceServerRead: true,
      );
      if (mounted) setState(() => _mitgliederStatus = status);
    } catch (_) {}
  }

  Future<void> _speichern() async {
    if (_einsatzNrCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Einsatz-Nr. ist Pflichtfeld.')),
      );
      return;
    }
    if (_einsatzDatum == null || _uhrzeitBeginn == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Datum und Uhrzeit Beginn sind Pflichtfelder.')),
      );
      return;
    }
    if (_nameBetroffenerCtrl.text.trim().isEmpty ||
        _strasseCtrl.text.trim().isEmpty ||
        _hausNrCtrl.text.trim().isEmpty ||
        _plzCtrl.text.trim().isEmpty ||
        _ortCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Name, Straße, Haus-Nr., PLZ und Ort sind Pflichtfelder.')),
      );
      return;
    }
    if (_einsatzindikation == null || _einsatzindikation!.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Einsatzindikation ist Pflichtfeld.')),
      );
      return;
    }
    if (_selectedIds.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Bitte mindestens einen Mitarbeiter auswählen.')),
      );
      return;
    }
    setState(() => _saving = true);
    try {
      await widget.service.update(
        widget.companyId,
        widget.docId,
        {
          'einsatzNr': _einsatzNrCtrl.text.trim(),
          'einsatzDatum': _formatDate(_einsatzDatum!),
          'uhrzeitBeginn': _formatTime(_uhrzeitBeginn!),
          'nameBetroffener': _nameBetroffenerCtrl.text.trim(),
          'strasse': _strasseCtrl.text.trim(),
          'hausNr': _hausNrCtrl.text.trim(),
          'plz': _plzCtrl.text.trim(),
          'ort': _ortCtrl.text.trim(),
          'einsatzindikation': _einsatzindikation,
          'bemerkungen': _bemerkungenCtrl.text.trim().isEmpty ? null : _bemerkungenCtrl.text.trim(),
          'alarmierteMitarbeiterIds': _selectedIds.toList(),
          'alarmierteMitarbeiterStatus': Map<String, int>.from(_alarmierteMitarbeiterStatus),
        },
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Einsatz aktualisiert.')),
        );
        if (mounted) Navigator.of(context).pop();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Fehler: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _abschliessen() async {
    setState(() => _saving = true);
    try {
      await widget.service.update(
        widget.companyId,
        widget.docId,
        {'status': 'abgeschlossen'},
      );
      if (!mounted) return;
      final messenger = ScaffoldMessenger.of(context);
      final onAbgeschlossen = widget.onEinsatzAbgeschlossen;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        messenger.showSnackBar(
          const SnackBar(content: Text('Einsatz abgeschlossen.')),
        );
        onAbgeschlossen?.call();
        if (mounted) Navigator.of(context).pop();
      });
    } catch (e, st) {
      debugPrint('Einsatz abschließen Fehler: $e');
      debugPrint('Stack: $st');
      if (mounted) {
        String msg = 'Fehler beim Abschließen: ';
        if (e is FirebaseException) {
          msg += '${e.code} – ${e.message ?? e.toString()}';
        } else {
          msg += e.toString();
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(msg), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _field(TextEditingController ctrl, String label, {bool required = false, bool readOnly = false}) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: TextField(
          controller: ctrl,
          readOnly: readOnly,
          onChanged: !readOnly && required ? (_) => setState(() {}) : null,
          decoration: _inputDecoration.copyWith(
            labelText: label,
            fillColor: required && ctrl.text.trim().isEmpty ? _pflichtfeldGelb : Colors.white,
          ),
        ),
      );

  Widget _uhrzeitField(
    String label,
    TimeOfDay? value,
    ValueChanged<TimeOfDay> onPicked, {
    bool required = false,
    bool readOnly = false,
  }) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: InkWell(
          onTap: readOnly ? null : () => _pickUhrzeit(onPicked, initial: value),
          child: InputDecorator(
            decoration: _inputDecoration.copyWith(
              labelText: label,
              fillColor: required && value == null ? _pflichtfeldGelb : Colors.white,
            ),
            child: Text(value != null ? _formatTime(value) : 'Uhrzeit eingeben'),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final nr = widget.einsatz['einsatzNr'] as String? ?? '-';
    return Scaffold(
      backgroundColor: AppTheme.surfaceBg,
      appBar: AppTheme.buildModuleAppBar(
        titleWidget: Row(
          children: [
            Text(
              _canEdit ? 'Einsatz $nr bearbeiten' : 'Einsatz $nr',
              style: const TextStyle(
                color: AppTheme.primary,
                fontWeight: FontWeight.w600,
                fontSize: 18,
              ),
            ),
            const Spacer(),
          ],
        ),
        onBack: () {
          if (mounted) Navigator.of(context).pop();
        },
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : LayoutBuilder(
              builder: (context, constraints) {
                final useTwoColumns = constraints.maxWidth > 600;
                final leftColumn = Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _buildEinsatzdatenCard(),
                    const SizedBox(height: 24),
                    _buildStatusCard(),
                  ],
                );
                final rightColumn = Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _buildBemerkungenCardBearbeiten(),
                    const SizedBox(height: 16),
                    _buildZuordnungEinsatzmittelCard(),
                    const SizedBox(height: 16),
                    _buildMassnahmenCardBearbeiten(),
                    const SizedBox(height: 16),
                    _buildRueckmeldungenCardBearbeiten(),
                  ],
                );
                return SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (useTwoColumns)
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(flex: 1, child: leftColumn),
                            const SizedBox(width: 24),
                            Expanded(flex: 1, child: rightColumn),
                          ],
                        )
                      else
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            ...leftColumn.children,
                            const SizedBox(height: 24),
                            ...rightColumn.children,
                          ],
                        ),
                      const SizedBox(height: 24),
                      if (_canEdit)
                      LayoutBuilder(
                        builder: (context, btnConstraints) {
                          final narrow = btnConstraints.maxWidth < 400;
                          if (narrow) {
                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                FilledButton(
                                  onPressed: _saving ? null : _speichern,
                                  style: FilledButton.styleFrom(
                                    backgroundColor: AppTheme.primary,
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(vertical: 16),
                                  ),
                                  child: _saving ? const Text('Wird gespeichert...') : const Text('Speichern'),
                                ),
                                if ((widget.einsatz['status'] ?? 'offen') != 'abgeschlossen') ...[
                                  const SizedBox(height: 12),
                                  OutlinedButton(
                                    onPressed: _saving ? null : _abschliessen,
                                    style: OutlinedButton.styleFrom(
                                      padding: const EdgeInsets.symmetric(vertical: 16),
                                    ),
                                    child: const Text('Einsatz abschließen'),
                                  ),
                                ],
                              ],
                            );
                          }
                          return Row(
                            children: [
                              Expanded(
                                child: FilledButton(
                                  onPressed: _saving ? null : _speichern,
                                  style: FilledButton.styleFrom(
                                    backgroundColor: AppTheme.primary,
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(vertical: 16),
                                  ),
                                  child: _saving ? const Text('Wird gespeichert...') : const Text('Speichern'),
                                ),
                              ),
                              if ((widget.einsatz['status'] ?? 'offen') != 'abgeschlossen') ...[
                                const SizedBox(width: 12),
                                Expanded(
                                  child: OutlinedButton(
                                    onPressed: _saving ? null : _abschliessen,
                                    style: OutlinedButton.styleFrom(
                                      padding: const EdgeInsets.symmetric(vertical: 16),
                                    ),
                                    child: const Text('Einsatz abschließen'),
                                  ),
                                ),
                              ],
                            ],
                          );
                        },
                      ),
                    ],
                  ),
                );
              },
            ),
    );
  }

  Widget _buildEinsatzdatenCard() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final narrow = constraints.maxWidth < 400;
        return Card(
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(color: Colors.grey.shade200),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Einsatzdaten',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey.shade800,
                  ),
                ),
                const SizedBox(height: 16),
                _field(_einsatzNrCtrl, 'Einsatz-Nr.', required: true, readOnly: !_canEdit),
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: InkWell(
                    onTap: _canEdit ? _pickDatum : null,
                    child: InputDecorator(
                      decoration: _inputDecoration.copyWith(
                        labelText: 'Einsatzdatum',
                        fillColor: _einsatzDatum == null ? _pflichtfeldGelb : Colors.white,
                      ),
                      child: Text(_einsatzDatum != null ? _formatDate(_einsatzDatum!) : 'Datum wählen'),
                    ),
                  ),
                ),
                _uhrzeitField(
                  'Uhrzeit Beginn',
                  _uhrzeitBeginn,
                  (t) => setState(() => _uhrzeitBeginn = t),
                  required: true,
                  readOnly: !_canEdit,
                ),
                _field(_nameBetroffenerCtrl, 'Name des Betroffenen', required: true, readOnly: !_canEdit),
                if (narrow) ...[
                  _field(_strasseCtrl, 'Straße', required: true, readOnly: !_canEdit),
                  _field(_hausNrCtrl, 'Haus-Nr.', required: true, readOnly: !_canEdit),
                  _field(_plzCtrl, 'PLZ', required: true, readOnly: !_canEdit),
                  _field(_ortCtrl, 'Ort', required: true, readOnly: !_canEdit),
                ] else ...[
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: _field(_strasseCtrl, 'Straße', required: true, readOnly: !_canEdit)),
                      const SizedBox(width: 12),
                      SizedBox(width: 100, child: _field(_hausNrCtrl, 'Haus-Nr.', required: true, readOnly: !_canEdit)),
                    ],
                  ),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(width: 100, child: _field(_plzCtrl, 'PLZ', required: true, readOnly: !_canEdit)),
                      const SizedBox(width: 12),
                      Expanded(child: _field(_ortCtrl, 'Ort', required: true, readOnly: !_canEdit)),
                    ],
                  ),
                ],
                const SizedBox(height: 16),
                DropdownButtonFormField<String?>(
                  value: _einsatzindikation,
                  isExpanded: true,
                  decoration: _inputDecoration.copyWith(
                    labelText: 'Einsatzindikation',
                    fillColor: (_einsatzindikation == null || (_einsatzindikation ?? '').trim().isEmpty)
                        ? _pflichtfeldGelb
                        : Colors.white,
                  ),
                  items: _einsatzindikationOptions
                      .map((e) => DropdownMenuItem<String?>(
                            value: e.$1,
                            child: Text(e.$2, overflow: TextOverflow.ellipsis, maxLines: 1),
                          ))
                      .toList(),
              onChanged: _canEdit ? (v) => setState(() => _einsatzindikation = v) : null,
            ),
          ],
        ),
      ),
    );
      },
    );
  }

  Widget _buildBemerkungenCardBearbeiten() {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Bemerkungen',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: Colors.grey.shade800,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _bemerkungenCtrl,
              readOnly: !_canEdit,
              maxLines: 5,
              decoration: _inputDecoration.copyWith(
                labelText: null,
                alignLabelWithHint: true,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _onStatusChanged(String mitarbeiterId, int? newStatus) async {
    if (newStatus != null) {
      try {
        final autoAbgeschlossen = await widget.service.setAlarmierterStatus(
          widget.companyId,
          widget.docId,
          mitarbeiterId,
          newStatus,
        );
        if (!mounted) return;
        setState(() => _alarmierteMitarbeiterStatus[mitarbeiterId] = newStatus);
        final statusMap = widget.einsatz['alarmierteMitarbeiterStatus'];
        final map = statusMap is Map ? statusMap : <String, dynamic>{};
        widget.einsatz['alarmierteMitarbeiterStatus'] = map;
        map[mitarbeiterId] = newStatus;
        final einsatzNeu = await widget.service.get(widget.companyId, widget.docId);
        if (mounted && einsatzNeu != null) setState(() => _einsatzData = einsatzNeu);
        if (autoAbgeschlossen && mounted) {
          widget.onEinsatzAbgeschlossen?.call();
          Navigator.of(context).pop();
        } else if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Status gespeichert und beim Mitarbeiter aktualisiert.')),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Fehler: $e'), backgroundColor: Colors.red),
          );
        }
      }
    } else {
      try {
        await widget.service.update(
          widget.companyId,
          widget.docId,
          {'alarmierteMitarbeiterStatus.$mitarbeiterId': FieldValue.delete()},
        );
        if (!mounted) return;
        setState(() => _alarmierteMitarbeiterStatus.remove(mitarbeiterId));
        final statusMap = widget.einsatz['alarmierteMitarbeiterStatus'];
        if (statusMap is Map) statusMap.remove(mitarbeiterId);
        final einsatzNeu = await widget.service.get(widget.companyId, widget.docId);
        if (mounted && einsatzNeu != null) setState(() => _einsatzData = einsatzNeu);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Status entfernt.')),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Fehler: $e'), backgroundColor: Colors.red),
          );
        }
      }
    }
  }

  Future<void> _showEmSuchenSheetBearbeiten() async {
    final selected = Set<String>.from(_selectedIds);
    final result = await showDialog<Set<String>>(
      context: context,
      builder: (ctx) => _EmSuchenDialog(
        mitarbeiter: _alleMitarbeiter,
        verfuegbare: _verfuegbareMitarbeiter,
        initialSelected: selected,
        onZuteilen: () => Navigator.of(ctx).pop(selected),
        onAbbrechen: () => Navigator.of(ctx).pop(),
      ),
    );
    if (result != null && mounted) setState(() => _selectedIds
      ..clear()
      ..addAll(result));
  }

  Widget _buildZuordnungEinsatzmittelCard() {
    final verfuegbareIds = _verfuegbareMitarbeiter.map((m) => m['id'] as String? ?? '').where((s) => s.isNotEmpty).toSet();
    final zugeordnet = _selectedIds.map((id) {
      for (final m in _verfuegbareMitarbeiter) {
        if ((m['id'] as String? ?? '') == id) return m;
      }
      for (final m in _alleMitarbeiter) {
        if ((m['id'] as String? ?? '') == id) return m;
      }
      return <String, dynamic>{'id': id, 'displayName': 'Unbekannt'};
    }).toList();
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Alarmierte Mitarbeiter',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Colors.grey.shade800),
            ),
            const SizedBox(height: 12),
            if (zugeordnet.isEmpty)
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.grey.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.grey.shade200),
                ),
                child: Text(
                  'Keine Kräfte zugeordnet. Tippen Sie auf „weitere Mitarbeiter alarmieren“ um Mitglieder hinzuzufügen.',
                  style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
                ),
              )
            else
              LayoutBuilder(
                builder: (context, listConstraints) {
                  final narrow = listConstraints.maxWidth < 400;
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: zugeordnet.map((m) {
                      final id = m['id'] as String? ?? '';
                      final name = m['displayName'] as String? ?? '${m['vorname']} ${m['nachname']}';
                      final typName = (m['typName'] ?? '').toString().trim();
                      final typColor = m['typColor'] as int?;
                      final isVerfuegbar = verfuegbareIds.contains(id);
                      final schichtColor = isVerfuegbar && typName.isNotEmpty
                          ? SchichtplanNfsBereitschaftstypUtils.colorForTypData(typColor: typColor, typName: typName)
                          : Colors.grey;
                      final typBadge = typName.isNotEmpty
                          ? Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: schichtColor.withOpacity(0.25),
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(color: schichtColor.withOpacity(0.6)),
                              ),
                              child: Text(typName, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: schichtColor), overflow: TextOverflow.ellipsis),
                            )
                          : const SizedBox.shrink();
                      final removeBtn = IconButton(
                        icon: const Icon(Icons.remove_circle_outline, size: 20),
                        iconSize: 20,
                        style: IconButton.styleFrom(
                          minimumSize: const Size(36, 36),
                          padding: EdgeInsets.zero,
                        ),
                        color: Colors.red.shade400,
                        onPressed: _canEdit
                            ? () {
                                setState(() {
                                  _selectedIds.remove(id);
                                  _alarmierteMitarbeiterStatus.remove(id);
                                });
                              }
                            : null,
                      );
                      if (narrow) {
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Icon(Icons.person_outline, size: 20, color: Colors.grey.shade600),
                                  const SizedBox(width: 8),
                                  Expanded(child: Text(name, overflow: TextOverflow.ellipsis)),
                                  removeBtn,
                                ],
                              ),
                              if (typName.isNotEmpty) ...[
                                const SizedBox(height: 6),
                                Align(
                                  alignment: Alignment.centerLeft,
                                  child: ConstrainedBox(
                                    constraints: BoxConstraints(maxWidth: listConstraints.maxWidth - 60),
                                    child: typBadge,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        );
                      }
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Row(
                          children: [
                            Icon(Icons.person_outline, size: 20, color: Colors.grey.shade600),
                            const SizedBox(width: 8),
                            Flexible(
                              child: Text(name, overflow: TextOverflow.ellipsis),
                            ),
                            const SizedBox(width: 6),
                            Flexible(child: typBadge),
                            const SizedBox(width: 6),
                            removeBtn,
                          ],
                        ),
                      );
                    }).toList(),
                  );
                },
              ),
            if (_canEdit) ...[
              const SizedBox(height: 12),
              LayoutBuilder(
                builder: (context, constraints) {
                  final narrow = constraints.maxWidth < 400;
                  if (narrow) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        OutlinedButton.icon(
                          onPressed: _showEmSuchenSheetBearbeiten,
                          icon: const Icon(Icons.search, size: 20),
                          label: const Text('weitere Mitarbeiter alarmieren'),
                          style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 12), alignment: Alignment.centerLeft),
                        ),
                        const SizedBox(height: 8),
                        FilledButton.icon(
                          onPressed: _showEmSuchenSheetBearbeiten,
                          icon: const Icon(Icons.add, size: 20),
                          label: const Text('Zuteilen'),
                          style: FilledButton.styleFrom(backgroundColor: AppTheme.primary, padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12)),
                        ),
                      ],
                    );
                  }
                  return Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _showEmSuchenSheetBearbeiten,
                          icon: const Icon(Icons.search, size: 20),
                          label: const Text('weitere Mitarbeiter alarmieren'),
                          style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 12), alignment: Alignment.centerLeft),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Flexible(
                        child: FilledButton.icon(
                          onPressed: _showEmSuchenSheetBearbeiten,
                          icon: const Icon(Icons.add, size: 20),
                          label: const Text('Zuteilen'),
                          style: FilledButton.styleFrom(backgroundColor: AppTheme.primary, padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12)),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildMassnahmenCardBearbeiten() {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Text(
                  'Maßnahmen',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Colors.grey.shade800),
                ),
                const Spacer(),
                if (_canEdit)
                  IconButton.filled(
                    onPressed: _showAddMassnahmeDialog,
                    icon: const Icon(Icons.add, size: 20),
                    style: IconButton.styleFrom(backgroundColor: Colors.green.shade600, foregroundColor: Colors.white),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Container(
              constraints: const BoxConstraints(maxHeight: 240),
              decoration: BoxDecoration(
                color: Colors.grey.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.grey.shade300),
              ),
              child: _massnahmen.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(
                        'Keine Maßnahmen eingetragen.',
                        style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
                      ),
                    )
                  : Builder(
                      builder: (context) {
                        final sorted = _massnahmen.toList()
                          ..sort((a, b) => ((b['datumUhrzeit'] ?? '').toString()).compareTo((a['datumUhrzeit'] ?? '').toString()));
                        return ListView.builder(
                          shrinkWrap: true,
                          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
                          itemCount: sorted.length,
                          itemBuilder: (context, i) {
                            final e = sorted[i];
                        final eintrag = (e['eintrag'] ?? '').toString();
                        return InkWell(
                          onTap: () => _showEintragDialog(
                            title: 'Maßnahme',
                            datumUhrzeit: (e['datumUhrzeit'] ?? '').toString(),
                            benutzer: (e['benutzer'] ?? '').toString(),
                            eintrag: eintrag,
                          ),
                          borderRadius: BorderRadius.circular(8),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                SizedBox(
                                  width: 55,
                                  child: Text(
                                    _timeFromDatumUhrzeit((e['datumUhrzeit'] ?? '').toString()),
                                    style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                SizedBox(
                                  width: 100,
                                  child: Text(
                                    (e['benutzer'] ?? '').toString(),
                                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    eintrag,
                                    style: const TextStyle(fontSize: 13),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                Icon(Icons.open_in_new, size: 16, color: Colors.grey.shade500),
                              ],
                            ),
                          ),
                        );
                          },
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showAddMassnahmeDialog() async {
    final ctrl = TextEditingController();
    final now = DateTime.now();
    final zeitstempel = '${now.day.toString().padLeft(2, '0')}.${now.month.toString().padLeft(2, '0')}.${now.year} '
        '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}:${now.second.toString().padLeft(2, '0')}';
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Maßnahme hinzufügen'),
        content: SizedBox(
          width: 400,
          height: 320,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Datum/Uhrzeit: $zeitstempel',
                style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: ctrl,
                decoration: const InputDecoration(
                  labelText: 'Was wurde getroffen?',
                  hintText: 'z.B. Polizei informiert',
                  border: OutlineInputBorder(),
                ),
                maxLines: 3,
                autofocus: true,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Abbrechen')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Hinzufügen'),
          ),
        ],
      ),
    );
    if (result == true && ctrl.text.trim().isNotEmpty && mounted) {
      final eintrag = ctrl.text.trim();
      final benutzer = _currentUserName ?? 'Unbekannt';
      final now = DateTime.now();
      final datumUhrzeit =
          '${now.day.toString().padLeft(2, '0')}.${now.month.toString().padLeft(2, '0')}.${now.year} '
          '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}:${now.second.toString().padLeft(2, '0')}';
      final newEntry = {
        'datumUhrzeit': datumUhrzeit,
        'benutzer': benutzer,
        'eintrag': eintrag,
      };
      setState(() => _massnahmen.add(newEntry));
      try {
        await widget.service.addMassnahme(
          widget.companyId,
          widget.docId,
          benutzer: benutzer,
          eintrag: eintrag,
        );
      } catch (e) {
        if (mounted) {
          setState(() => _massnahmen.removeLast());
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Speichern fehlgeschlagen: $e'), backgroundColor: Colors.red),
          );
        }
      }
    }
  }

  Widget _buildRueckmeldungenCardBearbeiten() {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Text(
                  'Rückmeldungen',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Colors.grey.shade800),
                ),
                const Spacer(),
                if (_canEdit)
                  IconButton.filled(
                    onPressed: _showAddRueckmeldungDialog,
                    icon: const Icon(Icons.add, size: 20),
                    style: IconButton.styleFrom(backgroundColor: Colors.green.shade600, foregroundColor: Colors.white),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Container(
              constraints: const BoxConstraints(maxHeight: 240),
              decoration: BoxDecoration(
                color: Colors.grey.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.grey.shade300),
              ),
              child: _rueckmeldungen.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(
                        'Keine Rückmeldungen eingetragen.',
                        style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
                      ),
                    )
                  : Builder(
                      builder: (context) {
                        final sorted = _rueckmeldungen.toList()
                          ..sort((a, b) => ((b['datumUhrzeit'] ?? '').toString()).compareTo((a['datumUhrzeit'] ?? '').toString()));
                        return ListView.builder(
                          shrinkWrap: true,
                          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
                          itemCount: sorted.length,
                          itemBuilder: (context, i) {
                            final e = sorted[i];
                        final eintrag = (e['eintrag'] ?? '').toString();
                        return InkWell(
                          onTap: () => _showEintragDialog(
                            title: 'Rückmeldung',
                            datumUhrzeit: (e['datumUhrzeit'] ?? '').toString(),
                            benutzer: (e['mitarbeiterName'] ?? '').toString(),
                            eintrag: eintrag,
                          ),
                          borderRadius: BorderRadius.circular(8),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                SizedBox(
                                  width: 55,
                                  child: Text(
                                    _timeFromDatumUhrzeit((e['datumUhrzeit'] ?? '').toString()),
                                    style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                SizedBox(
                                  width: 100,
                                  child: Text(
                                    (e['mitarbeiterName'] ?? '').toString(),
                                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    eintrag,
                                    style: const TextStyle(fontSize: 13),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                Icon(Icons.open_in_new, size: 16, color: Colors.grey.shade500),
                              ],
                            ),
                          ),
                        );
                          },
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  void _showEintragDialog({
    required String title,
    required String datumUhrzeit,
    required String benutzer,
    required String eintrag,
  }) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: SizedBox(
          width: 400,
          height: 320,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  datumUhrzeit,
                  style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
                ),
                if (benutzer.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    benutzer,
                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                  ),
                ],
                const SizedBox(height: 12),
                Text(
                  eintrag,
                  style: const TextStyle(fontSize: 15),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Schließen'),
          ),
        ],
      ),
    );
  }

  Future<void> _showAddRueckmeldungDialog() async {
    if (_selectedIds.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Bitte zuerst mindestens einen Mitarbeiter zuordnen.')),
      );
      return;
    }
    final selected = <String?>[null, null]; // [id, name]
    final ctrl = TextEditingController();
    final now = DateTime.now();
    final zeitstempel = '${now.day.toString().padLeft(2, '0')}.${now.month.toString().padLeft(2, '0')}.${now.year} '
        '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}:${now.second.toString().padLeft(2, '0')}';
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          return AlertDialog(
            title: const Text('Rückmeldung hinzufügen'),
            content: SizedBox(
              width: 400,
              height: 320,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Datum/Uhrzeit: $zeitstempel',
                    style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<String>(
                  value: selected[0],
                  decoration: const InputDecoration(labelText: 'Einsatzmittel'),
                  items: _selectedIds.map((id) {
                    String name = 'Unbekannt';
                    for (final m in _alleMitarbeiter) {
                      if ((m['id'] as String? ?? '') == id) {
                        name = m['displayName'] as String? ?? '${m['vorname']} ${m['nachname']}';
                        break;
                      }
                    }
                    return DropdownMenuItem(value: id, child: Text(name));
                  }).toList(),
                  onChanged: (v) {
                    String? name;
                    for (final m in _alleMitarbeiter) {
                      if ((m['id'] as String? ?? '') == v) {
                        name = m['displayName'] as String? ?? '${m['vorname']} ${m['nachname']}';
                        break;
                      }
                    }
                    selected[0] = v;
                    selected[1] = name;
                    setDialogState(() {});
                  },
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: ctrl,
                  decoration: const InputDecoration(
                    labelText: 'Eintrag',
                    hintText: 'z.B. keine weiteren Kräfte',
                    border: OutlineInputBorder(),
                  ),
                  maxLines: 2,
                  onChanged: (_) => setDialogState(() {}),
                ),
              ],
            ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Abbrechen')),
              FilledButton(
                onPressed: selected[0] == null || ctrl.text.trim().isEmpty
                    ? null
                    : () => Navigator.pop(ctx, true),
                child: const Text('Hinzufügen'),
              ),
            ],
          );
        },
      ),
    );
    if (result == true && selected[0] != null && selected[1] != null && ctrl.text.trim().isNotEmpty && mounted) {
      final eintrag = ctrl.text.trim();
      final mitarbeiterId = selected[0]!;
      final mitarbeiterName = selected[1]!;
      final now = DateTime.now();
      final datumUhrzeit =
          '${now.day.toString().padLeft(2, '0')}.${now.month.toString().padLeft(2, '0')}.${now.year} '
          '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}:${now.second.toString().padLeft(2, '0')}';
      final newEntry = {
        'datumUhrzeit': datumUhrzeit,
        'mitarbeiterId': mitarbeiterId,
        'mitarbeiterName': mitarbeiterName,
        'eintrag': eintrag,
      };
      setState(() => _rueckmeldungen.add(newEntry));
      try {
        await widget.service.addRueckmeldung(
          widget.companyId,
          widget.docId,
          mitarbeiterId: mitarbeiterId,
          mitarbeiterName: mitarbeiterName,
          eintrag: eintrag,
        );
      } catch (e) {
        if (mounted) {
          setState(() => _rueckmeldungen.removeLast());
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Speichern fehlgeschlagen: $e'), backgroundColor: Colors.red),
          );
        }
      }
    }
  }

  static Color _statusColor(int status) {
    switch (status) {
      case 3: return Colors.amber.shade700;   // Einsatz übernommen - gelb
      case 4: return Colors.red.shade700;    // Am Einsatzort - hellrot
      case 7: return Colors.deepPurple.shade700; // Einsatzstelle verlassen - violett
      case 2: return Colors.green.shade700;  // Einsatz beendet - grün
      default: return Colors.grey.shade600;
    }
  }

  Widget _buildStatusCard() {
    final einsatz = _einsatzData ?? widget.einsatz;
    final zeitenMap = einsatz['alarmierteMitarbeiterZeiten'];
    final zeiten = zeitenMap is Map ? zeitenMap as Map : <String, dynamic>{};
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Status der eingesetzten Kräfte',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: Colors.grey.shade800,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _lastStatusUpdateTime != null
                  ? 'Live (aktualisiert: ${_formatDate(_lastStatusUpdateTime!)}, ${_lastStatusUpdateTime!.hour.toString().padLeft(2, '0')}:${_lastStatusUpdateTime!.minute.toString().padLeft(2, '0')})'
                  : 'Aktueller Einsatzstatus (Stand: ${_formatDate(_einsatzDatum ?? DateTime.now())}, ${_formatTime(_uhrzeitBeginn ?? TimeOfDay.now())})',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
            ),
            const SizedBox(height: 16),
            ..._selectedIds.map((id) {
              String name = 'Unbekannt';
              for (final x in _alleMitarbeiter) {
                if ((x['id'] as String? ?? '') == id) {
                  name = x['displayName'] as String? ?? '${x['vorname']} ${x['nachname']}';
                  break;
                }
              }
              final status = _alarmierteMitarbeiterStatus[id];
              final label = status != null ? (AlarmierungNfsService.statusLabels[status] ?? 'Status $status') : '–';
              final color = status != null ? _statusColor(status) : Colors.grey;
              final z = zeiten[id];
              final zeitStr = z is Map
                  ? _zeitFromZeiten(z, status)
                  : '';
              final badge = zeitStr.isNotEmpty ? '$label ($zeitStr)' : label;
              final zeitenMap = z is Map ? z as Map<String, dynamic> : <String, dynamic>{};
              return _buildStatusRow(id, name, badge, color, zeitenMap);
            }),
          ],
        ),
      ),
    );
  }

  String _zeitFromZeiten(Map z, int? status) {
    if (status == 3) return (z['uhrzeitEinsatzUebernommen'] ?? '').toString();
    if (status == 4) return (z['uhrzeitAnEinsatzort'] ?? '').toString();
    if (status == 7) return (z['uhrzeitAbfahrt'] ?? '').toString();
    if (status == 2) return (z['uhrzeitZuHause'] ?? '').toString();
    return '';
  }

  Widget _buildStatusRow(String mitarbeiterId, String name, String badge, Color color, Map<String, dynamic> zeitenMap) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        onTap: () => _canEdit
            ? _showStatusBearbeitenDialog(mitarbeiterId, name, zeitenMap)
            : _showStatusZeitenDialog(name, zeitenMap),
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
          child: Row(
            children: [
              Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(
                  color: color.withOpacity(0.25),
                  shape: BoxShape.circle,
                  border: Border.all(color: color.withOpacity(0.6), width: 1),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(child: Text(name)),
              if (badge.isNotEmpty)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.25),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: color.withOpacity(0.6), width: 1),
                  ),
                  child: Text(
                    badge,
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: color),
                  ),
                ),
              const SizedBox(width: 4),
              Icon(Icons.info_outline, size: 18, color: Colors.grey.shade600),
            ],
          ),
        ),
      ),
    );
  }

  void _showStatusBearbeitenDialog(String mitarbeiterId, String mitarbeiterName, Map<String, dynamic> zeiten) {
    final currentStatus = _alarmierteMitarbeiterStatus[mitarbeiterId];
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Status setzen: $mitarbeiterName'),
        content: SizedBox(
          width: 400,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'Status und Zeitstempel werden gespeichert. Die Einsatzkraft sieht die Änderung sofort.',
                  style: TextStyle(fontSize: 13, color: Colors.grey),
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<int?>(
                  value: currentStatus,
                  decoration: const InputDecoration(
                    labelText: 'Status',
                    border: OutlineInputBorder(),
                  ),
                  items: const [
                    DropdownMenuItem(value: null, child: Text('– Kein Status')),
                    DropdownMenuItem(value: 3, child: Text('3 – Einsatz übernommen')),
                    DropdownMenuItem(value: 4, child: Text('4 – Am Einsatzort')),
                    DropdownMenuItem(value: 7, child: Text('7 – Einsatzstelle verlassen')),
                    DropdownMenuItem(value: 2, child: Text('2 – Einsatz beendet')),
                  ],
                  onChanged: (v) async {
                    Navigator.of(ctx).pop();
                    if (v != null) await _onStatusChanged(mitarbeiterId, v);
                  },
                ),
                const SizedBox(height: 16),
                Text('Bereits gespeicherte Zeiten:', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.grey.shade700)),
                const SizedBox(height: 8),
                ..._statusZeitenRows(zeiten),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Schließen'),
          ),
        ],
      ),
    );
  }

  List<Widget> _statusZeitenRows(Map<String, dynamic> zeiten) {
    final labels = {
      'uhrzeitEinsatzUebernommen': 'Einsatz übernommen',
      'uhrzeitAnEinsatzort': 'Am Einsatzort',
      'uhrzeitAbfahrt': 'Einsatzstelle verlassen',
      'uhrzeitZuHause': 'Einsatz beendet',
    };
    final rows = <Widget>[];
    for (final e in labels.entries) {
      final val = zeiten[e.key];
      if (val != null && val.toString().trim().isNotEmpty) {
        rows.add(Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(e.value, style: TextStyle(fontSize: 13, color: Colors.grey.shade700)),
              Text(val.toString(), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
            ],
          ),
        ));
      }
    }
    if (rows.isEmpty) {
      rows.add(Text('Keine Statuszeiten gespeichert.', style: TextStyle(fontSize: 13, color: Colors.grey.shade600)));
    }
    return rows;
  }

  void _showStatusZeitenDialog(String mitarbeiterName, Map<String, dynamic> zeiten) {
    final rows = _statusZeitenRows(zeiten);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Statuszeiten: $mitarbeiterName'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: rows,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Schließen'),
          ),
        ],
      ),
    );
  }
}
