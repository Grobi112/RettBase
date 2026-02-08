import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../models/dokumente_model.dart';
import '../services/dokumente_service.dart';
import '../services/auth_service.dart';

/// Einstellungen: Dokumente – Ordnerstruktur verwalten (Anlegen, Reihenfolge, Löschen)
class DokumenteEinstellungenScreen extends StatefulWidget {
  final String companyId;
  final String? userRole;
  final VoidCallback? onBack;

  const DokumenteEinstellungenScreen({
    super.key,
    required this.companyId,
    this.userRole,
    this.onBack,
  });

  @override
  State<DokumenteEinstellungenScreen> createState() => _DokumenteEinstellungenScreenState();
}

class _DokumenteEinstellungenScreenState extends State<DokumenteEinstellungenScreen> {
  final _service = DokumenteService();
  final _authService = AuthService();
  List<DokumenteOrdner> _ordner = [];
  bool _loading = true;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final list = await _service.loadOrdner(widget.companyId);
      if (mounted) {
        setState(() {
          _ordner = list;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = e.toString();
        });
      }
    }
  }

  Future<void> _addOrdner([String? parentId]) async {
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) {
        final ctrl = TextEditingController();
        return AlertDialog(
          title: Text(parentId == null ? 'Neuer Ordner' : 'Neuer Unterordner'),
          content: TextField(
            controller: ctrl,
            decoration: const InputDecoration(
              labelText: 'Ordnername',
              hintText: 'z.B. Formulare',
            ),
            autofocus: true,
            onSubmitted: (v) => Navigator.of(ctx).pop(v.trim()),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Abbrechen'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(ctrl.text.trim()),
              child: const Text('Anlegen'),
            ),
          ],
        );
      },
    );
    if (name == null || name.isEmpty) return;
    setState(() => _saving = true);
    try {
      final uid = _authService.currentUser?.uid ?? '';
      await _service.createOrdner(widget.companyId, name, (parentId == null || parentId.isEmpty) ? null : parentId, uid);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Ordner angelegt.')));
        _load();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Fehler: $e')));
        setState(() => _saving = false);
      }
    }
  }

  Future<void> _deleteOrdner(DokumenteOrdner folder) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Ordner löschen?'),
        content: Text('Möchten Sie „${folder.name}" wirklich löschen? Der Ordner muss leer sein.'),
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
    if (ok != true) return;
    setState(() => _saving = true);
    try {
      await _service.deleteOrdner(widget.companyId, folder.id);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Ordner gelöscht.')));
        _load();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Fehler: $e')));
        setState(() => _saving = false);
      }
    }
  }

  bool get _canEdit => _service.canCreateFolders(widget.userRole);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.surfaceBg,
      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: AppTheme.primary,
        elevation: 1,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: widget.onBack ?? () => Navigator.of(context).pop(),
        ),
        title: Text('Ordnerstruktur', style: TextStyle(color: AppTheme.primary, fontWeight: FontWeight.w600)),
        actions: [
          if (_canEdit)
            IconButton(
              icon: const Icon(Icons.create_new_folder),
              tooltip: 'Neuer Ordner',
              onPressed: _saving ? null : () => _addOrdner(),
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppTheme.primary))
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.error_outline, size: 48, color: Colors.grey[400]),
                        const SizedBox(height: 16),
                        Text(_error!, textAlign: TextAlign.center, style: TextStyle(color: Colors.grey[600])),
                        const SizedBox(height: 16),
                        FilledButton(
                          onPressed: _load,
                          child: const Text('Erneut laden'),
                        ),
                      ],
                    ),
                  ),
                )
              : _ordner.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(32),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.folder_open, size: 64, color: Colors.grey[400]),
                            const SizedBox(height: 16),
                            Text(
                              'Noch keine Ordner.',
                              style: TextStyle(fontSize: 16, color: AppTheme.textSecondary),
                            ),
                            if (_canEdit) ...[
                              const SizedBox(height: 16),
                              FilledButton.icon(
                                onPressed: () => _addOrdner(),
                                icon: const Icon(Icons.add),
                                label: const Text('Ersten Ordner anlegen'),
                              ),
                            ],
                          ],
                        ),
                      ),
                    )
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: ListView(
                        padding: const EdgeInsets.all(16),
                        children: _buildFolderList(null, 0),
                      ),
                    ),
    );
  }

  List<Widget> _buildFolderList(String? parentId, int level) {
    final children = _service.getChildFolders(_ordner, parentId);
    final widgets = <Widget>[];
    for (final f in children) {
      widgets.add(
        Padding(
          padding: EdgeInsets.only(left: level * 24.0, bottom: 8),
          child: Card(
            child: ListTile(
              leading: Icon(Icons.folder, color: Colors.amber[700]),
              title: Text(f.name, style: const TextStyle(fontWeight: FontWeight.w500)),
              trailing: _canEdit
                  ? Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.add, size: 20),
                          tooltip: 'Unterordner',
                          onPressed: () => _addOrdner(f.id),
                        ),
                        IconButton(
                          icon: Icon(Icons.delete_outline, size: 20, color: Colors.red[700]),
                          tooltip: 'Löschen',
                          onPressed: () => _deleteOrdner(f),
                        ),
                      ],
                    )
                  : null,
            ),
          ),
        ),
      );
      widgets.addAll(_buildFolderList(f.id, level + 1));
    }
    return widgets;
  }
}
