import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../theme/app_theme.dart';
import '../models/mitarbeiter_model.dart';
import '../services/mitarbeiter_service.dart';
import '../utils/phone_format.dart';

/// Telefonliste NFS – nur für Notfallseelsorge.
/// Daten wie bei der regulären Telefonliste aus der Mitgliederverwaltung (kunden/{companyId}/mitarbeiter).
/// Felder: Nachname, Vorname, Wohnort, Telefonnummer.
/// Admin, Koordinator, Superadmin: bearbeiten.
/// User: nur lesen, Telefonnummer anklicken zum Anrufen. Daten werden über das Profil aktualisiert.
class TelefonlisteNfsScreen extends StatefulWidget {
  final String companyId;
  final String userRole;
  /// Menü-Titel; falls gesetzt, wird dieser in der AppBar angezeigt.
  final String? title;
  final VoidCallback onBack;

  const TelefonlisteNfsScreen({
    super.key,
    required this.companyId,
    required this.userRole,
    this.title,
    required this.onBack,
  });

  @override
  State<TelefonlisteNfsScreen> createState() => _TelefonlisteNfsScreenState();
}

class _TelefonlisteNfsScreenState extends State<TelefonlisteNfsScreen> {
  final _service = MitarbeiterService();
  final _functions = FirebaseFunctions.instanceFor(region: 'europe-west1');
  final _searchController = TextEditingController();

  static const _editRoles = ['superadmin', 'admin', 'koordinator'];

  bool get _canEdit =>
      _editRoles.any((r) => widget.userRole.toLowerCase().trim() == r);

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

  Map<String, dynamic> _prepareForCloudFunction(Map<String, dynamic> updates) {
    final out = <String, dynamic>{};
    for (final e in updates.entries) {
      if (e.value is Timestamp) {
        out[e.key] = (e.value as Timestamp).millisecondsSinceEpoch;
      } else {
        out[e.key] = e.value;
      }
    }
    return out;
  }

  List<Mitarbeiter> _filter(List<Mitarbeiter> list) {
    final active = list.where((m) => m.active).toList();
    final q = _searchController.text.trim().toLowerCase();
    if (q.isEmpty) return active;
    return active.where((m) {
      final name = '${m.nachname ?? ''} ${m.vorname ?? ''}'.toLowerCase();
      final ort = (m.ort ?? '').toLowerCase();
      final tel = (m.telefon ?? m.handynummer ?? '').toLowerCase();
      return name.contains(q) || ort.contains(q) || tel.contains(q);
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
    if (!_canEdit) return;
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
            onSave: (data) async {
              final prepared = _prepareForCloudFunction(data);
              await _functions.httpsCallable('saveMitarbeiterDoc').call({
                'companyId': widget.companyId,
                'docId': m.id,
                'data': prepared,
              });
              if (ctx.mounted) Navigator.of(ctx).pop();
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Mitarbeiter aktualisiert.')),
                );
              }
            },
            onCancel: () => Navigator.of(ctx).pop(),
          ),
        ),
      ),
      transitionBuilder: (ctx, animation, _, child) => SlideTransition(
        position: Tween<Offset>(begin: const Offset(0, -1), end: Offset.zero)
            .animate(CurvedAnimation(parent: animation, curve: Curves.easeOut)),
        child: child,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.surfaceBg,
      appBar: AppTheme.buildModuleAppBar(
        title: widget.title ?? 'Telefonliste',
        onBack: widget.onBack,
      ),
      body: Column(
        children: [
          Padding(
            padding: EdgeInsets.all(Responsive.horizontalPadding(context)),
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
                final useCompactLayout = Responsive.isPhone(context);
                return ListView(
                  padding: EdgeInsets.fromLTRB(
                    Responsive.horizontalPadding(context),
                    0,
                    Responsive.horizontalPadding(context),
                    MediaQuery.paddingOf(context).bottom + 16,
                  ),
                  children: [
                    _buildHeader(useCompactLayout),
                    ...list.map((m) => _buildRow(m, useCompactLayout)),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(bool compact) {
    return Padding(
      padding: const EdgeInsets.only(left: 12, right: 12, bottom: 12),
      child: DefaultTextStyle(
        style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Colors.grey[700]),
        child: compact
            ? const Row(
                children: [
                  Expanded(flex: 3, child: Text('Nachname, Vorname')),
                  Expanded(flex: 2, child: Center(child: Text('Wohnort'))),
                  Expanded(flex: 3, child: Center(child: Text('Tel.Nr.'))),
                ],
              )
            : const Row(
                children: [
                  Expanded(flex: 3, child: Text('Nachname')),
                  Expanded(flex: 3, child: Center(child: Text('Vorname'))),
                  Expanded(flex: 3, child: Center(child: Text('Wohnort'))),
                  Expanded(flex: 3, child: Center(child: Text('Tel.Nr.'))),
                ],
              ),
      ),
    );
  }

  Widget _buildRow(Mitarbeiter m, bool compact) {
    final nachname = m.nachname ?? '';
    final vorname = m.vorname ?? '';
    final wohnort = _wohnort(m);
    final tel = m.telefon ?? m.handynummer ?? '';

    Widget _phoneLink(String text) {
      final display = text.trim().isEmpty ? '' : text;
      final hasNumber = RegExp(r'\d').hasMatch(text);
      final formatted = formatPhoneForDisplay(display);
      return InkWell(
        onTap: hasNumber ? () => _launchTel(text) : null,
        borderRadius: BorderRadius.circular(8),
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
            child: Text(
              display.isEmpty ? '-' : formatted,
              style: TextStyle(
                fontSize: 14,
                color: hasNumber ? AppTheme.primary : Colors.grey[600],
                decoration: hasNumber ? TextDecoration.underline : null,
              ),
              overflow: TextOverflow.ellipsis,
              maxLines: 2,
              textAlign: TextAlign.center,
            ),
          ),
        ),
      );
    }

    final canEdit = _canEdit;
    final onTap = canEdit ? () => _openEdit(m) : null;
    const textStyle = TextStyle(fontSize: 14);
    final textStyleMuted = TextStyle(fontSize: 14, color: Colors.grey[700]);

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: compact
            ? Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(
                    flex: 3,
                    child: InkWell(
                      onTap: onTap,
                      borderRadius: BorderRadius.circular(8),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Text(
                          m.displayName,
                          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
                          overflow: TextOverflow.ellipsis,
                          maxLines: 2,
                        ),
                      ),
                    ),
                  ),
                  Expanded(
                    flex: 2,
                    child: InkWell(
                      onTap: onTap,
                      borderRadius: BorderRadius.circular(8),
                      child: Center(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          child: Text(
                            wohnort,
                            style: textStyleMuted,
                            overflow: TextOverflow.ellipsis,
                            maxLines: 1,
                          ),
                        ),
                      ),
                    ),
                  ),
                  Expanded(flex: 3, child: _phoneLink(tel)),
                ],
              )
            : Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(
                    flex: 3,
                    child: InkWell(
                      onTap: onTap,
                      borderRadius: BorderRadius.circular(8),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Text(
                          nachname,
                          style: textStyle,
                          overflow: TextOverflow.ellipsis,
                          maxLines: 1,
                        ),
                      ),
                    ),
                  ),
                  Expanded(
                    flex: 3,
                    child: InkWell(
                      onTap: onTap,
                      borderRadius: BorderRadius.circular(8),
                      child: Center(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          child: Text(
                            vorname,
                            style: textStyleMuted,
                            overflow: TextOverflow.ellipsis,
                            maxLines: 1,
                          ),
                        ),
                      ),
                    ),
                  ),
                  Expanded(
                    flex: 3,
                    child: InkWell(
                      onTap: onTap,
                      borderRadius: BorderRadius.circular(8),
                      child: Center(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          child: Text(
                            wohnort,
                            style: textStyleMuted,
                            overflow: TextOverflow.ellipsis,
                            maxLines: 1,
                          ),
                        ),
                      ),
                    ),
                  ),
                  Expanded(flex: 3, child: _phoneLink(tel)),
                ],
              ),
      ),
    );
  }

  String _wohnort(Mitarbeiter m) {
    final plz = m.plz?.trim() ?? '';
    final ort = m.ort?.trim() ?? '';
    if (plz.isNotEmpty && ort.isNotEmpty) return '$plz $ort';
    if (ort.isNotEmpty) return ort;
    if (plz.isNotEmpty) return plz;
    return '';
  }
}

class _EditSheet extends StatefulWidget {
  final Mitarbeiter mitarbeiter;
  final Future<void> Function(Map<String, dynamic> data) onSave;
  final VoidCallback onCancel;

  const _EditSheet({
    required this.mitarbeiter,
    required this.onSave,
    required this.onCancel,
  });

  @override
  State<_EditSheet> createState() => _EditSheetState();
}

class _EditSheetState extends State<_EditSheet> {
  late final TextEditingController _nachnameCtrl;
  late final TextEditingController _vornameCtrl;
  late final TextEditingController _wohnortCtrl;
  late final TextEditingController _telefonCtrl;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final m = widget.mitarbeiter;
    _nachnameCtrl = TextEditingController(text: m.nachname ?? '');
    _vornameCtrl = TextEditingController(text: m.vorname ?? '');
    _wohnortCtrl = TextEditingController(text: _wohnort(m));
    _telefonCtrl = TextEditingController(text: m.telefon ?? m.handynummer ?? '');
  }

  String _wohnort(Mitarbeiter m) {
    final plz = m.plz?.trim() ?? '';
    final ort = m.ort?.trim() ?? '';
    if (plz.isNotEmpty && ort.isNotEmpty) return '$plz $ort';
    if (ort.isNotEmpty) return ort;
    if (plz.isNotEmpty) return plz;
    return '';
  }

  @override
  void dispose() {
    _nachnameCtrl.dispose();
    _vornameCtrl.dispose();
    _wohnortCtrl.dispose();
    _telefonCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final nachname = _nachnameCtrl.text.trim();
    final vorname = _vornameCtrl.text.trim();
    if (nachname.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Nachname ist erforderlich.')),
      );
      return;
    }
    setState(() => _saving = true);
    try {
      final wohnort = _wohnortCtrl.text.trim();
      final updates = <String, dynamic>{
        'nachname': nachname,
        'vorname': vorname,
        'name': '$nachname, $vorname'.trim(),
        'handynummer': {'__delete': true},
        'handy': {'__delete': true},
      };
      if (wohnort.isNotEmpty) {
        final parts = wohnort.split(RegExp(r'\s+'));
        if (parts.length >= 2 && RegExp(r'^\d{5}$').hasMatch(parts.first)) {
          updates['plz'] = parts.first;
          updates['ort'] = parts.sublist(1).join(' ');
        } else {
          updates['ort'] = wohnort;
        }
      } else {
        updates['plz'] = {'__delete': true};
        updates['ort'] = {'__delete': true};
      }
      final tel = _telefonCtrl.text.trim();
      updates['telefon'] = tel.isNotEmpty ? tel : null;
      updates['telefonnummer'] = tel.isNotEmpty ? tel : null;
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
            Text(
              'Mitarbeiter bearbeiten',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 20),
            TextField(
              controller: _nachnameCtrl,
              decoration: const InputDecoration(labelText: 'Nachname'),
              textCapitalization: TextCapitalization.words,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _vornameCtrl,
              decoration: const InputDecoration(labelText: 'Vorname'),
              textCapitalization: TextCapitalization.words,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _wohnortCtrl,
              decoration: const InputDecoration(labelText: 'Wohnort (PLZ Ort)'),
              textCapitalization: TextCapitalization.words,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _telefonCtrl,
              decoration: const InputDecoration(labelText: 'Telefonnummer'),
              keyboardType: TextInputType.phone,
              inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[\d\s\-\(\)\+]'))],
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
                  child: _saving
                      ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Text('Speichern'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
