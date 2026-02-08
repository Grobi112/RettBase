import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../theme/app_theme.dart';
import '../models/information_model.dart';
import '../services/informationssystem_service.dart';
import '../services/informationen_service.dart';
import '../services/auth_data_service.dart';
import '../services/auth_service.dart';

/// Einstellungen: Informationssystem – 3 Bereiche (Sortierung, Kategorien, Information erstellen)
class EinstellungenInformationssystemScreen extends StatefulWidget {
  final String companyId;
  final VoidCallback? onBack;
  final VoidCallback? onSaved;

  const EinstellungenInformationssystemScreen({
    super.key,
    required this.companyId,
    this.onBack,
    this.onSaved,
  });

  @override
  State<EinstellungenInformationssystemScreen> createState() => _EinstellungenInformationssystemScreenState();
}

class _EinstellungenInformationssystemScreenState extends State<EinstellungenInformationssystemScreen> {
  final _service = InformationssystemService();
  final _infoService = InformationenService();
  final _authService = AuthService();
  final _authDataService = AuthDataService();

  List<String?> _slots = [null, null];
  List<String> _kategorien = [];
  final _neueKategorieCtrl = TextEditingController();
  bool _loading = true;
  bool _saving = false;

  // Formular "Information erstellen"
  final _betreffCtrl = TextEditingController();
  final _textCtrl = TextEditingController();
  DateTime _formDatum = DateTime.now();
  TimeOfDay _formUhrzeit = TimeOfDay.now();
  String _formTyp = InformationssystemService.containerTypes.first;
  String _formKategorie = '';
  String _formLaufzeit = '1_monat';

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
  String? _formUserId;
  String _formUserDisplayName = '';
  bool _formSaving = false;

  @override
  void initState() {
    super.initState();
    _load();
    _loadCurrentUser();
  }

  @override
  void dispose() {
    _neueKategorieCtrl.dispose();
    _betreffCtrl.dispose();
    _textCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadCurrentUser() async {
    final user = _authService.currentUser;
    if (user == null) return;
    final authData = await _authDataService.getAuthData(user.uid, user.email ?? '', widget.companyId);
    if (mounted) {
      setState(() {
        _formUserId = user.uid;
        _formUserDisplayName = authData.displayName ?? user.email ?? 'Unbekannt';
      });
    }
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final results = await Future.wait([
        _service.loadContainerOrder(widget.companyId),
        _service.loadKategorien(widget.companyId),
      ]);
      if (mounted) {
        setState(() {
          _slots = results[0] as List<String?>;
          _kategorien = results[1] as List<String>;
          if (_kategorien.isNotEmpty && _formKategorie.isEmpty) _formKategorie = _kategorien.first;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _slots = [null, null];
          _kategorien = [];
          _loading = false;
        });
      }
    }
  }

  Future<void> _saveEinstellungen() async {
    setState(() => _saving = true);
    try {
      await _service.saveAll(widget.companyId, containerSlots: _slots, kategorien: _kategorien);
      if (mounted) {
        setState(() => _saving = false);
        widget.onSaved?.call();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Einstellungen gespeichert')),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Fehler: $e')),
        );
      }
    }
  }

  Future<void> _speichereInformation() async {
    final betreff = _betreffCtrl.text.trim();
    if (betreff.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Bitte Betreff eingeben.')));
      return;
    }
    final uid = _formUserId;
    if (uid == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Nicht angemeldet.')));
      return;
    }

    setState(() => _formSaving = true);
    try {
      final info = Information(
        id: '',
        datum: _formDatum,
        uhrzeit: '${_formUhrzeit.hour.toString().padLeft(2, '0')}:${_formUhrzeit.minute.toString().padLeft(2, '0')}',
        userId: uid,
        userDisplayName: _formUserDisplayName,
        typ: _formTyp,
        kategorie: _formKategorie,
        laufzeit: _formLaufzeit,
        betreff: betreff,
        text: _textCtrl.text.trim(),
        createdAt: DateTime.now(),
      );
      await _infoService.saveInformation(widget.companyId, info);
      if (mounted) {
        setState(() {
          _formSaving = false;
          _betreffCtrl.clear();
          _textCtrl.clear();
        });
        widget.onSaved?.call();
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Information gespeichert')));
      }
    } catch (e) {
      if (mounted) {
        setState(() => _formSaving = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Fehler: $e')));
      }
    }
  }

  void _addKategorie() {
    final t = _neueKategorieCtrl.text.trim();
    if (t.isEmpty) return;
    if (_kategorien.contains(t)) return;
    setState(() {
      _kategorien = [..._kategorien, t]..sort();
      _neueKategorieCtrl.clear();
    });
  }

  void _ensureNoDuplicate(String? selected, int changedIndex) {
    if (selected == null || selected.isEmpty) return;
    final other = changedIndex == 0 ? 1 : 0;
    if (_slots[other] == selected) {
      _slots[other] = null;
    }
  }

  String _formatDate(DateTime d) {
    final day = d.day.toString().padLeft(2, '0');
    final mon = d.month.toString().padLeft(2, '0');
    return '$day.$mon.${d.year}';
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
        actions: [
          FilledButton(
            onPressed: (_loading || _saving) ? null : _saveEinstellungen,
            style: FilledButton.styleFrom(backgroundColor: AppTheme.primary),
            child: _saving ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Text('Einstellungen speichern'),
          ),
          const SizedBox(width: 16),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppTheme.primary))
          : ListView(
              padding: const EdgeInsets.all(20),
              children: [
                _ExpandableSectionCard(
                  icon: Icons.swap_horiz,
                  title: 'Sortierung Container Hauptseite',
                  subtitle: 'Container auf der Hauptseite (Informationen, Verkehrslage) anordnen',
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Wählen Sie pro Position (von links nach rechts), welcher Container angezeigt werden soll.',
                        style: TextStyle(fontSize: 14, color: AppTheme.textSecondary, height: 1.4),
                      ),
                      const SizedBox(height: 16),
                      _SlotDropdown(
                        label: 'Position 1 (links)',
                        value: _slots[0],
                        onChanged: (v) => setState(() {
                          _slots = [_slots[0], _slots[1]];
                          _slots[0] = v;
                          _ensureNoDuplicate(v, 0);
                        }),
                      ),
                      const SizedBox(height: 12),
                      _SlotDropdown(
                        label: 'Position 2 (rechts)',
                        value: _slots[1],
                        onChanged: (v) => setState(() {
                          _slots = [_slots[0], _slots[1]];
                          _slots[1] = v;
                          _ensureNoDuplicate(v, 1);
                        }),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                _ExpandableSectionCard(
                  icon: Icons.category,
                  title: 'Kategorieeinstellung',
                  subtitle: 'Kategorien werden beim Erstellen einer Information zur Auswahl angezeigt',
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _neueKategorieCtrl,
                              decoration: const InputDecoration(
                                labelText: 'Neue Kategorie',
                                hintText: 'z.B. Allgemeine Information',
                                border: OutlineInputBorder(),
                              ),
                              onSubmitted: (_) => _addKategorie(),
                            ),
                          ),
                          const SizedBox(width: 12),
                          FilledButton.icon(
                            onPressed: _addKategorie,
                            icon: const Icon(Icons.add, size: 18),
                            label: const Text('Hinzufügen'),
                            style: FilledButton.styleFrom(backgroundColor: AppTheme.primary),
                          ),
                        ],
                      ),
                      if (_kategorien.isNotEmpty) ...[
                        const SizedBox(height: 16),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: _kategorien.map((k) => Chip(
                            label: Text(k),
                            onDeleted: () => setState(() => _kategorien.remove(k)),
                          )).toList(),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                _ExpandableSectionCard(
                  icon: Icons.add_circle_outline,
                  title: 'Information erstellen',
                  subtitle: 'Neue Information für den gewählten Container anlegen',
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: ListTile(
                              contentPadding: EdgeInsets.zero,
                              leading: const Icon(Icons.calendar_today, color: AppTheme.primary, size: 22),
                              title: const Text('Datum'),
                              subtitle: Text(_formatDate(_formDatum)),
                              onTap: () async {
                                final d = await showDatePicker(context: context, initialDate: _formDatum, firstDate: DateTime(2020), lastDate: DateTime(2030));
                                if (d != null && mounted) setState(() => _formDatum = d);
                              },
                            ),
                          ),
                          Expanded(
                            child: ListTile(
                              contentPadding: EdgeInsets.zero,
                              leading: const Icon(Icons.access_time, color: AppTheme.primary, size: 22),
                              title: const Text('Uhrzeit'),
                              subtitle: Text('${_formUhrzeit.hour.toString().padLeft(2, '0')}:${_formUhrzeit.minute.toString().padLeft(2, '0')}'),
                              onTap: () async {
                                final t = await showTimePicker(context: context, initialTime: _formUhrzeit);
                                if (t != null && mounted) setState(() => _formUhrzeit = t);
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
                              leading: const Icon(Icons.person, color: AppTheme.primary, size: 22),
                              title: const Text('User'),
                              subtitle: Text(_formUserDisplayName.isEmpty ? 'Wird aus Login geladen…' : _formUserDisplayName),
                            ),
                          ),
                          Expanded(
                            child: DropdownButtonFormField<String>(
                              value: _formLaufzeit,
                              decoration: InputDecoration(
                                labelText: 'Gültigkeit',
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                              ),
                              items: _laufzeitOptions.entries.map((e) => DropdownMenuItem(
                                value: e.key,
                                child: Text(e.value),
                              )).toList(),
                              onChanged: (v) => setState(() => _formLaufzeit = v ?? _formLaufzeit),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                        value: _formTyp,
                        decoration: InputDecoration(
                          labelText: 'Typ (Container)',
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                        items: InformationssystemService.containerTypes.map((id) => DropdownMenuItem(
                          value: id,
                          child: Text(InformationssystemService.containerLabels[id] ?? id),
                        )).toList(),
                        onChanged: (v) => setState(() => _formTyp = v ?? _formTyp),
                      ),
                      const SizedBox(height: 12),
                      if (_kategorien.isNotEmpty)
                        DropdownButtonFormField<String>(
                          value: _formKategorie.isEmpty ? null : _formKategorie,
                          decoration: InputDecoration(
                            labelText: 'Kategorie',
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                          ),
                          items: [
                            const DropdownMenuItem(value: null, child: Text('— Keine —')),
                            ..._kategorien.map((k) => DropdownMenuItem(value: k, child: Text(k))),
                          ],
                          onChanged: (v) => setState(() => _formKategorie = v ?? ''),
                        ),
                      if (_kategorien.isNotEmpty) const SizedBox(height: 12),
                      TextField(
                        controller: _betreffCtrl,
                        decoration: InputDecoration(
                          labelText: 'Überschrift / Betreff',
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                        maxLines: 1,
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _textCtrl,
                        decoration: InputDecoration(
                          labelText: 'Information',
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                          alignLabelWithHint: true,
                        ),
                        maxLines: 6,
                      ),
                      const SizedBox(height: 16),
                      FilledButton.icon(
                        onPressed: _formSaving ? null : _speichereInformation,
                        icon: _formSaving ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Icon(Icons.save, size: 18),
                        label: Text(_formSaving ? 'Wird gespeichert…' : 'Information speichern'),
                        style: FilledButton.styleFrom(backgroundColor: AppTheme.primary, padding: const EdgeInsets.symmetric(vertical: 14)),
                      ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }
}

class _ExpandableSectionCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Widget child;

  const _ExpandableSectionCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      clipBehavior: Clip.antiAlias,
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          initiallyExpanded: false,
          tilePadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          childrenPadding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          leading: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppTheme.primary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: AppTheme.primary, size: 28),
          ),
          title: Text(
            title,
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: AppTheme.textPrimary),
          ),
          subtitle: Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              subtitle,
              style: TextStyle(fontSize: 13, color: AppTheme.textSecondary),
            ),
          ),
          children: [child],
        ),
      ),
    );
  }
}

class _SlotDropdown extends StatelessWidget {
  final String label;
  final String? value;
  final void Function(String?) onChanged;

  const _SlotDropdown({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final options = [
      const DropdownMenuItem(value: null, child: Text('— Kein Container —')),
      ...InformationssystemService.containerTypes.map((id) => DropdownMenuItem(
            value: id,
            child: Text(InformationssystemService.containerLabels[id] ?? id),
          )),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: AppTheme.textPrimary)),
        const SizedBox(height: 8),
        DropdownButtonFormField<String?>(
          value: value,
          decoration: InputDecoration(
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          ),
          items: options,
          onChanged: onChanged,
        ),
      ],
    );
  }
}
