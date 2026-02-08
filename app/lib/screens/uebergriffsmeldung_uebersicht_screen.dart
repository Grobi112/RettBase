import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../models/uebergriffsmeldung_model.dart';
import '../services/uebergriffsmeldung_service.dart';
import 'uebergriffsmeldung_bearbeiten_screen.dart';
import 'uebergriffsmeldung_druck_screen.dart';

String _formatDate(DateTime? d) {
  if (d == null) return '-';
  return '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.${d.year}';
}

String _shortBeschreibung(String? v) {
  final s = (v ?? '').trim();
  if (s.isEmpty) return '-';
  if (s.length <= 80) return s;
  return '${s.substring(0, 80)}...';
}

/// Uebersicht aller Uebergriffsmeldungen
class UebergriffsmeldungUebersichtScreen extends StatefulWidget {
  final String companyId;
  final VoidCallback? onBack;

  const UebergriffsmeldungUebersichtScreen({
    super.key,
    required this.companyId,
    this.onBack,
  });

  @override
  State<UebergriffsmeldungUebersichtScreen> createState() => _UebergriffsmeldungUebersichtScreenState();
}

class _UebergriffsmeldungUebersichtScreenState extends State<UebergriffsmeldungUebersichtScreen> {
  final _service = UebergriffsmeldungService();
  List<Uebergriffsmeldung> _list = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final list = await _service.loadAll(widget.companyId);
    if (mounted) {
      setState(() {
        _list = list;
        _loading = false;
      });
    }
  }

  void _openBearbeiten(Uebergriffsmeldung m) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => UebergriffsmeldungBearbeitenScreen(
          companyId: widget.companyId,
          meldung: m,
          onBack: () => Navigator.of(context).pop(),
        ),
      ),
    );
    if (mounted) _load();
  }

  void _openDrucken(Uebergriffsmeldung m) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => UebergriffsmeldungDruckScreen(
          meldung: m,
          onBack: () => Navigator.of(context).pop(),
        ),
      ),
    );
  }

  Future<void> _confirmDelete(Uebergriffsmeldung m) async {
    final ok = await showDialog<bool>(
      context: context,
      barrierDismissible: true,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Übergriffsmeldung löschen'),
        content: Text(
          'Möchten Sie die Übergriffsmeldung vom ${_str(m.datumUhrzeit)} wirklich löschen?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Abbrechen'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Löschen'),
          ),
        ],
      ),
    );
    if (ok == true && mounted) {
      await _service.delete(widget.companyId, m.id);
      if (mounted) _load();
    }
  }

  String _str(String? s) => (s ?? '').trim().isEmpty ? '-' : (s ?? '').trim();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.surfaceBg,
      appBar: AppTheme.buildModuleAppBar(
        title: 'Uebergriffsmeldungen',
        onBack: widget.onBack ?? () => Navigator.of(context).pop(),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppTheme.primary))
          : _list.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.inbox, size: 64, color: Colors.grey[400]),
                        const SizedBox(height: 16),
                        Text(
                          'Noch keine Übergriffsmeldungen.',
                          style: TextStyle(fontSize: 16, color: AppTheme.textSecondary),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: _list.length,
                    itemBuilder: (_, i) {
                      final m = _list[i];
                      return Card(
                        margin: const EdgeInsets.only(bottom: 12),
                        child: InkWell(
                          onTap: () => _openBearbeiten(m),
                          borderRadius: BorderRadius.circular(8),
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Text(
                                            _str(m.datumUhrzeit),
                                            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppTheme.primary),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 6),
                                      Text(
                                        _shortBeschreibung(m.beschreibung),
                                        style: const TextStyle(fontSize: 14, color: Color(0xFF1e1f26)),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        'von ${m.createdByName ?? 'Unbekannt'}',
                                        style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                                      ),
                                    ],
                                  ),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.print),
                                  tooltip: 'Drucken',
                                  onPressed: () => _openDrucken(m),
                                ),
                                IconButton(
                                  icon: Icon(Icons.delete_outline, color: Colors.red[700]),
                                  tooltip: 'Löschen',
                                  onPressed: () => _confirmDelete(m),
                                ),
                                const Icon(Icons.chevron_right, color: Colors.grey),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
    );
  }
}
