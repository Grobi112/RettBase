import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../models/checkliste_model.dart';
import '../services/checklisten_service.dart';
import 'checkliste_erstellen_screen.dart';
import 'checkliste_ausfuellen_screen.dart';
import 'gespeicherte_checklisten_screen.dart';

/// Qualitätsmanagement – Checklisten-Übersicht
class ChecklistenUebersichtScreen extends StatefulWidget {
  final String companyId;
  final String userRole;
  final VoidCallback onBack;

  const ChecklistenUebersichtScreen({
    super.key,
    required this.companyId,
    required this.userRole,
    required this.onBack,
  });

  static const _editRoles = ['superadmin', 'admin', 'geschaeftsfuehrung', 'rettungsdienstleitung'];
  static const _viewSavedRoles = ['superadmin', 'admin', 'geschaeftsfuehrung', 'rettungsdienstleitung', 'wachleitung'];

  static bool canEdit(String role) => _editRoles.contains((role).toLowerCase().trim());
  static bool canViewSaved(String role) => _viewSavedRoles.contains((role).toLowerCase().trim());

  @override
  State<ChecklistenUebersichtScreen> createState() => _ChecklistenUebersichtScreenState();
}

class _ChecklistenUebersichtScreenState extends State<ChecklistenUebersichtScreen> {
  final _service = ChecklistenService();
  final _canEdit = ChecklistenUebersichtScreen.canEdit;
  final _canViewSaved = ChecklistenUebersichtScreen.canViewSaved;

  @override
  Widget build(BuildContext context) {
    final role = widget.userRole;
    final showEdit = _canEdit(role);
    final showSaved = _canViewSaved(role);

    return Scaffold(
      backgroundColor: AppTheme.surfaceBg,
      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: AppTheme.primary,
        elevation: 1,
        leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: widget.onBack),
        title: Text(
          'Checklisten',
          style: TextStyle(color: AppTheme.primary, fontWeight: FontWeight.w600, fontSize: 18),
        ),
      ),
      body: StreamBuilder<List<Checkliste>>(
        stream: _service.streamChecklisten(widget.companyId),
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting && !snap.hasData) {
            return const Center(child: CircularProgressIndicator(color: AppTheme.primary));
          }
          final list = snap.data ?? [];
          return ListView(
            padding: EdgeInsets.fromLTRB(16, 16, 16, MediaQuery.of(context).padding.bottom + (showEdit ? 80 : 24)),
            children: [
              if (showSaved) ...[
                Card(
                  margin: const EdgeInsets.only(bottom: 12),
                  child: ListTile(
                    leading: CircleAvatar(
                      backgroundColor: AppTheme.primary.withOpacity(0.15),
                      child: Icon(Icons.folder_open, color: AppTheme.primary),
                    ),
                    title: const Text('Gespeicherte Checklisten', style: TextStyle(fontWeight: FontWeight.w600)),
                    subtitle: const Text('Ausgefüllte Checklisten einsehen'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: _openGespeicherte,
                  ),
                ),
              ],
              if (list.isEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 32),
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.checklist_outlined, size: 64, color: Colors.grey[400]),
                        const SizedBox(height: 16),
                        Text(
                          'Noch keine Checklisten.',
                          style: TextStyle(color: Colors.grey[600], fontSize: 16),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          showEdit ? 'Tippen Sie auf + um eine neue Checkliste zu erstellen.' : 'Es wurden noch keine Checklisten angelegt.',
                          style: TextStyle(color: Colors.grey[500], fontSize: 14),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                )
              else
                ...list.map((c) => _buildChecklisteCard(c, showEdit)),
            ],
          );
        },
      ),
      floatingActionButton: showEdit
          ? FloatingActionButton(
              onPressed: _openErstellen,
              backgroundColor: AppTheme.primary,
              child: const Icon(Icons.add, color: Colors.white),
            )
          : null,
    );
  }

  Widget _buildChecklisteCard(Checkliste c, bool showEdit) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: AppTheme.primary.withOpacity(0.15),
          child: Icon(Icons.checklist, color: AppTheme.primary),
        ),
        title: Text(c.title, style: const TextStyle(fontWeight: FontWeight.w600)),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (showEdit)
              IconButton(
                icon: const Icon(Icons.edit_outlined),
                onPressed: () => _openBearbeiten(c),
                tooltip: 'Bearbeiten',
              ),
            const Icon(Icons.chevron_right),
          ],
        ),
        onTap: () => _openAusfuellen(c),
      ),
    );
  }

  void _openAusfuellen(Checkliste c) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ChecklisteAusfuellenScreen(
          key: ValueKey('ausfuellen_${c.id}_${DateTime.now().millisecondsSinceEpoch}'),
          companyId: widget.companyId,
          checkliste: c,
          onBack: () => Navigator.of(context).pop(),
        ),
      ),
    );
  }

  Future<void> _openErstellen() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ChecklisteErstellenScreen(
          companyId: widget.companyId,
          checkliste: null,
          onSaved: () => Navigator.of(context).pop(),
          onCancel: () => Navigator.of(context).pop(),
        ),
      ),
    );
  }

  Future<void> _openBearbeiten(Checkliste c) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ChecklisteErstellenScreen(
          companyId: widget.companyId,
          checkliste: c,
          onSaved: () => Navigator.of(context).pop(),
          onCancel: () => Navigator.of(context).pop(),
        ),
      ),
    );
  }

  void _openGespeicherte() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => GespeicherteChecklistenScreen(
          companyId: widget.companyId,
          userRole: widget.userRole,
          onBack: () => Navigator.of(context).pop(),
        ),
      ),
    );
  }
}
