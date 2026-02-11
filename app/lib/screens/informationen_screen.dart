import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../theme/app_theme.dart';
import '../models/information_model.dart';
import '../services/informationen_service.dart';
import '../services/informationssystem_service.dart';
import '../services/auth_data_service.dart';
import '../services/auth_service.dart';
import 'information_anlegen_screen.dart';

String _formatDate(DateTime d) {
  final day = d.day.toString().padLeft(2, '0');
  final mon = d.month.toString().padLeft(2, '0');
  return '$day.$mon.${d.year}';
}

/// Informationen – Übersicht und Anlegen von Informationseinträgen
class InformationenScreen extends StatefulWidget {
  final String companyId;
  final String? userRole;
  final VoidCallback? onBack;

  const InformationenScreen({
    super.key,
    required this.companyId,
    this.userRole,
    this.onBack,
  });

  static const _deleteAllowedRoles = {
    'superadmin', 'admin', 'geschaeftsfuehrung', 'rettungsdienstleitung', 'leiterssd', 'wachleitung',
  };

  @override
  State<InformationenScreen> createState() => _InformationenScreenState();
}

class _InformationenScreenState extends State<InformationenScreen> {
  final _infoService = InformationenService();
  final _settingsService = InformationssystemService();
  final _authDataService = AuthDataService();
  final _authService = AuthService();

  List<Information> _items = [];
  List<String> _kategorien = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final results = await Future.wait([
        _infoService.loadInformationen(widget.companyId),
        _settingsService.loadKategorien(widget.companyId),
      ]);
      if (mounted) {
        setState(() {
          _items = results[0] as List<Information>;
          _kategorien = results[1] as List<String>;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _openAnlegen() async {
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
        ),
      ),
    );
    if (created == true && mounted) _load();
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
            Text('Informationen', style: TextStyle(color: AppTheme.primary, fontWeight: FontWeight.w600)),
          ],
        ),
        onBack: widget.onBack ?? () => Navigator.of(context).pop(),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppTheme.primary))
          : _items.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.info_outline, size: 64, color: Colors.grey[400]),
                        const SizedBox(height: 16),
                        Text(
                          'Noch keine Informationen vorhanden.',
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
                )
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: _items.length,
                    itemBuilder: (context, i) {
                      final info = _items[i];
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
                          onTap: () => _showDetail(info),
                        ),
                      );
                    },
                  ),
                ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _openAnlegen,
        icon: const Icon(Icons.add),
        label: const Text('Neue Information'),
        backgroundColor: AppTheme.primary,
        foregroundColor: Colors.white,
      ),
    );
  }

  bool get _canDelete => widget.companyId.isNotEmpty &&
      widget.userRole != null &&
      InformationenScreen._deleteAllowedRoles.contains((widget.userRole ?? '').toLowerCase().trim());

  void _showDetail(Information info) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.6,
        maxChildSize: 0.9,
        minChildSize: 0.3,
        expand: false,
        builder: (ctx, scrollController) => SingleChildScrollView(
          controller: scrollController,
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      info.betreff,
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        color: info.isSehrWichtig ? Colors.red : AppTheme.textPrimary,
                      ),
                    ),
                  ),
                  if (_canDelete)
                    IconButton(
                      icon: Icon(Icons.delete_outline, color: Colors.red[700]),
                      tooltip: 'Information löschen',
                      onPressed: () async {
                        final ok = await showDialog<bool>(
                          context: ctx,
                          builder: (c) => AlertDialog(
                            title: const Text('Information löschen?'),
                            content: const Text('Möchten Sie diese Information wirklich löschen?'),
                            actions: [
                              TextButton(onPressed: () => Navigator.of(c).pop(false), child: const Text('Abbrechen')),
                              FilledButton(
                                style: FilledButton.styleFrom(backgroundColor: Colors.red),
                                onPressed: () => Navigator.of(c).pop(true),
                                child: const Text('Löschen'),
                              ),
                            ],
                          ),
                        );
                        if (ok == true) {
                          Navigator.of(ctx).pop();
                          await _infoService.deleteInformation(widget.companyId, info.id);
                          if (mounted) {
                            _load();
                            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Information gelöscht')));
                          }
                        }
                      },
                    ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  if (info.kategorie.isNotEmpty)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: AppTheme.primary.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(info.kategorie, style: TextStyle(fontSize: 12, color: AppTheme.primary)),
                    ),
                  const SizedBox(width: 12),
                  Text(
                    '${_formatDate(info.createdAt)} · ${info.userDisplayName}',
                    style: TextStyle(fontSize: 12, color: AppTheme.textMuted),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Text(info.text, style: TextStyle(fontSize: 14, height: 1.5, color: AppTheme.textPrimary)),
            ],
          ),
        ),
      ),
    );
  }
}

