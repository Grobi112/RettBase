import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../theme/app_theme.dart';
import '../models/information_model.dart';
import '../services/informationen_service.dart';
import '../services/informationssystem_service.dart';
import '../services/auth_data_service.dart';
import '../services/auth_service.dart';
import 'information_anlegen_screen.dart';
import 'informationssystem_einstellungen_screen.dart';

String _formatDate(DateTime d) {
  final day = d.day.toString().padLeft(2, '0');
  final mon = d.month.toString().padLeft(2, '0');
  return '$day.$mon.${d.year}';
}

/// Informationssystem – Übersichten pro Container-Typ (aus Einstellungen).
/// Jeder Tab zeigt alle Einträge des jeweiligen Typs mit Bearbeiten, Löschen, Neu anlegen.
/// Die Container-Darstellung auf dem Dashboard bleibt unverändert.
class InformationssystemScreen extends StatefulWidget {
  final String companyId;
  final String? userRole;
  final VoidCallback? onBack;
  /// Wird aufgerufen, wenn eine Information erstellt, bearbeitet oder gelöscht wurde – z.B. zur Aktualisierung der Dashboard-Container
  final VoidCallback? onInfoChanged;

  const InformationssystemScreen({
    super.key,
    required this.companyId,
    this.userRole,
    this.onBack,
    this.onInfoChanged,
  });

  @override
  State<InformationssystemScreen> createState() => _InformationssystemScreenState();
}

class _InformationssystemScreenState extends State<InformationssystemScreen> with TickerProviderStateMixin {
  final _infoService = InformationenService();
  final _settingsService = InformationssystemService();
  final _authService = AuthService();
  final _authDataService = AuthDataService();

  List<Information> _items = [];
  List<String> _containerTypes = ['informationen', 'verkehrslage'];
  Map<String, String> _containerLabels = InformationssystemService.defaultContainerLabels;
  List<String> _kategorien = [];
  bool _loading = true;
  TabController? _tabController;

  static const _deleteAllowedRoles = {
    'superadmin', 'admin', 'geschaeftsfuehrung', 'rettungsdienstleitung', 'leiterssd', 'wachleitung',
  };

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _tabController?.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final results = await Future.wait([
        _infoService.loadInformationen(widget.companyId),
        _settingsService.loadContainerTypeOrder(widget.companyId),
        _settingsService.loadContainerTypeLabels(widget.companyId),
        _settingsService.loadKategorien(widget.companyId),
      ]);
      if (mounted) {
        final types = results[1] as List<String>;
        final labels = results[2] as Map<String, String>;
        final items = results[0] as List<Information>;
        final kategorien = results[3] as List<String>;
        final typeList = types.isNotEmpty ? types : InformationssystemService.defaultContainerTypeIds;
        // Erst wenn Loading-Rebuild durch ist: TabController austauschen.
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          _tabController?.dispose();
          _containerTypes = typeList;
          _containerLabels = labels.isNotEmpty ? labels : InformationssystemService.defaultContainerLabels;
          _tabController = TabController(length: _containerTypes.length, vsync: this);
          setState(() {
            _items = items;
            _kategorien = kategorien;
            _loading = false;
          });
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  bool get _canDelete =>
      widget.userRole != null && _deleteAllowedRoles.contains((widget.userRole ?? '').toLowerCase().trim());

  void _openAnlegen(String defaultTyp) async {
    final user = _authService.currentUser;
    if (user == null) return;
    final authData = await _authDataService.getAuthData(user.uid, user.email ?? '', widget.companyId);
    if (!mounted) return;

    final created = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => InformationAnlegenScreen(
          companyId: widget.companyId,
          kategorien: _kategorien,
          userDisplayName: authData.displayName ?? user.email ?? 'Unbekannt',
          userId: user.uid,
          onBack: () => Navigator.of(context).pop(),
          onSaved: () => Navigator.of(context).pop(true),
          initialInfo: null,
          defaultTyp: defaultTyp,
          containerTypeIds: _containerTypes,
          containerTypeLabels: _containerLabels,
        ),
      ),
    );
    if (created == true && mounted) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _load();
          widget.onInfoChanged?.call();
        }
      });
    }
  }

  void _openBearbeiten(Information info) async {
    final user = _authService.currentUser;
    if (user == null) return;
    final authData = await _authDataService.getAuthData(user.uid, user.email ?? '', widget.companyId);
    if (!mounted) return;

    final result = await Navigator.of(context).push<Object?>(
      MaterialPageRoute(
        builder: (_) => InformationAnlegenScreen(
          companyId: widget.companyId,
          kategorien: _kategorien,
          userDisplayName: authData.displayName ?? user.email ?? 'Unbekannt',
          userId: user.uid,
          onBack: () => Navigator.of(context).pop(),
          onSaved: () => Navigator.of(context).pop(true),
          initialInfo: info,
          canDelete: _canDelete,
          containerTypeIds: _containerTypes,
          containerTypeLabels: _containerLabels,
        ),
      ),
    );
    if (result != null && mounted) {
      // Nach pop: erst nächsten Frame abwarten, dann _load/SnackBar – vermeidet null-Context
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _load();
        widget.onInfoChanged?.call();
        if (result == 'deleted') {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Information gelöscht')));
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.surfaceBg,
      appBar: AppTheme.buildModuleAppBar(
        titleWidget: Row(
          children: [
            SvgPicture.asset(
              'img/icon_informationssystem.svg',
              width: 24,
              height: 24,
              colorFilter: ColorFilter.mode(AppTheme.primary, BlendMode.srcIn),
            ),
            const SizedBox(width: 10),
            Text('Informationssystem', style: TextStyle(color: AppTheme.primary, fontWeight: FontWeight.w600)),
          ],
        ),
        onBack: widget.onBack ?? () => Navigator.of(context).pop(),
        actions: _loading || _tabController == null
            ? null
            : [
                IconButton(
                  icon: const Icon(Icons.settings_outlined),
                  tooltip: 'Einstellungen',
                  onPressed: () async {
                    await Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => InformationssystemEinstellungenScreen(
                          companyId: widget.companyId,
                          onBack: () => Navigator.of(context).pop(),
                          onSaved: () {},
                        ),
                      ),
                    );
                    if (mounted) _load();
                  },
                ),
                ListenableBuilder(
                  listenable: _tabController!,
                  builder: (ctx, _) {
                    final idx = _tabController!.index;
                    final typ = idx < _containerTypes.length ? _containerTypes[idx] : _containerTypes.first;
                    return MediaQuery.sizeOf(context).width < 400
                        ? IconButton(
                            onPressed: () => _openAnlegen(typ),
                            icon: const Icon(Icons.add),
                            tooltip: 'Neue Information',
                            style: IconButton.styleFrom(backgroundColor: AppTheme.primary, foregroundColor: Colors.white),
                          )
                        : Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: FilledButton.icon(
                              onPressed: () => _openAnlegen(typ),
                              icon: const Icon(Icons.add, size: 18),
                              label: const Text('Neue Information'),
                              style: FilledButton.styleFrom(backgroundColor: AppTheme.primary),
                            ),
                          );
                  },
                ),
              ],
        bottom: _loading || _tabController == null
            ? null
            : TabBar(
                controller: _tabController!,
                labelColor: AppTheme.primary,
                indicatorColor: AppTheme.primary,
                tabs: _containerTypes.map((t) => Tab(text: _containerLabels[t] ?? t)).toList(),
              ),
      ),
      body: _loading || _tabController == null
          ? const Center(child: CircularProgressIndicator(color: AppTheme.primary))
          : TabBarView(
              controller: _tabController!,
              children: _containerTypes.map((typ) => _InfoOverviewTab(
                items: _items.where((i) => i.typ == typ).toList(),
                containerTyp: typ,
                containerLabel: _containerLabels[typ] ?? typ,
                onRefresh: _load,
                onEdit: _openBearbeiten,
              )).toList(),
            ),
    );
  }
}

class _InfoOverviewTab extends StatelessWidget {
  final List<Information> items;
  final String containerTyp;
  final String containerLabel;
  final VoidCallback onRefresh;
  final void Function(Information) onEdit;

  const _InfoOverviewTab({
    required this.items,
    required this.containerTyp,
    required this.containerLabel,
    required this.onRefresh,
    required this.onEdit,
  });

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                containerTyp == 'verkehrslage' ? Icons.traffic : Icons.info_outline,
                size: 64,
                color: Colors.grey[400],
              ),
              const SizedBox(height: 16),
              Text(
                'Noch keine Einträge in $containerLabel.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 16, color: AppTheme.textSecondary),
              ),
              const SizedBox(height: 8),
              Text(
                'Tippen Sie auf + um eine neue Information anzulegen.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 14, color: AppTheme.textMuted),
              ),
            ],
          ),
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: () async => onRefresh(),
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: items.length,
        itemBuilder: (context, i) {
          final info = items[i];
          return Card(
            margin: const EdgeInsets.only(bottom: 12),
            child: ListTile(
              title: Text(
                info.betreff,
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: info.isSehrWichtig ? Colors.red : AppTheme.textPrimary,
                ),
              ),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (info.kategorie.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        info.kategorie,
                        style: TextStyle(fontSize: 12, color: AppTheme.textSecondary),
                      ),
                    ),
                  Text(
                    _formatDate(info.createdAt),
                    style: TextStyle(fontSize: 12, color: AppTheme.textMuted),
                  ),
                ],
              ),
              isThreeLine: true,
              trailing: const Icon(Icons.chevron_right),
              onTap: () => onEdit(info),
            ),
          );
        },
      ),
    );
  }
}
