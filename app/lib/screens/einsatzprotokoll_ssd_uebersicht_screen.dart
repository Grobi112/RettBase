import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../theme/app_theme.dart';
import '../services/einsatzprotokoll_ssd_service.dart';
import 'einsatzprotokoll_ssd_druck_screen.dart';

String _formatDate(DateTime? d) {
  if (d == null) return '–';
  return '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.${d.year}';
}

/// Protokollübersicht – gespeicherte Einsatzprotokolle für Superadmin, Admin, LeiterSSD
class EinsatzprotokollSsdUebersichtScreen extends StatefulWidget {
  final String companyId;
  final String userRole;
  final VoidCallback onBack;

  const EinsatzprotokollSsdUebersichtScreen({
    super.key,
    required this.companyId,
    required this.userRole,
    required this.onBack,
  });

  @override
  State<EinsatzprotokollSsdUebersichtScreen> createState() => _EinsatzprotokollSsdUebersichtScreenState();
}

enum _FilterMode { jahr, datum }

class _EinsatzprotokollSsdUebersichtScreenState extends State<EinsatzprotokollSsdUebersichtScreen> {
  _FilterMode _filterMode = _FilterMode.jahr;
  int _filterYear = DateTime.now().year;
  DateTime _filterDate = DateTime.now();
  final _service = EinsatzprotokollSsdService();

  bool get _isSuperadmin =>
      (widget.userRole).toLowerCase().trim() == 'superadmin';

  @override
  void initState() {
    super.initState();
    _filterYear = DateTime.now().year;
    _filterDate = DateTime.now();
  }

  List<Map<String, dynamic>> _applyFilter(List<Map<String, dynamic>> list) {
    return list.where((p) {
      final createdAt = p['createdAt'] is Timestamp
          ? (p['createdAt'] as Timestamp).toDate()
          : null;
      if (createdAt == null) return false;
      if (_filterMode == _FilterMode.jahr) {
        return createdAt.year == _filterYear;
      } else {
        return createdAt.year == _filterDate.year &&
            createdAt.month == _filterDate.month &&
            createdAt.day == _filterDate.day;
      }
    }).toList();
  }

  List<int> get _years => List.generate(DateTime.now().year - 2020 + 1, (i) => 2020 + i).reversed.toList();

  Future<void> _pickDate() async {
    final d = await showDatePicker(
      context: context,
      initialDate: _filterDate,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
    );
    if (d != null) setState(() => _filterDate = d);
  }

  void _resetFilter() {
    final now = DateTime.now();
    setState(() {
      _filterYear = now.year;
      _filterDate = now;
    });
  }

  Future<void> _resetNextEinsatzNr(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Einsatz-Nr. zurücksetzen?'),
        content: const Text(
          'Die nächste Einsatz-Nr. wird auf 20260001 gesetzt. Das neue Protokoll erhält dann diese Nummer.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Abbrechen')),
          FilledButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Zurücksetzen')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await _service.setNextEinsatzNr(widget.companyId, '20260001');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Nächste Einsatz-Nr. wurde auf 20260001 gesetzt.')),
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

  Future<void> _confirmDelete(BuildContext context, String docId, String protokollNr) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Protokoll löschen?'),
        content: Text(
          'Möchten Sie Protokoll Nr. $protokollNr wirklich unwiderruflich löschen?',
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
      await _service.delete(widget.companyId, docId);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Protokoll Nr. $protokollNr wurde gelöscht.')),
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.surfaceBg,
      appBar: AppTheme.buildModuleAppBar(
        title: 'Protokollübersicht',
        onBack: widget.onBack,
        actions: [
          if (_isSuperadmin)
            IconButton(
              icon: const Icon(Icons.restart_alt),
              tooltip: 'Nächste Einsatz-Nr. auf 20260001 zurücksetzen',
              onPressed: () => _resetNextEinsatzNr(context),
            ),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildFilterBar(),
          Expanded(
            child: StreamBuilder<List<Map<String, dynamic>>>(
              stream: EinsatzprotokollSsdService().streamProtokolle(widget.companyId),
              builder: (context, snap) {
                if (snap.connectionState == ConnectionState.waiting && !snap.hasData) {
                  return const Center(child: CircularProgressIndicator(color: AppTheme.primary));
                }
                final allList = snap.data ?? [];
                final list = _applyFilter(allList);
                if (list.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.folder_open_outlined, size: 64, color: Colors.grey[400]),
                        const SizedBox(height: 16),
                        Text(
                          _filterMode == _FilterMode.jahr
                              ? 'Keine Protokolle im Jahr $_filterYear.'
                              : 'Keine Protokolle am ${_formatDate(_filterDate)}.',
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
                  );
                }
                return ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                  itemCount: list.length,
                  itemBuilder: (_, i) {
                    final p = list[i];
                    final id = p['id'] as String?;
                    final protokollNr = (p['protokollNr'] ?? '').toString().trim();
                    final name = '${(p['vornameErkrankter'] ?? '').toString().trim()} ${(p['nameErkrankter'] ?? '').toString().trim()}'.trim();
                    final datum = p['datumEinsatz']?.toString();
                    final createdAt = p['createdAt'] is Timestamp
                        ? (p['createdAt'] as Timestamp).toDate()
                        : null;
                    final createdByName = (p['createdByName'] ?? '').toString().trim();

                    return Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: AppTheme.primary.withValues(alpha: 0.15),
                          child: Icon(Icons.description_outlined, color: AppTheme.primary),
                        ),
                        title: Text(
                          protokollNr.isNotEmpty ? 'Protokoll Nr. $protokollNr' : 'Protokoll',
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        subtitle: Text(
                          '${name.isNotEmpty ? "$name · " : ""}${datum ?? _formatDate(createdAt)} · ${createdByName.isEmpty ? "–" : createdByName}',
                          style: TextStyle(color: Colors.grey[600], fontSize: 13),
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (_isSuperadmin && id != null)
                              IconButton(
                                icon: Icon(Icons.delete_outline, color: Colors.red[700]),
                                onPressed: () => _confirmDelete(context, id, protokollNr),
                                tooltip: 'Löschen',
                              ),
                            const Icon(Icons.chevron_right),
                          ],
                        ),
                        onTap: id != null
                            ? () => Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder: (_) => EinsatzprotokollSsdDruckScreen(
                                      companyId: widget.companyId,
                                      protokollId: id,
                                      protokoll: p,
                                      userRole: widget.userRole,
                                      onBack: () => Navigator.of(context).pop(),
                                    ),
                                  ),
                                )
                            : null,
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterBar() {
    return Container(
      padding: const EdgeInsets.all(16),
      color: Colors.white,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Suchen',
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Colors.grey.shade700),
          ),
          const SizedBox(height: 12),
          SegmentedButton<_FilterMode>(
            segments: const [
              ButtonSegment(value: _FilterMode.jahr, label: Text('Nach Jahr'), icon: Icon(Icons.calendar_month, size: 18)),
              ButtonSegment(value: _FilterMode.datum, label: Text('Nach Datum'), icon: Icon(Icons.today, size: 18)),
            ],
            selected: {_filterMode},
            onSelectionChanged: (s) => setState(() => _filterMode = s.first),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _filterMode == _FilterMode.jahr
                    ? DropdownButtonFormField<int>(
                        value: _filterYear,
                        decoration: InputDecoration(
                          filled: true,
                          fillColor: Colors.white,
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        ),
                        items: _years.map((y) => DropdownMenuItem(value: y, child: Text('$y'))).toList(),
                        onChanged: (v) => setState(() => _filterYear = v ?? DateTime.now().year),
                      )
                    : OutlinedButton.icon(
                        onPressed: _pickDate,
                        icon: const Icon(Icons.today, size: 18),
                        label: Text(_formatDate(_filterDate)),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppTheme.primary,
                          side: BorderSide(color: AppTheme.primary),
                        ),
                      ),
              ),
              const SizedBox(width: 8),
              IconButton(
                onPressed: _resetFilter,
                icon: const Icon(Icons.refresh),
                tooltip: 'Zurücksetzen',
                color: Colors.grey.shade600,
              ),
            ],
          ),
        ],
      ),
    );
  }
}
