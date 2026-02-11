import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../models/information_model.dart';
import '../services/informationen_service.dart';
import '../services/informationssystem_service.dart';

String _formatDate(DateTime d) {
  final day = d.day.toString().padLeft(2, '0');
  final mon = d.month.toString().padLeft(2, '0');
  return '$day.$mon.${d.year}';
}

/// Screen zum Anlegen oder Bearbeiten einer Information (Informationssystem)
class InformationAnlegenScreen extends StatefulWidget {
  final String companyId;
  final List<String> kategorien;
  final String userDisplayName;
  final String userId;
  final VoidCallback onBack;
  final VoidCallback onSaved;
  /// Beim Bearbeiten: bestehende Information zum Vorausfüllen
  final Information? initialInfo;
  /// Beim Anlegen: Standard-Typ (z.B. aus aktuellem Tab)
  final String? defaultTyp;
  /// Beim Bearbeiten: Löschen-Button anzeigen (für berechtigte Rollen)
  final bool canDelete;
  /// Optionale Container-Typen (id → label); sonst Standard-Typen
  final List<String>? containerTypeIds;
  final Map<String, String>? containerTypeLabels;

  const InformationAnlegenScreen({
    super.key,
    required this.companyId,
    required this.kategorien,
    required this.userDisplayName,
    required this.userId,
    required this.onBack,
    required this.onSaved,
    this.initialInfo,
    this.defaultTyp,
    this.canDelete = false,
    this.containerTypeIds,
    this.containerTypeLabels,
  });

  @override
  State<InformationAnlegenScreen> createState() => _InformationAnlegenScreenState();
}

class _InformationAnlegenScreenState extends State<InformationAnlegenScreen> {
  final _infoService = InformationenService();
  late final TextEditingController _betreffCtrl;
  late final TextEditingController _textCtrl;

  late DateTime _datum;
  late TimeOfDay _uhrzeit;
  late String _typ;
  late String _kategorie;
  late String _laufzeit;
  late String _prioritaet;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final info = widget.initialInfo;
    if (info != null) {
      _datum = info.datum;
      final parts = info.uhrzeit.split(':');
      _uhrzeit = TimeOfDay(
        hour: parts.isNotEmpty ? int.tryParse(parts[0]) ?? 0 : 0,
        minute: parts.length > 1 ? int.tryParse(parts[1]) ?? 0 : 0,
      );
      _typ = info.typ;
      _kategorie = info.kategorie;
      _laufzeit = info.laufzeit;
      _prioritaet = info.prioritaet;
      _betreffCtrl = TextEditingController(text: info.betreff);
      _textCtrl = TextEditingController(text: info.text);
    } else {
      _datum = DateTime.now();
      _uhrzeit = TimeOfDay.now();
      _typ = widget.defaultTyp ?? (widget.containerTypeIds?.isNotEmpty == true ? widget.containerTypeIds!.first : InformationssystemService.containerTypes.first);
      _kategorie = '';
      _laufzeit = '1_monat';
      _prioritaet = 'normal';
      _betreffCtrl = TextEditingController();
      _textCtrl = TextEditingController();
    }
  }

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
    if (widget.companyId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Keine Firmen-ID vorhanden.')));
      return;
    }

    final navigator = Navigator.of(context);
    setState(() => _saving = true);
    try {
      final existingId = widget.initialInfo?.id ?? '';
      final info = Information(
        id: existingId,
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
        createdAt: widget.initialInfo?.createdAt ?? DateTime.now(),
      );
      await _infoService.saveInformation(widget.companyId, info);
      if (mounted) {
        // Kein setState vor pop – Screen wird entfernt, Rebuild würde auf ungültigem Context laufen
        navigator.pop(true);
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
        title: widget.initialInfo != null ? 'Information bearbeiten' : 'Neue Information',
        onBack: widget.onBack,
        leadingIcon: Icons.close,
        actions: [
          if (widget.canDelete && widget.initialInfo != null)
            IconButton(
              icon: Icon(Icons.delete_outline, color: Colors.red[700]),
              tooltip: 'Löschen',
              onPressed: () async {
                final navigator = Navigator.of(context);
                final infoId = widget.initialInfo!.id;
                final companyId = widget.companyId;
                final ok = await showDialog<bool>(
                  context: context,
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
                if (ok == true && mounted) {
                  await _infoService.deleteInformation(companyId, infoId);
                  if (mounted) {
                    // SnackBar im übergeordneten Screen zeigen – Context hier wäre nach pop ungültig
                    navigator.pop('deleted');
                  }
                }
              },
            ),
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
              items: (widget.containerTypeIds ?? InformationssystemService.containerTypes).map((id) {
                final label = widget.containerTypeLabels?[id] ?? InformationssystemService.containerLabels[id] ?? id;
                return DropdownMenuItem(value: id, child: Text(label));
              }).toList(),
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
