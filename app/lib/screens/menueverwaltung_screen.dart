import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../models/kunde_model.dart';
import '../services/menueverwaltung_service.dart';
import '../services/modulverwaltung_service.dart';
import '../services/kundenverwaltung_service.dart';
import '../services/modules_service.dart';

/// Native Menü-Verwaltung – WordPress-Style: links Einträge hinzufügen, rechts per Ziehen anordnen.
/// Ziehen nach rechts unter einen Oberbegriff = Unterpunkt (Dropdown).
class MenueverwaltungScreen extends StatefulWidget {
  final String companyId;
  final String? userRole;
  final VoidCallback? onBack;
  final VoidCallback? onMenuSaved;
  final bool hideAppBar;

  const MenueverwaltungScreen({
    super.key,
    required this.companyId,
    this.userRole,
    this.onBack,
    this.onMenuSaved,
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
  String _selectedBereich = KundenBereich.rettungsdienst;
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
      var items = await _menuService.loadMenuStructure(_selectedBereich);
      // Menü startet leer – keine Legacy-Migration, Nutzer legt alles selbst an
      var mods = await _modulService.getAllModules();
      if (mods.isEmpty) {
        final defs = await _kundenService.getAllModuleDefs();
        mods = {for (final e in defs.entries) e.key: {'id': e.key, ...e.value}};
      }
      for (final m in ModulesService.defaultNativeModules) {
        if (!mods.containsKey(m.id)) {
          mods[m.id] = {'id': m.id, 'label': m.label, 'url': m.url ?? ''};
        }
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

  Future<void> _clearMenu() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Menü leeren?'),
        content: const Text('Alle Menüeinträge werden gelöscht. Das können Sie nicht rückgängig machen. Fortfahren?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Abbrechen')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), style: FilledButton.styleFrom(backgroundColor: Colors.red), child: const Text('Menü leeren')),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _saving = true);
    try {
      await _menuService.saveMenuStructure(_selectedBereich, []);
      if (mounted) {
        setState(() {
          _items = [];
          _saving = false;
        });
        widget.onMenuSaved?.call();
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Menü geleert. Sie können jetzt neu anfangen.')));
      }
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Fehler: $e'), backgroundColor: Colors.red));
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
      await _menuService.saveMenuStructure(_selectedBereich, _items);
      if (mounted) {
        widget.onMenuSaved?.call();
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

  bool _isHeading(int topIndex) => (_items[topIndex]['type'] ?? '') == 'heading';

  List<Map<String, dynamic>> _getChildren(int topIndex) {
    final raw = _items[topIndex]['children'];
    if (raw is List) return raw.map((e) => Map<String, dynamic>.from(e as Map)).toList();
    return [];
  }

  void _setChildren(int topIndex, List<Map<String, dynamic>> children) {
    _items[topIndex] = {..._items[topIndex], 'children': children};
  }

  void _convertToHeading(int topIndex) {
    setState(() {
      _items[topIndex] = {
        'id': _items[topIndex]['id'] ?? 'heading_${DateTime.now().millisecondsSinceEpoch}',
        'label': _items[topIndex]['label'] ?? 'Oberbegriff',
        'type': 'heading',
        'children': [],
      };
    });
    _save();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Jetzt können Sie Unterpunkte hinzufügen (Symbol +).')));
    }
  }

  void _addHeading() {
    setState(() {
      _items.add({
        'id': 'heading_${DateTime.now().millisecondsSinceEpoch}',
        'label': 'Neuer Oberbegriff',
        'type': 'heading',
        'children': [],
        'order': _items.length,
      });
    });
  }

  void _addModule(String moduleId, {int? underHeadingIndex}) {
    final m = _availableModules[moduleId];
    if (m == null) return;
    final newItem = {
      'id': moduleId,
      'label': m['label'] ?? moduleId,
      'url': m['url'] ?? '',
      'type': 'module',
    };
    setState(() {
      if (underHeadingIndex != null && _isHeading(underHeadingIndex)) {
        final children = _getChildren(underHeadingIndex);
        if (children.length >= MenueverwaltungService.maxChildrenPerHeading) return;
        children.add(newItem);
        _setChildren(underHeadingIndex, children);
      } else {
        _items.add({...newItem, 'order': _items.length});
      }
    });
  }

  void _addCustom({int? underHeadingIndex}) async {
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (ctx) => _CustomItemDialog(),
    );
    if (result != null && mounted) {
      final newItem = {
        'id': 'custom_${DateTime.now().millisecondsSinceEpoch}',
        'label': result['label'],
        'url': result['url'] ?? '',
        'type': 'custom',
      };
      setState(() {
        if (underHeadingIndex != null && _isHeading(underHeadingIndex)) {
          final children = _getChildren(underHeadingIndex);
          if (children.length >= MenueverwaltungService.maxChildrenPerHeading) return;
          children.add(newItem);
          _setChildren(underHeadingIndex, children);
        } else {
          _items.add({...newItem, 'order': _items.length});
        }
      });
    }
  }

  void _removeAt(int topIndex, [int? childIndex]) {
    setState(() {
      if (childIndex != null) {
        final children = _getChildren(topIndex);
        children.removeAt(childIndex);
        _setChildren(topIndex, children);
      } else {
        _items.removeAt(topIndex);
      }
    });
  }

  void _editAt(int topIndex, [int? childIndex]) async {
    Map<String, dynamic> item;
    if (childIndex != null) {
      item = _getChildren(topIndex)[childIndex];
    } else {
      item = _items[topIndex];
    }
    if ((item['type'] ?? '') == 'heading') {
      final result = await showDialog<String>(
        context: context,
        builder: (ctx) => _HeadingEditDialog(label: (item['label'] ?? '').toString()),
      );
      if (result != null && mounted) {
        setState(() {
          if (childIndex != null) {
            final children = _getChildren(topIndex);
            children[childIndex]['label'] = result;
            _setChildren(topIndex, children);
          } else {
            _items[topIndex]['label'] = result;
          }
        });
      }
      return;
    }
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (ctx) => _CustomItemDialog(
        label: (item['label'] ?? '').toString(),
        url: (item['url'] ?? '').toString(),
      ),
    );
    if (result != null && mounted) {
      setState(() {
        if (childIndex != null) {
          final children = _getChildren(topIndex);
          children[childIndex] = {...children[childIndex], 'label': result['label'], 'url': result['url'] ?? ''};
          _setChildren(topIndex, children);
        } else {
          _items[topIndex] = {..._items[topIndex], 'label': result['label'], 'url': result['url'] ?? ''};
        }
      });
    }
  }

  /// Alle Modul-IDs die bereits im Menü verwendet werden
  Set<String> _usedModuleIds() {
    final used = <String>{};
    for (var i = 0; i < _items.length; i++) {
      if ((_items[i]['type'] ?? '') == 'module') {
        used.add((_items[i]['id'] ?? '').toString());
      }
      for (final c in _getChildren(i)) {
        if ((c['type'] ?? '') == 'module') used.add((c['id'] ?? '').toString());
      }
    }
    return used;
  }

  @override
  Widget build(BuildContext context) {
    final scaffold = Scaffold(
      backgroundColor: AppTheme.surfaceBg,
      appBar: AppTheme.buildModuleAppBar(
        title: 'Menü-Verwaltung',
        onBack: widget.onBack ?? () => Navigator.of(context).pop(),
        actions: [
          if (widget.userRole == 'superadmin') ...[
            IconButton(
              onPressed: _saving ? null : _clearMenu,
              icon: Icon(Icons.delete_sweep, size: 22, color: _saving ? Colors.grey : Colors.white70),
              tooltip: 'Menü leeren (neu anfangen)',
            ),
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

    return SingleChildScrollView(
      padding: EdgeInsets.all(Responsive.horizontalPadding(context)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DropdownButtonFormField<String>(
            value: _selectedBereich,
            decoration: const InputDecoration(labelText: 'Bereich', border: OutlineInputBorder()),
            items: KundenBereich.ids.map((id) => DropdownMenuItem(
              value: id,
              child: Text(KundenBereich.labels[id] ?? id),
            )).toList(),
            onChanged: (v) {
              if (v != null && v != _selectedBereich) {
                setState(() => _selectedBereich = v);
                _load();
              }
            },
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              FilledButton.icon(
                onPressed: _addHeading,
                icon: const Icon(Icons.folder_outlined, size: 18),
                label: const Text('Oberbegriff'),
                style: FilledButton.styleFrom(backgroundColor: AppTheme.primary),
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                onPressed: () => _showAddMenu(context),
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Hinzufügen'),
              ),
            ],
          ),
          const SizedBox(height: 20),
          if (_items.isEmpty)
            _buildEmptyState(context)
          else
            ...List.generate(_items.length, (i) => _buildMenuItem(context, i)),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  void _showAddMenu(BuildContext context) {
    final maxH = MediaQuery.of(context).size.height * 0.6;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: maxH),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Padding(
                padding: EdgeInsets.all(16),
                child: Text('Hinzufügen', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
              ),
              Flexible(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      ListTile(leading: const Icon(Icons.folder_outlined), title: const Text('Oberbegriff'), onTap: () { Navigator.pop(ctx); _addHeading(); }),
                      ListTile(leading: const Icon(Icons.list), title: const Text('Modul als eigenständigen Menüpunkt'), onTap: () { Navigator.pop(ctx); _showModulePicker(underHeadingIndex: null); }),
                      ..._items.asMap().entries.where((e) => _isHeading(e.key) && _getChildren(e.key).length < MenueverwaltungService.maxChildrenPerHeading).map((e) {
                        final label = (_items[e.key]['label'] ?? 'Oberbegriff').toString();
                        return ListTile(leading: const Icon(Icons.subdirectory_arrow_right), title: Text('Modul unter „$label"'), onTap: () { Navigator.pop(ctx); _showModulePicker(underHeadingIndex: e.key); });
                      }),
                      ListTile(leading: const Icon(Icons.add_link), title: const Text('Benutzerdefinierter Link'), onTap: () { Navigator.pop(ctx); _addCustom(); }),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showModulePicker({int? underHeadingIndex}) {
    final usedIds = _usedModuleIds();
    final available = _availableModules.entries
        .where((e) => !usedIds.contains(e.key))
        .toList()
      ..sort((a, b) {
        final la = (a.value['label'] ?? a.key).toString().toLowerCase();
        final lb = (b.value['label'] ?? b.key).toString().toLowerCase();
        return la.compareTo(lb);
      });
    final maxH = MediaQuery.of(context).size.height * 0.75;
    showDialog(
      context: context,
      builder: (ctx) => _ModulePickerDialog(
        availableModules: available,
        underHeadingIndex: underHeadingIndex,
        maxHeight: maxH,
        onAddModule: _addModule,
        onAddCustom: _addCustom,
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.menu_book, size: 48, color: Colors.grey[400]),
          const SizedBox(height: 16),
          Text('Menü ist leer. Klicken Sie „Oberbegriff" oder „Hinzufügen".', style: Theme.of(context).textTheme.bodyLarge?.copyWith(color: AppTheme.textMuted)),
        ],
      ),
    );
  }

  Widget _buildMenuItem(BuildContext context, int topIndex) {
    final item = _items[topIndex];
    final type = (item['type'] ?? 'module').toString();
    final isHeading = type == 'heading';
    final children = _getChildren(topIndex);

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (isHeading) ...[
            _buildHeadingCard(context, topIndex, item, children),
            ...children.asMap().entries.map((e) => Padding(
              padding: const EdgeInsets.only(left: 20, top: 4),
              child: _buildItemCard(context, topIndex, e.key, e.value),
            )),
            if (children.length < MenueverwaltungService.maxChildrenPerHeading)
              Padding(
                padding: const EdgeInsets.only(left: 20, top: 4),
                child: TextButton.icon(
                  onPressed: () => _showModulePicker(underHeadingIndex: topIndex),
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Unterpunkt hinzufügen'),
                ),
              ),
          ] else
            _buildItemCard(context, topIndex, null, item),
        ],
      ),
    );
  }

  Widget _buildHeadingCard(BuildContext context, int topIndex, Map<String, dynamic> item, List<Map<String, dynamic>> children) {
    final label = (item['label'] ?? '').toString();
    return Card(
      child: ListTile(
        leading: const Icon(Icons.folder_outlined, color: AppTheme.primary),
        title: Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (children.length < MenueverwaltungService.maxChildrenPerHeading)
              IconButton(icon: const Icon(Icons.add, size: 20), onPressed: () => _showModulePicker(underHeadingIndex: topIndex), tooltip: 'Unterpunkt'),
            IconButton(icon: const Icon(Icons.edit, size: 20), onPressed: () => _editAt(topIndex)),
            IconButton(icon: Icon(Icons.delete, size: 20, color: Colors.red[700]), onPressed: () => _removeAt(topIndex)),
          ],
        ),
      ),
    );
  }


  Widget _buildItemCard(BuildContext context, int topIndex, int? childIndex, Map<String, dynamic> item) {
    final label = (item['label'] ?? item['id'] ?? '').toString();
    final type = (item['type'] ?? 'module').toString();
    final isTopLevel = childIndex == null;
    return Card(
      child: ListTile(
        leading: Icon(type == 'custom' ? Icons.link : Icons.apps, size: 22, color: Colors.grey[600]),
        title: Text(label),
        subtitle: type == 'custom' ? const Text('Benutzerdefiniert') : null,
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (isTopLevel)
              IconButton(
                icon: const Icon(Icons.folder_outlined, size: 20),
                onPressed: () => _convertToHeading(topIndex),
                tooltip: 'Zu Oberbegriff machen (Unterpunkte hinzufügen)',
              ),
            IconButton(icon: const Icon(Icons.edit, size: 20), onPressed: () => _editAt(topIndex, childIndex)),
            IconButton(icon: Icon(Icons.delete, size: 20, color: Colors.red[700]), onPressed: () => _removeAt(topIndex, childIndex)),
          ],
        ),
      ),
    );
  }
}

class _ModulePickerDialog extends StatefulWidget {
  final List<MapEntry<String, Map<String, dynamic>>> availableModules;
  final int? underHeadingIndex;
  final double maxHeight;
  final void Function(String moduleId, {int? underHeadingIndex}) onAddModule;
  final void Function({int? underHeadingIndex}) onAddCustom;

  const _ModulePickerDialog({
    required this.availableModules,
    required this.underHeadingIndex,
    required this.maxHeight,
    required this.onAddModule,
    required this.onAddCustom,
  });

  @override
  State<_ModulePickerDialog> createState() => _ModulePickerDialogState();
}

class _ModulePickerDialogState extends State<_ModulePickerDialog> {
  final _searchCtrl = TextEditingController();
  String _query = '';

  @override
  void initState() {
    super.initState();
    _searchCtrl.addListener(() => setState(() => _query = _searchCtrl.text.trim().toLowerCase()));
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _query.isEmpty
        ? widget.availableModules
        : widget.availableModules.where((e) {
            final label = (e.value['label'] ?? e.key).toString().toLowerCase();
            return label.contains(_query);
          }).toList();
    return AlertDialog(
      title: const Text('Modul wählen'),
      content: SizedBox(
        width: double.maxFinite,
        height: widget.maxHeight,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _searchCtrl,
              decoration: InputDecoration(
                hintText: 'Suchen...',
                prefixIcon: const Icon(Icons.search, size: 22),
                border: const OutlineInputBorder(),
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              ),
              autofocus: true,
            ),
            const SizedBox(height: 12),
            Expanded(
              child: ListView(
                children: [
                  ...filtered.map((e) {
                    final label = (e.value['label'] ?? e.key).toString();
                    return ListTile(
                      leading: const Icon(Icons.apps, size: 22),
                      title: Text(label),
                      onTap: () {
                        Navigator.pop(context);
                        widget.onAddModule(e.key, underHeadingIndex: widget.underHeadingIndex);
                      },
                    );
                  }),
                  if ('benutzerdefinierter link'.contains(_query) || _query.isEmpty)
                    ListTile(
                      leading: const Icon(Icons.add_link),
                      title: const Text('Benutzerdefinierter Link'),
                      onTap: () {
                        Navigator.pop(context);
                        widget.onAddCustom(underHeadingIndex: widget.underHeadingIndex);
                      },
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Abbrechen')),
      ],
    );
  }
}

class _HeadingEditDialog extends StatefulWidget {
  final String label;

  const _HeadingEditDialog({required this.label});

  @override
  State<_HeadingEditDialog> createState() => _HeadingEditDialogState();
}

class _HeadingEditDialogState extends State<_HeadingEditDialog> {
  late final TextEditingController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: widget.label);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Oberbegriff bearbeiten'),
      content: TextField(
        controller: _ctrl,
        decoration: const InputDecoration(labelText: 'Bezeichnung'),
        autofocus: true,
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Abbrechen')),
        FilledButton(
          onPressed: () {
            if (_ctrl.text.trim().isNotEmpty) Navigator.of(context).pop(_ctrl.text.trim());
          },
          child: const Text('Speichern'),
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
