import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../theme/app_theme.dart';
import '../models/information_model.dart';
import '../services/informationen_service.dart';
import '../services/informationssystem_service.dart';
import '../services/auth_data_service.dart';
import '../services/auth_service.dart';

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
        builder: (_) => _InformationAnlegenScreen(
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

class _InformationAnlegenScreen extends StatefulWidget {
  final String companyId;
  final List<String> kategorien;
  final String userDisplayName;
  final String userId;
  final VoidCallback onBack;
  final VoidCallback onSaved;

  const _InformationAnlegenScreen({
    required this.companyId,
    required this.kategorien,
    required this.userDisplayName,
    required this.userId,
    required this.onBack,
    required this.onSaved,
  });

  @override
  State<_InformationAnlegenScreen> createState() => _InformationAnlegenScreenState();
}

class _InformationAnlegenScreenState extends State<_InformationAnlegenScreen> {
  final _infoService = InformationenService();
  final _betreffCtrl = TextEditingController();
  final _textCtrl = TextEditingController();

  DateTime _datum = DateTime.now();
  TimeOfDay _uhrzeit = TimeOfDay.now();
  String _typ = InformationssystemService.containerTypes.first;
  String _kategorie = '';
  String _laufzeit = '1_monat';
  String _prioritaet = 'normal';
  bool _saving = false;

  static const _laufzeitOptions = {
    '1_woche': '1 Woche',
    '2_wochen': '2 Wochen',
    '3_wochen': '3 Wochen',
    '1_monat': '1 Monat',
    '3_monate': '3 Monate',
    '6_monate': '6 Monate',
    '12_monate': '12 Monate',
    'bis_auf_widerruf': 'bis auf Widerruf',
  };

  @override
  void dispose() {
    _betreffCtrl.dispose();
    _textCtrl.dispose();
    super.dispose();
  }

  Future<void> _speichern() async {
    final betreff = _betreffCtrl.text.trim();
    if (betreff.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Bitte Betreff eingeben.')));
      return;
    }

    setState(() => _saving = true);
    try {
      final info = Information(
        id: '',
        datum: _datum,
        uhrzeit: '${_uhrzeit.hour.toString().padLeft(2, '0')}:${_uhrzeit.minute.toString().padLeft(2, '0')}',
        userId: widget.userId,
        userDisplayName: widget.userDisplayName,
        typ: _typ,
        kategorie: _kategorie,
        laufzeit: _laufzeit,
        prioritaet: _prioritaet,
        betreff: betreff,
        text: _textCtrl.text.trim(),
        createdAt: DateTime.now(),
      );
      await _infoService.saveInformation(widget.companyId, info);
      if (mounted) {
        setState(() => _saving = false);
        widget.onSaved();
      }
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Fehler: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.surfaceBg,
      appBar: AppTheme.buildModuleAppBar(
        title: 'Neue Information',
        onBack: widget.onBack,
        leadingIcon: Icons.close,
        actions: [
          FilledButton(
            onPressed: _saving ? null : _speichern,
            style: FilledButton.styleFrom(backgroundColor: AppTheme.primary),
            child: _saving ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Text('Speichern'),
          ),
          const SizedBox(width: 16),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.calendar_today, color: AppTheme.primary),
                    title: const Text('Datum'),
                    subtitle: Text(_formatDate(_datum)),
                    onTap: () async {
                      final d = await showDatePicker(context: context, initialDate: _datum, firstDate: DateTime(2020), lastDate: DateTime(2030));
                      if (d != null && mounted) setState(() => _datum = d);
                    },
                  ),
                ),
                Expanded(
                  child: ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.access_time, color: AppTheme.primary),
                    title: const Text('Uhrzeit'),
                    subtitle: Text('${_uhrzeit.hour.toString().padLeft(2, '0')}:${_uhrzeit.minute.toString().padLeft(2, '0')}'),
                    onTap: () async {
                      final t = await showTimePicker(context: context, initialTime: _uhrzeit);
                      if (t != null && mounted) setState(() => _uhrzeit = t);
                    },
                  ),
                ),
              ],
            ),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.person, color: AppTheme.primary),
                    title: const Text('Angemeldeter User'),
                    subtitle: Text(widget.userDisplayName),
                  ),
                ),
                Expanded(
                  child: DropdownButtonFormField<String>(
                    value: _laufzeit,
                    decoration: const InputDecoration(labelText: 'Gültigkeit', border: OutlineInputBorder()),
                    items: _laufzeitOptions.entries.map((e) => DropdownMenuItem(
                      value: e.key,
                      child: Text(e.value),
                    )).toList(),
                    onChanged: (v) => setState(() => _laufzeit = v ?? _laufzeit),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              value: _typ,
              decoration: const InputDecoration(labelText: 'Typ (Container)', border: OutlineInputBorder()),
              items: InformationssystemService.containerTypes.map((id) => DropdownMenuItem(
                value: id,
                child: Text(InformationssystemService.containerLabels[id] ?? id),
              )).toList(),
              onChanged: (v) => setState(() => _typ = v ?? _typ),
            ),
            const SizedBox(height: 16),
            if (widget.kategorien.isNotEmpty) ...[
              DropdownButtonFormField<String>(
                value: _kategorie.isEmpty ? null : _kategorie,
                decoration: const InputDecoration(labelText: 'Kategorie', border: OutlineInputBorder()),
                items: [
                  const DropdownMenuItem(value: null, child: Text('— Keine —')),
                  ...widget.kategorien.map((k) => DropdownMenuItem(value: k, child: Text(k))),
                ],
                onChanged: (v) => setState(() => _kategorie = v ?? ''),
              ),
              const SizedBox(height: 16),
            ],
            DropdownButtonFormField<String>(
              value: _prioritaet,
              decoration: const InputDecoration(labelText: 'Priorität', border: OutlineInputBorder()),
              items: const [
                DropdownMenuItem(value: 'normal', child: Text('Normal')),
                DropdownMenuItem(value: 'sehr_wichtig', child: Text('Sehr wichtig (rot in Übersicht)')),
              ],
              onChanged: (v) => setState(() => _prioritaet = v ?? 'normal'),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _betreffCtrl,
              decoration: const InputDecoration(labelText: 'Betreff / Überschrift', border: OutlineInputBorder()),
              maxLines: 1,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _textCtrl,
              decoration: const InputDecoration(labelText: 'Information', border: OutlineInputBorder(), alignLabelWithHint: true),
              maxLines: 6,
            ),
          ],
        ),
      ),
    );
  }
}
