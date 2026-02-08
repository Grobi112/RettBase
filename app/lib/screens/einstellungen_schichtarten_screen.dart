import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../services/schichtanmeldung_service.dart';

/// Einstellungen: Schicht- und Standortverwaltung – Standorte anlegen, Schichtarten mit Start-/Endzeit.
class EinstellungenSchichtartenScreen extends StatefulWidget {
  final String companyId;
  final VoidCallback? onBack;

  const EinstellungenSchichtartenScreen({
    super.key,
    required this.companyId,
    this.onBack,
  });

  @override
  State<EinstellungenSchichtartenScreen> createState() => _EinstellungenSchichtartenScreenState();
}

class _EinstellungenSchichtartenScreenState extends State<EinstellungenSchichtartenScreen> {
  final _service = SchichtanmeldungService();
  List<Standort> _standorte = [];
  List<SchichtTyp> _schichten = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final standorte = await _service.loadStandorte(widget.companyId);
      final schichten = await _service.loadSchichten(widget.companyId);
      if (mounted) {
        setState(() {
          _standorte = standorte;
          _schichten = schichten;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _standortName(String? id) {
    if (id == null || id.isEmpty) return '–';
    final s = _standorte.where((x) => x.id == id).firstOrNull;
    return s?.name ?? id;
  }

  Future<void> _addStandort() async {
    final name = await _showStandortDialog();
    if (name == null || name.isEmpty) return;
    try {
      await _service.createStandort(widget.companyId, name, order: _standorte.length);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Standort angelegt.')));
        _load();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Fehler: $e')));
      }
    }
  }

  Future<String?> _showStandortDialog({String? currentName}) async {
    final ctrl = TextEditingController(text: currentName ?? '');
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(currentName != null ? 'Standort bearbeiten' : 'Neuer Standort'),
        content: TextField(
          controller: ctrl,
          decoration: const InputDecoration(
            labelText: 'Name',
            hintText: 'z.B. Wache Nord',
          ),
          autofocus: true,
          onSubmitted: (_) => Navigator.of(ctx).pop(ctrl.text.trim()),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Abbrechen')),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(ctrl.text.trim()),
            child: const Text('Speichern'),
          ),
        ],
      ),
    );
  }

  Future<void> _editStandort(Standort s) async {
    final name = await _showStandortDialog(currentName: s.name);
    if (name == null || name.isEmpty) return;
    try {
      await _service.updateStandort(widget.companyId, s.id, name, order: s.order);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Standort aktualisiert.')));
        _load();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Fehler: $e')));
      }
    }
  }

  Future<void> _deleteStandort(Standort s) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Standort löschen'),
        content: Text('Standort "${s.name}" wirklich löschen? Schichtarten an diesem Standort werden nicht gelöscht.'),
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
    if (ok != true) return;
    try {
      await _service.deleteStandort(widget.companyId, s.id);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Standort gelöscht.')));
        _load();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Fehler: $e')));
      }
    }
  }

  Future<void> _addSchicht() async {
    if (_standorte.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Bitte zuerst mindestens einen Standort anlegen.')),
      );
      return;
    }
    final data = await _showSchichtDialog();
    if (data == null) return;
    try {
      final s = SchichtTyp(
        id: '',
        name: data['name'] as String,
        standortId: data['standortId'] as String?,
        startTime: data['startTime'] as String?,
        endTime: data['endTime'] as String?,
        endetFolgetag: SchichtTyp.computeEndetFolgetag(data['startTime'] as String?, data['endTime'] as String?),
        order: _schichten.length,
      );
      await _service.createSchicht(widget.companyId, s);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Schichtart angelegt.')));
        _load();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Fehler: $e')));
      }
    }
  }

  Future<Map<String, dynamic>?> _showSchichtDialog({SchichtTyp? current}) async {
    final nameCtrl = TextEditingController(text: current?.name ?? '');
    String? standortId = current?.standortId ?? (_standorte.isNotEmpty ? _standorte.first.id : null);
    final startCtrl = TextEditingController(text: current?.startTime ?? '07:00');
    final endCtrl = TextEditingController(text: current?.endTime ?? '19:00');

    return showDialog<Map<String, dynamic>>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx2, setDialogState) => AlertDialog(
          title: Text(current != null ? 'Schichtart bearbeiten' : 'Neue Schichtart'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  controller: nameCtrl,
                  decoration: const InputDecoration(labelText: 'Name', hintText: 'z.B. Tagdienst'),
                  onSubmitted: (_) {},
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  value: standortId,
                  decoration: const InputDecoration(labelText: 'Standort'),
                  items: [
                    const DropdownMenuItem(value: null, child: Text('– Keiner –')),
                    ..._standorte.map((s) => DropdownMenuItem(value: s.id, child: Text(s.name))),
                  ],
                  onChanged: (v) => setDialogState(() => standortId = v),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: startCtrl,
                  decoration: const InputDecoration(labelText: 'Startzeit (HH:mm)', hintText: '07:00'),
                  onChanged: (_) => setDialogState(() {}),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: endCtrl,
                  decoration: const InputDecoration(labelText: 'Endzeit (HH:mm)', hintText: '19:00'),
                  onChanged: (_) => setDialogState(() {}),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Abbrechen')),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop({
                'name': nameCtrl.text.trim(),
                'standortId': standortId,
                'startTime': startCtrl.text.trim().isNotEmpty ? startCtrl.text.trim() : null,
                'endTime': endCtrl.text.trim().isNotEmpty ? endCtrl.text.trim() : null,
              }),
              child: const Text('Speichern'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _editSchicht(SchichtTyp s) async {
    final data = await _showSchichtDialog(current: s);
    if (data == null) return;
    try {
      final updated = SchichtTyp(
        id: s.id,
        name: data['name'] as String,
        standortId: data['standortId'] as String?,
        startTime: data['startTime'] as String?,
        endTime: data['endTime'] as String?,
        endetFolgetag: SchichtTyp.computeEndetFolgetag(data['startTime'] as String?, data['endTime'] as String?),
        order: s.order,
        active: s.active,
      );
      await _service.updateSchicht(widget.companyId, s.id, updated);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Schichtart aktualisiert.')));
        _load();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Fehler: $e')));
      }
    }
  }

  Future<void> _deleteSchicht(SchichtTyp s) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Schichtart löschen'),
        content: Text('Schichtart "${s.name}" wirklich löschen?'),
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
    if (ok != true) return;
    try {
      await _service.deleteSchicht(widget.companyId, s.id);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Schichtart gelöscht.')));
        _load();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Fehler: $e')));
      }
    }
  }

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
        title: Text('Schicht- und Standortverwaltung', style: TextStyle(color: AppTheme.primary, fontWeight: FontWeight.w600)),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppTheme.primary))
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _SectionHeader(title: 'Standorte', onAdd: _addStandort),
                const SizedBox(height: 8),
                if (_standorte.isEmpty)
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text('Keine Standorte. Tippen Sie auf + um einen anzulegen.', style: TextStyle(color: Colors.grey[600], fontSize: 14)),
                    ),
                  )
                else
                  ..._standorte.map((s) => Card(
                        child: ListTile(
                          title: Text(s.name),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(icon: const Icon(Icons.edit, size: 20), onPressed: () => _editStandort(s)),
                              IconButton(icon: Icon(Icons.delete, size: 20, color: Colors.red[700]), onPressed: () => _deleteStandort(s)),
                            ],
                          ),
                        ),
                      )),
                const SizedBox(height: 24),
                _SectionHeader(title: 'Schichtarten', onAdd: _addSchicht),
                const SizedBox(height: 8),
                if (_schichten.isEmpty)
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text('Keine Schichtarten. Tippen Sie auf + um eine anzulegen.', style: TextStyle(color: Colors.grey[600], fontSize: 14)),
                    ),
                  )
                else
                  ..._schichten.map((s) => Card(
                        child: ListTile(
                          title: Text(s.name),
                          subtitle: Text(
                            '${_standortName(s.standortId)} · ${s.startTime ?? '–'} – ${s.endTime ?? '–'}${s.endetFolgetag ? ' (Folgetag)' : ''}',
                            style: TextStyle(fontSize: 13, color: Colors.grey[600]),
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(icon: const Icon(Icons.edit, size: 20), onPressed: () => _editSchicht(s)),
                              IconButton(icon: Icon(Icons.delete, size: 20, color: Colors.red[700]), onPressed: () => _deleteSchicht(s)),
                            ],
                          ),
                        ),
                      )),
              ],
            ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  final VoidCallback onAdd;

  const _SectionHeader({required this.title, required this.onAdd});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(title, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
        IconButton(icon: const Icon(Icons.add), onPressed: onAdd, tooltip: 'Hinzufügen'),
      ],
    );
  }
}
