import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../theme/app_theme.dart';
import '../models/kunde_model.dart';
import '../services/kundenverwaltung_service.dart';
import '../app_config.dart';

/// Native Kundenverwaltung – lädt Kunden (Firmen) aus Firebase, Liste, Bearbeiten, Löschen.
/// Nur für Superadmin-Rolle.
class KundenverwaltungScreen extends StatefulWidget {
  final String companyId;
  final VoidCallback? onBack;
  final bool hideAppBar;

  const KundenverwaltungScreen({
    super.key,
    required this.companyId,
    this.onBack,
    this.hideAppBar = false,
  });

  @override
  State<KundenverwaltungScreen> createState() => _KundenverwaltungScreenState();
}

class _KundenverwaltungScreenState extends State<KundenverwaltungScreen> {
  final _service = KundenverwaltungService();
  final _searchController = TextEditingController();

  List<Kunde> _allKunden = [];
  Map<String, int> _userCounts = {};
  bool _loading = true;
  String? _error;
  String _statusFilter = 'all';
  String _sortBy = 'name-asc';

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() => setState(() {}));
    _load();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final kunden = await _service.loadKunden();
      final counts = <String, int>{};
      for (final k in kunden) {
        counts[k.id] = await _service.getUserCount(k.id);
      }
      if (mounted) {
        setState(() {
          _allKunden = kunden;
          _userCounts = counts;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = 'Fehler beim Laden: $e';
        });
      }
    }
  }

  List<Kunde> _getFilteredAndSorted() {
    var list = List<Kunde>.from(_allKunden);

    // Suche
    final q = _searchController.text.trim().toLowerCase();
    if (q.isNotEmpty) {
      list = list.where((k) {
        return k.name.toLowerCase().contains(q) ||
            k.id.toLowerCase().contains(q) ||
            k.kundenId.toLowerCase().contains(q) ||
            (k.email ?? '').toLowerCase().contains(q);
      }).toList();
    }

    // Status-Filter
    if (_statusFilter != 'all') {
      list = list.where((k) => k.status == _statusFilter).toList();
    }

    // Sortierung
    list.sort((a, b) {
      switch (_sortBy) {
        case 'name-desc':
          return (b.name).compareTo(a.name);
        case 'date-asc':
          return (a.createdAt ?? DateTime(0)).compareTo(b.createdAt ?? DateTime(0));
        case 'date-desc':
          return (b.createdAt ?? DateTime(0)).compareTo(a.createdAt ?? DateTime(0));
        case 'status':
          return (a.status).compareTo(b.status);
        default:
          return (a.name).compareTo(b.name);
      }
    });

    return list;
  }

  String _formatDate(DateTime? d) {
    if (d == null) return '–';
    return '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.${d.year}';
  }

  Widget _statusBadge(Kunde k) {
    Color color;
    switch (k.status) {
      case 'inactive':
        color = Colors.orange;
        break;
      case 'suspended':
        color = Colors.red;
        break;
      default:
        color = Colors.green;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.15),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.5)),
      ),
      child: Text(k.statusLabel, style: TextStyle(fontSize: 12, color: color, fontWeight: FontWeight.w600)),
    );
  }

  Future<void> _openEdit(Kunde kunde) async {
    final enabledModules = await _service.getCompanyModules(kunde.id);
    final allModuleDefs = await _service.getAllModuleDefs();
    if (!mounted) return;
    final result = await Navigator.of(context, rootNavigator: true).push<Map<String, dynamic>>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (ctx) => _EditKundeScreen(
          kunde: kunde,
          enabledModules: enabledModules,
          allModuleDefs: allModuleDefs,
        ),
      ),
    );
    if (result != null && mounted) {
      try {
        final mods = result.remove('_modules') as Map<String, bool>?;
        await _service.updateKunde(kunde, result);
        if (mods != null) {
          await _service.setCompanyModules(kunde.id, mods);
        }
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Kunde gespeichert.')));
          _load();
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Fehler: $e'), backgroundColor: Colors.red));
        }
      }
    }
  }

  Future<void> _confirmDelete(Kunde kunde) async {
    if (kunde.id == 'admin' || kunde.kundenId.toLowerCase() == 'admin') {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Die Firma „admin" kann nicht gelöscht werden.'), backgroundColor: Colors.orange),
      );
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Kunde löschen?'),
        content: Text(
          'Sind Sie sicher, dass Sie „${kunde.name}" (ID: ${kunde.id}) löschen möchten? '
          'Alle Stammdaten werden entfernt. Sub-Collections (Benutzer etc.) müssen ggf. separat bereinigt werden.',
        ),
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
        await _service.deleteKunde(kunde.id);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Kunde gelöscht.')));
          _load();
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Fehler: $e'), backgroundColor: Colors.red));
        }
      }
    }
  }

  Future<void> _openKundenUrl(String kundenId) async {
    final url = Uri.parse('https://$kundenId.${AppConfig.rootDomain}');
    try {
      if (await canLaunchUrl(url)) {
        await launchUrl(url, mode: LaunchMode.externalApplication);
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final scaffold = Scaffold(
      backgroundColor: AppTheme.surfaceBg,
      appBar: AppTheme.buildModuleAppBar(
        title: 'Kundenverwaltung',
        onBack: widget.onBack ?? () => Navigator.of(context).pop(),
      ),
      body: Column(
        children: [
          Padding(
            padding: EdgeInsets.all(Responsive.horizontalPadding(context)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  controller: _searchController,
                  decoration: InputDecoration(
                    hintText: 'Kunden suchen…',
                    prefixIcon: const Icon(Icons.search),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    filled: true,
                    fillColor: Colors.white,
                  ),
                ),
                const SizedBox(height: 12),
                LayoutBuilder(
                  builder: (_, bc) {
                    final stackFilters = bc.maxWidth < 400;
                    return stackFilters
                        ? Column(
                            children: [
                              _buildStatusDropdown(),
                              const SizedBox(height: 12),
                              _buildSortDropdown(),
                            ],
                          )
                        : Row(
                            children: [
                              Expanded(child: _buildStatusDropdown()),
                              const SizedBox(width: 12),
                              Expanded(child: _buildSortDropdown()),
                            ],
                          );
                  },
                ),
                const SizedBox(height: 12),
              ],
            ),
          ),
          Expanded(
            child: _buildBody(),
          ),
        ],
      ),
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

  Widget _buildStatusDropdown() {
    return DropdownButtonFormField<String>(
      value: _statusFilter,
      decoration: InputDecoration(
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      ),
      items: const [
        DropdownMenuItem(value: 'all', child: Text('Alle Status')),
        DropdownMenuItem(value: 'active', child: Text('Aktiv')),
        DropdownMenuItem(value: 'inactive', child: Text('Inaktiv')),
        DropdownMenuItem(value: 'suspended', child: Text('Gesperrt')),
      ],
      onChanged: (v) => setState(() => _statusFilter = v ?? 'all'),
    );
  }

  Widget _buildSortDropdown() {
    return DropdownButtonFormField<String>(
      value: _sortBy,
      decoration: InputDecoration(
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      ),
      items: const [
        DropdownMenuItem(value: 'name-asc', child: Text('Name A–Z')),
        DropdownMenuItem(value: 'name-desc', child: Text('Name Z–A')),
        DropdownMenuItem(value: 'date-desc', child: Text('Neueste zuerst')),
        DropdownMenuItem(value: 'date-asc', child: Text('Älteste zuerst')),
        DropdownMenuItem(value: 'status', child: Text('Status')),
      ],
      onChanged: (v) => setState(() => _sortBy = v ?? 'name-asc'),
    );
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
              FilledButton.icon(
                onPressed: _load,
                icon: const Icon(Icons.refresh),
                label: const Text('Erneut versuchen'),
                style: FilledButton.styleFrom(backgroundColor: AppTheme.primary),
              ),
            ],
          ),
        ),
      );
    }

    final list = _getFilteredAndSorted();
    if (list.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            _allKunden.isEmpty ? 'Keine Kunden vorhanden.' : 'Keine Treffer für Ihre Suche.',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppTheme.textMuted, fontSize: 16),
          ),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _load,
      color: AppTheme.primary,
      child: ListView.builder(
        padding: EdgeInsets.fromLTRB(
          Responsive.horizontalPadding(context),
          0,
          Responsive.horizontalPadding(context),
          24,
        ),
        itemCount: list.length,
        itemBuilder: (_, i) {
          final k = list[i];
          final userCount = _userCounts[k.id] ?? 0;
          return Card(
            margin: const EdgeInsets.only(bottom: 12),
            child: InkWell(
              onTap: () => _openEdit(k),
              borderRadius: BorderRadius.circular(12),
              child: Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: Responsive.horizontalPadding(context),
                  vertical: 12,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            k.name,
                            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                          ),
                        ),
                        _statusBadge(k),
                      ],
                    ),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton.icon(
                          onPressed: () => _openEdit(k),
                          icon: const Icon(Icons.edit, size: 18),
                          label: const Text('Bearbeiten'),
                        ),
                        if (k.id != 'admin' && k.kundenId.toLowerCase() != 'admin')
                          TextButton.icon(
                            onPressed: () => _confirmDelete(k),
                            icon: Icon(Icons.delete, size: 18, color: Colors.red[700]),
                            label: Text('Löschen', style: TextStyle(color: Colors.red[700])),
                          ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 16,
                      runSpacing: 4,
                      children: [
                        _infoChip(Icons.badge, 'Kunden-ID: ${k.kundenId}', () => _openKundenUrl(k.kundenId)),
                        if (k.bereich != null && k.bereich!.isNotEmpty)
                          _infoChip(Icons.category, KundenBereich.labels[k.bereich!] ?? k.bereich!, null),
                        _infoChip(Icons.person, '$userCount Benutzer', null),
                        if (k.email != null && k.email!.isNotEmpty)
                          _infoChip(Icons.email, k.email!, null),
                      ],
                    ),
                    if (k.address != null || k.zipCity != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        '${k.address ?? ''} ${k.zipCity ?? ''}'.trim(),
                        style: TextStyle(fontSize: 13, color: AppTheme.textMuted),
                      ),
                    ],
                    const SizedBox(height: 2),
                    Text(
                      'Erstellt: ${_formatDate(k.createdAt)} · ID: ${k.id}',
                      style: TextStyle(fontSize: 12, color: AppTheme.textMuted),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _infoChip(IconData icon, String text, VoidCallback? onTap) {
    final child = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: AppTheme.textMuted),
        const SizedBox(width: 4),
        Text(text, style: TextStyle(fontSize: 13, color: AppTheme.textSecondary)),
      ],
    );
    if (onTap != null) {
      return InkWell(onTap: onTap, child: child);
    }
    return child;
  }
}

class _EditKundeScreen extends StatefulWidget {
  final Kunde kunde;
  final Map<String, bool> enabledModules;
  final Map<String, Map<String, dynamic>> allModuleDefs;

  const _EditKundeScreen({
    required this.kunde,
    required this.enabledModules,
    required this.allModuleDefs,
  });

  @override
  State<_EditKundeScreen> createState() => _EditKundeScreenState();
}

class _EditKundeScreenState extends State<_EditKundeScreen> {
  late final TextEditingController _nameCtrl;
  late final TextEditingController _addressCtrl;
  late final TextEditingController _zipCityCtrl;
  late final TextEditingController _phoneCtrl;
  late final TextEditingController _emailCtrl;
  late final TextEditingController _kundenIdCtrl;
  late String _status;
  late String? _bereich;
  late Map<String, bool> _modules;

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController(text: widget.kunde.name);
    _addressCtrl = TextEditingController(text: widget.kunde.address ?? '');
    _zipCityCtrl = TextEditingController(text: widget.kunde.zipCity ?? '');
    _phoneCtrl = TextEditingController(text: widget.kunde.phone ?? '');
    _emailCtrl = TextEditingController(text: widget.kunde.email ?? '');
    _kundenIdCtrl = TextEditingController(text: widget.kunde.kundenId);
    _status = widget.kunde.status;
    _bereich = widget.kunde.bereich;
    if (_bereich != null && !KundenBereich.ids.contains(_bereich)) _bereich = null;
    _modules = Map<String, bool>.from(widget.enabledModules);
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _addressCtrl.dispose();
    _zipCityCtrl.dispose();
    _phoneCtrl.dispose();
    _emailCtrl.dispose();
    _kundenIdCtrl.dispose();
    super.dispose();
  }

  void _save() {
    final kundenId = _kundenIdCtrl.text.trim().toLowerCase();
    if (kundenId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Kunden-ID ist erforderlich.')));
      return;
    }
    if (!RegExp(r'^[a-z0-9-]+$').hasMatch(kundenId) || kundenId.startsWith('-') || kundenId.endsWith('-')) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Kunden-ID darf nur Kleinbuchstaben, Zahlen und Bindestriche enthalten.'),
      ));
      return;
    }
    final modulesToSave = Map<String, bool>.from(_modules);
    modulesToSave['home'] = true;
    modulesToSave['admin'] = true;

    Navigator.of(context).pop(<String, dynamic>{
      'name': _nameCtrl.text.trim(),
      'address': _addressCtrl.text.trim(),
      'zipCity': _zipCityCtrl.text.trim(),
      'phone': _phoneCtrl.text.trim(),
      'email': _emailCtrl.text.trim(),
      'subdomain': kundenId,
      'bereich': _bereich,
      'status': _status,
      '_modules': modulesToSave,
    });
  }

  @override
  Widget build(BuildContext context) {
    final configurableModules = widget.allModuleDefs.entries
        .where((e) => !['home', 'admin', 'kundenverwaltung'].contains(e.key))
        .where((e) => e.value['active'] != false)
        .toList()
      ..sort((a, b) => ((a.value['order'] as num?) ?? 999).compareTo((b.value['order'] as num?) ?? 999));

    return Scaffold(
      backgroundColor: AppTheme.surfaceBg,
      appBar: AppBar(
        title: const Text('Kunde bearbeiten'),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.of(context).pop(),
        ),
        backgroundColor: AppTheme.headerBg,
        foregroundColor: Colors.white,
      ),
      body: Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            TextField(
              controller: _nameCtrl,
              decoration: const InputDecoration(labelText: 'Firmenname'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _addressCtrl,
              decoration: const InputDecoration(labelText: 'Anschrift'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _zipCityCtrl,
              decoration: const InputDecoration(labelText: 'PLZ und Ort'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _phoneCtrl,
              decoration: const InputDecoration(labelText: 'Telefon'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _emailCtrl,
              decoration: const InputDecoration(labelText: 'E-Mail'),
              keyboardType: TextInputType.emailAddress,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _kundenIdCtrl,
              decoration: const InputDecoration(
                labelText: 'Kunden-ID',
                hintText: 'z.B. feuerwehr-luenen',
              ),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String?>(
              value: _bereich,
              decoration: const InputDecoration(
                labelText: 'Bereich',
                hintText: 'Definiert das Menü (Rettungsdienst, Notfallseelsorge, …)',
              ),
              items: [
                const DropdownMenuItem(value: null, child: Text('— Kein Bereich —')),
                ...KundenBereich.ids.map((id) => DropdownMenuItem(
                  value: id,
                  child: Text(KundenBereich.labels[id] ?? id),
                )),
              ],
              onChanged: (v) => setState(() => _bereich = v),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              value: _status,
              decoration: const InputDecoration(labelText: 'Status'),
              items: const [
                DropdownMenuItem(value: 'active', child: Text('Aktiv')),
                DropdownMenuItem(value: 'inactive', child: Text('Inaktiv')),
                DropdownMenuItem(value: 'suspended', child: Text('Gesperrt')),
              ],
              onChanged: (v) => setState(() => _status = v ?? 'active'),
            ),
            const SizedBox(height: 24),
            Text('Module freischalten', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            ...configurableModules.map((e) {
              final id = e.key;
              final label = (e.value['label'] ?? id).toString();
              return CheckboxListTile(
                title: Text(label),
                value: _modules[id] == true,
                onChanged: (v) => setState(() => _modules[id] = v ?? false),
              );
            }),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _save,
              style: FilledButton.styleFrom(
                backgroundColor: AppTheme.primary,
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              child: const Text('Speichern'),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}
