import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../models/checkliste_model.dart';
import '../services/checklisten_service.dart';
import 'checkliste_ausfuellung_detail_screen.dart';

/// Gespeicherte Checklisten einsehen (nur für berechtigte Rollen)
class GespeicherteChecklistenScreen extends StatefulWidget {
  final String companyId;
  final String userRole;
  final VoidCallback onBack;

  const GespeicherteChecklistenScreen({
    super.key,
    required this.companyId,
    required this.userRole,
    required this.onBack,
  });

  static const _deleteRoles = ['superadmin', 'admin', 'geschaeftsfuehrung', 'rettungsdienstleitung'];
  static bool canDelete(String role) => _deleteRoles.contains(role.toLowerCase().trim());

  @override
  State<GespeicherteChecklistenScreen> createState() => _GespeicherteChecklistenScreenState();
}

class _GespeicherteChecklistenScreenState extends State<GespeicherteChecklistenScreen> {
  final _service = ChecklistenService();

  DateTime? _filterVon;
  DateTime? _filterBis;
  String? _filterStandort;
  String? _filterFahrzeug; // Format: "checklisteTitel|||kennzeichen"

  /// Überschrift: Fahrzeugkennung (checklisteTitel) und Kennzeichen
  static String _buildTitle(ChecklisteAusfuellung a) {
    final titel = (a.checklisteTitel ?? '').trim();
    final kz = (a.kennzeichen ?? '').trim();
    if (titel.isNotEmpty && kz.isNotEmpty) return '$titel · $kz';
    if (kz.isNotEmpty) return kz;
    return titel.isNotEmpty ? titel : 'Checkliste';
  }

  Future<void> _confirmDelete(BuildContext context, ChecklisteAusfuellung a) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Checkliste löschen?'),
        content: Text(
          'Möchten Sie die gespeicherte Checkliste „${_buildTitle(a)}" vom ${_fmt(a.createdAt)} wirklich löschen?',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Abbrechen')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Löschen'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await _service.deleteAusfuellung(widget.companyId, a.id);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Checkliste „${_buildTitle(a)}" wurde gelöscht.')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Fehler beim Löschen: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  static String _fmt(DateTime? d) {
    if (d == null) return '–';
    return '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.${d.year} '
        '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
  }

  List<ChecklisteAusfuellung> _applyFilter(List<ChecklisteAusfuellung> list) {
    return list.where((a) {
      if (_filterVon != null) {
        final d = a.createdAt;
        if (d == null) return false;
        if (d.isBefore(DateTime(_filterVon!.year, _filterVon!.month, _filterVon!.day))) return false;
      }
      if (_filterBis != null) {
        final d = a.createdAt;
        if (d == null) return false;
        final bisEnd = DateTime(_filterBis!.year, _filterBis!.month, _filterBis!.day, 23, 59, 59);
        if (d.isAfter(bisEnd)) return false;
      }
      if (_filterStandort != null && _filterStandort!.isNotEmpty) {
        final s = (a.standort ?? '').trim();
        if (s != _filterStandort) return false;
      }
      if (_filterFahrzeug != null && _filterFahrzeug!.isNotEmpty) {
        final parts = _filterFahrzeug!.split('|||');
        final wantTitel = parts.length > 1 ? parts[0] : '';
        final wantKz = parts.length > 1 ? parts[1] : parts[0];
        final titel = (a.checklisteTitel ?? '').trim();
        final kz = (a.kennzeichen ?? '').trim();
        if (titel != wantTitel || kz != wantKz) return false;
      }
      return true;
    }).toList();
  }

  void _resetFilter() {
    setState(() {
      _filterVon = null;
      _filterBis = null;
      _filterStandort = null;
      _filterFahrzeug = null;
    });
  }

  Future<void> _pickDateVon() async {
    final d = await showDatePicker(
      context: context,
      initialDate: _filterVon ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
    );
    if (d != null) setState(() => _filterVon = d);
  }

  Future<void> _pickDateBis() async {
    final d = await showDatePicker(
      context: context,
      initialDate: _filterBis ?? _filterVon ?? DateTime.now(),
      firstDate: _filterVon ?? DateTime(2020),
      lastDate: DateTime.now(),
    );
    if (d != null) setState(() => _filterBis = d);
  }

  static String _formatDateShort(DateTime? d) {
    if (d == null) return '–';
    return '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.${d.year}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.surfaceBg,
      appBar: AppTheme.buildModuleAppBar(
        title: 'Gespeicherte Checklisten',
        onBack: widget.onBack,
      ),
      body: StreamBuilder<List<ChecklisteAusfuellung>>(
        stream: _service.streamAusfuellungen(widget.companyId),
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting && !snap.hasData) {
            return const Center(child: CircularProgressIndicator(color: AppTheme.primary));
          }
          final allList = snap.data ?? [];
          final list = _applyFilter(allList);

          // Filter-Optionen aus allen Daten
          final standortOptions = allList
              .map((a) => (a.standort ?? '').trim())
              .where((s) => s.isNotEmpty)
              .toSet()
              .toList()
            ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
          final fahrzeugOptions = <String>[];
          for (final a in allList) {
            final titel = (a.checklisteTitel ?? '').trim();
            final kz = (a.kennzeichen ?? '').trim();
            final key = titel.isNotEmpty && kz.isNotEmpty ? '$titel|||$kz' : (kz.isNotEmpty ? kz : titel);
            if (key.isNotEmpty && !fahrzeugOptions.contains(key)) fahrzeugOptions.add(key);
          }
          fahrzeugOptions.sort((a, b) {
            final aDisplay = a.contains('|||') ? a.split('|||').last : a;
            final bDisplay = b.contains('|||') ? b.split('|||').last : b;
            return aDisplay.toLowerCase().compareTo(bDisplay.toLowerCase());
          });

          if (allList.isEmpty) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.folder_open_outlined, size: 64, color: Colors.grey[400]),
                  const SizedBox(height: 16),
                  Text(
                    'Noch keine gespeicherten Checklisten.',
                    style: TextStyle(color: Colors.grey[600], fontSize: 16),
                  ),
                ],
              ),
            );
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildFilterBar(context, standortOptions, fahrzeugOptions),
              Expanded(
                child: list.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.filter_list_off, size: 64, color: Colors.grey[400]),
                            const SizedBox(height: 16),
                            Text(
                              'Keine Checklisten im gewählten Filter.',
                              style: TextStyle(color: Colors.grey[600], fontSize: 16),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 12),
                            TextButton(
                              onPressed: _resetFilter,
                              child: const Text('Filter zurücksetzen'),
                            ),
                          ],
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                        itemCount: list.length,
                        itemBuilder: (_, i) {
                          final a = list[i];
                          final canDelete = GespeicherteChecklistenScreen.canDelete(widget.userRole);
                          return Card(
                            margin: const EdgeInsets.only(bottom: 8),
                            child: ListTile(
                              leading: CircleAvatar(
                                backgroundColor: AppTheme.primary.withOpacity(0.15),
                                child: Icon(Icons.check_circle_outline, color: AppTheme.primary),
                              ),
                              title: Text(_buildTitle(a), style: const TextStyle(fontWeight: FontWeight.w600)),
                              subtitle: Text(
                                '${_fmt(a.createdAt)} · ${a.createdByName ?? 'Unbekannt'}',
                                style: TextStyle(color: Colors.grey[600], fontSize: 13),
                              ),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  if (canDelete)
                                    IconButton(
                                      icon: Icon(Icons.delete_outline, color: Colors.red[700]),
                                      onPressed: () => _confirmDelete(context, a),
                                      tooltip: 'Löschen',
                                    ),
                                  const Icon(Icons.chevron_right),
                                ],
                              ),
                              onTap: () => Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) => ChecklisteAusfuellungDetailScreen(
                                    companyId: widget.companyId,
                                    ausfuellung: a,
                                    onBack: () => Navigator.of(context).pop(),
                                  ),
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
      ),
    );
  }

  Widget _buildFilterBar(
    BuildContext context,
    List<String> standortOptions,
    List<String> fahrzeugOptions,
  ) {
    final hasFilter = _filterVon != null || _filterBis != null ||
        (_filterStandort != null && _filterStandort!.isNotEmpty) ||
        (_filterFahrzeug != null && _filterFahrzeug!.isNotEmpty);
    return Container(
      padding: const EdgeInsets.all(16),
      color: Colors.white,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Filter',
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Colors.grey.shade700),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _FilterChip(
                label: 'Von: ${_formatDateShort(_filterVon)}',
                onTap: _pickDateVon,
              ),
              _FilterChip(
                label: 'Bis: ${_formatDateShort(_filterBis)}',
                onTap: _pickDateBis,
              ),
              if (standortOptions.isNotEmpty)
                _FilterDropdown<String>(
                  label: 'Standort',
                  value: _filterStandort,
                  options: [null, ...standortOptions],
                  display: (v) => v ?? 'Alle',
                  onChanged: (v) => setState(() => _filterStandort = v),
                ),
              if (fahrzeugOptions.isNotEmpty)
                _FilterDropdown<String>(
                  label: 'Fahrzeug',
                  value: _filterFahrzeug,
                  options: [null, ...fahrzeugOptions],
                  display: (v) {
                    if (v == null || v.isEmpty) return 'Alle';
                    if (v.contains('|||')) {
                      final parts = v.split('|||');
                      return '${parts[0]} · ${parts[1]}';
                    }
                    return v;
                  },
                  onChanged: (v) => setState(() => _filterFahrzeug = v),
                ),
              if (hasFilter)
                TextButton(
                  onPressed: _resetFilter,
                  child: const Text('Zurücksetzen'),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  final String label;
  final VoidCallback onTap;

  const _FilterChip({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: AppTheme.primary.withOpacity(0.1),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppTheme.primary.withOpacity(0.3)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(label, style: const TextStyle(fontSize: 13)),
            const SizedBox(width: 4),
            Icon(Icons.calendar_today, size: 16, color: AppTheme.primary),
          ],
        ),
      ),
    );
  }
}

class _FilterDropdown<T> extends StatelessWidget {
  final String label;
  final T? value;
  final List<T?> options;
  final String Function(T?) display;
  final ValueChanged<T?> onChanged;

  const _FilterDropdown({
    required this.label,
    required this.value,
    required this.options,
    required this.display,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<T?>(
      onSelected: (v) => onChanged(v),
      offset: const Offset(0, 40),
      padding: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      itemBuilder: (_) => options
          .map((o) => PopupMenuItem<T?>(
                value: o,
                child: Text(display(o)),
              ))
          .toList(),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: AppTheme.primary.withOpacity(0.1),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppTheme.primary.withOpacity(0.3)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('$label: ${display(value)}', style: const TextStyle(fontSize: 13)),
            const SizedBox(width: 4),
            Icon(Icons.arrow_drop_down, color: AppTheme.primary),
          ],
        ),
      ),
    );
  }
}
