import 'package:flutter/material.dart';
import '../utils/schichtplan_nfs_bereitschaftstyp_utils.dart';
import 'package:url_launcher/url_launcher.dart';
import '../theme/app_theme.dart';
import '../services/schichtanmeldung_service.dart';
import '../services/schichtplan_nfs_service.dart';
import 'schichtplan_nfs_schicht_anlegen_sheet.dart';
import 'schichtplan_nfs_offene_schicht_melden_sheet.dart';

/// Schichten-Ansicht für einen Tag: Freie Stunden oben, eingesetzte Mitarbeiter unten.
/// Klick auf Mitarbeiter öffnet Datenblatt mit Anruf-Möglichkeit.
bool _canSchichtenHinzufuegen(String? role) {
  if (role == null || role.isEmpty) return false;
  final r = role.trim().toLowerCase();
  return r == 'superadmin' || r == 'admin' || r == 'koordinator';
}

class SchichtplanNfsSchichtenScreen extends StatefulWidget {
  final String companyId;
  final DateTime selectedDate;
  final String? userRole;
  final VoidCallback onBack;

  const SchichtplanNfsSchichtenScreen({
    super.key,
    required this.companyId,
    required this.selectedDate,
    this.userRole,
    required this.onBack,
  });

  @override
  State<SchichtplanNfsSchichtenScreen> createState() =>
      _SchichtplanNfsSchichtenScreenState();
}

class _SchichtplanNfsSchichtenScreenState
    extends State<SchichtplanNfsSchichtenScreen> {
  final _service = SchichtplanNfsService();

  List<BereitschaftsTyp> _typen = [];
  List<NfsMitarbeiterRow> _mitarbeiter = [];
  Map<String, String> _eintraege = {};
  bool _loading = true;
  String? _error;

  String get _dayId =>
      '${widget.selectedDate.day.toString().padLeft(2, '0')}.${widget.selectedDate.month.toString().padLeft(2, '0')}.${widget.selectedDate.year}';

  static const _wochentage = [
    'Montag', 'Dienstag', 'Mittwoch', 'Donnerstag', 'Freitag', 'Samstag', 'Sonntag'
  ];

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
      final alleTypen = await _service.loadBereitschaftsTypen(widget.companyId);
      final typen = SchichtplanNfsBereitschaftstypUtils.filterAndSortS1S2B(
        alleTypen,
      );
      final ma =
          await _service.loadMitarbeiterMitStandort(widget.companyId);
      final eintraege = await _service
          .loadStundenplanEintraege(widget.companyId, _dayId);
      if (mounted) {
        setState(() {
          _typen = typen;
          _mitarbeiter = ma;
          _eintraege = eintraege;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _loading = false;
        });
      }
    }
  }

  /// Stunden (0–23), die noch nicht belegt sind
  List<int> get _freieStunden {
    final belegt = <int>{};
    for (final k in _eintraege.keys) {
      final parts = k.split('_');
      if (parts.length == 2) {
        final h = int.tryParse(parts[1]);
        if (h != null && h >= 0 && h < 24) belegt.add(h);
      }
    }
    return [for (var h = 0; h < 24; h++) if (!belegt.contains(h)) h];
  }

  /// Pro Stunde (0–23): 'free' = rot, 's1' = grün, 'other' = neutral
  String _stundenStatus(int h) {
    final s1Typ = _typen
        .where((t) => (t.name ?? '').trim().toLowerCase() == 's1')
        .firstOrNull;
    final s1TypId = s1Typ?.id;
    var hasS1 = false;
    var hasOther = false;
    for (final e in _eintraege.entries) {
      final parts = e.key.split('_');
      if (parts.length == 2 && int.tryParse(parts[1]) == h) {
        final typId = (e.value ?? '').trim();
        if (typId.isEmpty) continue;
        if (s1TypId != null && typId == s1TypId) {
          hasS1 = true;
        } else {
          hasOther = true;
        }
      }
    }
    if (!hasS1 && !hasOther) return 'free';
    if (hasS1) return 's1';
    return 'other';
  }

  /// Mitarbeiter, die an diesem Tag mindestens eine Stunde belegt haben
  List<NfsMitarbeiterRow> get _eingesetzteMitarbeiter {
    final ids = <String>{};
    for (final k in _eintraege.keys) {
      final parts = k.split('_');
      if (parts.length == 2 && _eintraege[k]?.trim().isNotEmpty == true) {
        ids.add(parts[0]);
      }
    }
    return _mitarbeiter.where((r) => ids.contains(r.mitarbeiter.id)).toList();
  }

  Color _colorForTyp(String id) =>
      SchichtplanNfsBereitschaftstypUtils.colorForTypId(id, _typen);

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

  void _openOffeneSchichtMelden() {
    showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Schließen',
      barrierColor: Colors.black54,
      transitionDuration: const Duration(milliseconds: 200),
      pageBuilder: (ctx, _, __) => Center(
        child: Material(
          color: Colors.transparent,
          child: SchichtplanNfsOffeneSchichtMeldenSheet(
            companyId: widget.companyId,
            initialDate: widget.selectedDate,
            onSaved: () {
              Navigator.pop(ctx);
              _load();
            },
            onCancel: () => Navigator.pop(ctx),
          ),
        ),
      ),
    );
  }

  void _openSchichtHinzufuegen() {
    showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Schließen',
      barrierColor: Colors.black54,
      transitionDuration: const Duration(milliseconds: 200),
      pageBuilder: (ctx, _, __) => Center(
        child: Material(
          color: Colors.transparent,
          child: SchichtAnlegenSheet(
            companyId: widget.companyId,
            initialDate: widget.selectedDate,
            onSaved: () {
              Navigator.pop(ctx);
              _load();
            },
            onCancel: () => Navigator.pop(ctx),
          ),
        ),
      ),
    );
  }

  Future<void> _confirmLoeschen(NfsMitarbeiterRow row) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Einsatz entfernen'),
        content: Text(
          'Alle Schichten von ${row.mitarbeiter.displayName} an diesem Tag wirklich entfernen?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Abbrechen'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Entfernen'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await _service.deleteStundenplanEintraegeForMitarbeiter(
      widget.companyId,
      _dayId,
      row.mitarbeiter.id,
    );
    if (mounted) await _load();
  }

  void _openBearbeiten(NfsMitarbeiterRow row) {
    final blocks = _getBlocksForMember(row.mitarbeiter.id);
    if (blocks.isEmpty) return;
    showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Schließen',
      barrierColor: Colors.black54,
      transitionDuration: const Duration(milliseconds: 200),
      pageBuilder: (ctx, _, __) => Center(
        child: Material(
          color: Colors.transparent,
          child: _BearbeitenBereitschaftszeitDialog(
            companyId: widget.companyId,
            selectedDate: widget.selectedDate,
            mitarbeiterName: row.mitarbeiter.displayName,
            mitarbeiterId: row.mitarbeiter.id,
            blocks: blocks,
            typen: _typen,
            service: _service,
            onSaved: () {
              Navigator.pop(ctx);
              _load();
            },
            onCancel: () => Navigator.pop(ctx),
          ),
        ),
      ),
    ).then((_) {
      if (mounted) _load();
    });
  }

  void _openMitarbeiterDatenblatt(NfsMitarbeiterRow row) {
    final m = row.mitarbeiter;
    showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Schließen',
      barrierColor: Colors.black54,
      transitionDuration: const Duration(milliseconds: 200),
      pageBuilder: (ctx, _, __) => Center(
        child: Material(
          color: Colors.transparent,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: 400,
              maxHeight: MediaQuery.sizeOf(ctx).height * 0.6,
            ),
            child: Card(
              margin: const EdgeInsets.symmetric(horizontal: 24),
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: _MitarbeiterDatenblatt(
                  mitarbeiter: m,
                  standortName: row.standortName,
                  onCall: () {
                    Navigator.pop(ctx);
                    final tel = m.telefonnummer?.trim();
                    if (tel != null && tel.isNotEmpty) {
                      _launchTel(tel);
                    } else {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Keine Telefonnummer hinterlegt'),
                        ),
                      );
                    }
                  },
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(
        backgroundColor: AppTheme.surfaceBg,
        appBar: AppTheme.buildModuleAppBar(
          title: 'Schichten',
          onBack: widget.onBack,
        ),
        body: const Center(
          child: CircularProgressIndicator(color: AppTheme.primary),
        ),
      );
    }
    if (_error != null) {
      return Scaffold(
        backgroundColor: AppTheme.surfaceBg,
        appBar: AppTheme.buildModuleAppBar(
          title: 'Schichten',
          onBack: widget.onBack,
        ),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.error_outline, size: 48, color: Colors.red[400]),
                const SizedBox(height: 16),
                Text(_error!, textAlign: TextAlign.center),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: _load,
                  child: const Text('Erneut versuchen'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final wochentag =
        _wochentage[widget.selectedDate.weekday - 1];
    final datum =
        '${widget.selectedDate.day.toString().padLeft(2, '0')}.${widget.selectedDate.month.toString().padLeft(2, '0')}.${widget.selectedDate.year}';

    return Scaffold(
      backgroundColor: AppTheme.surfaceBg,
      appBar: AppTheme.buildModuleAppBar(
        title: 'Schichten – $wochentag, $datum',
        onBack: widget.onBack,
        actions: [
          TextButton.icon(
            onPressed: _openOffeneSchichtMelden,
            icon: const Icon(Icons.person_add_outlined, size: 20),
            label: const Text('Verfügbarkeit angeben'),
          ),
          if (_canSchichtenHinzufuegen(widget.userRole))
            TextButton.icon(
              onPressed: _openSchichtHinzufuegen,
              icon: const Icon(Icons.add_circle_outline, size: 20),
              label: const Text('Schicht hinzufügen'),
            ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(child: _buildFreieStunden()),
            SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: Responsive.horizontalPadding(context),
                  vertical: 16,
                ),
                child: Text(
                  'Eingesetzte Mitarbeiter',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 16,
                    color: AppTheme.textPrimary,
                  ),
                ),
              ),
            ),
            SliverPadding(
              padding: EdgeInsets.symmetric(
                horizontal: Responsive.horizontalPadding(context),
              ),
              sliver: SliverList(
                delegate: SliverChildBuilderDelegate(
                  (ctx, i) {
                    final row = _eingesetzteMitarbeiter[i];
                    return _buildMitarbeiterCard(row);
                  },
                  childCount: _eingesetzteMitarbeiter.length,
                ),
              ),
            ),
            const SliverToBoxAdapter(child: SizedBox(height: 24)),
          ],
        ),
      ),
    );
  }

  Widget _buildFreieStunden() {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(Responsive.horizontalPadding(context)),
      color: Colors.white,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Stundenübersicht',
            style: const TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: 16,
              color: AppTheme.textPrimary,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Rot = frei · Grün = S1 belegt',
            style: TextStyle(
              fontSize: 12,
              color: AppTheme.textMuted,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [for (var h = 0; h < 24; h++) _buildStundenChip(h)],
          ),
        ],
      ),
    );
  }

  Widget _buildStundenChip(int h) {
    final status = _stundenStatus(h);
    final label = h == 23
        ? '23:00–24:00'
        : '${h.toString().padLeft(2, '0')}:00–${(h + 1).toString().padLeft(2, '0')}:00';
    final Color bgColor;
    final Color borderColor;
    final Color textColor;
    switch (status) {
      case 's1':
        bgColor = Colors.green.shade100;
        borderColor = Colors.green.shade300;
        textColor = Colors.green.shade800;
        break;
      case 'other':
        bgColor = Colors.grey.shade200;
        borderColor = Colors.grey.shade400;
        textColor = Colors.grey.shade700;
        break;
      default:
        bgColor = Colors.red.shade100;
        borderColor = Colors.red.shade300;
        textColor = Colors.red.shade800;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: borderColor),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w500,
          color: textColor,
        ),
      ),
    );
  }

  Widget _buildMitarbeiterCard(NfsMitarbeiterRow row) {
    final m = row.mitarbeiter;
    final blocks = _getBlocksForMember(m.id);

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        onTap: () => _openMitarbeiterDatenblatt(row),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              CircleAvatar(
                backgroundColor: AppTheme.primary.withOpacity(0.2),
                child: Text(
                  _initial(m),
                  style: TextStyle(
                    color: AppTheme.primary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      m.displayName,
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 15,
                      ),
                    ),
                    if (row.standortName != null && row.standortName!.trim().isNotEmpty)
                      Text(
                        'Ort (Wohnort): ${row.standortName!}',
                        style: TextStyle(
                          fontSize: 12,
                          color: AppTheme.textMuted,
                        ),
                      ),
                    if (blocks.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 4,
                        runSpacing: 4,
                        children: blocks.map((b) {
                          final typ = _typen
                              .where((t) => t.id == b.typId)
                              .firstOrNull;
                          final typName = typ?.name ?? b.typId;
                          final isS1 = (typ?.name ?? '').trim().toLowerCase() == 's1';
                          final color = isS1
                              ? Colors.green
                              : _colorForTyp(b.typId);
                          final bgColor = isS1
                              ? Colors.green.shade100
                              : color.withOpacity(0.15);
                          final label = b.start + 1 == b.end
                              ? '${b.start.toString().padLeft(2, '0')}:00 $typName'
                              : '${b.start.toString().padLeft(2, '0')}–${b.end.toString().padLeft(2, '0')} $typName';
                          return Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: bgColor,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              label,
                              style: TextStyle(
                                fontSize: 11,
                                color: isS1 ? Colors.green.shade800 : color,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                    ],
                  ],
                ),
              ),
              if (_canSchichtenHinzufuegen(widget.userRole))
                PopupMenuButton<String>(
                  icon: Icon(Icons.more_vert, color: AppTheme.textMuted),
                  padding: EdgeInsets.zero,
                  onSelected: (v) {
                    if (v == 'edit') _openBearbeiten(row);
                    if (v == 'delete') _confirmLoeschen(row);
                  },
                  itemBuilder: (_) => [
                    const PopupMenuItem(
                      value: 'edit',
                      child: Row(
                        children: [
                          Icon(Icons.edit, size: 20),
                          SizedBox(width: 8),
                          Text('Bearbeiten'),
                        ],
                      ),
                    ),
                    const PopupMenuItem(
                      value: 'delete',
                      child: Row(
                        children: [
                          Icon(Icons.delete, size: 20, color: Colors.red),
                          SizedBox(width: 8),
                          Text('Löschen', style: TextStyle(color: Colors.red)),
                        ],
                      ),
                    ),
                  ],
                )
              else
                Icon(Icons.chevron_right, color: AppTheme.textMuted),
            ],
          ),
        ),
      ),
    );
  }

  List<({int start, int end, String typId})> _getBlocksForMember(
      String mitarbeiterId) {
    final blocks = <({int start, int end, String typId})>[];
    for (var h = 0; h < 24; h++) {
      final t = _eintraege['${mitarbeiterId}_$h'];
      if (t != null && t.isNotEmpty) {
        if (blocks.isNotEmpty &&
            blocks.last.end == h &&
            blocks.last.typId == t) {
          blocks[blocks.length - 1] = (
            start: blocks.last.start,
            end: h + 1,
            typId: t,
          );
        } else {
          blocks.add((start: h, end: h + 1, typId: t));
        }
      }
    }
    return blocks;
  }

  String _initial(SchichtplanMitarbeiter m) {
    final v = (m.vorname ?? '').trim();
    final n = (m.nachname ?? '').trim();
    if (v.isNotEmpty) return v.substring(0, 1).toUpperCase();
    if (n.isNotEmpty) return n.substring(0, 1).toUpperCase();
    return '?';
  }
}

/// Dialog zum Bearbeiten der Bereitschaftszeit eines Mitarbeiters (zentriert, mit Datum/Zeit)
class _BearbeitenBereitschaftszeitDialog extends StatefulWidget {
  final String companyId;
  final DateTime selectedDate;
  final String mitarbeiterName;
  final String mitarbeiterId;
  final List<({int start, int end, String typId})> blocks;
  final List<BereitschaftsTyp> typen;
  final SchichtplanNfsService service;
  final VoidCallback onSaved;
  final VoidCallback onCancel;

  const _BearbeitenBereitschaftszeitDialog({
    required this.companyId,
    required this.selectedDate,
    required this.mitarbeiterName,
    required this.mitarbeiterId,
    required this.blocks,
    required this.typen,
    required this.service,
    required this.onSaved,
    required this.onCancel,
  });

  @override
  State<_BearbeitenBereitschaftszeitDialog> createState() =>
      _BearbeitenBereitschaftszeitDialogState();
}

class _EditableBlock {
  DateTime datum;
  int startHour;
  int endHour;
  String typId;

  _EditableBlock({
    required this.datum,
    required this.startHour,
    required this.endHour,
    required this.typId,
  });
}

class _BearbeitenBereitschaftszeitDialogState
    extends State<_BearbeitenBereitschaftszeitDialog> {
  late List<_EditableBlock> _blocks;
  bool _saving = false;

  String _dayId(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.${d.year}';

  @override
  void initState() {
    super.initState();
    _blocks = widget.blocks
        .map((b) => _EditableBlock(
              datum: widget.selectedDate,
              startHour: b.start,
              endHour: b.end,
              typId: b.typId,
            ))
        .toList();
  }

  Future<void> _speichern() async {
    if (_saving) return;
    setState(() => _saving = true);
    final oldDayId = _dayId(widget.selectedDate);
    await widget.service.deleteStundenplanEintraegeForMitarbeiter(
      widget.companyId,
      oldDayId,
      widget.mitarbeiterId,
    );
    for (final blk in _blocks) {
      final newDayId = _dayId(blk.datum);
      for (var h = blk.startHour; h < blk.endHour; h++) {
        await widget.service.saveStundenplanEintrag(
          widget.companyId,
          newDayId,
          widget.mitarbeiterId,
          h,
          blk.typId,
        );
      }
    }
    if (mounted) {
      setState(() => _saving = false);
      widget.onSaved();
    }
  }

  Future<void> _removeBlock(int index) async {
    if (index < 0 || index >= _blocks.length) return;
    final blk = _blocks[index];
    final dayId = _dayId(blk.datum);
    try {
      await widget.service.deleteStundenplanEintraegeForMitarbeiterStunden(
        widget.companyId,
        dayId,
        widget.mitarbeiterId,
        blk.startHour,
        blk.endHour,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Fehler beim Löschen: $e')),
        );
      }
      return;
    }
    if (mounted) {
      setState(() {
        _blocks.removeAt(index);
      });
      if (_blocks.isEmpty) widget.onSaved();
    }
  }

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: BoxConstraints(
        maxWidth: 500,
        maxHeight: MediaQuery.sizeOf(context).height * 0.85,
      ),
      child: Card(
        margin: const EdgeInsets.symmetric(horizontal: 24),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Bereitschaftszeit bearbeiten – ${widget.mitarbeiterName}',
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 18,
                ),
              ),
              const SizedBox(height: 20),
              ...List.generate(_blocks.length, (i) {
                final blk = _blocks[i];
                return Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              '${blk.startHour.toString().padLeft(2, '0')}:00 – ${blk.endHour.toString().padLeft(2, '0')}:00',
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 14,
                              ),
                            ),
                          ),
                          IconButton(
                            icon: Icon(Icons.delete_outline, color: Colors.red[700]),
                            onPressed: () async => await _removeBlock(i),
                            tooltip: 'Block entfernen',
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: ListTile(
                              contentPadding: EdgeInsets.zero,
                              title: const Text('Datum', style: TextStyle(fontSize: 12)),
                              subtitle: Text(
                                '${blk.datum.day.toString().padLeft(2, '0')}.${blk.datum.month.toString().padLeft(2, '0')}.${blk.datum.year}',
                                style: const TextStyle(fontWeight: FontWeight.w600),
                              ),
                              trailing: Icon(Icons.calendar_today, size: 18, color: AppTheme.primary),
                              onTap: () async {
                                final picked = await showDatePicker(
                                  context: context,
                                  initialDate: blk.datum,
                                  firstDate: DateTime(2020),
                                  lastDate: DateTime(2030),
                                );
                                if (picked != null && mounted) {
                                  setState(() => blk.datum = picked);
                                }
                              },
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: DropdownButtonFormField<int>(
                              value: blk.startHour,
                              decoration: const InputDecoration(
                                labelText: 'Von',
                                isDense: true,
                                border: OutlineInputBorder(),
                              ),
                              items: List.generate(
                                24,
                                (h) => DropdownMenuItem(
                                  value: h,
                                  child: Text('${h.toString().padLeft(2, '0')}:00'),
                                ),
                              ),
                              onChanged: (v) {
                                if (v != null) {
                                  setState(() {
                                    blk.startHour = v;
                                    if (blk.endHour <= blk.startHour) {
                                      blk.endHour = blk.startHour < 23 ? blk.startHour + 1 : 24;
                                    }
                                  });
                                }
                              },
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: DropdownButtonFormField<int>(
                              value: blk.endHour > blk.startHour ? blk.endHour : blk.startHour + 1,
                              decoration: const InputDecoration(
                                labelText: 'Bis',
                                isDense: true,
                                border: OutlineInputBorder(),
                              ),
                              items: [
                                for (var h = blk.startHour + 1; h <= 24; h++)
                                  DropdownMenuItem(
                                    value: h,
                                    child: Text(h == 24 ? '24:00' : '${h.toString().padLeft(2, '0')}:00'),
                                  ),
                              ],
                              onChanged: (v) => setState(() => blk.endHour = v ?? blk.startHour + 1),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      DropdownButtonFormField<String>(
                        value: widget.typen.any((t) => t.id == blk.typId)
                            ? blk.typId
                            : (widget.typen.isNotEmpty ? widget.typen.first.id : null),
                        decoration: const InputDecoration(
                          labelText: 'Bereitschaftstyp',
                          border: OutlineInputBorder(),
                        ),
                        items: widget.typen
                            .map((t) => DropdownMenuItem(
                                  value: t.id,
                                  child: Row(
                                    children: [
                                      Container(
                                        width: 12,
                                        height: 12,
                                        decoration: BoxDecoration(
                                          color: SchichtplanNfsBereitschaftstypUtils
                                              .colorForTyp(t),
                                          borderRadius: BorderRadius.circular(2),
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Text(t.name),
                                    ],
                                  ),
                                ))
                            .toList(),
                        onChanged: (v) => setState(() => blk.typId = v ?? blk.typId),
                      ),
                    ],
                  ),
                );
              }),
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: _saving ? null : widget.onCancel,
                    child: const Text('Abbrechen'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: _saving ? null : _speichern,
                    child: _saving
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : const Text('Speichern'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Mitarbeiterdatenblatt (Bottom Sheet) mit Anruf-Button
class _MitarbeiterDatenblatt extends StatelessWidget {
  final SchichtplanMitarbeiter mitarbeiter;
  final String? standortName;
  final VoidCallback onCall;

  const _MitarbeiterDatenblatt({
    required this.mitarbeiter,
    this.standortName,
    required this.onCall,
  });

  @override
  Widget build(BuildContext context) {
    final m = mitarbeiter;
    final tel = m.telefonnummer?.trim() ?? '';
    final hasTel = tel.isNotEmpty && RegExp(r'\d').hasMatch(tel);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            m.displayName,
            style: const TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 20,
            ),
          ),
          const SizedBox(height: 16),
          _DataRow(label: 'E-Mail', value: m.email ?? '—'),
          _DataRow(label: 'Telefonnummer', value: tel.isEmpty ? '—' : tel),
          _DataRow(
            label: 'Ort (Wohnort)',
            value: (m.ort ?? standortName)?.trim().isEmpty == true
                ? '—'
                : (m.ort ?? standortName ?? '—'),
          ),
          const SizedBox(height: 24),
          if (hasTel)
            FilledButton.icon(
              onPressed: onCall,
              icon: const Icon(Icons.phone),
              label: const Text('Anrufen'),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
            )
          else
            Text(
              'Keine Telefonnummer zum Anrufen hinterlegt.',
              style: TextStyle(fontSize: 13, color: AppTheme.textMuted),
            ),
        ],
      ),
    );
  }

}

class _DataRow extends StatelessWidget {
  final String label;
  final String value;

  const _DataRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 13,
                color: AppTheme.textMuted,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontSize: 14),
            ),
          ),
        ],
      ),
    );
  }
}

/// Sheet: Mitarbeiter und Typ für eine Stunde wählen
class _ZuweisenStundeSheet extends StatefulWidget {
  final int stunde;
  final List<NfsMitarbeiterRow> mitarbeiter;
  final List<BereitschaftsTyp> typen;
  final Color Function(String id) colorForTyp;

  const _ZuweisenStundeSheet({
    required this.stunde,
    required this.mitarbeiter,
    required this.typen,
    required this.colorForTyp,
  });

  @override
  State<_ZuweisenStundeSheet> createState() => _ZuweisenStundeSheetState();
}

class _ZuweisenStundeSheetState extends State<_ZuweisenStundeSheet> {
  String? _mitarbeiterId;
  String? _typId;

  @override
  void initState() {
    super.initState();
    if (widget.typen.isNotEmpty) _typId = widget.typen.first.id;
    if (widget.mitarbeiter.isNotEmpty) _mitarbeiterId = widget.mitarbeiter.first.mitarbeiter.id;
  }

  @override
  Widget build(BuildContext context) {
    final label = widget.stunde == 23
        ? '23:00–24:00'
        : '${widget.stunde.toString().padLeft(2, '0')}:00–${(widget.stunde + 1).toString().padLeft(2, '0')}:00';
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          left: 16,
          right: 16,
          top: 16,
          bottom: 16 + MediaQuery.viewPaddingOf(context).bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Schicht zuweisen – $label',
              style: const TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 16,
              ),
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              value: _mitarbeiterId,
              decoration: const InputDecoration(
                labelText: 'Mitarbeiter',
                border: OutlineInputBorder(),
              ),
              items: widget.mitarbeiter
                  .map((r) => DropdownMenuItem(
                        value: r.mitarbeiter.id,
                        child: Text(r.mitarbeiter.displayName),
                      ))
                  .toList(),
              onChanged: (v) => setState(() => _mitarbeiterId = v),
            ),
            const SizedBox(height: 12),
            if (widget.typen.isNotEmpty)
              DropdownButtonFormField<String>(
                value: _typId ?? widget.typen.first.id,
                decoration: const InputDecoration(
                  labelText: 'Bereitschafts-Typ',
                  border: OutlineInputBorder(),
                ),
                items: widget.typen
                    .map((t) => DropdownMenuItem(
                          value: t.id,
                          child: Row(
                            children: [
                              Container(
                                width: 12,
                                height: 12,
                                decoration: BoxDecoration(
                                  color: widget.colorForTyp(t.id),
                                  borderRadius: BorderRadius.circular(2),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(t.name),
                            ],
                          ),
                        ))
                    .toList(),
                onChanged: (v) => setState(() => _typId = v),
              ),
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Abbrechen'),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: (_mitarbeiterId != null &&
                          _typId != null &&
                          _mitarbeiterId!.isNotEmpty &&
                          _typId!.isNotEmpty)
                      ? () => Navigator.pop(
                            context,
                            (
                              mitarbeiterId: _mitarbeiterId!,
                              typId: _typId!,
                            ),
                          )
                      : null,
                  child: const Text('Zuweisen'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
