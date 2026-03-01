import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../services/informationssystem_service.dart';

/// Einstellungen im Informationssystem: Kategorien und Container-Typen verwalten
class InformationssystemEinstellungenScreen extends StatefulWidget {
  final String companyId;
  final VoidCallback onBack;
  final VoidCallback? onSaved;

  const InformationssystemEinstellungenScreen({
    super.key,
    required this.companyId,
    required this.onBack,
    this.onSaved,
  });

  @override
  State<InformationssystemEinstellungenScreen> createState() => _InformationssystemEinstellungenScreenState();
}

class _InformationssystemEinstellungenScreenState extends State<InformationssystemEinstellungenScreen> {
  final _service = InformationssystemService();

  List<MapEntry<String, String>> _containerTypes = [];
  List<String> _kategorien = [];
  List<String?> _slots = List.filled(InformationssystemService.maxContainerSlots, null);

  final _neueKategorieCtrl = TextEditingController();
  final _neuerTypIdCtrl = TextEditingController();
  final _neuerTypLabelCtrl = TextEditingController();

  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _neueKategorieCtrl.dispose();
    _neuerTypIdCtrl.dispose();
    _neuerTypLabelCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final results = await Future.wait([
        _service.loadContainerTypeLabels(widget.companyId),
        _service.loadContainerTypeOrder(widget.companyId),
        _service.loadKategorien(widget.companyId),
        _service.loadContainerOrder(widget.companyId),
      ]);
      if (mounted) {
        final labels = results[0] as Map<String, String>;
        final order = results[1] as List<String>;
        final kategorien = results[2] as List<String>;
        final rawSlots = results[3] as List<String?>;
        final orderSet = order.toSet();
        setState(() {
          _containerTypes = [
            ...order.map((id) => MapEntry(id, labels[id] ?? id)),
            ...labels.entries.where((e) => !orderSet.contains(e.key)),
          ];
          _kategorien = kategorien;
          _slots = rawSlots.asMap().entries.map((e) {
            if (e.key >= InformationssystemService.maxContainerSlots) return null;
            final s = e.value?.trim();
            if (s == null || s.isEmpty || s == 'null') return null;
            return orderSet.contains(s) ? s : null;
          }).toList();
          while (_slots.length < InformationssystemService.maxContainerSlots) {
            _slots.add(null);
          }
          _slots = _slots.take(InformationssystemService.maxContainerSlots).toList();
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _speichern() async {
    if (_containerTypes.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Mindestens ein Container-Typ erforderlich.')),
      );
      return;
    }

    setState(() => _saving = true);
    try {
      await _service.saveContainerTypesAndKategorien(
        widget.companyId,
        containerTypes: _containerTypes,
        kategorien: _kategorien,
        containerSlotsOverride: _slots,
      );
      if (mounted) {
        setState(() => _saving = false);
        widget.onSaved?.call();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Einstellungen gespeichert')),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Fehler: $e')),
        );
      }
    }
  }

  void _addKategorie() {
    final t = _neueKategorieCtrl.text.trim();
    if (t.isEmpty) return;
    if (_kategorien.contains(t)) return;
    setState(() {
      _kategorien = [..._kategorien, t];
      _neueKategorieCtrl.clear();
    });
  }

  void _reorderContainerTypes(int oldIndex, int newIndex) {
    setState(() {
      final item = _containerTypes.removeAt(oldIndex);
      if (newIndex > oldIndex) newIndex--;
      _containerTypes.insert(newIndex, item);
    });
  }

  void _reorderKategorien(int oldIndex, int newIndex) {
    setState(() {
      final item = _kategorien.removeAt(oldIndex);
      if (newIndex > oldIndex) newIndex--;
      _kategorien.insert(newIndex, item);
    });
  }

  void _ensureNoDuplicateSlot(String? selected, int changedIndex) {
    if (selected == null || selected.isEmpty) return;
    for (var i = 0; i < _slots.length; i++) {
      if (i != changedIndex && _slots[i] == selected) {
        _slots[i] = null;
      }
    }
  }

  void _addContainerTyp() {
    final id = _neuerTypIdCtrl.text.trim().toLowerCase().replaceAll(RegExp(r'[^a-z0-9_]'), '_');
    final label = _neuerTypLabelCtrl.text.trim();
    if (id.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Bitte eine ID eingeben (z.B. dienstanweisungen).')),
      );
      return;
    }
    if (_containerTypes.any((e) => e.key == id)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Diese Container-ID existiert bereits.')),
      );
      return;
    }
    setState(() {
      _containerTypes = [..._containerTypes, MapEntry(id, label.isEmpty ? id : label)];
      _neuerTypIdCtrl.clear();
      _neuerTypLabelCtrl.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.surfaceBg,
      appBar: AppTheme.buildModuleAppBar(
        title: 'Einstellungen',
        onBack: widget.onBack,
        leadingIcon: Icons.close,
        actions: [
          FilledButton(
            onPressed: (_loading || _saving) ? null : _speichern,
            style: FilledButton.styleFrom(backgroundColor: AppTheme.primary),
            child: _saving
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Text('Speichern'),
          ),
          const SizedBox(width: 16),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppTheme.primary))
          : ListView(
              padding: const EdgeInsets.all(20),
              children: [
                Card(
                  elevation: 1,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.category, color: AppTheme.primary, size: 28),
                            const SizedBox(width: 12),
                            Text('Container-Typen', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: AppTheme.textPrimary)),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Typen definieren die Tabs (von links nach rechts). Reihenfolge per Drag & Drop ändern.',
                          style: TextStyle(fontSize: 14, color: AppTheme.textSecondary),
                        ),
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            Expanded(
                              flex: 1,
                              child: TextField(
                                controller: _neuerTypIdCtrl,
                                decoration: const InputDecoration(
                                  labelText: 'ID (klein, z.B. dienstanweisungen)',
                                  border: OutlineInputBorder(),
                                ),
                                textCapitalization: TextCapitalization.none,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              flex: 2,
                              child: TextField(
                                controller: _neuerTypLabelCtrl,
                                decoration: const InputDecoration(
                                  labelText: 'Anzeigename',
                                  border: OutlineInputBorder(),
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            FilledButton.icon(
                              onPressed: _addContainerTyp,
                              icon: const Icon(Icons.add, size: 18),
                              label: const Text('Hinzufügen'),
                              style: FilledButton.styleFrom(backgroundColor: AppTheme.primary),
                            ),
                          ],
                        ),
                        if (_containerTypes.isNotEmpty) ...[
                          const SizedBox(height: 16),
                          ReorderableListView.builder(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            buildDefaultDragHandles: false,
                            itemCount: _containerTypes.length,
                            onReorder: _reorderContainerTypes,
                            itemBuilder: (context, index) {
                              final e = _containerTypes[index];
                              return ListTile(
                                key: ValueKey('container_${e.key}'),
                                leading: ReorderableDragStartListener(
                                  index: index,
                                  child: Icon(Icons.drag_handle, color: AppTheme.textMuted),
                                ),
                                title: Text('${e.value} (${e.key})'),
                                trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    if (_containerTypes.length > 1)
                                      IconButton(
                                        icon: const Icon(Icons.delete_outline),
                                        onPressed: () => setState(() => _containerTypes.removeAt(index)),
                                      ),
                                  ],
                                ),
                              );
                            },
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Card(
                  elevation: 1,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.dashboard, color: AppTheme.primary, size: 28),
                            const SizedBox(width: 12),
                            Text('Container auf Hauptseite', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: AppTheme.textPrimary)),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Welche Container sollen auf der Hauptseite angezeigt werden? (max. ${InformationssystemService.maxContainerSlots})',
                          style: TextStyle(fontSize: 14, color: AppTheme.textSecondary),
                        ),
                        const SizedBox(height: 16),
                        ...List.generate(InformationssystemService.maxContainerSlots, (i) {
                          return Padding(
                            padding: EdgeInsets.only(bottom: i < InformationssystemService.maxContainerSlots - 1 ? 12 : 0),
                            child: _SlotDropdown(
                              label: 'Position ${i + 1}',
                              value: i < _slots.length ? _slots[i] : null,
                              containerTypeIds: _containerTypes.map((e) => e.key).toList(),
                              containerLabels: {for (var e in _containerTypes) e.key: e.value},
                              onChanged: (v) => setState(() {
                                _slots = List<String?>.from(_slots);
                                while (_slots.length <= i) _slots.add(null);
                                _slots[i] = v;
                                _ensureNoDuplicateSlot(v, i);
                              }),
                            ),
                          );
                        }),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Card(
                  elevation: 1,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.label, color: AppTheme.primary, size: 28),
                            const SizedBox(width: 12),
                            Text('Kategorien', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: AppTheme.textPrimary)),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Kategorien werden im Dropdown angezeigt (von oben nach unten). Reihenfolge per Drag & Drop ändern.',
                          style: TextStyle(fontSize: 14, color: AppTheme.textSecondary),
                        ),
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: _neueKategorieCtrl,
                                decoration: const InputDecoration(
                                  labelText: 'Neue Kategorie',
                                  hintText: 'z.B. Allgemeine Information',
                                  border: OutlineInputBorder(),
                                ),
                                onSubmitted: (_) => _addKategorie(),
                              ),
                            ),
                            const SizedBox(width: 12),
                            FilledButton.icon(
                              onPressed: _addKategorie,
                              icon: const Icon(Icons.add, size: 18),
                              label: const Text('Hinzufügen'),
                              style: FilledButton.styleFrom(backgroundColor: AppTheme.primary),
                            ),
                          ],
                        ),
                        if (_kategorien.isNotEmpty) ...[
                          const SizedBox(height: 16),
                          ReorderableListView.builder(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            buildDefaultDragHandles: false,
                            itemCount: _kategorien.length,
                            onReorder: _reorderKategorien,
                            itemBuilder: (context, index) {
                              final k = _kategorien[index];
                              return ListTile(
                                key: ValueKey('kategorie_$k'),
                                leading: ReorderableDragStartListener(
                                  index: index,
                                  child: Icon(Icons.drag_handle, color: AppTheme.textMuted),
                                ),
                                title: Text(k),
                                trailing: IconButton(
                                  icon: const Icon(Icons.delete_outline),
                                  onPressed: () => setState(() => _kategorien.removeAt(index)),
                                ),
                              );
                            },
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}

class _SlotDropdown extends StatelessWidget {
  final String label;
  final String? value;
  final List<String> containerTypeIds;
  final Map<String, String> containerLabels;
  final void Function(String?) onChanged;

  const _SlotDropdown({
    required this.label,
    required this.value,
    required this.containerTypeIds,
    required this.containerLabels,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final options = [
      const DropdownMenuItem(value: null, child: Text('— Kein Container —')),
      ...containerTypeIds.map((id) => DropdownMenuItem(
            value: id,
            child: Text(containerLabels[id] ?? id),
          )),
    ];
    final safeValue = value == null || containerTypeIds.contains(value) ? value : null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: AppTheme.textPrimary)),
        const SizedBox(height: 8),
        DropdownButtonFormField<String?>(
          value: safeValue,
          decoration: InputDecoration(
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          ),
          items: options,
          onChanged: onChanged,
        ),
      ],
    );
  }
}
