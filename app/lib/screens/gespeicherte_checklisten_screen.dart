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

  Future<void> _confirmDelete(BuildContext context, ChecklisteAusfuellung a) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Checkliste löschen?'),
        content: Text(
          'Möchten Sie die gespeicherte Checkliste „${a.checklisteTitel}" vom ${_fmt(a.createdAt)} wirklich löschen?',
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
          SnackBar(content: Text('Checkliste „${a.checklisteTitel}" wurde gelöscht.')),
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
          final list = snap.data ?? [];
          if (list.isEmpty) {
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
          return ListView.builder(
            padding: const EdgeInsets.all(16),
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
                  title: Text(a.checklisteTitel, style: const TextStyle(fontWeight: FontWeight.w600)),
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
          );
        },
      ),
    );
  }
}
