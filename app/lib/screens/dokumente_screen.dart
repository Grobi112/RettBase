import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../models/dokumente_model.dart';
import '../services/dokumente_service.dart';
import '../services/auth_data_service.dart';
import '../services/auth_service.dart';
import 'dokumente_einstellungen_screen.dart';
import 'dokumente_ordner_screen.dart';

/// Dokumente – Übersicht über Ordner, Einstellungsrad für Ordnerverwaltung
class DokumenteScreen extends StatefulWidget {
  final String companyId;
  final String? userRole;
  final VoidCallback? onBack;

  const DokumenteScreen({
    super.key,
    required this.companyId,
    this.userRole,
    this.onBack,
  });

  @override
  State<DokumenteScreen> createState() => _DokumenteScreenState();
}

class _DokumenteScreenState extends State<DokumenteScreen> {
  final _service = DokumenteService();
  List<DokumenteOrdner> _ordner = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final list = await _service.loadOrdner(widget.companyId);
      if (mounted) {
        setState(() {
          _ordner = list;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _openEinstellungen() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => DokumenteEinstellungenScreen(
          companyId: widget.companyId,
          userRole: widget.userRole,
          onBack: () => Navigator.of(context).pop(),
        ),
      ),
    );
    if (mounted) _load();
  }

  void _openOrdner(DokumenteOrdner folder, List<DokumenteOrdner> breadcrumbs) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => DokumenteOrdnerScreen(
          companyId: widget.companyId,
          folder: folder,
          breadcrumbs: breadcrumbs,
          userRole: widget.userRole,
          onBack: () => Navigator.of(context).pop(),
        ),
      ),
    );
    if (mounted) _load();
  }

  @override
  Widget build(BuildContext context) {
    final rootFolders = _service.getChildFolders(_ordner, null);
    final canEdit = _service.canCreateFolders(widget.userRole);

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
        title: Text('Dokumente', style: TextStyle(color: AppTheme.primary, fontWeight: FontWeight.w600)),
        actions: [
          if (canEdit)
            IconButton(
              icon: const Icon(Icons.settings),
              tooltip: 'Ordnerstruktur verwalten',
              onPressed: _openEinstellungen,
            ),
          const SizedBox(width: 8),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppTheme.primary))
          : rootFolders.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.folder_open, size: 64, color: Colors.grey[400]),
                        const SizedBox(height: 16),
                        Text(
                          'Noch keine Ordner angelegt.',
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 16, color: AppTheme.textSecondary),
                        ),
                        if (canEdit) ...[
                          const SizedBox(height: 8),
                          Text(
                            'Tippen Sie auf das Zahnrad oben, um Ordnerstrukturen anzulegen.',
                            textAlign: TextAlign.center,
                            style: TextStyle(fontSize: 14, color: AppTheme.textMuted),
                          ),
                        ],
                      ],
                    ),
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: rootFolders.length,
                    itemBuilder: (context, i) {
                      final f = rootFolders[i];
                      return Card(
                        margin: const EdgeInsets.only(bottom: 12),
                        child: ListTile(
                          leading: Icon(Icons.folder, color: Colors.amber[700]),
                          title: Text(f.name, style: TextStyle(fontWeight: FontWeight.w500)),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () => _openOrdner(f, [f]),
                        ),
                      );
                    },
                  ),
                ),
    );
  }
}
