import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme/app_theme.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/checkliste_model.dart';
import '../models/checklisten_vorlage.dart';
import '../models/fleet_model.dart';
import '../services/checklisten_service.dart';
import '../services/auth_service.dart';
import '../services/auth_data_service.dart';
import '../services/schicht_status_service.dart';
import '../services/schichtanmeldung_service.dart';
import '../services/fahrtenbuch_service.dart';
import '../services/fleet_service.dart';
import '../services/mitarbeiter_service.dart';
import 'fahrzeugmangel_detail_screen.dart';

/// Checkliste ausfüllen und speichern
class ChecklisteAusfuellenScreen extends StatefulWidget {
  final String companyId;
  final Checkliste checkliste;
  final VoidCallback onBack;

  const ChecklisteAusfuellenScreen({
    super.key,
    required this.companyId,
    required this.checkliste,
    required this.onBack,
  });

  @override
  State<ChecklisteAusfuellenScreen> createState() => _ChecklisteAusfuellenScreenState();
}

class _ChecklisteAusfuellenScreenState extends State<ChecklisteAusfuellenScreen> {
  final _service = ChecklistenService();
  final _fleetService = FleetService();
  final _mitarbeiterService = MitarbeiterService();
  final _authService = AuthService();
  final _authDataService = AuthDataService();

  static const _mangelStatusOffen = ['offen', 'inbearbeitung'];
  final Map<String, dynamic> _values = {};
  final Map<String, TextEditingController> _textControllers = {};
  bool _saving = false;
  bool _loadingVorlage = true;
  Checkliste? _checklisteCache;
  ChecklistenVorlage? _vorlage;
  String? _fahrer;
  String? _beifahrer;
  String? _kennzeichen;
  String? _standort;
  String? _wachbuchSchicht;
  final _praktikantCtrl = TextEditingController();
  List<String> _alleMitarbeiterNamen = [];
  final _kmStandCtrl = TextEditingController();
  int? _lastKmFromFahrtenbuch;
  List<String> _fleetKennzeichenOptionen = [];

  Checkliste get _checkliste {
    _checklisteCache ??= widget.checkliste.ensureUniqueItemIds();
    return _checklisteCache!;
  }

  @override
  void initState() {
    super.initState();
    for (final item in _checkliste.items) {
      if (item.type == 'header') continue;
      if (item.type == 'checkbox') {
        _values[item.id] = false;
      } else if (item.type == 'slider') {
        _values[item.id] = false;
      } else {
        final ctrl = TextEditingController();
        _textControllers[item.id] = ctrl;
        _values[item.id] = '';
      }
    }
    _loadVorlage();
  }

  Future<void> _loadVorlage() async {
    try {
      final mitarbeiter = await _mitarbeiterService.loadMitarbeiter(widget.companyId);
      final namen = mitarbeiter.map((m) => m.displayName.trim()).where((n) => n.isNotEmpty).toSet().toList();
      namen.sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
      if (mounted) setState(() => _alleMitarbeiterNamen = namen);

      var aktiveSchicht = await SchichtStatusService().getAktiveSchicht(widget.companyId);
      if (aktiveSchicht == null && widget.companyId.trim().toLowerCase() != widget.companyId) {
        aktiveSchicht = await SchichtStatusService().getAktiveSchicht(widget.companyId.trim().toLowerCase());
      }
      if (aktiveSchicht != null) {
        final v = await SchichtanmeldungService().buildChecklistenVorlageFromAnmeldung(
          widget.companyId, aktiveSchicht, FahrtenbuchService());
        if (v != null && mounted) {
          setState(() {
            _vorlage = v;
            _fahrer = v.fahrer;
            _beifahrer = v.beifahrer;
            _praktikantCtrl.text = v.praktikantAzubi ?? '';
            _kennzeichen = v.kennzeichen;
            _standort = v.standort;
            _wachbuchSchicht = v.wachbuchSchicht;
          });
          _loadLetzterKm();
        }
      } else {
        try {
          final fz = await FahrtenbuchService().loadFahrzeuge(widget.companyId);
          final opts = <String>[];
          for (final f in fz) {
            final kz = (f.kennzeichen ?? '').trim();
            final ruf = (f.rufname ?? f.id ?? '').trim();
            if (kz.isNotEmpty && !opts.contains(kz)) opts.add(kz);
            if (ruf.isNotEmpty && !opts.contains(ruf)) opts.add(ruf);
          }
          opts.sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
          if (mounted) setState(() => _fleetKennzeichenOptionen = opts);
        } catch (_) {}
      }
    } catch (_) {}
    if (mounted) setState(() => _loadingVorlage = false);
  }

  @override
  void dispose() {
    _praktikantCtrl.dispose();
    _kmStandCtrl.dispose();
    for (final c in _textControllers.values) c.dispose();
    super.dispose();
  }

  int? get _parsedKmStand {
    final s = _kmStandCtrl.text.trim();
    if (s.isEmpty) return null;
    return int.tryParse(s);
  }

  Future<void> _loadLetzterKm() async {
    final kz = _kennzeichen?.trim();
    final ruf = _vorlage?.fahrzeugRufname?.trim();
    final fzId = _vorlage?.fahrzeugId?.trim();
    if ((kz == null || kz.isEmpty) && (ruf == null || ruf.isEmpty) && (fzId == null || fzId.isEmpty)) {
      if (mounted) setState(() => _lastKmFromFahrtenbuch = null);
      return;
    }
    try {
      final km = await FahrtenbuchService().getLetzterKmEndeByKennzeichenOderRufname(
        widget.companyId,
        kz?.isNotEmpty == true ? kz : null,
        fahrzeugRufnameAlternativ: ruf?.isNotEmpty == true && ruf != kz ? ruf : null,
        fahrzeugId: fzId?.isNotEmpty == true ? fzId : null,
      );
      if (mounted) setState(() => _lastKmFromFahrtenbuch = km);
    } catch (_) {
      if (mounted) setState(() => _lastKmFromFahrtenbuch = null);
    }
  }

  Future<void> _save() async {
    for (final e in _textControllers.entries) {
      _values[e.key] = e.value.text;
    }
    for (final s in _checkliste.sections) {
      for (final item in s.items) {
        if (!item.isRequired) continue;
        if (item.type == 'text') {
          final val = (_values[item.id] as String?)?.trim() ?? '';
          if (val.isEmpty) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Pflichtfeld „${item.label}" ist noch leer.')),
            );
            return;
          }
        } else if (item.type == 'checkbox' || item.type == 'slider') {
          if (!_toBool(_values[item.id])) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Pflichtfeld „${item.label}" muss bestätigt werden.')),
            );
            return;
          }
        }
      }
    }
    setState(() => _saving = true);
    try {
      final user = _authService.currentUser;
      final uid = user?.uid ?? '';
      String? userName;
      try {
        final authData = await _authDataService.getAuthData(uid, user?.email ?? '', widget.companyId);
        userName = authData.displayName;
      } catch (_) {}
      final kmStand = _parsedKmStand;
      List<Map<String, dynamic>>? maengelSnapshot;
      try {
        final all = await _fleetService.streamMaengel(widget.companyId).first;
        final offen = all.where((m) => _mangelStatusOffen.contains(m.status.toLowerCase())).toList();
        if (offen.isNotEmpty) {
          maengelSnapshot = offen.map((m) {
            final datum = m.datum ?? m.createdAt;
            return <String, dynamic>{
              'id': m.id,
              'betreff': m.betreff ?? '',
              'beschreibung': m.beschreibung,
              'datum': datum != null ? Timestamp.fromDate(datum) : null,
              'melderName': m.melderName ?? '',
              'status': m.status,
            };
          }).toList();
        }
      } catch (_) {}
      final a = ChecklisteAusfuellung(
        id: '',
        checklisteId: _checkliste.id,
        checklisteTitel: _checkliste.title,
        values: Map<String, dynamic>.from(_values),
        fahrer: _fahrer?.trim().isEmpty == true ? null : _fahrer,
        beifahrer: _beifahrer?.trim().isEmpty == true ? null : _beifahrer,
        praktikantAzubi: _praktikantCtrl.text.trim().isEmpty ? null : _praktikantCtrl.text.trim(),
        kennzeichen: _kennzeichen?.trim().isEmpty == true ? null : _kennzeichen,
        standort: _standort?.trim().isEmpty == true ? null : _standort,
        wachbuchSchicht: _wachbuchSchicht?.trim().isEmpty == true ? null : _wachbuchSchicht,
        kmStand: kmStand,
        maengelSnapshot: maengelSnapshot,
        createdAt: DateTime.now(),
        createdBy: uid,
        createdByName: userName,
      );
      await _service.saveAusfuellung(widget.companyId, a, uid, userName);

      // Wenn KM-Stand eingegeben und (vom Fahrtenbuch abweichend oder kein letzter KM): manuelle KM-Korrektur speichern
      final kz = _kennzeichen?.trim();
      final ruf = _vorlage?.fahrzeugRufname?.trim();
      final vehicleKey = (kz?.isNotEmpty == true ? kz : null) ?? (ruf?.isNotEmpty == true ? ruf : null);
      if (kmStand != null &&
          vehicleKey != null &&
          (kmStand != _lastKmFromFahrtenbuch || _lastKmFromFahrtenbuch == null)) {
        try {
          await FahrtenbuchService().createManuelleKmKorrektur(
            widget.companyId,
            kennzeichen: kz?.isNotEmpty == true ? kz : null,
            fahrzeugkennung: ruf?.isNotEmpty == true ? ruf : null,
            kmEnde: kmStand,
            kmAnfang: _lastKmFromFahrtenbuch,
            uid: uid,
            userName: userName,
          );
        } catch (e) {
          if (mounted) ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('KM-Korrektur konnte nicht gespeichert werden: $e')),
          );
        }
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Checkliste gespeichert.')));
        widget.onBack();
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Fehler: $e')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppTheme.buildModuleAppBar(
        title: _checkliste.title,
        onBack: widget.onBack,
        actions: [
          FilledButton.icon(
            onPressed: _saving ? null : _save,
            icon: _saving ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Icon(Icons.save, size: 20),
            label: Text(_saving ? 'Speichern…' : 'Speichern'),
            style: FilledButton.styleFrom(backgroundColor: AppTheme.primary),
          ),
          const SizedBox(width: 16),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _buildSchichtFelder(),
          const SizedBox(height: 24),
          ..._checkliste.sections.expand((s) => [
            Padding(
              padding: const EdgeInsets.only(top: 16, bottom: 8),
              child: Text(s.title, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: AppTheme.primary)),
            ),
            ...s.items.map((item) => _buildItem(item)),
          ]),
          const SizedBox(height: 24),
          _buildFahrzeugmangelCard(),
          const SizedBox(height: 24),
          _buildKmStandSection(),
        ],
      ),
    );
  }

  List<String> _safeStringList(List<String>? list) => list != null ? List<String>.from(list) : const [];

  List<String> get _kennzeichenOptionen {
    final vorlageOpts = _safeStringList(_vorlage?.kennzeichenOptionen);
    if (vorlageOpts.isNotEmpty) return vorlageOpts;
    return _fleetKennzeichenOptionen;
  }

  List<String> get _fahrerOptionen {
    final schicht = _safeStringList(_vorlage?.fahrerOptionen);
    final rest = _alleMitarbeiterNamen.where((n) => !schicht.contains(n)).toList();
    return [...schicht, ...rest];
  }

  List<String> get _beifahrerOptionen {
    final schicht = _safeStringList(_vorlage?.beifahrerOptionen);
    final rest = _alleMitarbeiterNamen.where((n) => n != 'Keiner' && !schicht.contains(n)).toList();
    return ['Keiner', ...schicht, ...rest];
  }

  bool _toBool(dynamic v) {
    if (v == null) return false;
    if (v is bool) return v;
    if (v is String) return v.toLowerCase() == 'true' || v == '1';
    if (v is num) return v != 0;
    return false;
  }

  Widget _buildSchichtFelder() {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Schicht-Daten', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Colors.grey[800])),
            const SizedBox(height: 12),
            _buildSearchableMitarbeiterDropdown('Fahrer', _fahrer, _fahrerOptionen, 'Bitte wählen', (v) => setState(() => _fahrer = v)),
            const SizedBox(height: 12),
            _buildSearchableMitarbeiterDropdown('Beifahrer', _beifahrer, _beifahrerOptionen, 'Keiner', (v) => setState(() => _beifahrer = v == 'Keiner' ? null : v)),
            const SizedBox(height: 12),
            TextFormField(
              controller: _praktikantCtrl,
              decoration: const InputDecoration(labelText: 'Praktikant / Azubi', hintText: 'Keiner'),
              textCapitalization: TextCapitalization.none,
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 12),
            _buildDropdown('Kennzeichen', _kennzeichen, _kennzeichenOptionen, 'Bitte wählen', (v) {
              setState(() => _kennzeichen = v);
              _loadLetzterKm();
            }),
            const SizedBox(height: 12),
            _buildDropdown('Standort', _standort, _standort != null && _standort!.isNotEmpty ? [_standort!] : const <String>[], 'Bitte wählen', (v) => setState(() => _standort = v)),
            const SizedBox(height: 12),
            _buildDropdown('Wachbuch-Schicht', _wachbuchSchicht, _wachbuchSchicht != null && _wachbuchSchicht!.isNotEmpty ? [_wachbuchSchicht!] : const <String>[], 'Bitte wählen', (v) => setState(() => _wachbuchSchicht = v)),
          ],
        ),
      ),
    );
  }

  String _initials(String name) {
    final parts = name.split(RegExp(r'[\s,]+')).where((s) => s.isNotEmpty).take(2).toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts.first.isNotEmpty ? parts.first[0].toUpperCase() : '?';
    return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
  }

  Future<void> _showSearchableMitarbeiterPicker(
    BuildContext context, {
    required String label,
    required String? value,
    required List<String> options,
    required String emptyLabel,
    required ValueChanged<String?> onChanged,
  }) async {
    final ctrl = TextEditingController();
    final selected = await showGeneralDialog<String?>(
      context: context,
      barrierDismissible: true,
      barrierColor: Colors.black54,
      barrierLabel: 'Mitarbeiter auswählen',
      pageBuilder: (ctx, _, __) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            final query = ctrl.text.toLowerCase().trim();
            var filtered = query.isEmpty
                ? options
                : options.where((o) => o.toLowerCase().contains(query)).toList();
            if (!filtered.contains(emptyLabel)) {
              final matchesEmpty = emptyLabel.toLowerCase().contains(query);
              if (query.isEmpty || matchesEmpty) filtered = [emptyLabel, ...filtered];
            }
            return Align(
              alignment: Alignment.topCenter,
              child: Material(
                color: Colors.white,
                borderRadius: const BorderRadius.vertical(bottom: Radius.circular(24)),
                elevation: 8,
                shadowColor: Colors.black.withOpacity(0.15),
                child: SafeArea(
                  top: false,
                  child: ClipRRect(
                    borderRadius: const BorderRadius.vertical(bottom: Radius.circular(24)),
                    child: SizedBox(
                      height: MediaQuery.of(context).size.height * 0.7,
                      child: Padding(
                        padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
                        child: Column(
                          children: [
                            // Drag-Handle (moderner Touchpunkt)
                            Padding(
                              padding: const EdgeInsets.only(top: 12, bottom: 8),
                              child: Container(
                                width: 36,
                                height: 4,
                                decoration: BoxDecoration(
                                  color: Colors.grey.shade300,
                                  borderRadius: BorderRadius.circular(2),
                                ),
                              ),
                            ),
                            // Header mit Titel
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    label,
                                    style: const TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.w600,
                                      color: AppTheme.textPrimary,
                                    ),
                                  ),
                                  IconButton(
                                    icon: Icon(Icons.close, color: Colors.grey.shade600),
                                    onPressed: () => Navigator.of(ctx).pop(),
                                    style: IconButton.styleFrom(
                                      backgroundColor: Colors.grey.shade100,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            // Modernes Suchfeld
                            Padding(
                              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                              child: TextField(
                                controller: ctrl,
                                autofocus: true,
                                style: const TextStyle(fontSize: 16),
                                decoration: InputDecoration(
                                  hintText: 'Namen durchsuchen...',
                                  hintStyle: TextStyle(color: Colors.grey.shade500, fontSize: 15),
                                  prefixIcon: Icon(Icons.search_rounded, color: Colors.grey.shade600, size: 22),
                                  filled: true,
                                  fillColor: Colors.grey.shade50,
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12),
                                    borderSide: BorderSide.none,
                                  ),
                                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                                ),
                                onChanged: (_) => setModalState(() {}),
                              ),
                            ),
                            // Mitarbeiterliste
                            Expanded(
                              child: ListView.separated(
                                padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
                                itemCount: filtered.length,
                                separatorBuilder: (_, __) => const SizedBox(height: 4),
                                itemBuilder: (_, i) {
                                  final opt = filtered[i];
                                  final isSelected = value == opt || (opt == emptyLabel && value == null);
                                  return Material(
                                    color: Colors.transparent,
                                    child: InkWell(
                                      onTap: () => Navigator.of(ctx).pop(opt == emptyLabel ? null : opt),
                                      borderRadius: BorderRadius.circular(12),
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                                        decoration: BoxDecoration(
                                          color: isSelected ? AppTheme.primary.withOpacity(0.08) : null,
                                          borderRadius: BorderRadius.circular(12),
                                          border: isSelected ? Border.all(color: AppTheme.primary.withOpacity(0.3), width: 1) : null,
                                        ),
                                        child: Row(
                                          children: [
                                            if (opt != emptyLabel)
                                              CircleAvatar(
                                                radius: 18,
                                                backgroundColor: isSelected ? AppTheme.primary : Colors.grey.shade200,
                                                child: Text(
                                                  _initials(opt),
                                                  style: TextStyle(
                                                    fontSize: 13,
                                                    fontWeight: FontWeight.w600,
                                                    color: isSelected ? Colors.white : Colors.grey.shade700,
                                                  ),
                                                ),
                                              )
                                            else
                                              SizedBox(
                                                width: 36,
                                                height: 36,
                                                child: Center(child: Icon(Icons.person_off_rounded, color: Colors.grey.shade400, size: 22)),
                                              ),
                                            const SizedBox(width: 14),
                                            Expanded(
                                              child: Text(
                                                opt,
                                                style: TextStyle(
                                                  fontSize: 16,
                                                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                                                  color: isSelected ? AppTheme.primary : AppTheme.textPrimary,
                                                ),
                                              ),
                                            ),
                                            if (isSelected)
                                              Icon(Icons.check_circle_rounded, color: AppTheme.primary, size: 22),
                                          ],
                                        ),
                                      ),
                                    ),
                                  );
                                },
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
    if (selected != null) onChanged(selected);
  }

  Widget _buildSearchableMitarbeiterDropdown(
    String label,
    String? value,
    List<String> options,
    String emptyLabel,
    ValueChanged<String?> onChanged,
  ) {
    final displayValue = value ?? emptyLabel;
    return InkWell(
      onTap: () => _showSearchableMitarbeiterPicker(
        context,
        label: label,
        value: value,
        options: options,
        emptyLabel: emptyLabel,
        onChanged: onChanged,
      ),
      borderRadius: BorderRadius.circular(4),
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
          suffixIcon: const Icon(Icons.arrow_drop_down),
        ),
        child: Text(displayValue, style: TextStyle(fontSize: 16, color: value != null ? Colors.black87 : Colors.grey[600])),
      ),
    );
  }

  Widget _buildDropdown(String label, String? value, List<String> options, String emptyLabel, ValueChanged<String?> onChanged) {
    final items = [emptyLabel, ...options.where((o) => o != emptyLabel)];
    final displayValue = value ?? emptyLabel;
    return DropdownButtonFormField<String>(
      value: items.contains(displayValue) ? displayValue : items.first,
      decoration: InputDecoration(labelText: label),
      items: items.map((s) => DropdownMenuItem(value: s, child: Text(s))).toList(),
      onChanged: (v) => onChanged(v == emptyLabel ? null : v),
    );
  }

  Widget _buildItem(ChecklisteItem item) {
    if (item.type == 'checkbox') {
      final value = _toBool(_values[item.id]);
      return Card(
        margin: const EdgeInsets.only(bottom: 8),
        child: CheckboxListTile(
          title: Text(item.isRequired ? '${item.label} *' : item.label),
          value: value,
          onChanged: (v) => setState(() => _values[item.id] = v ?? false),
          activeColor: AppTheme.primary,
        ),
      );
    }
    if (item.type == 'slider') {
      final value = _toBool(_values[item.id]);
      return Card(
        margin: const EdgeInsets.only(bottom: 8),
        child: SwitchListTile(
          title: Text(item.isRequired ? '${item.label} *' : item.label),
          value: value,
          onChanged: (v) => setState(() => _values[item.id] = v ?? false),
          activeColor: AppTheme.primary,
        ),
      );
    }
    // text / Eingabefeld
    final ctrl = _textControllers[item.id];
    if (ctrl == null) {
      return Card(
        margin: const EdgeInsets.only(bottom: 8),
        child: ListTile(title: Text(item.label)),
      );
    }
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: TextFormField(
          controller: ctrl,
          decoration: InputDecoration(
            labelText: item.isRequired ? '${item.label} *' : item.label,
            border: const OutlineInputBorder(),
          ),
          textCapitalization: TextCapitalization.none,
        ),
      ),
    );
  }

  String _formatDateTime(DateTime? d) {
    if (d == null) return '–';
    return '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.${d.year} ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
  }

  String _shortDesc(FahrzeugMangel m) =>
      m.betreff?.trim().isNotEmpty == true ? m.betreff! : (m.beschreibung.split('\n').isNotEmpty ? m.beschreibung.split('\n').first : m.beschreibung);

  Widget _buildFahrzeugmangelCard() {
    return StreamBuilder<List<FahrzeugMangel>>(
      stream: _fleetService.streamMaengel(widget.companyId),
      builder: (context, snap) {
        final all = snap.data ?? [];
        final list = all.where((m) => _mangelStatusOffen.contains(m.status.toLowerCase())).toList();
        return Container(
          margin: const EdgeInsets.only(bottom: 16),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.grey[50],
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.grey[300]!),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Fahrzeugmangel', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600, color: Colors.black)),
              const SizedBox(height: 4),
              Text(
                list.isEmpty ? 'Keine offenen oder in Bearbeitung befindlichen Mängel' : '${list.length} offene/in Bearbeitung',
                style: TextStyle(fontSize: 13, color: Colors.grey[600]),
              ),
              if (list.isNotEmpty) ...[
                const SizedBox(height: 12),
                ...list.map((m) => _buildMangelRow(m)),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _buildMangelRow(FahrzeugMangel m) {
    final datum = m.datum ?? m.createdAt;
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        title: Text(_shortDesc(m), style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text('Erfasst: ${_formatDateTime(datum)} · ${m.melderName ?? 'Unbekannt'}', style: TextStyle(fontSize: 12, color: Colors.grey[600])),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => _openMangelDetail(m),
      ),
    );
  }

  Widget _buildKmStandSection() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.grey[50],
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey[300]!),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Aktuellen KM-Stand erfassen', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600, color: Colors.black)),
          Divider(height: 24, color: Colors.grey[300]),
          Text('Aktueller KM-Stand', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Colors.grey[800])),
          const SizedBox(height: 4),
          Text('Es können nur ganze KM eingetragen werden!', style: TextStyle(fontSize: 13, color: Colors.red[700])),
          const SizedBox(height: 8),
          TextFormField(
            controller: _kmStandCtrl,
            decoration: const InputDecoration(
              hintText: 'z.B. 62700',
              border: OutlineInputBorder(),
            ),
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 12),
          Text(
            _lastKmFromFahrtenbuch != null
                ? 'Letzter eingetragener Endkm vom Fahrtenbuch: ${_lastKmFromFahrtenbuch} km'
                : 'Letzter eingetragener Endkm vom Fahrtenbuch: –',
            style: TextStyle(fontSize: 13, color: Colors.red[700]),
          ),
        ],
      ),
    );
  }

  void _openMangelDetail(FahrzeugMangel m) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => FahrzeugmangelDetailScreen(
          mangel: m,
          onBack: () => Navigator.of(context).pop(),
        ),
      ),
    );
  }
}
