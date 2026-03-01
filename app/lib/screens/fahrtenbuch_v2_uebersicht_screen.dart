import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../models/fahrtenbuch_v2_model.dart';
import '../models/fahrtenbuch_v2_vorlage.dart';
import '../models/fleet_model.dart';
import '../services/fahrtenbuch_v2_service.dart';
import '../services/schichtanmeldung_service.dart';
import 'fahrtenbuch_v2_screen.dart';
import 'fahrtenbuch_v2_druck_screen.dart';

/// Fahrtenbuch V2 – Start mit 2 Karten: Neuer Eintrag + Fahrtenübersicht
class FahrtenbuchV2UebersichtScreen extends StatefulWidget {
  /// Rollen, die Fahrtenbuch drucken dürfen: Admin, Geschäftsführung, Rettungsdienstleitung
  static const _druckRoles = ['superadmin', 'admin', 'geschaeftsfuehrung', 'rettungsdienstleitung'];
  final String companyId;
  final String? title;
  final VoidCallback onBack;
  /// Wird mit Vorlage aufgerufen (für Kennzeichen-Vorauswahl); null = ohne Vorlage
  final void Function(FahrtenbuchV2Vorlage? vorlage)? onAddTap;
  final FahrtenbuchV2Service service;
  final String? userRole;
  /// Vorlage aus Schichtanmeldung – wird an onAddTap übergeben
  final FahrtenbuchV2Vorlage? initialVorlage;

  const FahrtenbuchV2UebersichtScreen({
    super.key,
    required this.companyId,
    this.title,
    required this.onBack,
    this.onAddTap,
    required this.service,
    this.userRole,
    this.initialVorlage,
  });

  static bool canPrint(String? role) {
    if (role == null || role.trim().isEmpty) return false;
    return _druckRoles.contains(role.toLowerCase().trim());
  }

  @override
  State<FahrtenbuchV2UebersichtScreen> createState() => _FahrtenbuchV2UebersichtScreenState();
}

class _FahrtenbuchV2UebersichtScreenState extends State<FahrtenbuchV2UebersichtScreen> {
  bool _showFahrtenuebersicht = false;
  DateTime? _filterVon;
  DateTime? _filterBis;
  String? _filterStandortId;
  String? _filterFahrzeugKey;
  List<Standort> _standorte = [];
  List<Fahrzeug> _fahrzeuge = [];
  Map<String, String> _fahrzeugToStandort = {};

  @override
  void initState() {
    super.initState();
    _loadFilterData();
  }

  Future<void> _loadFilterData() async {
    try {
      final standorte = await SchichtanmeldungService().loadStandorte(widget.companyId);
      final fahrzeuge = await widget.service.loadFahrzeuge(widget.companyId);
      final map = <String, String>{};
      for (final f in fahrzeuge) {
        final wache = (f.wache ?? '').trim();
        if (wache.isEmpty) continue;
        if ((f.kennzeichen ?? '').trim().isNotEmpty) map[(f.kennzeichen ?? '').trim()] = wache;
        final ruf = (f.rufname ?? f.id ?? '').trim();
        if (ruf.isNotEmpty) map[ruf] = wache;
      }
      if (mounted) {
        setState(() {
          _standorte = standorte;
          _fahrzeuge = fahrzeuge;
          _fahrzeugToStandort = map;
        });
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.surfaceBg,
      appBar: AppTheme.buildModuleAppBar(
        title: _showFahrtenuebersicht ? 'Fahrtenübersicht' : (widget.title ?? 'Fahrtenbuch-Menü'),
        onBack: () {
          if (_showFahrtenuebersicht) {
            setState(() => _showFahrtenuebersicht = false);
          } else {
            widget.onBack();
          }
        },
      ),
      body: _showFahrtenuebersicht ? _buildFahrtenuebersicht() : _buildStartKarten(),
    );
  }

  Widget _buildStartKarten() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          margin: const EdgeInsets.only(bottom: 12),
          child: ListTile(
            leading: CircleAvatar(
              backgroundColor: AppTheme.primary.withOpacity(0.15),
              child: Icon(Icons.add_road, color: AppTheme.primary),
            ),
            title: const Text('Neuer Fahrtenbucheintrag', style: TextStyle(fontWeight: FontWeight.w600)),
            subtitle: const Text('Neuen Eintrag erfassen'),
            trailing: const Icon(Icons.chevron_right),
            onTap: widget.onAddTap != null ? () => widget.onAddTap!(widget.initialVorlage) : () {},
          ),
        ),
        Card(
          margin: const EdgeInsets.only(bottom: 12),
          child: ListTile(
            leading: CircleAvatar(
              backgroundColor: AppTheme.primary.withOpacity(0.15),
              child: Icon(Icons.list_alt, color: AppTheme.primary),
            ),
            title: const Text('Fahrtenübersicht', style: TextStyle(fontWeight: FontWeight.w600)),
            subtitle: const Text('Alle Fahrten mit Filter anzeigen'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => setState(() => _showFahrtenuebersicht = true),
          ),
        ),
        if (FahrtenbuchV2UebersichtScreen.canPrint(widget.userRole))
          Card(
            margin: const EdgeInsets.only(bottom: 12),
            child: ListTile(
              leading: CircleAvatar(
                backgroundColor: AppTheme.primary.withOpacity(0.15),
                child: Icon(Icons.print, color: AppTheme.primary),
              ),
              title: const Text('Fahrtenbuch drucken', style: TextStyle(fontWeight: FontWeight.w600)),
              subtitle: const Text('Fahrzeug und Monat auswählen'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => _openDruckDialog(),
            ),
          ),
      ],
    );
  }

  Widget _buildFahrtenuebersicht() {
    return StreamBuilder<List<FahrtenbuchV2Eintrag>>(
      stream: widget.service.streamEintraege(widget.companyId),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting && !snap.hasData) {
          return const Center(child: CircularProgressIndicator(color: AppTheme.primary));
        }
        var list = snap.data ?? [];
        if (_filterVon != null) {
          list = list.where((e) => e.datum != null && !e.datum!.isBefore(DateTime(_filterVon!.year, _filterVon!.month, _filterVon!.day))).toList();
        }
        if (_filterBis != null) {
          list = list.where((e) => e.datum != null && !e.datum!.isAfter(DateTime(_filterBis!.year, _filterBis!.month, _filterBis!.day, 23, 59, 59))).toList();
        }
        if (_filterFahrzeugKey != null && _filterFahrzeugKey!.isNotEmpty) {
          list = list.where((e) {
            final kz = (e.kennzeichen ?? '').trim();
            final fk = (e.fahrzeugkennung ?? '').trim();
            return kz == _filterFahrzeugKey || fk == _filterFahrzeugKey;
          }).toList();
        }
        if (_filterStandortId != null && _filterStandortId!.isNotEmpty) {
          list = list.where((e) {
            final kz = (e.kennzeichen ?? '').trim();
            final fk = (e.fahrzeugkennung ?? '').trim();
            final key = kz.isNotEmpty ? kz : fk;
            if (key.isEmpty) return false;
            final standortId = _fahrzeugToStandort[key];
            return standortId == _filterStandortId;
          }).toList();
        }
        list.sort((a, b) => (b.datum ?? DateTime(0)).compareTo(a.datum ?? DateTime(0)));

        return Column(
          children: [
            _buildFilterBar(list),
            Expanded(
              child: list.isEmpty
                  ? Center(child: Text('Keine Einträge.', style: TextStyle(color: Colors.grey[600])))
                  : ListView.builder(
                      padding: const EdgeInsets.all(16),
                      itemCount: list.length,
                      itemBuilder: (_, i) => _buildEintragCard(list[i]),
                    ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildFilterBar(List<FahrtenbuchV2Eintrag> list) {
    return Container(
      padding: const EdgeInsets.all(12),
      color: Colors.white,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.calendar_today, size: 18),
                  label: Text(_filterVon != null ? '${_filterVon!.day.toString().padLeft(2, '0')}.${_filterVon!.month.toString().padLeft(2, '0')}.${_filterVon!.year}' : 'Von'),
                  onPressed: () async {
                    final d = await showDatePicker(context: context, initialDate: _filterVon ?? DateTime.now(), firstDate: DateTime(2020), lastDate: DateTime.now().add(const Duration(days: 365)));
                    if (d != null) setState(() => _filterVon = d);
                  },
                ),
              ),
              const Padding(padding: EdgeInsets.symmetric(horizontal: 8), child: Text('-')),
              Expanded(
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.calendar_today, size: 18),
                  label: Text(_filterBis != null ? '${_filterBis!.day.toString().padLeft(2, '0')}.${_filterBis!.month.toString().padLeft(2, '0')}.${_filterBis!.year}' : 'Bis'),
                  onPressed: () async {
                    final d = await showDatePicker(context: context, initialDate: _filterBis ?? DateTime.now(), firstDate: DateTime(2020), lastDate: DateTime.now().add(const Duration(days: 365)));
                    if (d != null) setState(() => _filterBis = d);
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                flex: 2,
                child: DropdownButtonFormField<String>(
                  value: _filterStandortId,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Standort',
                    isDense: true,
                    contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  ),
                  items: [
                    const DropdownMenuItem(value: null, child: Text('Alle Standorte', overflow: TextOverflow.ellipsis, maxLines: 1)),
                    ..._standorte.map((s) => DropdownMenuItem(value: s.id, child: Text(s.name, overflow: TextOverflow.ellipsis, maxLines: 1))),
                  ],
                  onChanged: (v) => setState(() => _filterStandortId = v),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 2,
                child: DropdownButtonFormField<String>(
                  value: _filterFahrzeugKey,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Fahrzeug',
                    isDense: true,
                    contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  ),
                  items: [
                    const DropdownMenuItem(value: null, child: Text('Alle Fahrzeuge', overflow: TextOverflow.ellipsis, maxLines: 1)),
                    ..._fahrzeuge.map((f) {
                      final kz = (f.kennzeichen ?? '').trim();
                      final key = kz.isNotEmpty ? kz : (f.rufname ?? f.id ?? '');
                      final label = kz.isNotEmpty ? kz : f.displayName;
                      return DropdownMenuItem(value: key, child: Text(label, overflow: TextOverflow.ellipsis, maxLines: 1));
                    }),
                  ],
                  onChanged: (v) => setState(() => _filterFahrzeugKey = v),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.clear),
                onPressed: () => setState(() {
                  _filterVon = null;
                  _filterBis = null;
                  _filterStandortId = null;
                  _filterFahrzeugKey = null;
                }),
                tooltip: 'Filter zurücksetzen',
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _openDruckDialog() async {
    final fahrzeuge = _fahrzeuge.isEmpty ? await widget.service.loadFahrzeuge(widget.companyId) : _fahrzeuge;
    if (!mounted) return;
    await showDialog(
      context: context,
      builder: (ctx) => _FahrtenbuchDruckDialog(
        companyId: widget.companyId,
        fahrzeuge: fahrzeuge,
        service: widget.service,
        onDruck: (eintraege, kennzeichen, von, bis) {
          Navigator.of(ctx).pop();
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => FahrtenbuchV2DruckScreen(
                eintraege: eintraege,
                kennzeichen: kennzeichen,
                filterVon: von,
                filterBis: bis,
                onBack: () => Navigator.of(context).pop(),
              ),
            ),
          );
        },
        onAbbrechen: () => Navigator.of(ctx).pop(),
      ),
    );
  }

  Widget _buildEintragCard(FahrtenbuchV2Eintrag e) {
    final datumStr = e.datum != null ? '${e.datum!.day.toString().padLeft(2, '0')}.${e.datum!.month.toString().padLeft(2, '0')}.${e.datum!.year}' : '-';
    final zeitStr = [e.fahrzeitVon, e.fahrzeitBis].where((x) => x != null && x.toString().trim().isNotEmpty).join(' - ');
    final kennzeichen = (e.kennzeichen ?? e.fahrzeugkennung ?? '').trim();

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        onTap: () => _openEintragForm(e),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(datumStr, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                  if (zeitStr.isNotEmpty) ...[
                    const SizedBox(width: 8),
                    Text(zeitStr, style: TextStyle(color: Colors.grey[700], fontSize: 13)),
                  ],
                  const Spacer(),
                  if (kennzeichen.isNotEmpty)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(color: AppTheme.primary.withOpacity(0.1), borderRadius: BorderRadius.circular(4)),
                      child: Text(kennzeichen, style: TextStyle(color: AppTheme.primary, fontWeight: FontWeight.w500, fontSize: 12)),
                    ),
                  if (e.kmEnde != null && e.kmAnfang != null) ...[
                    if (kennzeichen.isNotEmpty) const SizedBox(width: 8),
                    Text('${e.kmEnde! - e.kmAnfang!} km', style: TextStyle(color: AppTheme.primary, fontWeight: FontWeight.w500, fontSize: 13)),
                  ],
                ],
              ),
              if (e.nameFahrer != null && e.nameFahrer!.trim().isNotEmpty)
                Text('Fahrer: ${e.nameFahrer}', style: TextStyle(color: Colors.grey[600], fontSize: 12)),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _openEintragForm(FahrtenbuchV2Eintrag e) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (ctx) => FahrtenbuchV2Screen(
          companyId: widget.companyId,
          onBack: () {
            Navigator.of(ctx).pop();
            setState(() {});
          },
          initialEintrag: e,
          userRole: widget.userRole,
        ),
      ),
    );
  }
}

/// Dialog für Fahrtenbuch-Druck: Fahrzeug + Monat auswählen
class _FahrtenbuchDruckDialog extends StatefulWidget {
  final String companyId;
  final List<Fahrzeug> fahrzeuge;
  final FahrtenbuchV2Service service;
  final void Function(List<FahrtenbuchV2Eintrag> eintraege, String kennzeichen, DateTime von, DateTime bis) onDruck;
  final VoidCallback onAbbrechen;

  const _FahrtenbuchDruckDialog({
    required this.companyId,
    required this.fahrzeuge,
    required this.service,
    required this.onDruck,
    required this.onAbbrechen,
  });

  @override
  State<_FahrtenbuchDruckDialog> createState() => _FahrtenbuchDruckDialogState();
}

class _FahrtenbuchDruckDialogState extends State<_FahrtenbuchDruckDialog> {
  String? _selectedKey;
  int? _selectedMonat; // 1-12
  int? _selectedJahr;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _selectedMonat = now.month;
    _selectedJahr = now.year;
  }

  static const _monatsNamen = ['Januar', 'Februar', 'März', 'April', 'Mai', 'Juni', 'Juli', 'August', 'September', 'Oktober', 'November', 'Dezember'];

  List<int> get _jahre {
    final now = DateTime.now();
    return List.generate(2050 - now.year + 1, (i) => now.year + i);
  }

  Future<void> _doDruck() async {
    if (_selectedKey == null || _selectedKey!.isEmpty || _selectedMonat == null || _selectedJahr == null) return;
    setState(() => _loading = true);
    try {
      final von = DateTime(_selectedJahr!, _selectedMonat!, 1);
      final bis = DateTime(_selectedJahr!, _selectedMonat! + 1, 0, 23, 59, 59);
      final list = await widget.service.streamEintraegeVonBis(widget.companyId, von: von, bis: bis).first;
      final filtered = list.where((e) {
        final kz = (e.kennzeichen ?? '').trim();
        final fk = (e.fahrzeugkennung ?? '').trim();
        return kz == _selectedKey || fk == _selectedKey;
      }).toList();
      filtered.sort((a, b) => (a.datum ?? DateTime(0)).compareTo(b.datum ?? DateTime(0)));
      final f = widget.fahrzeuge.where((f) {
        final kz = (f.kennzeichen ?? '').trim();
        final key = kz.isNotEmpty ? kz : (f.rufname ?? f.id ?? '');
        return key == _selectedKey;
      }).firstOrNull;
      final kzLabel = (f != null && (f.kennzeichen ?? '').trim().isNotEmpty) ? f.kennzeichen! : (f?.rufname ?? f?.id ?? _selectedKey!);
      final monatJahr = '${_monatsNamen[_selectedMonat! - 1]} $_selectedJahr';
      final titel = 'Fahrtenbuch für $kzLabel - $monatJahr';
      if (mounted) widget.onDruck(filtered, titel, von, bis);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Fahrtenbuch drucken'),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 400),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              DropdownButtonFormField<String>(
                value: _selectedKey,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Fahrzeug',
                  border: OutlineInputBorder(),
                ),
                items: [
                  const DropdownMenuItem(value: null, child: Text('– Fahrzeug wählen –', overflow: TextOverflow.ellipsis, maxLines: 1)),
                  ...widget.fahrzeuge.map((f) {
                    final kz = (f.kennzeichen ?? '').trim();
                    final key = kz.isNotEmpty ? kz : (f.rufname ?? f.id ?? '');
                    final label = kz.isNotEmpty ? '$kz (${f.rufname ?? f.id ?? ''})' : (f.rufname ?? f.id ?? '');
                    return DropdownMenuItem(value: key, child: Text(label, overflow: TextOverflow.ellipsis, maxLines: 1));
                  }),
                ],
                onChanged: _loading ? null : (v) => setState(() => _selectedKey = v),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<int>(
                      value: _selectedMonat,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: 'Monat',
                        border: OutlineInputBorder(),
                      ),
                      items: [
                        const DropdownMenuItem(value: null, child: Text('– Monat –')),
                        ...List.generate(12, (i) => i + 1).map((m) => DropdownMenuItem(
                              value: m,
                              child: Text(_monatsNamen[m - 1]),
                            )),
                      ],
                      onChanged: _loading ? null : (v) => setState(() => _selectedMonat = v),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: DropdownButtonFormField<int>(
                      value: _selectedJahr,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: 'Jahr',
                        border: OutlineInputBorder(),
                      ),
                      items: [
                        const DropdownMenuItem(value: null, child: Text('– Jahr –')),
                        ..._jahre.map((j) => DropdownMenuItem(value: j, child: Text('$j'))),
                      ],
                      onChanged: _loading ? null : (v) => setState(() => _selectedJahr = v),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _loading ? null : widget.onAbbrechen,
          child: const Text('Abbrechen'),
        ),
        FilledButton(
          onPressed: (_loading || _selectedKey == null || _selectedKey!.isEmpty || _selectedMonat == null || _selectedJahr == null)
              ? null
              : _doDruck,
          child: _loading ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('Drucken'),
        ),
      ],
    );
  }
}
