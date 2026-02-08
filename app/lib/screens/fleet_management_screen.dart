import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../theme/app_theme.dart';
import '../models/fleet_model.dart';
import '../services/fleet_service.dart';

class FleetManagementScreen extends StatefulWidget {
  final String companyId;
  final String userRole;
  final VoidCallback? onBack;
  final int initialTabIndex;

  const FleetManagementScreen({super.key, required this.companyId, this.userRole = 'user', this.onBack, this.initialTabIndex = 0});

  @override
  State<FleetManagementScreen> createState() => _FleetManagementScreenState();
}

class _FleetManagementScreenState extends State<FleetManagementScreen> with SingleTickerProviderStateMixin {
  final _fleetService = FleetService();
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    final idx = widget.initialTabIndex.clamp(0, 2);
    _tabController = TabController(length: 3, vsync: this, initialIndex: idx);
    _tabController.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.surfaceBg,
      appBar: AppTheme.buildModuleAppBar(
        title: 'Flottenmanagement',
        onBack: widget.onBack ?? () => Navigator.of(context).pop(),
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: AppTheme.primary,
          labelColor: AppTheme.primary,
          unselectedLabelColor: AppTheme.textSecondary,
          tabs: const [
            Tab(text: 'Fahrzeugstammdaten'),
            Tab(text: 'Terminfestlegung'),
            Tab(text: 'Mängelübersicht'),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            tooltip: 'Einstellungen',
            onPressed: () => _openSettings(),
          ),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 200),
            child: _tabController.index == 1
                ? IconButton(
                    icon: const Icon(Icons.event_available),
                    tooltip: 'Termin anlegen',
                    onPressed: () => _openTerminAdd(),
                  )
                : _tabController.index == 2
                    ? const SizedBox.shrink()
                    : IconButton(
                        key: const ValueKey('fahrzeug'),
                        icon: Container(
                          width: 32,
                          height: 32,
                          decoration: const BoxDecoration(color: AppTheme.primary, shape: BoxShape.circle),
                          alignment: Alignment.center,
                          child: const Icon(Icons.add, color: Colors.white, size: 24, weight: 700),
                        ),
                        tooltip: 'Neues Fahrzeug',
                        onPressed: () => _openFahrzeugEdit(),
                      ),
          ),
        ],
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _FahrzeugListTab(companyId: widget.companyId, fleetService: _fleetService, onAdd: _openFahrzeugEdit),
          _TerminListTab(companyId: widget.companyId, fleetService: _fleetService, userRole: widget.userRole),
          _MangelListTab(companyId: widget.companyId, fleetService: _fleetService),
        ],
      ),
    );
  }

  void _openFahrzeugEdit({Fahrzeug? fahrzeug}) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => _FahrzeugEditScreen(
          companyId: widget.companyId,
          fleetService: _fleetService,
          fahrzeug: fahrzeug,
          onBack: () => Navigator.of(context).pop(),
        ),
      ),
    ).then((_) => setState(() {}));
  }

  void _openSettings() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => _FleetSettingsScreen(
          companyId: widget.companyId,
          fleetService: _fleetService,
          onBack: () => Navigator.of(context).pop(),
        ),
      ),
    ).then((_) => setState(() {}));
  }

  void _openTerminAdd() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => _TerminEditScreen(
          companyId: widget.companyId,
          fleetService: _fleetService,
          termin: null,
          onBack: () => Navigator.of(context).pop(),
        ),
      ),
    ).then((_) => setState(() {}));
  }
}

class _FahrzeugListTab extends StatelessWidget {
  final String companyId;
  final FleetService fleetService;
  final VoidCallback onAdd;

  const _FahrzeugListTab({required this.companyId, required this.fleetService, required this.onAdd});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Fahrzeug>>(
      stream: fleetService.streamFahrzeuge(companyId),
      builder: (ctx, snap) {
        if (!snap.hasData) {
          return const Center(child: CircularProgressIndicator(color: AppTheme.primary));
        }
        final list = snap.data!;
        if (list.isEmpty) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.directions_car_outlined, size: 64, color: Colors.grey[400]),
                const SizedBox(height: 16),
                Text('Keine Fahrzeuge', style: TextStyle(color: AppTheme.textSecondary)),
                const SizedBox(height: 24),
                FilledButton(
                  onPressed: onAdd,
                  style: FilledButton.styleFrom(backgroundColor: AppTheme.primary),
                  child: const Text('Fahrzeug hinzufügen'),
                ),
              ],
            ),
          );
        }
        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: list.length,
          itemBuilder: (_, i) {
            final f = list[i];
            return Card(
              margin: const EdgeInsets.only(bottom: 12),
              child: ListTile(
                leading: Icon(Icons.directions_car, color: AppTheme.primary),
                title: Text(f.displayName, style: const TextStyle(fontWeight: FontWeight.w600)),
                subtitle: Text([
                  if (f.fahrzeugtyp != null && f.fahrzeugtyp!.isNotEmpty) f.fahrzeugtyp,
                  if (f.kennzeichen != null && f.kennzeichen!.isNotEmpty) f.kennzeichen!,
                  if (f.beauftragte.isNotEmpty) '${f.beauftragte.length} Beauftragte',
                ].join(' · ')),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => _FahrzeugEditScreen(
                      companyId: companyId,
                      fleetService: fleetService,
                      fahrzeug: f,
                      onBack: () => Navigator.of(context).pop(),
                    ),
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

/// Rollen, die Termine anlegen und löschen dürfen (wie Modul-Zugriff Flottenmanagement)
const _terminManagementRoles = ['superadmin', 'admin', 'geschaeftsfuehrung', 'leiterssd', 'koordinator', 'fahrzeugbeauftragter', 'supervisor'];

class _TerminListTab extends StatefulWidget {
  final String companyId;
  final FleetService fleetService;
  final String userRole;

  const _TerminListTab({required this.companyId, required this.fleetService, this.userRole = 'user'});

  @override
  State<_TerminListTab> createState() => _TerminListTabState();
}

class _TerminListTabState extends State<_TerminListTab> {
  bool _showArchiv = false; // false = Aktuell (upcoming), true = Archiv (past)

  bool get _canManageTermine =>
      _terminManagementRoles.contains(widget.userRole.toLowerCase().trim());

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: SegmentedButton<bool>(
            segments: const [
              ButtonSegment(value: false, label: Text('Aktuell'), icon: Icon(Icons.event_available)),
              ButtonSegment(value: true, label: Text('Archiv'), icon: Icon(Icons.archive)),
            ],
            selected: {_showArchiv},
            onSelectionChanged: (s) => setState(() => _showArchiv = s.first),
          ),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: StreamBuilder<List<FahrzeugTermin>>(
            stream: widget.fleetService.streamTermine(widget.companyId),
            builder: (ctx, snap) {
              if (!snap.hasData) {
                return const Center(child: CircularProgressIndicator(color: AppTheme.primary));
              }
              final list = snap.data!;
              final now = DateTime.now();
              final upcoming = list.where((t) => t.datum.isAfter(now)).toList()
                ..sort((a, b) => a.datum.compareTo(b.datum));
              final archived = list.where((t) => !t.datum.isAfter(now)).toList()
                ..sort((a, b) => b.datum.compareTo(a.datum));

              final displayList = _showArchiv ? archived : upcoming;

              if (displayList.isEmpty) {
                return Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        _showArchiv ? Icons.archive_outlined : Icons.event_note,
                        size: 64,
                        color: Colors.grey[400],
                      ),
                      const SizedBox(height: 16),
                      Text(
                        _showArchiv ? 'Keine archivierten Termine' : 'Keine Termine',
                        style: TextStyle(color: AppTheme.textSecondary),
                      ),
                      if (!_showArchiv) ...[
                        const SizedBox(height: 24),
                        FilledButton(
                          onPressed: () => _openTerminAdd(context),
                          style: FilledButton.styleFrom(backgroundColor: AppTheme.primary),
                          child: const Text('Termin anlegen'),
                        ),
                      ],
                    ],
                  ),
                );
              }

              final byVehicle = <String, List<FahrzeugTermin>>{};
              for (final t in displayList) {
                byVehicle.putIfAbsent(t.fahrzeugRufname.isEmpty ? '(Unbekannt)' : t.fahrzeugRufname, () => []).add(t);
              }
              final vehicleOrder = byVehicle.keys.toList()
                ..sort((a, b) {
                  final listA = byVehicle[a]!;
                  final listB = byVehicle[b]!;
                  final dateA = listA.first.datum;
                  final dateB = listB.first.datum;
                  return _showArchiv ? dateB.compareTo(dateA) : dateA.compareTo(dateB);
                });

              return ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: vehicleOrder.length,
                itemBuilder: (_, i) {
                  final rufname = vehicleOrder[i];
                  final termine = byVehicle[rufname]!;
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(left: 4, bottom: 8),
                        child: Row(
                          children: [
                            Icon(Icons.directions_car, size: 18, color: AppTheme.primary),
                            const SizedBox(width: 6),
                            Text(
                              rufname,
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 15,
                                color: AppTheme.textPrimary,
                              ),
                            ),
                          ],
                        ),
                      ),
                      ...termine.map((t) => Card(
                            margin: const EdgeInsets.only(bottom: 8),
                            child: ListTile(
                              leading: CircleAvatar(
                                backgroundColor: AppTheme.primary.withOpacity(0.2),
                                child: Icon(Icons.event, color: AppTheme.primary),
                              ),
                              title: Text(t.typ, style: const TextStyle(fontWeight: FontWeight.w600)),
                              subtitle: Text(
                                _formatDate(t.datum) + (t.notiz != null && t.notiz!.isNotEmpty ? '\n${t.notiz}' : ''),
                              ),
                              trailing: _canManageTermine
                                  ? IconButton(
                                      icon: const Icon(Icons.delete_outline),
                                      color: Colors.red,
                                      tooltip: 'Termin löschen',
                                      onPressed: () => _confirmDeleteTermin(context, t),
                                    )
                                  : null,
                            ),
                          )),
                      if (i < vehicleOrder.length - 1) const SizedBox(height: 8),
                    ],
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }

  String _formatDate(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.${d.year} ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

  Future<void> _confirmDeleteTermin(BuildContext context, FahrzeugTermin t) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Termin löschen?'),
        content: Text(
          'Termin „${t.typ}" für ${t.fahrzeugRufname} am ${_formatDate(t.datum)} wirklich löschen?',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Abbrechen')),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Löschen'),
          ),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    try {
      await widget.fleetService.deleteTermin(widget.companyId, t.id);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Termin gelöscht.')));
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Fehler: $e')));
      }
    }
  }

  void _openTerminAdd(BuildContext context) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => _TerminEditScreen(
          companyId: widget.companyId,
          fleetService: widget.fleetService,
          termin: null,
          onBack: () => Navigator.of(context).pop(),
        ),
      ),
    );
  }
}

const _mangelStatusOptions = ['offen', 'inBearbeitung', 'selbstRepariert', 'repariert', 'abgeschlossen', 'geprueftEinsatzbereit'];
const _mangelStatusLabels = {
  'offen': 'Offen',
  'inbearbeitung': 'In Bearbeitung',
  'selbstrepariert': 'Selbst repariert',
  'repariert': 'Repariert',
  'abgeschlossen': 'Abgeschlossen',
  'gepruefteinsatzbereit': 'Geprüft und einsatzbereit',
};

class _MangelListTab extends StatefulWidget {
  final String companyId;
  final FleetService fleetService;

  const _MangelListTab({required this.companyId, required this.fleetService});

  @override
  State<_MangelListTab> createState() => _MangelListTabState();
}

class _MangelListTabState extends State<_MangelListTab> {
  String? _filterFahrzeug;
  String? _filterStatus;
  String? _filterKategorie;
  String? _filterPrioritaet;
  String? _filterStandort;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<FahrzeugMangel>>(
      stream: widget.fleetService.streamMaengel(widget.companyId),
      builder: (ctx, mangelSnap) {
        if (!mangelSnap.hasData) {
          return const Center(child: CircularProgressIndicator(color: AppTheme.primary));
        }
        final allMaengel = mangelSnap.data!;
        return StreamBuilder<List<Fahrzeug>>(
          stream: widget.fleetService.streamFahrzeuge(widget.companyId),
          builder: (ctx, fahrzeugSnap) {
            final fahrzeuge = fahrzeugSnap.data ?? [];
            final fahrzeugIdToWache = <String, String>{};
            for (final f in fahrzeuge) {
              if (f.wache != null && f.wache!.isNotEmpty) {
                fahrzeugIdToWache[f.id] = f.wache!;
              }
            }
            return FutureBuilder<List<Standort>>(
              future: widget.fleetService.loadStandorte(widget.companyId),
              builder: (ctx, standortSnap) {
                final standorte = standortSnap.data ?? [];
                final list = _filterMaengel(allMaengel, fahrzeuge, fahrzeugIdToWache, standorte);
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _buildHeaderAndFilters(fahrzeuge, standorte),
                    Expanded(
                      child: list.isEmpty
                          ? Center(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.build_outlined, size: 64, color: Colors.grey[400]),
                                  const SizedBox(height: 16),
                                  Text('Keine Mängel gemeldet', style: TextStyle(color: AppTheme.textSecondary)),
                                ],
                              ),
                            )
                          : ListView.separated(
                              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                              itemCount: list.length,
                              separatorBuilder: (_, __) => const Padding(
                                padding: EdgeInsets.symmetric(vertical: 12),
                                child: Divider(height: 2, thickness: 2, color: Color(0xFF9CA3AF)),
                              ),
                              itemBuilder: (_, i) => _buildMangelCard(list[i]),
                            ),
                    ),
                  ],
                );
              },
            );
          },
        );
      },
    );
  }

  List<FahrzeugMangel> _filterMaengel(
    List<FahrzeugMangel> list,
    List<Fahrzeug> fahrzeuge,
    Map<String, String> fahrzeugIdToWache,
    List<Standort> standorte,
  ) {
    var result = list;
    if (_filterFahrzeug != null && _filterFahrzeug!.isNotEmpty) {
      result = result.where((m) => m.fahrzeugId == _filterFahrzeug || m.displayLabel == _filterFahrzeug).toList();
    }
    if (_filterStatus != null && _filterStatus!.isNotEmpty) {
      result = result.where((m) => m.status.toLowerCase() == _filterStatus!.toLowerCase()).toList();
    }
    if (_filterKategorie != null && _filterKategorie!.isNotEmpty) {
      result = result.where((m) => m.kategorie == _filterKategorie).toList();
    }
    if (_filterPrioritaet != null && _filterPrioritaet!.isNotEmpty) {
      result = result.where((m) => (m.prioritaet ?? '').toLowerCase() == _filterPrioritaet!.toLowerCase()).toList();
    }
    if (_filterStandort != null && _filterStandort!.isNotEmpty) {
      result = result.where((m) => fahrzeugIdToWache[m.fahrzeugId] == _filterStandort).toList();
    }
    return result;
  }

  Widget _buildHeaderAndFilters(List<Fahrzeug> fahrzeuge, List<Standort> standorte) {
    final fahrzeugItems = ['', ...fahrzeuge.map((f) => f.id)];
    final fahrzeugLabels = {'': 'Alle Fahrzeuge', for (final f in fahrzeuge) f.id: (f.kennzeichen ?? f.rufname ?? f.displayName)};
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Alle Mängel', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold) ?? const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _buildFilterDropdown(
                label: 'Alle Fahrzeuge',
                value: _filterFahrzeug,
                items: fahrzeugItems,
                labels: fahrzeugLabels,
                onChanged: (v) => setState(() => _filterFahrzeug = v?.isEmpty == true ? null : v),
              ),
              _buildFilterDropdown(
                label: 'Alle Status',
                value: _filterStatus,
                items: ['', ..._mangelStatusOptions],
                labels: {'': 'Alle Status', for (final s in _mangelStatusOptions) s: _mangelStatusLabels[s.toLowerCase()] ?? s},
                onChanged: (v) => setState(() => _filterStatus = v?.isEmpty == true ? null : v),
              ),
              _buildFilterDropdown(
                label: 'Alle Kategorien',
                value: _filterKategorie,
                items: ['', ..._mangelKategorien],
                labels: {'': 'Alle Kategorien'},
                onChanged: (v) => setState(() => _filterKategorie = v?.isEmpty == true ? null : v),
              ),
              _buildFilterDropdown(
                label: 'Alle Prioritäten',
                value: _filterPrioritaet,
                items: ['', 'niedrig', 'mittel', 'hoch'],
                labels: {'': 'Alle Prioritäten', 'niedrig': 'Niedrig', 'mittel': 'Mittel', 'hoch': 'Hoch'},
                onChanged: (v) => setState(() => _filterPrioritaet = v?.isEmpty == true ? null : v),
              ),
              _buildFilterDropdown(
                label: 'Alle Standorte',
                value: _filterStandort,
                items: ['', ...standorte.map((s) => s.name)],
                labels: {'': 'Alle Standorte'},
                onChanged: (v) => setState(() => _filterStandort = v?.isEmpty == true ? null : v),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildFilterDropdown({
    required String label,
    required String? value,
    required List<String> items,
    Map<String, String>? labels,
    required ValueChanged<String?> onChanged,
  }) {
    final effectiveLabels = <String, String>{'': label};
    if (labels != null) effectiveLabels.addAll(labels);
    final currentValue = (value == null || value.isEmpty) ? '' : value;
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: currentValue,
          isExpanded: false,
          icon: const Icon(Icons.keyboard_arrow_down, size: 20),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          items: items.map((e) {
            final display = effectiveLabels[e] ?? (e.isEmpty ? label : e);
            return DropdownMenuItem(value: e, child: Text(display, style: const TextStyle(fontSize: 13)));
          }).toList(),
          onChanged: onChanged,
        ),
      ),
    );
  }

  Color _ampelColor(FahrzeugMangel m) {
    final p = m.prioritaet?.toLowerCase() ?? '';
    if (p == 'hoch') return const Color(0xFFef4444);
    if (p == 'mittel') return const Color(0xFFf59e0b);
    return const Color(0xFF22c55e);
  }

  String _formatDateTime(DateTime? d) {
    if (d == null) return '–';
    return '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.${d.year} - ${d.hour.toString().padLeft(2, '0')}.${d.minute.toString().padLeft(2, '0')}';
  }

  String _shortDesc(FahrzeugMangel m) => m.betreff?.trim().isNotEmpty == true
      ? m.betreff!
      : (m.beschreibung.split('\n').isNotEmpty ? m.beschreibung.split('\n').first : m.beschreibung);

  Widget _buildMangelCard(FahrzeugMangel m) {
    final statusNorm = m.status.toLowerCase();
    return Card(
              margin: EdgeInsets.zero,
              color: const Color(0xFFF5F5F5),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              child: InkWell(
                    borderRadius: BorderRadius.circular(8),
                    onTap: () => _openMangelEdit(context, m),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              m.displayLabel,
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                                color: Color(0xFF1e1f26),
                              ),
                            ),
                            const SizedBox(height: 6),
                            Wrap(
                              spacing: 16,
                              runSpacing: 2,
                              children: [
                                Text('Erfasst: ${_formatDateTime(m.createdAt)}', style: TextStyle(fontSize: 12, color: Colors.grey[600])),
                                if (m.kategorie != null && m.kategorie!.isNotEmpty)
                                  Text('Kategorie: ${m.kategorie}', style: TextStyle(fontSize: 12, color: Colors.grey[600])),
                                Text('Gemeldet von: ${m.melderName ?? 'Unbekannt'}', style: TextStyle(fontSize: 12, color: Colors.grey[600])),
                                Text('Letzte Bearbeitung: ${m.updatedAt != null ? _formatDateTime(m.updatedAt) : 'Unbekannt'}', style: TextStyle(fontSize: 12, color: Colors.grey[600])),
                              ],
                            ),
                            const SizedBox(height: 10),
                            Text(
                              _shortDesc(m),
                              style: const TextStyle(fontSize: 14, color: Color(0xFF1e1f26)),
                            ),
                          ],
                        ),
                      ),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              Text('MÄNGELAMPEL', style: TextStyle(fontSize: 10, color: Colors.grey[600], letterSpacing: 0.5)),
                              const SizedBox(height: 4),
                              Container(
                                width: 24,
                                height: 24,
                                decoration: BoxDecoration(
                                  color: _ampelColor(m),
                                  shape: BoxShape.circle,
                                  boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 2, offset: const Offset(0, 1))],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          GestureDetector(
                            onTap: () {},
                            behavior: HitTestBehavior.opaque,
                            child: Container(
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(color: const Color(0xFFe5e7eb)),
                              ),
                              child: PopupMenuButton<String>(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                                icon: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(_mangelStatusLabels[statusNorm] ?? m.status, style: const TextStyle(fontSize: 13, color: Color(0xFF1e1f26))),
                                    const Icon(Icons.keyboard_arrow_down, size: 20),
                                  ],
                                ),
                                offset: const Offset(0, 36),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                itemBuilder: (ctx) {
                                  final items = <PopupMenuEntry<String>>[];
                                  for (var i = 0; i < _mangelStatusOptions.length; i++) {
                                    if (i > 0) items.add(const PopupMenuDivider());
                                    final s = _mangelStatusOptions[i];
                                    final label = _mangelStatusLabels[s.toLowerCase()] ?? s;
                                    final isSelected = statusNorm == s.toLowerCase();
                                    items.add(PopupMenuItem<String>(
                                      value: s,
                                      child: Row(
                                        children: [
                                          if (isSelected) const Icon(Icons.check, size: 20, color: Colors.black) else const SizedBox(width: 20),
                                          if (isSelected) const SizedBox(width: 8),
                                          Text(label, style: const TextStyle(fontSize: 14, color: Colors.black)),
                                        ],
                                      ),
                                    ));
                                  }
                                  return items;
                                },
                                onSelected: (v) {
                                  if (v != statusNorm) {
                                    widget.fleetService.updateMangelStatus(widget.companyId, m.id, v);
                                  }
                                },
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            );
  }

  void _openMangelEdit(BuildContext context, FahrzeugMangel m) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => _MangelEditScreen(
          companyId: widget.companyId,
          fleetService: widget.fleetService,
          mangel: m,
          onBack: () => Navigator.of(context).pop(),
        ),
      ),
    );
  }
}

/// Vordefinierte Kategorien für Mängel (wie Web-App)
const _mangelKategorien = ['Getriebe', 'Motor', 'Bremsen', 'Elektrik', 'Bereifung', 'Karosserie', 'Innenausstattung', 'Sonstiges'];

class _MangelEditScreen extends StatefulWidget {
  final String companyId;
  final FleetService fleetService;
  final FahrzeugMangel mangel;
  final VoidCallback onBack;

  const _MangelEditScreen({required this.companyId, required this.fleetService, required this.mangel, required this.onBack});

  @override
  State<_MangelEditScreen> createState() => _MangelEditScreenState();
}

class _MangelEditScreenState extends State<_MangelEditScreen> {
  late TextEditingController _betreffController;
  late TextEditingController _beschreibungController;
  late TextEditingController _kennzeichenController;
  late TextEditingController _melderController;
  late TextEditingController _kilometerstandController;
  late DateTime _datum;
  late String _status;
  late String _prioritaet;
  late String _kategorie;
  bool _saving = false;
  List<XFile> _pickedImages = [];
  List<String> _existingBilderUrls = []; // Bereits in Firestore gespeicherte Bild-URLs

  @override
  void initState() {
    super.initState();
    final m = widget.mangel;
    _betreffController = TextEditingController(text: m.betreff ?? (m.beschreibung.split('\n').isNotEmpty ? m.beschreibung.split('\n').first : ''));
    _beschreibungController = TextEditingController(text: m.beschreibung);
    _kennzeichenController = TextEditingController(text: m.kennzeichen ?? '');
    _melderController = TextEditingController(text: m.melderName ?? '');
    _kilometerstandController = TextEditingController(text: m.kilometerstand?.toString() ?? '');
    _datum = m.datum ?? m.createdAt ?? DateTime.now();
    _status = m.status;
    _prioritaet = m.prioritaet ?? 'niedrig';
    final kat = m.kategorie?.trim();
    _kategorie = (kat != null && kat.isNotEmpty)
        ? kat
        : (_mangelKategorien.isNotEmpty ? _mangelKategorien.first : 'Sonstiges');
    _existingBilderUrls = List<String>.from(m.bilder);
  }

  @override
  void dispose() {
    _betreffController.dispose();
    _beschreibungController.dispose();
    _kennzeichenController.dispose();
    _melderController.dispose();
    _kilometerstandController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      List<String> bilder = List<String>.from(_existingBilderUrls);
      if (_pickedImages.isNotEmpty) {
        final bytesList = <Uint8List>[];
        final namesList = <String>[];
        for (final x in _pickedImages) {
          final b = await x.readAsBytes();
          bytesList.add(b);
          namesList.add(x.name);
        }
        final newUrls = await widget.fleetService.uploadMangelBilder(
          widget.companyId,
          widget.mangel.id,
          bytesList,
          namesList,
        );
        bilder.addAll(newUrls);
      }
      final km = int.tryParse(_kilometerstandController.text.trim());
      final updated = widget.mangel.copyWith(
        kennzeichen: _kennzeichenController.text.trim().isEmpty ? null : _kennzeichenController.text.trim(),
        betreff: _betreffController.text.trim().isEmpty ? null : _betreffController.text.trim(),
        beschreibung: _beschreibungController.text.trim(),
        kategorie: _kategorie,
        melderName: _melderController.text.trim().isEmpty ? null : _melderController.text.trim(),
        status: _status,
        prioritaet: _prioritaet,
        datum: _datum,
        kilometerstand: km,
        bilder: bilder,
      );
      await widget.fleetService.updateMangel(widget.companyId, updated);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Mangel aktualisiert.')));
        widget.onBack();
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Fehler: $e')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _delete() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Mangel löschen'),
        content: const Text('Möchten Sie diesen Mangel wirklich löschen? Diese Aktion kann nicht rückgängig gemacht werden.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Abbrechen')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Löschen'),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;
    setState(() => _saving = true);
    try {
      await widget.fleetService.deleteMangel(widget.companyId, widget.mangel.id);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Mangel gelöscht.')));
        widget.onBack();
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Fehler: $e')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _pickImages() async {
    try {
      final picker = ImagePicker();
      final files = await picker.pickMultiImage();
      if (files.isEmpty) return;
      if (mounted) setState(() {
        final remaining = 10 - _pickedImages.length;
        _pickedImages.addAll(files.take(remaining));
      });
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Fehler: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppTheme.buildModuleAppBar(
        title: 'Mangel bearbeiten',
        onBack: widget.onBack,
        leadingIcon: Icons.close,
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _buildDateField(),
                    const SizedBox(height: 16),
                    _buildTextField(_kennzeichenController, 'Kennzeichen *'),
                    const SizedBox(height: 16),
                    _buildKategorieDropdown(),
                    const SizedBox(height: 16),
                    _buildTextField(_melderController, 'Melder'),
                  ],
                ),
              ),
              const SizedBox(width: 24),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _buildStatusDropdown(),
                    const SizedBox(height: 16),
                    _buildTextField(_kilometerstandController, 'Kilometerstand *', keyboardType: TextInputType.number),
                    const SizedBox(height: 16),
                    _buildPrioritaetDropdown(),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          _buildTextField(_betreffController, 'Mangel (Kurzbeschreibung/Betreff) *'),
          const SizedBox(height: 16),
          _buildTextField(_beschreibungController, 'Mangelbeschreibung *', maxLines: 5),
          const SizedBox(height: 24),
          _buildImageUploadSection(),
          const SizedBox(height: 32),
          Row(
            children: [
              OutlinedButton.icon(
                onPressed: _saving ? null : _delete,
                icon: const Icon(Icons.delete_outline, size: 18),
                label: const Text('Mangel löschen'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.red,
                  side: const BorderSide(color: Colors.red),
                ),
              ),
              const Spacer(),
              TextButton(onPressed: widget.onBack, child: const Text('Abbrechen')),
              const SizedBox(width: 12),
              FilledButton(
                onPressed: _saving ? null : _save,
                child: _saving
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Text('Änderungen speichern'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildDateField() {
    return InputDecorator(
      decoration: const InputDecoration(
        labelText: 'Datum',
        filled: true,
        fillColor: Color(0xFFF5F5F5),
        border: OutlineInputBorder(borderSide: BorderSide(color: Color(0xFFE5E7EB))),
      ),
      child: InkWell(
        onTap: () async {
          final d = await showDatePicker(
            context: context,
            initialDate: _datum,
            firstDate: DateTime(2020),
            lastDate: DateTime(2030),
          );
          if (d != null) setState(() => _datum = DateTime(d.year, d.month, d.day));
        },
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('${_datum.day.toString().padLeft(2, '0')}.${_datum.month.toString().padLeft(2, '0')}.${_datum.year}'),
            const Icon(Icons.keyboard_arrow_down, size: 20),
          ],
        ),
      ),
    );
  }

  Widget _buildTextField(TextEditingController ctrl, String label, {int maxLines = 1, TextInputType? keyboardType}) {
    return TextFormField(
      controller: ctrl,
      maxLines: maxLines,
      keyboardType: keyboardType,
      decoration: InputDecoration(
        labelText: label,
        filled: true,
        fillColor: const Color(0xFFF5F5F5),
        border: const OutlineInputBorder(borderSide: BorderSide(color: Color(0xFFE5E7EB))),
      ),
    );
  }

  Widget _buildKategorieDropdown() {
    final options = _mangelKategorien.contains(_kategorie)
        ? _mangelKategorien
        : [_kategorie, ..._mangelKategorien];
    return InputDecorator(
      decoration: const InputDecoration(
        labelText: 'Kategorie *',
        filled: true,
        fillColor: Color(0xFFF5F5F5),
        border: OutlineInputBorder(borderSide: BorderSide(color: Color(0xFFE5E7EB))),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: _kategorie,
          isExpanded: true,
          items: options.map((k) => DropdownMenuItem(value: k, child: Text(k))).toList(),
          onChanged: (v) => setState(() => _kategorie = v ?? _mangelKategorien.first),
        ),
      ),
    );
  }

  Widget _buildStatusDropdown() {
    return InputDecorator(
      decoration: const InputDecoration(
        labelText: 'Status',
        filled: true,
        fillColor: Color(0xFFF5F5F5),
        border: OutlineInputBorder(borderSide: BorderSide(color: Color(0xFFE5E7EB))),
      ),
      child: PopupMenuButton<String>(
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(_mangelStatusLabels[_status.toLowerCase()] ?? _status),
            const Icon(Icons.keyboard_arrow_down, size: 20),
          ],
        ),
        itemBuilder: (ctx) {
          final items = <PopupMenuEntry<String>>[];
          for (var i = 0; i < _mangelStatusOptions.length; i++) {
            if (i > 0) items.add(const PopupMenuDivider());
            final s = _mangelStatusOptions[i];
            final label = _mangelStatusLabels[s.toLowerCase()] ?? s;
            final isSelected = _status.toLowerCase() == s.toLowerCase();
            items.add(PopupMenuItem<String>(
              value: s,
              child: Row(
                children: [
                  if (isSelected) const Icon(Icons.check, size: 20, color: Colors.black) else const SizedBox(width: 20),
                  if (isSelected) const SizedBox(width: 8),
                  Text(label, style: const TextStyle(fontSize: 14, color: Colors.black)),
                ],
              ),
            ));
          }
          return items;
        },
        onSelected: (v) => setState(() => _status = v),
      ),
    );
  }

  Widget _buildPrioritaetDropdown() {
    return InputDecorator(
      decoration: const InputDecoration(
        labelText: 'Priorität',
        filled: true,
        fillColor: Color(0xFFF5F5F5),
        border: OutlineInputBorder(borderSide: BorderSide(color: Color(0xFFE5E7EB))),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: ['niedrig', 'mittel', 'hoch'].contains(_prioritaet) ? _prioritaet : 'niedrig',
          isExpanded: true,
          items: const [
            DropdownMenuItem(value: 'niedrig', child: Text('Niedrig')),
            DropdownMenuItem(value: 'mittel', child: Text('Mittel')),
            DropdownMenuItem(value: 'hoch', child: Text('Hoch')),
          ],
          onChanged: (v) => setState(() => _prioritaet = v ?? 'niedrig'),
        ),
      ),
    );
  }

  void _removeExistingImage(int index) {
    setState(() => _existingBilderUrls.removeAt(index));
  }

  void _removePickedImage(int index) {
    setState(() => _pickedImages.removeAt(index));
  }

  Widget _buildImageUploadSection() {
    final totalCount = _existingBilderUrls.length + _pickedImages.length;
    final canAdd = totalCount < 10;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Bilder (max. 10)', style: TextStyle(fontSize: 14, color: Colors.grey[700], fontWeight: FontWeight.w500)),
        const SizedBox(height: 4),
        Text(
          'Im Mängelmelder hochgeladene Bilder erscheinen hier. Der Fahrzeugbeauftragte kann sie in der Bearbeitung einsehen und weitere ergänzen.',
          style: TextStyle(fontSize: 12, color: Colors.grey[600], fontStyle: FontStyle.italic),
        ),
        const SizedBox(height: 8),
        if (_existingBilderUrls.isNotEmpty || _pickedImages.isNotEmpty) ...[
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              ...List.generate(_existingBilderUrls.length, (i) => _buildImageThumbnail(url: _existingBilderUrls[i], onRemove: () => _removeExistingImage(i))),
              ...List.generate(_pickedImages.length, (i) => _buildPickedImageThumbnail(_pickedImages[i], () => _removePickedImage(i))),
            ],
          ),
          const SizedBox(height: 12),
        ],
        if (canAdd)
          GestureDetector(
            onTap: _pickImages,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 16),
              decoration: BoxDecoration(
                color: AppTheme.primary.withOpacity(0.08),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppTheme.primary, width: 2),
              ),
              child: Column(
                children: [
                  Icon(Icons.image_outlined, size: 48, color: AppTheme.primary.withOpacity(0.7)),
                  const SizedBox(height: 12),
                  Text(
                    totalCount == 0 ? 'Bilder hier ablegen oder' : '${totalCount} Bild(er) – weitere hinzufügen',
                    style: TextStyle(fontSize: 14, color: Colors.grey[700]),
                  ),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    onPressed: _pickImages,
                    icon: const Icon(Icons.add_photo_alternate, size: 18),
                    label: const Text('Dateien auswählen'),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildImageThumbnail({required String url, required VoidCallback onRemove}) {
    return Stack(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Image.network(
            url,
            width: 80,
            height: 80,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => Container(
              width: 80,
              height: 80,
              color: Colors.grey[300],
              child: const Icon(Icons.broken_image),
            ),
          ),
        ),
        Positioned(
          top: 4,
          right: 4,
          child: GestureDetector(
            onTap: onRemove,
            child: Container(
              padding: const EdgeInsets.all(4),
              decoration: const BoxDecoration(color: Colors.red, shape: BoxShape.circle),
              child: const Icon(Icons.close, size: 16, color: Colors.white),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildPickedImageThumbnail(XFile file, VoidCallback onRemove) {
    return Stack(
      children: [
        FutureBuilder<Uint8List>(
          future: file.readAsBytes(),
          builder: (ctx, snap) {
            if (!snap.hasData) return const SizedBox(width: 80, height: 80, child: Center(child: CircularProgressIndicator()));
            return ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.memory(
                snap.data!,
                width: 80,
                height: 80,
                fit: BoxFit.cover,
              ),
            );
          },
        ),
        Positioned(
          top: 4,
          right: 4,
          child: GestureDetector(
            onTap: onRemove,
            child: Container(
              padding: const EdgeInsets.all(4),
              decoration: const BoxDecoration(color: Colors.red, shape: BoxShape.circle),
              child: const Icon(Icons.close, size: 16, color: Colors.white),
            ),
          ),
        ),
      ],
    );
  }
}

class _FahrzeugEditScreen extends StatefulWidget {
  final String companyId;
  final FleetService fleetService;
  final Fahrzeug? fahrzeug;
  final VoidCallback onBack;

  const _FahrzeugEditScreen({
    required this.companyId,
    required this.fleetService,
    this.fahrzeug,
    required this.onBack,
  });

  @override
  State<_FahrzeugEditScreen> createState() => _FahrzeugEditScreenState();
}

class _FahrzeugEditScreenState extends State<_FahrzeugEditScreen> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _rufname, _kennzeichen, _hersteller, _modell;
  late TextEditingController _baujahr, _indienststellung, _traeger, _kostenstelle, _gruppe, _kraftstoff, _antrieb;
  bool _aktiv = true;
  List<String> _fahrzeugtypen = ['RTW', 'KTW', 'NEF', 'MTW', 'KEF', 'Sonstiges'];
  String _selectedFahrzeugtyp = '';
  List<Standort> _standorte = [];
  String? _selectedWache; // Standort-Name (für wache-Feld)
  bool _loading = true;
  bool _saving = false;
  bool _deleting = false;

  @override
  void initState() {
    super.initState();
    final f = widget.fahrzeug;
    _rufname = TextEditingController(text: f?.rufname ?? '');
    _selectedWache = f?.wache;
    _kennzeichen = TextEditingController(text: f?.kennzeichen ?? '');
    _hersteller = TextEditingController(text: f?.hersteller ?? '');
    _modell = TextEditingController(text: f?.modell ?? '');
    _baujahr = TextEditingController(text: f?.baujahr?.toString() ?? '');
    _indienststellung = TextEditingController(text: f?.indienststellung ?? '');
    _traeger = TextEditingController(text: f?.traeger ?? '');
    _kostenstelle = TextEditingController(text: f?.kostenstelle ?? '');
    _gruppe = TextEditingController(text: f?.gruppe ?? '');
    _kraftstoff = TextEditingController(text: f?.kraftstoff ?? '');
    _antrieb = TextEditingController(text: f?.antrieb ?? '');
    _aktiv = f?.aktiv ?? true;
    _selectedFahrzeugtyp = f?.fahrzeugtyp ?? '';
    _load();
  }

  Future<void> _load() async {
    final settings = await widget.fleetService.loadSettings(widget.companyId);
    final standorte = await widget.fleetService.loadStandorte(widget.companyId);
    if (!mounted) return;
    setState(() {
      _fahrzeugtypen = settings.fahrzeugtypen;
      _standorte = standorte;
      if (_selectedFahrzeugtyp.isEmpty && _fahrzeugtypen.isNotEmpty) _selectedFahrzeugtyp = _fahrzeugtypen.first;
      if (!_fahrzeugtypen.contains(_selectedFahrzeugtyp) && _selectedFahrzeugtyp.isNotEmpty) {
        _fahrzeugtypen = [_selectedFahrzeugtyp, ..._fahrzeugtypen];
      }
      if (_selectedWache != null && !standorte.any((s) => s.name == _selectedWache)) {
        _selectedWache = null; // Alter Wert existiert nicht mehr
      }
      if (_selectedWache == null && _standorte.isNotEmpty) _selectedWache = _standorte.first.name;
      _loading = false;
    });
  }

  @override
  void dispose() {
    _rufname.dispose();
    _kennzeichen.dispose();
    _hersteller.dispose();
    _modell.dispose();
    _baujahr.dispose();
    _indienststellung.dispose();
    _traeger.dispose();
    _kostenstelle.dispose();
    _gruppe.dispose();
    _kraftstoff.dispose();
    _antrieb.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      final f = Fahrzeug(
        id: widget.fahrzeug?.id ?? '',
        rufname: _rufname.text.trim().isEmpty ? null : _rufname.text.trim(),
        fahrzeugtyp: _selectedFahrzeugtyp.trim().isEmpty ? null : _selectedFahrzeugtyp.trim(),
        wache: (_selectedWache != null && _selectedWache!.trim().isNotEmpty) ? _selectedWache!.trim() : null,
        aktiv: _aktiv,
        kennzeichen: _kennzeichen.text.trim().isEmpty ? null : _kennzeichen.text.trim(),
        hersteller: _hersteller.text.trim().isEmpty ? null : _hersteller.text.trim(),
        modell: _modell.text.trim().isEmpty ? null : _modell.text.trim(),
        baujahr: int.tryParse(_baujahr.text.trim()),
        indienststellung: _indienststellung.text.trim().isEmpty ? null : _indienststellung.text.trim(),
        traeger: _traeger.text.trim().isEmpty ? null : _traeger.text.trim(),
        kostenstelle: _kostenstelle.text.trim().isEmpty ? null : _kostenstelle.text.trim(),
        gruppe: _gruppe.text.trim().isEmpty ? null : _gruppe.text.trim(),
        kraftstoff: _kraftstoff.text.trim().isEmpty ? null : _kraftstoff.text.trim(),
        antrieb: _antrieb.text.trim().isEmpty ? null : _antrieb.text.trim(),
        beauftragte: widget.fahrzeug?.beauftragte ?? [],
      );

      if (widget.fahrzeug != null) {
        await widget.fleetService.updateFahrzeug(widget.companyId, f);
      } else {
        await widget.fleetService.createFahrzeug(widget.companyId, f);
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Fahrzeug gespeichert.')));
        widget.onBack();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Fehler: $e')));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _confirmDeleteFahrzeug() async {
    final f = widget.fahrzeug;
    if (f == null) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Fahrzeug löschen?'),
        content: Text(
          'Fahrzeug „${f.displayName}" unwiderruflich löschen?',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Abbrechen')),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Löschen'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _deleting = true);
    try {
      await widget.fleetService.deleteFahrzeug(widget.companyId, f.id);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Fahrzeug gelöscht.')));
        widget.onBack();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Fehler: $e')));
      }
    } finally {
      if (mounted) setState(() => _deleting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.surfaceBg,
      appBar: AppTheme.buildModuleAppBar(
        title: widget.fahrzeug != null ? 'Fahrzeug bearbeiten' : 'Neues Fahrzeug',
        onBack: widget.onBack,
        leadingIcon: Icons.close,
        actions: [
          if (_saving)
            const Padding(padding: EdgeInsets.all(16), child: SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.primary)))
          else
            TextButton(onPressed: _save, child: const Text('Speichern')),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppTheme.primary))
          : ListView(
              padding: const EdgeInsets.all(20),
              children: [
                Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      TextFormField(controller: _rufname, decoration: const InputDecoration(labelText: 'Rufname *'), validator: (v) => (v?.trim().isEmpty ?? true) ? 'Pflichtfeld' : null),
                      const SizedBox(height: 16),
                      DropdownButtonFormField<String>(
                        value: _fahrzeugtypen.contains(_selectedFahrzeugtyp) ? _selectedFahrzeugtyp : (_fahrzeugtypen.isNotEmpty ? _fahrzeugtypen.first : null),
                        decoration: const InputDecoration(labelText: 'Fahrzeugtyp'),
                        items: _fahrzeugtypen.map((t) => DropdownMenuItem(value: t, child: Text(t))).toList(),
                        onChanged: (v) => setState(() => _selectedFahrzeugtyp = v ?? ''),
                      ),
                      const SizedBox(height: 16),
                      DropdownButtonFormField<String>(
                        value: _standorte.any((s) => s.name == _selectedWache) ? _selectedWache : (_standorte.isNotEmpty ? _standorte.first.name : null),
                        decoration: InputDecoration(
                          labelText: 'Wache',
                          helperText: _standorte.isEmpty ? 'Keine Standorte vorhanden. Bitte zuerst im Schichtplan anlegen.' : null,
                        ),
                        hint: const Text('Standort wählen'),
                        items: _standorte.map((s) => DropdownMenuItem(value: s.name, child: Text(s.name))).toList(),
                        onChanged: _standorte.isEmpty ? null : (v) => setState(() => _selectedWache = v),
                      ),
                      const SizedBox(height: 16),
                      SwitchListTile(title: const Text('Aktiv'), value: _aktiv, onChanged: (v) => setState(() => _aktiv = v ?? false)),
                      const SizedBox(height: 8),
                      TextFormField(controller: _kennzeichen, decoration: const InputDecoration(labelText: 'Kennzeichen')),
                      const SizedBox(height: 16),
                      TextFormField(controller: _hersteller, decoration: const InputDecoration(labelText: 'Hersteller')),
                      const SizedBox(height: 16),
                      TextFormField(controller: _modell, decoration: const InputDecoration(labelText: 'Modell')),
                      const SizedBox(height: 16),
                      TextFormField(controller: _baujahr, decoration: const InputDecoration(labelText: 'Baujahr'), keyboardType: TextInputType.number),
                      const SizedBox(height: 16),
                      TextFormField(controller: _indienststellung, decoration: const InputDecoration(labelText: 'Indienststellung (TT.MM.JJJJ)')),
                      const SizedBox(height: 16),
                      TextFormField(controller: _traeger, decoration: const InputDecoration(labelText: 'Träger')),
                      const SizedBox(height: 16),
                      TextFormField(controller: _kostenstelle, decoration: const InputDecoration(labelText: 'Kostenstelle')),
                      const SizedBox(height: 16),
                      TextFormField(controller: _gruppe, decoration: const InputDecoration(labelText: 'Gruppe')),
                      const SizedBox(height: 16),
                      TextFormField(controller: _kraftstoff, decoration: const InputDecoration(labelText: 'Kraftstoff')),
                      const SizedBox(height: 16),
                      TextFormField(controller: _antrieb, decoration: const InputDecoration(labelText: 'Antrieb')),
                      if (widget.fahrzeug != null) ...[
                        const SizedBox(height: 32),
                        const SizedBox(height: 32),
                        SizedBox(
                          width: double.infinity,
                          child: FilledButton.icon(
                            onPressed: _deleting ? null : _confirmDeleteFahrzeug,
                            icon: _deleting
                                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                                : const Icon(Icons.delete_outline),
                            label: Text(_deleting ? 'Wird gelöscht...' : 'Fahrzeug löschen'),
                            style: FilledButton.styleFrom(
                              backgroundColor: Colors.red,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 14),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
    );
  }
}

class _TerminEditScreen extends StatefulWidget {
  final String companyId;
  final FleetService fleetService;
  final FahrzeugTermin? termin;
  final VoidCallback onBack;

  const _TerminEditScreen({required this.companyId, required this.fleetService, this.termin, required this.onBack});

  @override
  State<_TerminEditScreen> createState() => _TerminEditScreenState();
}

class _TerminEditScreenState extends State<_TerminEditScreen> {
  List<Fahrzeug> _fahrzeuge = [];
  List<String> _terminarten = ['Werkstatt', 'TÜV', 'HU', 'AU', 'Sonstiges'];
  String? _selectedFahrzeugId;
  late DateTime _datum;
  String _selectedTyp = 'Werkstatt';
  final _notizController = TextEditingController();
  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final t = widget.termin;
    _datum = t?.datum ?? DateTime.now();
    _selectedTyp = t?.typ ?? 'Werkstatt';
    _notizController.text = t?.notiz ?? '';
    _selectedFahrzeugId = t?.fahrzeugId;
    _load();
  }

  Future<void> _load() async {
    final list = await widget.fleetService.streamFahrzeuge(widget.companyId).first;
    final settings = await widget.fleetService.loadSettings(widget.companyId);
    if (!mounted) return;
    setState(() {
      _fahrzeuge = list;
      _terminarten = settings.terminarten;
      if (!_terminarten.contains(_selectedTyp)) _selectedTyp = _terminarten.isNotEmpty ? _terminarten.first : 'Sonstiges';
      if (_selectedFahrzeugId == null && _fahrzeuge.isNotEmpty) _selectedFahrzeugId = _fahrzeuge.first.id;
      _loading = false;
    });
  }

  @override
  void dispose() {
    _notizController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final fId = _selectedFahrzeugId;
    if (fId == null || fId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Bitte Fahrzeug wählen.')));
      return;
    }
    String rufname = '';
    for (final f in _fahrzeuge) {
      if (f.id == fId) { rufname = f.displayName; break; }
    }
    setState(() => _saving = true);
    try {
      final t = FahrzeugTermin(
        id: '',
        fahrzeugId: fId,
        fahrzeugRufname: rufname,
        datum: _datum,
        typ: _selectedTyp,
        notiz: _notizController.text.trim().isEmpty ? null : _notizController.text.trim(),
      );
      await widget.fleetService.createTermin(widget.companyId, t);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Termin angelegt.')));
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
      backgroundColor: AppTheme.surfaceBg,
      appBar: AppTheme.buildModuleAppBar(
        title: 'Termin anlegen',
        onBack: widget.onBack,
        leadingIcon: Icons.close,
        actions: [
          if (_saving)
            const Padding(padding: EdgeInsets.all(16), child: SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.primary)))
          else
            TextButton(onPressed: _save, child: const Text('Speichern')),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppTheme.primary))
          : ListView(
              padding: const EdgeInsets.all(20),
              children: [
                DropdownButtonFormField<String>(
                  value: _selectedFahrzeugId,
                  decoration: const InputDecoration(labelText: 'Fahrzeug *'),
                  items: _fahrzeuge.map((f) => DropdownMenuItem(value: f.id, child: Text(f.displayName))).toList(),
                  onChanged: (v) => setState(() => _selectedFahrzeugId = v),
                ),
                const SizedBox(height: 16),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: InputDecorator(
                        decoration: InputDecoration(
                          labelText: 'Datum',
                          filled: true,
                          fillColor: Colors.white,
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(4)),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(4),
                            borderSide: const BorderSide(color: Color(0xFFCCCCCC)),
                          ),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                        ),
                        child: InkWell(
                          onTap: () async {
                            final d = await showDatePicker(context: context, initialDate: _datum, firstDate: DateTime(2020), lastDate: DateTime(2030));
                            if (d != null) setState(() => _datum = DateTime(d.year, d.month, d.day, _datum.hour, _datum.minute));
                          },
                          child: Row(
                            children: [
                              Icon(Icons.calendar_today, size: 20, color: AppTheme.textSecondary),
                              const SizedBox(width: 8),
                              Text(
                                '${_datum.day.toString().padLeft(2, '0')}.${_datum.month.toString().padLeft(2, '0')}.${_datum.year}',
                                style: Theme.of(context).textTheme.bodyLarge?.copyWith(color: AppTheme.textPrimary) ?? const TextStyle(fontSize: 16),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: InputDecorator(
                        decoration: InputDecoration(
                          labelText: 'Uhrzeit',
                          filled: true,
                          fillColor: Colors.white,
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(4)),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(4),
                            borderSide: const BorderSide(color: Color(0xFFCCCCCC)),
                          ),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                        ),
                        child: InkWell(
                          onTap: () async {
                            final t = await showTimePicker(
                              context: context,
                              initialTime: TimeOfDay(hour: _datum.hour, minute: _datum.minute),
                            );
                            if (t != null) setState(() => _datum = DateTime(_datum.year, _datum.month, _datum.day, t.hour, t.minute));
                          },
                          child: Row(
                            children: [
                              Icon(Icons.access_time, size: 20, color: AppTheme.textSecondary),
                              const SizedBox(width: 8),
                              Text(
                                '${_datum.hour.toString().padLeft(2, '0')}:${_datum.minute.toString().padLeft(2, '0')}',
                                style: Theme.of(context).textTheme.bodyLarge?.copyWith(color: AppTheme.textPrimary) ?? const TextStyle(fontSize: 16),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  value: _terminarten.contains(_selectedTyp) ? _selectedTyp : (_terminarten.isNotEmpty ? _terminarten.first : null),
                  decoration: const InputDecoration(labelText: 'Art'),
                  items: _terminarten.map((t) => DropdownMenuItem(value: t, child: Text(t))).toList(),
                  onChanged: (v) => setState(() => _selectedTyp = v ?? 'Sonstiges'),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _notizController,
                  decoration: const InputDecoration(labelText: 'Notiz'),
                  maxLines: 3,
                ),
              ],
            ),
    );
  }
}

class _FleetSettingsScreen extends StatefulWidget {
  final String companyId;
  final FleetService fleetService;
  final VoidCallback onBack;

  const _FleetSettingsScreen({required this.companyId, required this.fleetService, required this.onBack});

  @override
  State<_FleetSettingsScreen> createState() => _FleetSettingsScreenState();
}

class _FleetSettingsScreenState extends State<_FleetSettingsScreen> {
  FleetSettings? _settings;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final s = await widget.fleetService.loadSettings(widget.companyId);
    if (!mounted) return;
    setState(() {
      _settings = s;
      _loading = false;
    });
  }

  void _openMenuItem(String key) async {
    if (key == 'fahrzeugbeauftragte') {
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => _FahrzeugbeauftragteEditScreen(
            companyId: widget.companyId,
            fleetService: widget.fleetService,
            beauftragte: _settings?.fahrzeugbeauftragte ?? [],
            onBack: () => Navigator.of(context).pop(),
          ),
        ),
      );
    } else {
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => _FleetSettingEditScreen(
            companyId: widget.companyId,
            fleetService: widget.fleetService,
            settingKey: key,
            settings: _settings ?? FleetSettings(),
            onBack: () => Navigator.of(context).pop(),
          ),
        ),
      );
    }
    _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.surfaceBg,
      appBar: AppTheme.buildModuleAppBar(
        title: 'Einstellungen',
        onBack: widget.onBack,
        leadingIcon: Icons.close,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppTheme.primary))
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Card(
                  child: ListTile(
                    leading: CircleAvatar(backgroundColor: AppTheme.primary.withOpacity(0.2), child: Icon(Icons.directions_car, color: AppTheme.primary)),
                    title: const Text('Fahrzeugtypen', style: TextStyle(fontWeight: FontWeight.w600)),
                    subtitle: Text(
                      _settings?.fahrzeugtypen.join(', ') ?? '–',
                      style: TextStyle(fontSize: 13, color: AppTheme.textSecondary),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => _openMenuItem('fahrzeugtypen'),
                  ),
                ),
                const SizedBox(height: 8),
                Card(
                  child: ListTile(
                    leading: CircleAvatar(backgroundColor: AppTheme.primary.withOpacity(0.2), child: Icon(Icons.event, color: AppTheme.primary)),
                    title: const Text('Terminarten', style: TextStyle(fontWeight: FontWeight.w600)),
                    subtitle: Text(
                      _settings?.terminarten.join(', ') ?? '–',
                      style: TextStyle(fontSize: 13, color: AppTheme.textSecondary),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => _openMenuItem('terminarten'),
                  ),
                ),
                const SizedBox(height: 8),
                Card(
                  child: ListTile(
                    leading: CircleAvatar(backgroundColor: AppTheme.primary.withOpacity(0.2), child: Icon(Icons.notifications, color: AppTheme.primary)),
                    title: const Text('Erinnerungstage', style: TextStyle(fontWeight: FontWeight.w600)),
                    subtitle: Text(
                      _settings != null ? '${_settings!.erinnerungstage} Tage' : '–',
                      style: TextStyle(fontSize: 13, color: AppTheme.textSecondary),
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => _openMenuItem('erinnerungstage'),
                  ),
                ),
                const SizedBox(height: 8),
                Card(
                  child: ListTile(
                    leading: CircleAvatar(backgroundColor: AppTheme.primary.withOpacity(0.2), child: Icon(Icons.person, color: AppTheme.primary)),
                    title: const Text('Fahrzeugbeauftragte', style: TextStyle(fontWeight: FontWeight.w600)),
                    subtitle: Text(
                      _settings != null && _settings!.fahrzeugbeauftragte.isNotEmpty
                          ? '${_settings!.fahrzeugbeauftragte.length} Person(en)'
                          : '–',
                      style: TextStyle(fontSize: 13, color: AppTheme.textSecondary),
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => _openMenuItem('fahrzeugbeauftragte'),
                  ),
                ),
              ],
            ),
    );
  }
}

class _FahrzeugbeauftragteEditScreen extends StatefulWidget {
  final String companyId;
  final FleetService fleetService;
  final List<Fahrzeugbeauftragter> beauftragte;
  final VoidCallback onBack;

  const _FahrzeugbeauftragteEditScreen({
    required this.companyId,
    required this.fleetService,
    required this.beauftragte,
    required this.onBack,
  });

  @override
  State<_FahrzeugbeauftragteEditScreen> createState() => _FahrzeugbeauftragteEditScreenState();
}

class _FahrzeugbeauftragteEditScreenState extends State<_FahrzeugbeauftragteEditScreen> {
  late List<Fahrzeugbeauftragter> _list;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _list = List.from(widget.beauftragte);
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final settings = await widget.fleetService.loadSettings(widget.companyId);
      await widget.fleetService.saveSettings(widget.companyId, FleetSettings(
        fahrzeugtypen: settings.fahrzeugtypen,
        terminarten: settings.terminarten,
        erinnerungstage: settings.erinnerungstage,
        fahrzeugbeauftragte: _list,
      ));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Fahrzeugbeauftragte gespeichert.')));
        widget.onBack();
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Fehler: $e')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _showAddPicker() {
    showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Mitarbeiter auswählen',
      barrierColor: Colors.black54,
      transitionDuration: const Duration(milliseconds: 200),
      pageBuilder: (ctx, _, __) => Align(
        alignment: Alignment.topCenter,
        child: Material(
          color: Colors.white,
          borderRadius: const BorderRadius.vertical(bottom: Radius.circular(12)),
          child: SizedBox(
            width: MediaQuery.of(ctx).size.width,
            height: MediaQuery.of(ctx).size.height * 0.7,
            child: _BeauftragtePickerSheet(
              companyId: widget.companyId,
              fleetService: widget.fleetService,
              selected: List.from(_list),
              onConfirm: (list) {
                setState(() => _list = list);
                Navigator.of(ctx).pop();
              },
            ),
          ),
        ),
      ),
    );
  }

  void _remove(Fahrzeugbeauftragter b) {
    setState(() => _list.removeWhere((e) => e.uid == b.uid && e.name == b.name));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.surfaceBg,
      appBar: AppTheme.buildModuleAppBar(
        title: 'Fahrzeugbeauftragte',
        onBack: widget.onBack,
        leadingIcon: Icons.close,
        actions: [
          if (_saving)
            const Padding(padding: EdgeInsets.all(16), child: SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.primary)))
          else
            TextButton(onPressed: _save, child: const Text('Speichern')),
        ],
      ),
      body: _list.isEmpty
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.person_add, size: 64, color: Colors.grey[400]),
                  const SizedBox(height: 16),
                  Text('Keine Fahrzeugbeauftragte', style: TextStyle(color: AppTheme.textSecondary)),
                  const SizedBox(height: 8),
                  Text('Tippen Sie auf + um Mitarbeiter hinzuzufügen.', style: TextStyle(fontSize: 13, color: AppTheme.textSecondary)),
                ],
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: _list.length,
              itemBuilder: (_, i) {
                final b = _list[i];
                return Card(
                  margin: const EdgeInsets.only(bottom: 12),
                  child: ListTile(
                    leading: CircleAvatar(
                      backgroundColor: AppTheme.primary.withOpacity(0.2),
                      child: Icon(Icons.person, color: AppTheme.primary),
                    ),
                    title: Text(b.name, style: const TextStyle(fontWeight: FontWeight.w500)),
                    trailing: IconButton(
                      icon: const Icon(Icons.delete_outline, color: Colors.red),
                      tooltip: 'Entfernen',
                      onPressed: () => _remove(b),
                    ),
                  ),
                );
              },
            ),
      floatingActionButton: FloatingActionButton(
        onPressed: _showAddPicker,
        backgroundColor: AppTheme.primary,
        child: const Icon(Icons.add, color: Colors.white),
      ),
    );
  }
}

class _BeauftragtePickerSheet extends StatefulWidget {
  final String companyId;
  final FleetService fleetService;
  final List<Fahrzeugbeauftragter> selected;
  final void Function(List<Fahrzeugbeauftragter>) onConfirm;

  const _BeauftragtePickerSheet({
    required this.companyId,
    required this.fleetService,
    required this.selected,
    required this.onConfirm,
  });

  @override
  State<_BeauftragtePickerSheet> createState() => _BeauftragtePickerSheetState();
}

class _BeauftragtePickerSheetState extends State<_BeauftragtePickerSheet> {
  late List<Fahrzeugbeauftragter> _selected;
  List<Fahrzeugbeauftragter> _mitarbeiter = [];
  String _search = '';
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _selected = List.from(widget.selected);
    _load();
  }

  Future<void> _load() async {
    final list = await widget.fleetService.loadMitarbeiter(widget.companyId);
    if (!mounted) return;
    setState(() {
      _mitarbeiter = list;
      _loading = false;
    });
  }

  List<Fahrzeugbeauftragter> get _filtered {
    if (_search.isEmpty) return _mitarbeiter;
    final q = _search.toLowerCase();
    return _mitarbeiter.where((m) => m.name.toLowerCase().contains(q)).toList();
  }

  void _toggle(Fahrzeugbeauftragter m) {
    setState(() {
      final idx = _selected.indexWhere((s) => s.uid == m.uid && s.name == m.name);
      if (idx >= 0) {
        _selected.removeAt(idx);
      } else {
        _selected.add(m);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: TextField(
            decoration: InputDecoration(
              labelText: 'Mitarbeiter suchen',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: _search.isNotEmpty
                  ? IconButton(icon: const Icon(Icons.close), onPressed: () => setState(() => _search = ''))
                  : null,
            ),
            onChanged: (v) => setState(() => _search = v),
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator(color: AppTheme.primary))
              : ListView.builder(
                  itemCount: _filtered.length,
                  itemBuilder: (_, i) {
                    final m = _filtered[i];
                    final ok = _selected.any((s) => s.uid == m.uid && s.name == m.name);
                    return CheckboxListTile(value: ok, onChanged: (_) => _toggle(m), title: Text(m.name));
                  },
                ),
        ),
        Padding(
          padding: const EdgeInsets.all(16),
          child: FilledButton(
            onPressed: () => widget.onConfirm(_selected),
            style: FilledButton.styleFrom(backgroundColor: AppTheme.primary, minimumSize: const Size(double.infinity, 48)),
            child: Text('Übernehmen (${_selected.length})'),
          ),
        ),
      ],
    );
  }
}

class _FleetSettingEditScreen extends StatefulWidget {
  final String companyId;
  final FleetService fleetService;
  final String settingKey;
  final FleetSettings settings;
  final VoidCallback onBack;

  const _FleetSettingEditScreen({
    required this.companyId,
    required this.fleetService,
    required this.settingKey,
    required this.settings,
    required this.onBack,
  });

  @override
  State<_FleetSettingEditScreen> createState() => _FleetSettingEditScreenState();
}

class _FleetSettingEditScreenState extends State<_FleetSettingEditScreen> {
  List<String> _listItems = []; // für fahrzeugtypen und terminarten
  late TextEditingController _erinnerungController;
  late TextEditingController _addController;
  bool _saving = false;

  bool get _isListMode =>
      widget.settingKey == 'fahrzeugtypen' || widget.settingKey == 'terminarten';

  String get _title {
    switch (widget.settingKey) {
      case 'fahrzeugtypen': return 'Fahrzeugtypen';
      case 'terminarten': return 'Terminarten';
      case 'erinnerungstage': return 'Erinnerungstage';
      default: return 'Einstellung';
    }
  }

  String get _addHint {
    switch (widget.settingKey) {
      case 'fahrzeugtypen': return 'z.B. RTW, KTW, NEF';
      case 'terminarten': return 'z.B. Werkstatt, TÜV, HU';
      default: return 'Neuer Eintrag';
    }
  }

  String get _addLabel {
    switch (widget.settingKey) {
      case 'fahrzeugtypen': return 'Neuen Fahrzeugtyp hinzufügen';
      case 'terminarten': return 'Neue Terminart hinzufügen';
      default: return 'Neuen Eintrag hinzufügen';
    }
  }

  String get _listSectionTitle {
    switch (widget.settingKey) {
      case 'fahrzeugtypen': return 'Vorhandene Fahrzeugtypen';
      case 'terminarten': return 'Vorhandene Terminarten';
      default: return 'Vorhandene Einträge';
    }
  }

  String get _emptyHint {
    switch (widget.settingKey) {
      case 'fahrzeugtypen': return 'Noch keine Fahrzeugtypen. Fügen Sie oben einen hinzu.';
      case 'terminarten': return 'Noch keine Terminarten. Fügen Sie oben eine hinzu.';
      default: return 'Noch keine Einträge. Fügen Sie oben einen hinzu.';
    }
  }

  @override
  void initState() {
    super.initState();
    if (_isListMode) {
      _listItems = List.from(
        widget.settingKey == 'fahrzeugtypen'
            ? widget.settings.fahrzeugtypen
            : widget.settings.terminarten,
      );
      _addController = TextEditingController();
      _erinnerungController = TextEditingController();
    } else {
      _erinnerungController = TextEditingController(text: widget.settings.erinnerungstage.toString());
      _addController = TextEditingController();
    }
  }

  @override
  void dispose() {
    _addController.dispose();
    _erinnerungController.dispose();
    super.dispose();
  }

  void _addItem() {
    final text = _addController.text.trim();
    if (text.isEmpty) return;
    if (_listItems.any((e) => e.toLowerCase() == text.toLowerCase())) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Dieser Eintrag existiert bereits.')));
      return;
    }
    setState(() {
      _listItems.add(text);
      _addController.clear();
    });
  }

  void _removeItem(String item) {
    setState(() => _listItems.remove(item));
  }

  void _moveItemUp(int index) {
    if (index <= 0) return;
    setState(() {
      final tmp = _listItems[index];
      _listItems[index] = _listItems[index - 1];
      _listItems[index - 1] = tmp;
    });
  }

  void _moveItemDown(int index) {
    if (index >= _listItems.length - 1) return;
    setState(() {
      final tmp = _listItems[index];
      _listItems[index] = _listItems[index + 1];
      _listItems[index + 1] = tmp;
    });
  }

  Future<void> _save() async {
    FleetSettings newSettings;
    if (widget.settingKey == 'fahrzeugtypen') {
      if (_listItems.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Bitte mindestens einen Fahrzeugtyp angeben.')));
        return;
      }
      newSettings = FleetSettings(
        fahrzeugtypen: _listItems,
        terminarten: widget.settings.terminarten,
        erinnerungstage: widget.settings.erinnerungstage,
      );
    } else if (widget.settingKey == 'terminarten') {
      if (_listItems.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Bitte mindestens eine Terminart angeben.')));
        return;
      }
      newSettings = FleetSettings(
        fahrzeugtypen: widget.settings.fahrzeugtypen,
        terminarten: _listItems,
        erinnerungstage: widget.settings.erinnerungstage,
      );
    } else if (widget.settingKey == 'erinnerungstage') {
      final val = int.tryParse(_erinnerungController.text.trim()) ?? 14;
      if (val < 1 || val > 365) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Erinnerungstage zwischen 1 und 365.')));
        return;
      }
      newSettings = FleetSettings(
        fahrzeugtypen: widget.settings.fahrzeugtypen,
        terminarten: widget.settings.terminarten,
        erinnerungstage: val,
      );
    } else {
      return;
    }

    setState(() => _saving = true);
    try {
      await widget.fleetService.saveSettings(widget.companyId, newSettings);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Einstellung gespeichert.')));
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
      backgroundColor: AppTheme.surfaceBg,
      appBar: AppTheme.buildModuleAppBar(
        title: _title,
        onBack: widget.onBack,
        leadingIcon: Icons.close,
        actions: [
          if (_saving)
            const Padding(padding: EdgeInsets.all(16), child: SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.primary)))
          else
            TextButton(onPressed: _save, child: const Text('Speichern')),
        ],
      ),
      body: _isListMode
          ? _buildListBody()
          : _buildErinnerungstageBody(),
    );
  }

  Widget _buildListBody() {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Text(
          widget.settingKey == 'fahrzeugtypen'
              ? 'Fahrzeugtypen für die Stammdaten. Einträge einzeln hinzufügen oder entfernen.'
              : 'Terminarten für die Terminfestlegung. Einträge einzeln hinzufügen oder entfernen.',
          style: TextStyle(fontSize: 14, color: AppTheme.textSecondary),
        ),
        const SizedBox(height: 20),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _addController,
                decoration: InputDecoration(
                  labelText: _addLabel,
                  hintText: _addHint,
                  border: const OutlineInputBorder(),
                ),
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => _addItem(),
              ),
            ),
            const SizedBox(width: 12),
            IconButton.filled(
              onPressed: _addItem,
              icon: const Icon(Icons.add),
              tooltip: 'Hinzufügen',
              style: IconButton.styleFrom(backgroundColor: AppTheme.primary),
            ),
          ],
        ),
        const SizedBox(height: 24),
        Text(_listSectionTitle, style: const TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        if (_listItems.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: Text(_emptyHint, style: TextStyle(color: AppTheme.textSecondary)),
          )
        else
          ...List.generate(_listItems.length, (i) {
                final item = _listItems[i];
                final showReorder = widget.settingKey == 'terminarten';
                return Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: ListTile(
                    title: Text(item),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.delete_outline, color: Colors.red),
                          tooltip: 'Löschen',
                          onPressed: () => _removeItem(item),
                        ),
                        if (showReorder) ...[
                          IconButton(
                            icon: const Icon(Icons.arrow_upward),
                            tooltip: 'Nach oben',
                            onPressed: i > 0 ? () => _moveItemUp(i) : null,
                          ),
                          IconButton(
                            icon: const Icon(Icons.arrow_downward),
                            tooltip: 'Nach unten',
                            onPressed: i < _listItems.length - 1 ? () => _moveItemDown(i) : null,
                          ),
                        ],
                      ],
                    ),
                  ),
                );
              }),
      ],
    );
  }

  Widget _buildErinnerungstageBody() {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Text(
          'Tage vor einem Termin für Erinnerung (1–365).',
          style: TextStyle(fontSize: 14, color: AppTheme.textSecondary),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _erinnerungController,
          decoration: const InputDecoration(labelText: 'Erinnerungstage', hintText: '14'),
          keyboardType: TextInputType.number,
        ),
      ],
    );
  }
}
