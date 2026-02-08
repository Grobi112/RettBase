import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../theme/app_theme.dart';
import '../models/mitarbeiter_model.dart';
import '../services/mitarbeiter_service.dart';

/// Telefonliste – gleiche Datenbank (kunden/{companyId}/mitarbeiter), gleiche Funktion und Rollen wie Web
/// Bearbeiten (voll): Admin, Rettungsdienstleitung, Geschäftsführung, Wachleitung
/// OVD: nur Telefonnummer bearbeiten
/// Eingeloggter User: voller Zugriff auf eigenes Profil
class TelefonlisteScreen extends StatefulWidget {
  final String companyId;
  final String userRole;
  final String? currentUserUid;
  final VoidCallback onBack;

  const TelefonlisteScreen({
    super.key,
    required this.companyId,
    required this.userRole,
    this.currentUserUid,
    required this.onBack,
  });

  @override
  State<TelefonlisteScreen> createState() => _TelefonlisteScreenState();
}

class _TelefonlisteScreenState extends State<TelefonlisteScreen> {
  final _service = MitarbeiterService();
  final _searchController = TextEditingController();

  static const _editAllRoles = ['superadmin', 'admin', 'rettungsdienstleitung', 'leiterssd', 'geschaeftsfuehrung', 'wachleitung', 'koordinator'];
  static const _editPhoneOnlyRoles = ['ovd'];
  static const _qualifikationen = ['RH', 'RS', 'RA', 'NFS'];
  /// Alle Führerscheinklassen in Deutschland (wie Unfallbericht)
  static const _fuehrerscheinklassen = ['A', 'A1', 'A2', 'AM', 'B', 'BE', 'C', 'CE', 'C1', 'C1E', 'D', 'DE', 'D1', 'D1E', 'L', 'T'];

  bool get _canEditAllByRole =>
      _editAllRoles.any((r) => widget.userRole.toLowerCase().trim() == r);

  bool get _canEditPhoneOnlyByRole =>
      _editPhoneOnlyRoles.any((r) => widget.userRole.toLowerCase().trim() == r);

  bool _isOwnProfile(Mitarbeiter m) {
    final uid = widget.currentUserUid;
    if (uid == null || uid.isEmpty) return false;
    return m.uid == uid || m.id == uid;
  }

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<Mitarbeiter> _filter(List<Mitarbeiter> list) {
    final active = list.where((m) => m.active).toList();
    final q = _searchController.text.trim().toLowerCase();
    if (q.isEmpty) return active;
    return active.where((m) {
      final name = '${m.nachname ?? ''} ${m.vorname ?? ''}'.toLowerCase();
      final qualis = (m.qualifikation ?? []).join(' ').toLowerCase();
      final tel = (m.telefon ?? '').toLowerCase();
      return name.contains(q) || qualis.contains(q) || tel.contains(q);
    }).toList();
  }

  Future<void> _launchTel(String number) async {
    if (number.trim().isEmpty) return;
    final clean = number.replaceAll(RegExp(r'[\s\-\(\)]'), '');
    if (clean.isEmpty) return;
    final uri = Uri(scheme: 'tel', path: clean);
    try {
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else {
        await launchUrl(uri);
      }
    } catch (_) {}
  }

  void _openEdit(Mitarbeiter m) {
    final isOwn = _isOwnProfile(m);
    final canEditAll = _canEditAllByRole || isOwn;
    final canEditPhoneOnly = _canEditPhoneOnlyByRole && !isOwn;
    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Schließen',
      barrierColor: Colors.black54,
      transitionDuration: const Duration(milliseconds: 250),
      pageBuilder: (ctx, _, __) => Align(
        alignment: Alignment.topCenter,
        child: Material(
          color: Colors.transparent,
          child: _EditSheet(
            mitarbeiter: m,
            canEditAll: canEditAll,
            canEditPhoneOnly: canEditPhoneOnly,
            qualifikationen: _qualifikationen,
        fuehrerscheinklassen: _fuehrerscheinklassen,
            onSave: (updates) async {
              await _service.updateMitarbeiterFields(widget.companyId, m.id, updates);
              if (ctx.mounted) Navigator.of(ctx).pop();
              if (mounted) ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Mitarbeiter aktualisiert.')),
              );
            },
            onCancel: () => Navigator.of(ctx).pop(),
          ),
        ),
      ),
      transitionBuilder: (ctx, animation, _, child) => SlideTransition(
        position: Tween<Offset>(begin: const Offset(0, -1), end: Offset.zero).animate(CurvedAnimation(parent: animation, curve: Curves.easeOut)),
        child: child,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.surfaceBg,
      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: AppTheme.primary,
        elevation: 1,
        leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: widget.onBack),
        title: Text('Telefonliste', style: TextStyle(color: AppTheme.primary, fontWeight: FontWeight.w600)),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Suche...',
                prefixIcon: const Icon(Icons.search),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              ),
            ),
          ),
          Expanded(
            child: StreamBuilder<List<Mitarbeiter>>(
              stream: _service.streamMitarbeiter(widget.companyId),
              builder: (_, snap) {
                if (!snap.hasData) {
                  return const Center(child: CircularProgressIndicator(color: AppTheme.primary));
                }
                final list = _filter(snap.data!);
                if (list.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.phone_outlined, size: 64, color: Colors.grey[400]),
                        const SizedBox(height: 16),
                        Text(
                          snap.data!.where((m) => m.active).isEmpty
                              ? 'Keine aktiven Mitarbeiter.'
                              : 'Keine Treffer für "${_searchController.text.trim()}".',
                          style: TextStyle(color: Colors.grey[600]),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  );
                }
                return ListView(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  children: [
                    _buildHeader(),
                    ...list.map((m) => _buildRow(m)),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.only(left: 12, right: 12, bottom: 12),
      child: DefaultTextStyle(
        style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Colors.grey[700]),
        child: LayoutBuilder(
          builder: (_, constraints) {
            final narrow = constraints.maxWidth < 600;
            if (narrow) {
              return const Row(
                children: [
                  Expanded(flex: 4, child: Text('Name')),
                  Expanded(flex: 3, child: Center(child: Text('Qual.'))),
                  Expanded(flex: 1, child: Center(child: Text('FS'))),
                  Expanded(flex: 2, child: Center(child: Text('Telefonnummer'))),
                ],
              );
            }
            return const Row(
              children: [
                Expanded(flex: 4, child: Text('Nachname, Vorname')),
                Expanded(flex: 4, child: Center(child: Text('Qualifikation'))),
                Expanded(flex: 2, child: Center(child: Text('Führerschein'))),
                Expanded(flex: 2, child: Center(child: Text('Telefonnummer'))),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildRow(Mitarbeiter m) {
    final name = m.displayName;
    final qualis = (m.qualifikation ?? []).join(' / ');
    final fs = m.fuehrerschein ?? '';
    final tel = m.telefon ?? '';

    Widget _phoneLink(String text) {
      final display = text.trim().isEmpty ? '' : text;
      final hasNumber = RegExp(r'\d').hasMatch(text);
      return InkWell(
        onTap: hasNumber ? () => _launchTel(text) : null,
        borderRadius: BorderRadius.circular(8),
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
            child: Text(
              display.isEmpty ? '-' : display,
              style: TextStyle(
                fontSize: 14,
                color: hasNumber ? AppTheme.primary : Colors.grey[600],
                decoration: hasNumber ? TextDecoration.underline : null,
              ),
            ),
          ),
        ),
      );
    }

    final canEditThis = _canEditAllByRole || _canEditPhoneOnlyByRole || _isOwnProfile(m);
    final editArea = canEditThis ? () => _openEdit(m) : null;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: LayoutBuilder(
          builder: (_, constraints) {
            if (constraints.maxWidth < 500) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  InkWell(
                    onTap: editArea,
                    borderRadius: BorderRadius.circular(8),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(name, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
                          if (qualis.isNotEmpty || fs.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: Text('$qualis${fs.isNotEmpty ? ' · $fs' : ''}', style: TextStyle(fontSize: 14, color: Colors.grey[600])),
                            ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  _phoneLink(tel),
                ],
              );
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(flex: 4, child: InkWell(onTap: editArea, borderRadius: BorderRadius.circular(8), child: Padding(padding: const EdgeInsets.symmetric(vertical: 8), child: Text(name, style: const TextStyle(fontSize: 14))))),
                Expanded(flex: 4, child: InkWell(onTap: editArea, borderRadius: BorderRadius.circular(8), child: Center(child: Padding(padding: const EdgeInsets.symmetric(vertical: 8), child: Text(qualis, style: TextStyle(fontSize: 14, color: Colors.grey[700])))))),
                Expanded(flex: 2, child: InkWell(onTap: editArea, borderRadius: BorderRadius.circular(8), child: Center(child: Padding(padding: const EdgeInsets.symmetric(vertical: 8), child: Text(fs, style: TextStyle(fontSize: 14, color: Colors.grey[700])))))),
                Expanded(flex: 2, child: _phoneLink(tel)),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _EditSheet extends StatefulWidget {
  final Mitarbeiter mitarbeiter;
  final bool canEditAll;
  final bool canEditPhoneOnly;
  final List<String> qualifikationen;
  final List<String> fuehrerscheinklassen;
  final Future<void> Function(Map<String, dynamic> updates) onSave;
  final VoidCallback onCancel;

  const _EditSheet({
    required this.mitarbeiter,
    required this.canEditAll,
    required this.canEditPhoneOnly,
    required this.qualifikationen,
    required this.fuehrerscheinklassen,
    required this.onSave,
    required this.onCancel,
  });

  @override
  State<_EditSheet> createState() => _EditSheetState();
}

class _EditSheetState extends State<_EditSheet> {
  late final TextEditingController _nachnameCtrl;
  late final TextEditingController _vornameCtrl;
  late final TextEditingController _telefonCtrl;
  String? _qualifikation;
  late String _fuehrerschein;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _nachnameCtrl = TextEditingController(text: widget.mitarbeiter.nachname ?? '');
    _vornameCtrl = TextEditingController(text: widget.mitarbeiter.vorname ?? '');
    _telefonCtrl = TextEditingController(text: widget.mitarbeiter.telefon ?? widget.mitarbeiter.handynummer ?? '');
    final q = widget.mitarbeiter.qualifikation;
    _qualifikation = q != null && q.isNotEmpty ? q.first : null;
    if (_qualifikation != null && !widget.qualifikationen.contains(_qualifikation)) {
      _qualifikation = null;
    }
    final fs = widget.mitarbeiter.fuehrerschein ?? '';
    _fuehrerschein = widget.fuehrerscheinklassen.contains(fs) ? fs : widget.fuehrerscheinklassen.first;
  }

  @override
  void dispose() {
    _nachnameCtrl.dispose();
    _vornameCtrl.dispose();
    _telefonCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() => _saving = true);
    try {
      final updates = <String, dynamic>{};

      if (widget.canEditAll) {
        final nachname = _nachnameCtrl.text.trim();
        final vorname = _vornameCtrl.text.trim();
        if (nachname.isNotEmpty) updates['nachname'] = nachname;
        if (vorname.isNotEmpty) updates['vorname'] = vorname;
        updates['fuehrerschein'] = _fuehrerschein;
        if (nachname.isNotEmpty || vorname.isNotEmpty) {
          updates['name'] = '$vorname $nachname'.trim();
        }
        if (_qualifikation != null) {
          updates['qualifikation'] = [_qualifikation];
        }
      }

      final telefon = _telefonCtrl.text.trim();
      updates['telefon'] = telefon.isNotEmpty ? telefon : null;
      updates['telefonnummer'] = telefon.isNotEmpty ? telefon : null;
      updates['handynummer'] = FieldValue.delete();
      updates['handy'] = FieldValue.delete();

      await widget.onSave(updates);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: EdgeInsets.only(top: MediaQuery.of(context).padding.top),
      padding: EdgeInsets.only(
        left: 24,
        right: 24,
        top: 24,
        bottom: 24 + MediaQuery.of(context).viewInsets.bottom,
      ),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(16)),
        boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 8, offset: Offset(0, 4))],
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Mitarbeiter bearbeiten', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 20),

            if (widget.canEditAll) ...[
              TextField(
                controller: _nachnameCtrl,
                decoration: const InputDecoration(labelText: 'Nachname'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _vornameCtrl,
                decoration: const InputDecoration(labelText: 'Vorname'),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                value: _qualifikation,
                decoration: const InputDecoration(labelText: 'Qualifikation'),
                items: [
                  const DropdownMenuItem(value: null, child: Text('-')),
                  ...widget.qualifikationen.map((q) => DropdownMenuItem(value: q, child: Text(q))),
                ],
                onChanged: (v) => setState(() => _qualifikation = v),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                value: _fuehrerschein,
                decoration: const InputDecoration(labelText: 'Führerscheinklasse'),
                items: widget.fuehrerscheinklassen.map((k) => DropdownMenuItem(value: k, child: Text(k))).toList(),
                onChanged: (v) => setState(() => _fuehrerschein = v ?? widget.fuehrerscheinklassen.first),
              ),
              const SizedBox(height: 12),
            ],

            TextField(
              controller: _telefonCtrl,
              decoration: const InputDecoration(labelText: 'Telefonnummer'),
              keyboardType: TextInputType.phone,
            ),
            const SizedBox(height: 24),

            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(onPressed: widget.onCancel, child: const Text('Abbrechen')),
                const SizedBox(width: 12),
                FilledButton(
                  onPressed: _saving ? null : _submit,
                  style: FilledButton.styleFrom(backgroundColor: AppTheme.primary),
                  child: _saving ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Text('Speichern'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
