import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../services/menueverwaltung_service.dart';
import '../services/modulverwaltung_service.dart';
import '../services/kundenverwaltung_service.dart';

/// Native Menü-Verwaltung – Bearbeitung der globalen Menüstruktur (settings/globalMenu).
/// Nur für Superadmin.
class MenueverwaltungScreen extends StatefulWidget {
  final String companyId;
  final String? userRole;
  final VoidCallback? onBack;
  final bool hideAppBar;

  const MenueverwaltungScreen({
    super.key,
    required this.companyId,
    this.userRole,
    this.onBack,
    this.hideAppBar = false,
  });

  @override
  State<MenueverwaltungScreen> createState() => _MenueverwaltungScreenState();
}

class _MenueverwaltungScreenState extends State<MenueverwaltungScreen> {
  final _menuService = MenueverwaltungService();
  final _modulService = ModulverwaltungService();
  final _kundenService = KundenverwaltungService();

  List<Map<String, dynamic>> _items = [];
  Map<String, Map<String, dynamic>> _availableModules = {};
  bool _loading = true;
  String? _error;
  bool _saving = false;

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
      final items = await _menuService.loadMenuStructure();
      var mods = await _modulService.getAllModules();
      if (mods.isEmpty) {
        final defs = await _kundenService.getAllModuleDefs();
        mods = {for (final e in defs.entries) e.key: {'id': e.key, ...e.value}};
      }
      if (mounted) {
        setState(() {
          _items = items;
          _availableModules = mods;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = 'Fehler: $e';
        });
      }
    }
  }

  Future<void> _save() async {
    if (widget.userRole != 'superadmin') return;
    setState(() => _saving = true);
    try {
      for (var i = 0; i < _items.length; i++) {
        _items[i]['order'] = i;
      }
      await _menuService.saveMenuStructure(_items);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Menü gespeichert.')));
        setState(() => _saving = false);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Fehler: $e'), backgroundColor: Colors.red));
      }
    }
  }

  void _addModule(String moduleId) {
    final m = _availableModules[moduleId];
    if (m == null) return;
    setState(() {
      _items.add({
        'id': moduleId,
        'label': m['label'] ?? moduleId,
        'url': m['url'] ?? '',
        'type': 'module',
        'level': 0,
        'order': _items.length,
      });
    });
  }

  void _addCustom() async {
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (ctx) => _CustomItemDialog(),
    );
    if (result != null && mounted) {
      setState(() {
        _items.add({
          'id': 'custom_${DateTime.now().millisecondsSinceEpoch}',
          'label': result['label'],
          'url': result['url'] ?? '',
          'type': 'custom',
          'level': 0,
          'order': _items.length,
        });
      });
    }
  }

  void _removeAt(int index) {
    setState(() => _items.removeAt(index));
  }

  void _editAt(int index) async {
    final item = _items[index];
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (ctx) => _CustomItemDialog(
        label: (item['label'] ?? '').toString(),
        url: (item['url'] ?? '').toString(),
      ),
    );
    if (result != null && mounted) {
      setState(() {
        _items[index] = {...item, 'label': result['label'], 'url': result['url'] ?? ''};
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final scaffold = Scaffold(
      backgroundColor: AppTheme.surfaceBg,
      appBar: AppTheme.buildModuleAppBar(
        title: 'Menü-Verwaltung',
        onBack: widget.onBack ?? () => Navigator.of(context).pop(),
        actions: [
          if (widget.userRole == 'superadmin')
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: MediaQuery.sizeOf(context).width < 400
                  ? IconButton(
                      onPressed: _saving ? null : _save,
                      icon: _saving ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Icon(Icons.save, size: 20),
                      style: IconButton.styleFrom(backgroundColor: AppTheme.primary, foregroundColor: Colors.white),
                      tooltip: 'Menü speichern',
                    )
                  : FilledButton.icon(
                      onPressed: _saving ? null : _save,
                      icon: _saving ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Icon(Icons.save, size: 20),
                      label: Text(_saving ? 'Speichert…' : 'Menü speichern'),
                      style: FilledButton.styleFrom(backgroundColor: AppTheme.primary),
                    ),
            ),
        ],
      ),
      body: _buildBody(),
    );

    if (widget.hideAppBar && widget.onBack != null) {
      return PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) widget.onBack!();
        },
        child: scaffold,
      );
    }
    return scaffold;
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator(color: AppTheme.primary));
    }
    if (widget.userRole != 'superadmin') {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            'Sie benötigen Superadmin-Rechte, um die Menüstruktur zu bearbeiten.',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppTheme.textMuted, fontSize: 16),
          ),
        ),
      );
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.error_outline, size: 48, color: Colors.red[400]),
              const SizedBox(height: 16),
              Text(_error!, textAlign: TextAlign.center, style: TextStyle(color: Colors.red[700])),
              const SizedBox(height: 16),
              FilledButton.icon(onPressed: _load, icon: const Icon(Icons.refresh), label: const Text('Erneut versuchen'), style: FilledButton.styleFrom(backgroundColor: AppTheme.primary)),
            ],
          ),
        ),
      );
    }

    final usedIds = _items.where((e) => (e['type'] ?? 'module') == 'module').map((e) => e['id']).toSet();
    final unusedModules = _availableModules.entries.where((e) => !usedIds.contains(e.key)).toList();

    return Column(
      children: [
        if (unusedModules.isNotEmpty)
          Container(
            padding: EdgeInsets.all(Responsive.horizontalPadding(context)),
            color: Colors.white,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('Modul hinzufügen', style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: unusedModules.map((e) {
                    final label = (e.value['label'] ?? e.key).toString();
                    return ActionChip(
                      label: Text(label),
                      onPressed: () => _addModule(e.key),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 8),
                TextButton.icon(
                  onPressed: _addCustom,
                  icon: const Icon(Icons.add_link),
                  label: const Text('Benutzerdefinierten Menüpunkt'),
                ),
              ],
            ),
          ),
        Expanded(
          child: ReorderableListView.builder(
            padding: EdgeInsets.fromLTRB(
              Responsive.horizontalPadding(context),
              16,
              Responsive.horizontalPadding(context),
              24,
            ),
            onReorder: (oldIndex, newIndex) {
              setState(() {
                final item = _items.removeAt(oldIndex);
                var idx = newIndex;
                if (idx > oldIndex) idx--;
                _items.insert(idx, item);
              });
            },
            itemCount: _items.length,
            itemBuilder: (ctx, i) {
              final item = _items[i];
              final label = (item['label'] ?? item['id'] ?? '').toString();
              final type = (item['type'] ?? 'module').toString();
              return Card(
                key: ValueKey(item['id'] ?? i),
                margin: const EdgeInsets.only(bottom: 8),
                child: ListTile(
                  leading: const Icon(Icons.drag_handle),
                  title: Text(label),
                  subtitle: type == 'custom' ? const Text('Benutzerdefiniert') : null,
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(icon: const Icon(Icons.edit, size: 20), onPressed: () => _editAt(i)),
                      IconButton(icon: Icon(Icons.delete, size: 20, color: Colors.red[700]), onPressed: () => _removeAt(i)),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _CustomItemDialog extends StatefulWidget {
  final String? label;
  final String? url;

  const _CustomItemDialog({this.label, this.url});

  @override
  State<_CustomItemDialog> createState() => _CustomItemDialogState();
}

class _CustomItemDialogState extends State<_CustomItemDialog> {
  late final TextEditingController _labelCtrl;
  late final TextEditingController _urlCtrl;

  @override
  void initState() {
    super.initState();
    _labelCtrl = TextEditingController(text: widget.label ?? '');
    _urlCtrl = TextEditingController(text: widget.url ?? '');
  }

  @override
  void dispose() {
    _labelCtrl.dispose();
    _urlCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.label == null ? 'Benutzerdefinierter Menüpunkt' : 'Menüpunkt bearbeiten'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(controller: _labelCtrl, decoration: const InputDecoration(labelText: 'Bezeichnung')),
          const SizedBox(height: 12),
          TextField(controller: _urlCtrl, decoration: const InputDecoration(labelText: 'URL (optional, # = Container)')),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Abbrechen')),
        FilledButton(
          onPressed: () {
            if (_labelCtrl.text.trim().isNotEmpty) {
              Navigator.of(context).pop({
                'label': _labelCtrl.text.trim(),
                'url': _urlCtrl.text.trim().isEmpty ? null : _urlCtrl.text.trim(),
              });
            }
          },
          child: const Text('Speichern'),
        ),
      ],
    );
  }
}
