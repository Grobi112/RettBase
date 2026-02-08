import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../models/fahrtenbuch_vorlage.dart';
import '../services/schichtanmeldung_service.dart';
import '../services/auth_service.dart';
import '../services/fahrtenbuch_service.dart';

/// Tätigkeit-Optionen für Dropdown
const _taetigkeitOptions = ['hauptamtlich', 'nebenamtlich', 'honorar'];

/// Schichtanmeldung – Formular wie in der Webversion
class SchichtanmeldungScreen extends StatefulWidget {
  final String companyId;
  final VoidCallback onBack;
  final void Function(FahrtenbuchVorlage vorlage)? onFahrtenbuchOpen;
  final bool hideAppBar;

  const SchichtanmeldungScreen({
    required this.companyId,
    required this.onBack,
    this.onFahrtenbuchOpen,
    this.hideAppBar = false,
  });

  @override
  State<SchichtanmeldungScreen> createState() => _SchichtanmeldungScreenState();
}

class _SchichtanmeldungScreenState extends State<SchichtanmeldungScreen> {
  final _service = SchichtanmeldungService();
  final _authService = AuthService();
  final _fahrtenbuchService = FahrtenbuchService();
  final _bemerkungController = TextEditingController();

  SchichtplanMitarbeiter? _mitarbeiter;
  SchichtanmeldungEintrag? _aktiveSchichtanmeldung;
  List<Standort> _standorte = [];
  List<SchichtTyp> _allSchichten = [];
  List<FahrzeugKurz> _allFahrzeuge = [];

  String? _wacheId;
  String? _schichtId;
  String _fahrzeugId = 'alle';
  String _taetigkeit = 'hauptamtlich';
  bool _isFahrer = true; // true = Fahrer, false = Beifahrer
  DateTime _selectedDate = DateTime.now();

  bool _loading = true;
  bool _saving = false;
  String? _error;

  String get _dayId =>
      '${_selectedDate.day.toString().padLeft(2, '0')}.${_selectedDate.month.toString().padLeft(2, '0')}.${_selectedDate.year}';

  Future<FahrtenbuchVorlage?> _buildFahrtenbuchVorlage(SchichtanmeldungEintrag e) async {
    DateTime datumTag;
    try {
      final p = e.datum.split('.');
      if (p.length != 3) return null;
      datumTag = DateTime(int.parse(p[2]), int.parse(p[1]), int.parse(p[0]));
    } catch (_) {
      datumTag = _selectedDate;
    }
    final mitarbeiterList = await _service.loadSchichtplanMitarbeiter(widget.companyId);
    final mitarbeiterMap = {for (final m in mitarbeiterList) m.id: m};
    String mitarbeiterName(String id) {
      final m = mitarbeiterMap[id];
      return m?.displayName ?? id;
    }
    final alleFuerSchicht = await _service.loadSchichtanmeldungenForDateRange(
      widget.companyId,
      datumTag,
      datumTag,
    );
    final gruppe = alleFuerSchicht
        .where((a) =>
            a.datum == e.datum &&
            a.wacheId == e.wacheId &&
            a.schichtId == e.schichtId &&
            a.fahrzeugId == e.fahrzeugId)
        .toList();
    final fahrer = gruppe.where((a) => a.rolle == 'fahrer').toList();
    final beifahrer = gruppe.where((a) => a.rolle != 'fahrer').toList();
    String? nameFahrer = fahrer.isNotEmpty ? mitarbeiterName(fahrer.first.mitarbeiterId) : null;
    String? nameBeifahrer = beifahrer.isNotEmpty ? mitarbeiterName(beifahrer.first.mitarbeiterId) : null;
    final fahrerNamen = fahrer.map((a) => mitarbeiterName(a.mitarbeiterId)).where((n) => n != '–' && n.isNotEmpty).toSet().toList();
    final beifahrerNamen = beifahrer.map((a) => mitarbeiterName(a.mitarbeiterId)).where((n) => n != '–' && n.isNotEmpty).toSet().toList();
    final fahrzeugKurz = _allFahrzeuge.where((f) => f.id == e.fahrzeugId).firstOrNull;
    final rufname = fahrzeugKurz?.displayName ?? e.fahrzeugId;
    var kennzeichen = fahrzeugKurz?.kennzeichen;
    if (kennzeichen == null || kennzeichen!.isEmpty) {
      try {
        final fleetFz = await _fahrtenbuchService.loadFahrzeuge(widget.companyId);
        final ff = fleetFz.where((f) => f.id == e.fahrzeugId).firstOrNull;
        kennzeichen = ff?.kennzeichen;
      } catch (_) {}
    }
    final kmAnfang = await _fahrtenbuchService.getLetzterKmEnde(widget.companyId, rufname);
    return FahrtenbuchVorlage(
      fahrzeugId: e.fahrzeugId,
      fahrzeugRufname: rufname,
      kennzeichen: kennzeichen,
      nameFahrer: nameFahrer,
      nameBeifahrer: nameBeifahrer,
      kmAnfang: kmAnfang,
      datum: datumTag,
      fahrerOptionen: fahrerNamen,
      beifahrerOptionen: beifahrerNamen,
    );
  }

  /// Schichten, die dem gewählten Standort zugeordnet sind
  List<SchichtTyp> get _schichtenFuerWache {
    if (_wacheId == null || _wacheId!.isEmpty) return [];
    return _allSchichten.where((s) => s.standortId == _wacheId).toList();
  }

  /// Fahrzeuge, die dem gewählten Standort zugeordnet sind
  List<FahrzeugKurz> get _fahrzeugeFuerWache {
    if (_wacheId == null || _wacheId!.isEmpty) return [];
    final standort = _standorte.where((s) => s.id == _wacheId).firstOrNull;
    final standortId = standort?.id ?? '';
    final standortName = standort?.name ?? '';
    final list = <FahrzeugKurz>[];
    for (final f in _allFahrzeuge) {
      if (f.id == 'alle') continue;
      final w = (f.wache ?? '').trim();
      if (w.isEmpty) continue;
      if (w == standortId || w == standortName) list.add(f);
    }
    return list;
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _bemerkungController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final user = _authService.currentUser;
      final email = user?.email ?? '';
      final uid = user?.uid ?? '';

      final standorte = await _service.loadStandorte(widget.companyId);
      final schichten = await _service.loadSchichten(widget.companyId);
      final fahrzeuge = await _service.loadFahrzeuge(widget.companyId);

      SchichtplanMitarbeiter? mitarbeiter;
      if (email.isNotEmpty) {
        mitarbeiter = await _service.findMitarbeiterByEmail(widget.companyId, email);
      }
      if (mitarbeiter == null && uid.isNotEmpty) {
        mitarbeiter = await _service.findMitarbeiterByUid(widget.companyId, uid);
      }

      SchichtanmeldungEintrag? aktiveSchicht;
      if (mitarbeiter != null) {
        aktiveSchicht = await _service.getAktiveSchichtanmeldung(widget.companyId, mitarbeiter.id);
      }

      if (mounted) {
        setState(() {
          _standorte = standorte;
          _allSchichten = schichten;
          _allFahrzeuge = fahrzeuge;
          _mitarbeiter = mitarbeiter;
          _aktiveSchichtanmeldung = aktiveSchicht;
          _wacheId = null;
          _schichtId = null;
          _fahrzeugId = '';
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _loading = false;
        });
      }
    }
  }

  Future<void> _erfassen() async {
    if (_mitarbeiter == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Keine Mitarbeiter-Zuordnung gefunden.')),
      );
      return;
    }
    if (_wacheId == null || _wacheId!.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Bitte Wache auswählen.')),
      );
      return;
    }
    if (_schichtId == null || _schichtId!.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Bitte Schicht auswählen.')),
      );
      return;
    }
    setState(() => _saving = true);
    try {
      final e = SchichtanmeldungEintrag(
        id: '',
        mitarbeiterId: _mitarbeiter!.id,
        wacheId: _wacheId!,
        schichtId: _schichtId!,
        fahrzeugId: _fahrzeugId.isEmpty ? 'alle' : _fahrzeugId,
        taetigkeit: _taetigkeit,
        bereitschaftszeitMin: null,
        rolle: _isFahrer ? 'fahrer' : 'beifahrer',
        datum: _dayId,
        bemerkung: _bemerkungController.text.trim().isEmpty ? null : _bemerkungController.text.trim(),
      );
      await _service.saveSchichtanmeldung(widget.companyId, e);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Schichtanmeldung erfasst.')),
        );
        _bemerkungController.clear();
        final aktiveSchicht = await _service.getAktiveSchichtanmeldung(widget.companyId, _mitarbeiter!.id);
        setState(() {
          _schichtId = null;
          _aktiveSchichtanmeldung = aktiveSchicht;
          _saving = false;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Fehler: $e')),
        );
        setState(() => _saving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final scaffold = Scaffold(
      backgroundColor: AppTheme.surfaceBg,
      appBar: AppTheme.buildModuleAppBar(
        title: 'Schichtanmeldung',
        onBack: widget.onBack,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _mitarbeiter == null
              ? _buildNichtZugeordnet()
              : _buildForm(),
    );
    if (widget.hideAppBar) {
      return PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) widget.onBack();
        },
        child: scaffold,
      );
    }
    return scaffold;
  }

  Widget _buildNichtZugeordnet() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.person_off, size: 64, color: Colors.grey[400]),
            const SizedBox(height: 16),
            Text(
              'Keine Zuordnung gefunden',
              style: Theme.of(context).textTheme.titleLarge,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            Text(
              'Ihr Benutzer konnte keinem Mitarbeiter im Schichtplan zugeordnet werden. '
              'Bitte wenden Sie sich an Ihren Administrator.',
              style: TextStyle(color: Colors.grey[600]),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  String? _formatEndzeit(SchichtanmeldungEintrag e) {
    final schicht = _allSchichten.where((s) => s.id == e.schichtId).firstOrNull;
    if (schicht == null || schicht.endTime == null || schicht.endTime!.isEmpty) return null;
    final parts = e.datum.split('.');
    if (parts.length != 3) return null;
    DateTime tag;
    try {
      tag = DateTime(int.parse(parts[2]), int.parse(parts[1]), int.parse(parts[0]));
    } catch (_) {
      return null;
    }
    final ep = schicht.endTime!.split(':');
    if (ep.length < 2) return null;
    final endMin = (int.tryParse(ep[0]) ?? 0) * 60 + (int.tryParse(ep[1]) ?? 0);
    final endDate = schicht.endetFolgetag
        ? tag.add(const Duration(days: 1)).add(Duration(minutes: endMin))
        : tag.add(Duration(minutes: endMin));
    final d = endDate.day.toString().padLeft(2, '0');
    final m = endDate.month.toString().padLeft(2, '0');
    final h = endDate.hour.toString().padLeft(2, '0');
    final min = endDate.minute.toString().padLeft(2, '0');
    return '$d.$m. ${h}:$min Uhr';
  }

  Widget _buildAktiveSchichtBanner() {
    final e = _aktiveSchichtanmeldung!;
    final schicht = _allSchichten.where((s) => s.id == e.schichtId).firstOrNull;
    final schichtName = schicht?.name ?? e.schichtId;
    final endzeit = _formatEndzeit(e);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.green.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.green.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(Icons.schedule, color: Colors.green.shade700, size: 28),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'In Schicht aktiv',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: Colors.green.shade900,
                        fontSize: 15,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      endzeit != null
                          ? '$schichtName – endet $endzeit'
                          : schichtName,
                      style: TextStyle(color: Colors.green.shade800, fontSize: 13),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Sie bleiben bis zur Endzeit aktiv, auch wenn Sie die App schließen oder abmelden.',
                      style: TextStyle(color: Colors.green.shade700, fontSize: 12),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (widget.onFahrtenbuchOpen != null) ...[
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: () async {
                  final vorlage = await _buildFahrtenbuchVorlage(e);
                  if (vorlage != null && mounted) {
                    widget.onFahrtenbuchOpen!(vorlage);
                  }
                },
                icon: const Icon(Icons.add_road, size: 20),
                label: const Text('Neuer Fahrtenbucheintrag'),
                style: FilledButton.styleFrom(
                  backgroundColor: AppTheme.primary,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildForm() {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        if (_aktiveSchichtanmeldung != null) ...[
          _buildAktiveSchichtBanner(),
          const SizedBox(height: 16),
        ],
        if (_error != null) ...[
          Container(
            padding: const EdgeInsets.all(12),
            margin: const EdgeInsets.only(bottom: 16),
            decoration: BoxDecoration(
              color: Colors.red.shade50,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(_error!, style: TextStyle(color: Colors.red.shade800)),
          ),
        ],
        _buildDropdown<String>(
          labelText: 'Wache',
          value: _wacheId,
          items: _standorte.map((s) => DropdownMenuItem(value: s.id, child: Text(s.name))).toList(),
          onChanged: (v) => setState(() {
            _wacheId = v;
            _schichtId = null;
            final fw = _fahrzeugeFuerWache;
            if (!fw.any((f) => f.id == _fahrzeugId)) _fahrzeugId = '';
          }),
          hint: 'bitte wählen',
        ),
        const SizedBox(height: 16),
        _buildDropdown<String>(
          labelText: 'Schicht',
          value: _schichtId,
          items: _schichtenFuerWache.map((s) => DropdownMenuItem(value: s.id, child: Text(s.name))).toList(),
          onChanged: (v) => setState(() => _schichtId = v),
          hint: 'bitte wählen',
        ),
        const SizedBox(height: 16),
        _buildDropdown<String>(
          labelText: 'Fahrzeug',
          value: _fahrzeugId.isEmpty ? null : _fahrzeugId,
          items: _fahrzeugeFuerWache.map((f) => DropdownMenuItem(value: f.id, child: Text(f.displayName))).toList(),
          onChanged: (v) => setState(() => _fahrzeugId = v ?? ''),
          hint: 'bitte wählen',
        ),
        const SizedBox(height: 16),
        _buildDropdown<String>(
          labelText: 'Tätigkeit',
          value: _taetigkeit,
          items: _taetigkeitOptions.map((t) => DropdownMenuItem(value: t, child: Text(t))).toList(),
          onChanged: (v) => setState(() => _taetigkeit = v ?? 'hauptamtlich'),
        ),
        const SizedBox(height: 16),
        InputDecorator(
          decoration: const InputDecoration(
            labelText: 'Rolle',
            border: OutlineInputBorder(),
            contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          ),
          isEmpty: false,
          child: Row(
            children: [
              Expanded(
                child: RadioListTile<bool>(
                  title: const Text('Fahrer'),
                  value: true,
                  groupValue: _isFahrer,
                  onChanged: (v) => setState(() => _isFahrer = v ?? true),
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                ),
              ),
              Expanded(
                child: RadioListTile<bool>(
                  title: const Text('Beifahrer'),
                  value: false,
                  groupValue: _isFahrer,
                  onChanged: (v) => setState(() => _isFahrer = v ?? false),
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        InkWell(
          onTap: () async {
            final d = await showDatePicker(
              context: context,
              initialDate: _selectedDate,
              firstDate: DateTime.now().subtract(const Duration(days: 365)),
              lastDate: DateTime.now().add(const Duration(days: 365)),
            );
            if (d != null && mounted) setState(() => _selectedDate = d);
          },
          child: InputDecorator(
            decoration: const InputDecoration(
              labelText: 'Datum',
              border: OutlineInputBorder(),
              suffixIcon: Icon(Icons.calendar_today),
              contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            ),
            child: Text(_dayId, style: const TextStyle(fontSize: 16)),
          ),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _bemerkungController,
          maxLines: 4,
          decoration: const InputDecoration(
            labelText: 'Bemerkung',
            hintText: 'Optionale Bemerkung',
            border: OutlineInputBorder(),
            contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            alignLabelWithHint: true,
          ),
        ),
        const SizedBox(height: 28),
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            onPressed: _saving ? null : _erfassen,
            style: FilledButton.styleFrom(
              backgroundColor: AppTheme.primary,
              padding: const EdgeInsets.symmetric(vertical: 16),
            ),
            child: _saving
                ? const SizedBox(
                    height: 24,
                    width: 24,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                : const Text('Erfassen'),
          ),
        ),
      ],
    );
  }

  Widget _buildDropdown<T>({
    required String labelText,
    required T? value,
    required List<DropdownMenuItem<T>> items,
    required ValueChanged<T?> onChanged,
    String? hint,
  }) {
    return DropdownButtonFormField<T>(
      value: value,
      decoration: InputDecoration(
        labelText: labelText,
        border: const OutlineInputBorder(),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      ),
      items: items,
      onChanged: onChanged,
      hint: hint != null ? Text(hint) : null,
    );
  }
}
