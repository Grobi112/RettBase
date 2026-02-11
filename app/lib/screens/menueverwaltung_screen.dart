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

/// Hilfsdaten für Drag & Drop
class _DragPayload {
  final int topIndex;
  final int? childIndex; // null = Top-Level-Item
  final Map<String, dynamic> item;

  _DragPayload(this.topIndex, this.childIndex, this.item);
}

/// Payload beim Ziehen eines Modul-Chips aus "Hinzufügen"
class _AddModulePayload {
  final String moduleId;
  final String label;

  _AddModulePayload(this.moduleId, this.label);
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
      if (items.isEmpty) {
        final legacy = await _menuService.loadLegacyGlobalMenu();
        if (legacy.isNotEmpty) {
          await _menuService.saveMenuStructure(_selectedBereich, legacy);
          items = legacy;
        }
      }
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

  Future<void> _save() async {
    if (widget.userRole != 'superadmin') return;
    setState(() => _saving = true);
    try {
      for (var i = 0; i < _items.length; i++) {
        _items[i]['order'] = i;
      }
      await _menuService.saveMenuStructure(_selectedBereich, _items);
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

  bool _isHeading(int topIndex) => (_items[topIndex]['type'] ?? '') == 'heading';

  List<Map<String, dynamic>> _getChildren(int topIndex) {
    final raw = _items[topIndex]['children'];
    if (raw is List) return raw.map((e) => Map<String, dynamic>.from(e as Map)).toList();
    return [];
  }

  void _setChildren(int topIndex, List<Map<String, dynamic>> children) {
    _items[topIndex]['children'] = children;
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

  /// Verarbeitet Drop eines neuen Moduls aus "Hinzufügen"
  void _onDropAddModule(_AddModulePayload payload, int destTopIndex, int? destChildIndex) {
    final m = _availableModules[payload.moduleId];
    if (m == null) return;
    final newItem = {
      'id': payload.moduleId,
      'label': payload.label,
      'url': m['url'] ?? '',
      'type': 'module',
    };
    setState(() {
      if (destChildIndex != null && destTopIndex < _items.length && _isHeading(destTopIndex)) {
        final children = _getChildren(destTopIndex);
        if (children.length >= MenueverwaltungService.maxChildrenPerHeading) return;
        children.insert(destChildIndex.clamp(0, children.length), newItem);
        _setChildren(destTopIndex, children);
      } else {
        _items.insert(destTopIndex.clamp(0, _items.length), newItem);
      }
    });
  }

  /// Verarbeitet einen Drop und aktualisiert _items
  void _onDrop(_DragPayload payload, int destTopIndex, int? destChildIndex) {
    // Zielindex anpassen, wenn wir ein Top-Level-Item entfernen und Ziel danach liegt
    var adjDestTop = destTopIndex;
    if (payload.childIndex == null && payload.topIndex < destTopIndex) {
      adjDestTop = destTopIndex - 1;
    }
    if (payload.topIndex == adjDestTop && payload.childIndex == destChildIndex) return;

    setState(() {
      Map<String, dynamic> item;
      if (payload.childIndex != null) {
        final children = _getChildren(payload.topIndex);
        item = children.removeAt(payload.childIndex!);
        _setChildren(payload.topIndex, children);
      } else {
        item = _items.removeAt(payload.topIndex);
        if (adjDestTop > payload.topIndex) adjDestTop--;
      }

      if (destChildIndex != null) {
        if (adjDestTop < 0 || adjDestTop >= _items.length) return;
        if (!_isHeading(adjDestTop)) return;
        final children = _getChildren(adjDestTop);
        if (children.length >= MenueverwaltungService.maxChildrenPerHeading) return;
        children.insert(destChildIndex.clamp(0, children.length), item);
        _setChildren(adjDestTop, children);
      } else {
        _items.insert(adjDestTop.clamp(0, _items.length), item);
      }
    });
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

    final usedIds = _usedModuleIds();
    final allModules = _availableModules.entries.toList();
    final isWide = MediaQuery.sizeOf(context).width >= 700;

    final leftPanel = _buildAddPanel(context, usedIds, allModules);
    final rightPanel = Expanded(
      child: Container(
        color: Colors.grey[50],
        child: ListView.builder(
          padding: EdgeInsets.fromLTRB(
            Responsive.horizontalPadding(context),
            16,
            Responsive.horizontalPadding(context),
            24,
          ),
          itemCount: _items.length + 1,
          itemBuilder: (ctx, index) {
            if (index == _items.length) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 24),
                child: _buildDropTarget(destTopIndex: _items.length, destChildIndex: null),
              );
            }
            return _buildMenuItem(context, index);
          },
        ),
      ),
    );

    return Column(
      children: [
        Padding(
          padding: EdgeInsets.symmetric(horizontal: Responsive.horizontalPadding(context)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Bereich', style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                value: _selectedBereich,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                ),
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
            ],
          ),
        ),
        const SizedBox(height: 16),
        Expanded(
          child: isWide
              ? Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SingleChildScrollView(
                      child: SizedBox(width: 280, child: leftPanel),
                    ),
                    Container(width: 1, color: Colors.grey[300]),
                    rightPanel,
                  ],
                )
              : Column(
                  children: [
                    leftPanel,
                    Container(height: 1, color: Colors.grey[300]),
                    rightPanel,
                  ],
                ),
        ),
      ],
    );
  }

  Widget _buildAddPanel(BuildContext context, Set<String> usedIds, List<MapEntry<String, Map<String, dynamic>>> allModules) {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Menüeinträge hinzufügen',
            style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          Text(
            'Klicken oder hierher ziehen, um hinzuzufügen. Ziehen Sie unter einen Oberbegriff, um als Unterpunkt einzufügen.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppTheme.textMuted),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                onPressed: _addHeading,
                icon: const Icon(Icons.title, size: 18),
                label: const Text('Oberbegriff'),
              ),
              ...allModules.map((e) {
                final label = (e.value['label'] ?? e.key).toString();
                final alreadyUsed = usedIds.contains(e.key);
                final chip = ActionChip(
                  label: Text(label),
                  onPressed: alreadyUsed ? null : () => _addModule(e.key),
                  avatar: alreadyUsed ? Icon(Icons.check, size: 16, color: Colors.grey[600]) : null,
                );
                if (alreadyUsed) return chip;
                return LongPressDraggable<_AddModulePayload>(
                  data: _AddModulePayload(e.key, label),
                  feedback: Material(
                    elevation: 8,
                    borderRadius: BorderRadius.circular(24),
                    child: chip,
                  ),
                  childWhenDragging: Opacity(opacity: 0.5, child: chip),
                  child: chip,
                );
              }),
              TextButton.icon(
                onPressed: _addCustom,
                icon: const Icon(Icons.add_link),
                label: const Text('Benutzerdefiniert'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMenuItem(BuildContext context, int topIndex) {
    final item = _items[topIndex];
    final type = (item['type'] ?? 'module').toString();
    final isHeading = type == 'heading';
    final children = _getChildren(topIndex);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        _buildDropTarget(destTopIndex: topIndex, destChildIndex: null),
        if (isHeading) ...[
          _buildDraggableCard(
            payload: _DragPayload(topIndex, null, item),
            child: _buildHeadingCard(context, topIndex, item, children),
          ),
          ...List.generate(children.length, (ci) {
            return Padding(
              padding: const EdgeInsets.only(left: 24),
              child: Column(
                children: [
                  _buildDropTarget(destTopIndex: topIndex, destChildIndex: ci),
                  _buildDraggableCard(
                    payload: _DragPayload(topIndex, ci, children[ci]),
                    child: _buildItemCard(context, topIndex, ci, children[ci]),
                  ),
                ],
              ),
            );
          }),
          if (children.length < MenueverwaltungService.maxChildrenPerHeading)
            Padding(
              padding: const EdgeInsets.only(left: 24),
              child: _buildAddChildArea(topIndex),
            ),
        ] else
          _buildDraggableCard(
            payload: _DragPayload(topIndex, null, item),
            child: _buildItemCard(context, topIndex, null, item),
          ),
      ],
    );
  }

  static const double _dropZoneHeight = 36;

  Widget _buildDropTarget({required int destTopIndex, required int? destChildIndex}) {
    return DragTarget<Object>(
      onAcceptWithDetails: (d) {
        if (d.data is _AddModulePayload) {
          _onDropAddModule(d.data as _AddModulePayload, destTopIndex, destChildIndex);
        } else if (d.data is _DragPayload) {
          _onDrop(d.data as _DragPayload, destTopIndex, destChildIndex);
        }
      },
      onWillAcceptWithDetails: (d) {
        if (d.data is _AddModulePayload) {
          final p = d.data as _AddModulePayload;
          if (_usedModuleIds().contains(p.moduleId)) return false;
          if (destChildIndex != null && destTopIndex < _items.length && _isHeading(destTopIndex)) {
            return _getChildren(destTopIndex).length < MenueverwaltungService.maxChildrenPerHeading;
          }
          return true;
        }
        return d.data is _DragPayload;
      },
      builder: (context, candidateData, rejectedData) {
        final isHighlighted = candidateData.isNotEmpty;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          height: _dropZoneHeight,
          margin: const EdgeInsets.symmetric(vertical: 4),
          decoration: BoxDecoration(
            color: isHighlighted ? AppTheme.primary.withOpacity(0.2) : Colors.transparent,
            border: Border.all(
              color: isHighlighted ? AppTheme.primary : Colors.grey.withOpacity(0.4),
              width: isHighlighted ? 2 : 1,
              strokeAlign: BorderSide.strokeAlignInside,
            ),
            borderRadius: BorderRadius.circular(8),
          ),
          child: isHighlighted
              ? Center(child: Text('Hier ablegen', style: TextStyle(color: AppTheme.primary, fontSize: 12)))
              : null,
        );
      },
    );
  }

  Widget _buildDraggableCard({required _DragPayload payload, required Widget child}) {
    return LongPressDraggable<_DragPayload>(
      data: payload,
      feedback: Material(
        elevation: 8,
        borderRadius: BorderRadius.circular(12),
        child: SizedBox(
          width: 280,
          child: Opacity(opacity: 0.95, child: child),
        ),
      ),
      childWhenDragging: Opacity(opacity: 0.4, child: child),
      child: child,
    );
  }

  Widget _buildHeadingCard(BuildContext context, int topIndex, Map<String, dynamic> item, List<Map<String, dynamic>> children) {
    final label = (item['label'] ?? '').toString();
    return Card(
      margin: const EdgeInsets.only(bottom: 4),
      child: ListTile(
        leading: const Icon(Icons.drag_handle, color: AppTheme.textMuted),
        title: Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: children.isEmpty ? const Text('Oberbegriff – Unterpunkte per Ziehen hinzufügen') : null,
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (children.length < MenueverwaltungService.maxChildrenPerHeading)
              IconButton(
                icon: const Icon(Icons.add, size: 20),
                onPressed: () => _showAddChildMenu(context, topIndex),
                tooltip: 'Unterpunkt hinzufügen',
              ),
            IconButton(icon: const Icon(Icons.edit, size: 20), onPressed: () => _editAt(topIndex)),
            IconButton(icon: Icon(Icons.delete, size: 20, color: Colors.red[700]), onPressed: () => _removeAt(topIndex)),
          ],
        ),
      ),
    );
  }

  void _showAddChildMenu(BuildContext context, int topIndex) {
    final usedIds = _usedModuleIds();
    final allModules = _availableModules.entries.toList();

    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text('Unterpunkt hinzufügen', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
            ),
            ...allModules.map((e) {
              final used = usedIds.contains(e.key);
              return ListTile(
                title: Text((e.value['label'] ?? e.key).toString()),
                trailing: used ? Icon(Icons.check, size: 18, color: Colors.grey[600]) : null,
                onTap: used ? null : () {
                  Navigator.pop(ctx);
                  _addModule(e.key, underHeadingIndex: topIndex);
                },
              );
            }),
            ListTile(
              leading: const Icon(Icons.add_link),
              title: const Text('Benutzerdefinierter Menüpunkt'),
              onTap: () {
                Navigator.pop(ctx);
                _addCustom(underHeadingIndex: topIndex);
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAddChildArea(int topIndex) {
    final childIndex = _getChildren(topIndex).length;
    final headingLabel = (_items[topIndex]['label'] ?? 'Oberbegriff').toString();
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: DragTarget<Object>(
        onAcceptWithDetails: (d) {
          if (d.data is _AddModulePayload) {
            _onDropAddModule(d.data as _AddModulePayload, topIndex, childIndex);
          } else if (d.data is _DragPayload) {
            _onDrop(d.data as _DragPayload, topIndex, childIndex);
          }
        },
        onWillAcceptWithDetails: (d) {
          if (d.data is _AddModulePayload) {
            final p = d.data as _AddModulePayload;
            if (_usedModuleIds().contains(p.moduleId)) return false;
            return _getChildren(topIndex).length < MenueverwaltungService.maxChildrenPerHeading;
          }
          if (d.data is _DragPayload) {
            final p = d.data as _DragPayload;
            if (p.topIndex == topIndex && p.childIndex == childIndex) return false;
            return _getChildren(topIndex).length < MenueverwaltungService.maxChildrenPerHeading;
          }
          return false;
        },
        builder: (context, candidateData, rejectedData) {
          final isHighlighted = candidateData.isNotEmpty;
          return InkWell(
            onTap: () => _showAddChildMenu(context, topIndex),
            borderRadius: BorderRadius.circular(8),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
              decoration: BoxDecoration(
                color: isHighlighted ? AppTheme.primary.withOpacity(0.12) : null,
                border: Border.all(
                  color: isHighlighted ? AppTheme.primary : AppTheme.border,
                  width: isHighlighted ? 2 : 1,
                  strokeAlign: BorderSide.strokeAlignInside,
                ),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.add, size: 20, color: isHighlighted ? AppTheme.primary : AppTheme.primary),
                  const SizedBox(width: 8),
                  Text(
                    isHighlighted ? 'Hier als Unterpunkt von „$headingLabel“ ablegen' : 'Unterpunkt hinzufügen (oder hierher ziehen)',
                    style: TextStyle(color: AppTheme.primary, fontSize: 14, fontWeight: isHighlighted ? FontWeight.w600 : FontWeight.normal),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildItemCard(BuildContext context, int topIndex, int? childIndex, Map<String, dynamic> item) {
    final label = (item['label'] ?? item['id'] ?? '').toString();
    final type = (item['type'] ?? 'module').toString();
    return Card(
      margin: const EdgeInsets.only(bottom: 4),
      child: ListTile(
        leading: const Icon(Icons.drag_handle, color: AppTheme.textMuted),
        title: Text(label),
        subtitle: type == 'custom' ? const Text('Benutzerdefiniert') : null,
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(icon: const Icon(Icons.edit, size: 20), onPressed: () => _editAt(topIndex, childIndex)),
            IconButton(icon: Icon(Icons.delete, size: 20, color: Colors.red[700]), onPressed: () => _removeAt(topIndex, childIndex)),
          ],
        ),
      ),
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
