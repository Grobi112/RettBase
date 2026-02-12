import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../services/modulverwaltung_service.dart';
import '../services/kundenverwaltung_service.dart';
import '../services/modules_service.dart';

/// Native Modulverwaltung – CRUD für settings/modules/items.
/// Nur für Superadmin.
class ModulverwaltungScreen extends StatefulWidget {
  final String companyId;
  final String? userRole;
  final VoidCallback? onBack;
  final bool hideAppBar;

  const ModulverwaltungScreen({
    super.key,
    required this.companyId,
    this.userRole,
    this.onBack,
    this.hideAppBar = false,
  });

  @override
  State<ModulverwaltungScreen> createState() => _ModulverwaltungScreenState();
}

class _ModulverwaltungScreenState extends State<ModulverwaltungScreen> {
  final _modulService = ModulverwaltungService();
  final _kundenService = KundenverwaltungService();
  final _searchCtrl = TextEditingController();

  Map<String, Map<String, dynamic>> _modules = {};
  bool _loading = true;
  String? _error;

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

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
      await _modulService.ensureSsdModuleExists();
      var mods = await _modulService.getAllModules();
      if (mods.isEmpty) {
        final defs = await _kundenService.getAllModuleDefs();
        if (defs.isNotEmpty) {
          mods = {for (final e in defs.entries) e.key: {'id': e.key, ...e.value}};
        }
      }
      for (final m in ModulesService.defaultNativeModules) {
        if (!mods.containsKey(m.id)) {
          mods[m.id] = {'id': m.id, 'label': m.label, 'url': m.url ?? '', 'order': m.order};
        }
      }
      // Einsatzprotokoll SSD immer anzeigen (Fallback falls Merge übersprungen)
      mods['ssd'] ??= {'id': 'ssd', 'label': 'Einsatzprotokoll SSD', 'url': '', 'order': 29, 'active': true, 'roles': _allRoles};
      if (mounted) {
        setState(() {
          _modules = mods;
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

  Future<void> _openCreate() async {
    final result = await Navigator.of(context, rootNavigator: true).push<Map<String, dynamic>?>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (ctx) => _ModulFormScreen(
          allRoles: _allRoles,
          module: null,
        ),
      ),
    );
    if (result != null && mounted) {
      try {
        final id = await _modulService.saveModule(result);
        await _modulService.setCompanyModule('admin', id, true);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Modul angelegt.')));
          _load();
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Fehler: $e'), backgroundColor: Colors.red));
        }
      }
    }
  }

  Future<void> _openEdit(String moduleId) async {
    final m = _modules[moduleId];
    if (m == null) return;
    final result = await Navigator.of(context, rootNavigator: true).push<Map<String, dynamic>?>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (ctx) => _ModulFormScreen(
          allRoles: _allRoles,
          module: m,
        ),
      ),
    );
    if (result != null && mounted) {
      try {
        result['id'] = moduleId;
        await _modulService.saveModule(result);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Modul gespeichert.')));
          _load();
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Fehler: $e'), backgroundColor: Colors.red));
        }
      }
    }
  }

  Future<void> _confirmDelete(String moduleId, String label) async {
    if (['home', 'admin', 'kundenverwaltung'].contains(moduleId)) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('System-Module können nicht gelöscht werden.')));
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Modul löschen?'),
        content: Text('Sind Sie sicher, dass Sie „$label" löschen möchten?'),
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
    if (ok == true) {
      try {
        await _modulService.deleteModule(moduleId);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Modul gelöscht.')));
          _load();
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Fehler: $e'), backgroundColor: Colors.red));
        }
      }
    }
  }

  static const _allRoles = [
    'superadmin', 'admin', 'leiterssd', 'geschaeftsfuehrung', 'rettungsdienstleitung',
    'koordinator', 'wachleitung', 'ovd', 'user', 'fahrzeugbeauftragter', 'mpg-beauftragter',
  ];

  @override
  Widget build(BuildContext context) {
    final scaffold = Scaffold(
      backgroundColor: AppTheme.surfaceBg,
      appBar: AppTheme.buildModuleAppBar(
        title: 'Modul-Verwaltung',
        onBack: widget.onBack ?? () => Navigator.of(context).pop(),
        actions: [
          if (widget.userRole == 'superadmin')
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: MediaQuery.sizeOf(context).width < 400
                  ? IconButton(
                      onPressed: _openCreate,
                      icon: const Icon(Icons.add),
                      style: IconButton.styleFrom(backgroundColor: AppTheme.primary, foregroundColor: Colors.white),
                      tooltip: 'Neues Modul',
                    )
                  : FilledButton.icon(
                      onPressed: _openCreate,
                      icon: const Icon(Icons.add, size: 20),
                      label: const Text('Neues Modul'),
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

    final query = _searchCtrl.text.trim().toLowerCase();
    var list = _modules.entries.toList();
    if (query.isNotEmpty) {
      list = list.where((e) {
        final label = (e.value['label'] ?? e.key).toString().toLowerCase();
        final id = e.key.toLowerCase();
        return label.contains(query) || id.contains(query);
      }).toList();
    }
    list.sort((a, b) {
      final la = (a.value['label'] ?? a.key).toString().toLowerCase();
      final lb = (b.value['label'] ?? b.key).toString().toLowerCase();
      return la.compareTo(lb);
    });

    return Column(
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(Responsive.horizontalPadding(context), 12, Responsive.horizontalPadding(context), 8),
          child: TextField(
            controller: _searchCtrl,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              hintText: 'Module suchen …',
              prefixIcon: const Icon(Icons.search),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              filled: true,
              fillColor: Colors.white,
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            ),
          ),
        ),
        Expanded(
          child: list.isEmpty
              ? Center(
                  child: Text(
                    query.isNotEmpty ? 'Keine Module gefunden.' : 'Keine Module vorhanden.',
                    style: TextStyle(color: AppTheme.textMuted, fontSize: 16),
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _load,
                  color: AppTheme.primary,
                  child: ListView.builder(
        padding: EdgeInsets.fromLTRB(
          Responsive.horizontalPadding(context),
          8,
          Responsive.horizontalPadding(context),
          24,
        ),
        itemCount: list.length,
        itemBuilder: (_, i) {
          final e = list[i];
          final id = e.key;
          final m = e.value;
          final label = (m['label'] ?? id).toString();
          final active = m['active'] != false;
          final isSystem = ['home', 'admin', 'kundenverwaltung'].contains(id);

          return Card(
            margin: const EdgeInsets.only(bottom: 12),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                          Row(
                          children: [
                            Text(label, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                            if (id == 'ssd') ...[
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: Colors.blue.shade50,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text('Nur Schulsanitätsdienst', style: TextStyle(fontSize: 10, color: Colors.blue.shade700)),
                              ),
                            ],
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: active ? Colors.green.withOpacity(0.15) : Colors.red.withOpacity(0.15),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(active ? 'Aktiv' : 'Inaktiv', style: TextStyle(fontSize: 11, color: active ? Colors.green : Colors.red)),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text('ID: $id', style: TextStyle(fontSize: 13, color: AppTheme.textMuted)),
                        if (m['roles'] is List)
                          Text('Rollen: ${(m['roles'] as List).join(', ')}', style: TextStyle(fontSize: 12, color: AppTheme.textSecondary)),
                      ],
                    ),
                  ),
                  if (!isSystem) ...[
                    IconButton(icon: const Icon(Icons.edit), onPressed: () => _openEdit(id), tooltip: 'Bearbeiten'),
                    IconButton(icon: Icon(Icons.delete, color: Colors.red[700]), onPressed: () => _confirmDelete(id, label), tooltip: 'Löschen'),
                  ] else
                    Text('System', style: TextStyle(fontSize: 12, color: AppTheme.textMuted)),
                ],
              ),
            ),
          );
        },
      ),
                ),
        ),
      ],
    );
  }
}

class _ModulFormScreen extends StatefulWidget {
  final List<String> allRoles;
  final Map<String, dynamic>? module;

  const _ModulFormScreen({required this.allRoles, this.module});

  @override
  State<_ModulFormScreen> createState() => _ModulFormScreenState();
}

class _ModulFormScreenState extends State<_ModulFormScreen> {
  late final TextEditingController _labelCtrl;
  late final TextEditingController _orderCtrl;
  late bool _active;
  late Set<String> _selectedRoles;

  @override
  void initState() {
    super.initState();
    final m = widget.module;
    _labelCtrl = TextEditingController(text: (m?['label'] ?? '').toString());
    _orderCtrl = TextEditingController(text: ((m?['order'] as num?) ?? 999).toString());
    _active = m?['active'] != false;
    final roles = m?['roles'];
    _selectedRoles = roles is List ? (roles.map((e) => e.toString()).toSet()) : widget.allRoles.toSet();
  }

  @override
  void dispose() {
    _labelCtrl.dispose();
    _orderCtrl.dispose();
    super.dispose();
  }

  void _save() {
    final label = _labelCtrl.text.trim();
    if (label.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Label erforderlich.')));
      return;
    }
    if (_selectedRoles.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Mindestens eine Rolle wählen.')));
      return;
    }
    Navigator.of(context).pop({
      'label': label,
      'url': '', // Flutter nutzt keine URLs – native Module
      'icon': 'default',
      'order': int.tryParse(_orderCtrl.text) ?? 999,
      'active': _active,
      'roles': _selectedRoles.toList(),
      'free': true,
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.surfaceBg,
      appBar: AppBar(
        title: Text(widget.module == null ? 'Neues Modul' : 'Modul bearbeiten'),
        leading: IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.of(context).pop()),
        backgroundColor: AppTheme.headerBg,
        foregroundColor: Colors.white,
      ),
      body: ListView(
        padding: EdgeInsets.all(Responsive.horizontalPadding(context)),
        children: [
          TextField(controller: _labelCtrl, decoration: const InputDecoration(labelText: 'Label *')),
          const SizedBox(height: 12),
          TextField(controller: _orderCtrl, decoration: const InputDecoration(labelText: 'Reihenfolge (für Menü)'), keyboardType: TextInputType.number),
          const SizedBox(height: 12),
          SwitchListTile(title: const Text('Aktiv'), value: _active, onChanged: (v) => setState(() => _active = v)),
          const SizedBox(height: 16),
          Text('Rollen', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
          ...widget.allRoles.map((r) => CheckboxListTile(
                title: Text(r),
                value: _selectedRoles.contains(r),
                onChanged: (v) => setState(() {
                  if (v == true) _selectedRoles.add(r);
                  else _selectedRoles.remove(r);
                }),
              )),
          const SizedBox(height: 24),
          FilledButton(onPressed: _save, style: FilledButton.styleFrom(backgroundColor: AppTheme.primary, padding: const EdgeInsets.symmetric(vertical: 14)), child: const Text('Speichern')),
        ],
      ),
    );
  }
}
