import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../services/schichtanmeldung_service.dart';
import '../services/schichtplan_nfs_service.dart';
import '../utils/schichtplan_nfs_bereitschaftstyp_utils.dart';

/// Dialog „Schicht anlegen“: Datum von–bis, Uhrzeit von–bis, Bereitschaftstyp, Name
/// Mittig zentriert. Optional initialDate für Vorbelegung (z.B. aus Tagesansicht).
class SchichtAnlegenSheet extends StatefulWidget {
  final String companyId;
  final VoidCallback onSaved;
  final VoidCallback? onCancel;
  final DateTime? initialDate;

  const SchichtAnlegenSheet({
    super.key,
    required this.companyId,
    required this.onSaved,
    this.onCancel,
    this.initialDate,
  });

  @override
  State<SchichtAnlegenSheet> createState() => _SchichtAnlegenSheetState();
}

class _SchichtAnlegenSheetState extends State<SchichtAnlegenSheet> {
  final _service = SchichtplanNfsService();
  late DateTime _datumVon;
  late DateTime _datumBis;
  int _uhrzeitVon = 8;
  int _uhrzeitBis = 12;
  String? _typId;
  NfsMitarbeiterRow? _selectedMitarbeiter;
  List<BereitschaftsTyp> _typen = [];
  List<NfsMitarbeiterRow> _mitarbeiter = [];
  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final init = widget.initialDate ?? DateTime.now();
    _datumVon = init;
    _datumBis = init;
    _load();
  }

  Future<void> _load() async {
    try {
      final alleTypen = await _service.loadBereitschaftsTypen(widget.companyId);
      final typen = SchichtplanNfsBereitschaftstypUtils.filterAndSortS1S2B(
        alleTypen,
      );
      final ma = await _service.loadMitarbeiterMitStandort(widget.companyId);
      if (mounted) {
        setState(() {
          _typen = typen;
          _mitarbeiter = ma;
          _loading = false;
          if (_typId == null && typen.isNotEmpty) _typId = typen.first.id;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Color _colorForTyp(String id) =>
      SchichtplanNfsBereitschaftstypUtils.colorForTypId(id, _typen);

  Future<void> _save() async {
    final m = _selectedMitarbeiter?.mitarbeiter;
    if (m == null || _typId == null || _typId!.isEmpty || _uhrzeitBis <= _uhrzeitVon) return;
    if (_datumBis.isBefore(_datumVon)) return;
    setState(() => _saving = true);
    try {
      var d = DateTime(_datumVon.year, _datumVon.month, _datumVon.day);
      final end = DateTime(_datumBis.year, _datumBis.month, _datumBis.day);
      while (!d.isAfter(end)) {
        final dayId =
            '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.${d.year}';
        for (var h = _uhrzeitVon; h < _uhrzeitBis; h++) {
          await _service.saveStundenplanEintrag(
            widget.companyId,
            dayId,
            m.id,
            h,
            _typId!,
          );
        }
        d = d.add(const Duration(days: 1));
      }
      if (mounted) widget.onSaved();
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Card(
        margin: const EdgeInsets.symmetric(horizontal: 24),
        child: const Padding(
          padding: EdgeInsets.all(48),
          child: CircularProgressIndicator(color: AppTheme.primary),
        ),
      );
    }
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
              const Text(
                'Schicht anlegen',
                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 18),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Datum von'),
                      subtitle: Text(
                        '${_datumVon.day.toString().padLeft(2, '0')}.${_datumVon.month.toString().padLeft(2, '0')}.${_datumVon.year}',
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      trailing: Icon(Icons.calendar_today, color: AppTheme.primary),
                      onTap: () async {
                        final picked = await showDatePicker(
                          context: context,
                          initialDate: _datumVon,
                          firstDate: DateTime(2020),
                          lastDate: DateTime(2030),
                        );
                        if (picked != null && mounted) {
                          setState(() {
                            _datumVon = picked;
                            if (_datumBis.isBefore(_datumVon)) _datumBis = _datumVon;
                          });
                        }
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Datum bis'),
                      subtitle: Text(
                        '${_datumBis.day.toString().padLeft(2, '0')}.${_datumBis.month.toString().padLeft(2, '0')}.${_datumBis.year}',
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      trailing: Icon(Icons.calendar_today, color: AppTheme.primary),
                      onTap: () async {
                        final picked = await showDatePicker(
                          context: context,
                          initialDate: _datumBis.isBefore(_datumVon) ? _datumVon : _datumBis,
                          firstDate: _datumVon,
                          lastDate: DateTime(2030),
                        );
                        if (picked != null && mounted) setState(() => _datumBis = picked);
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<int>(
                      value: _uhrzeitVon,
                      decoration: const InputDecoration(
                        labelText: 'Uhrzeit von',
                        border: OutlineInputBorder(),
                      ),
                      items: List.generate(
                        24,
                        (i) => DropdownMenuItem(
                          value: i,
                          child: Text('${i.toString().padLeft(2, '0')}:00'),
                        ),
                      ),
                      onChanged: (v) {
                        if (v != null) {
                          setState(() {
                            _uhrzeitVon = v;
                            if (_uhrzeitBis <= _uhrzeitVon) _uhrzeitBis = _uhrzeitVon + 1;
                          });
                        }
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: DropdownButtonFormField<int>(
                      value: _uhrzeitBis > _uhrzeitVon ? _uhrzeitBis : (_uhrzeitVon < 23 ? _uhrzeitVon + 1 : 24),
                      decoration: const InputDecoration(
                        labelText: 'Uhrzeit bis',
                        border: OutlineInputBorder(),
                      ),
                      items: [
                        for (var v = _uhrzeitVon + 1; v <= 24; v++)
                          DropdownMenuItem(
                            value: v,
                            child: Text(
                              v == 24 ? '24:00' : '${v.toString().padLeft(2, '0')}:00',
                            ),
                          ),
                      ],
                      onChanged: (v) => setState(() => _uhrzeitBis = v ?? _uhrzeitVon + 1),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              if (_typen.isNotEmpty)
                DropdownButtonFormField<String>(
                  value: _typId ?? _typen.first.id,
                  decoration: const InputDecoration(
                    labelText: 'Bereitschaftstyp',
                    border: OutlineInputBorder(),
                  ),
                  items: _typen
                      .map((t) => DropdownMenuItem(
                            value: t.id,
                            child: Row(
                              children: [
                                Container(
                                  width: 14,
                                  height: 14,
                                  decoration: BoxDecoration(
                                    color: _colorForTyp(t.id),
                                    borderRadius: BorderRadius.circular(3),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Text(t.name),
                              ],
                            ),
                          ))
                      .toList(),
                  onChanged: (v) => setState(() => _typId = v),
                ),
              const SizedBox(height: 12),
              _SearchableMitarbeiterDropdown(
                mitarbeiter: _mitarbeiter,
                selected: _selectedMitarbeiter,
                onSelected: (r) => setState(() => _selectedMitarbeiter = r),
                onCleared: () => setState(() => _selectedMitarbeiter = null),
              ),
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: _saving ? null : () { widget.onCancel != null ? widget.onCancel!() : Navigator.pop(context); },
                    child: const Text('Abbrechen'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: (_saving ||
                            _selectedMitarbeiter == null ||
                            _typId == null ||
                            _typId!.isEmpty ||
                            _uhrzeitBis <= _uhrzeitVon ||
                            _datumBis.isBefore(_datumVon))
                        ? null
                        : _save,
                    child: _saving
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : const Text('Schicht anlegen'),
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

class _SearchableMitarbeiterDropdown extends StatefulWidget {
  final List<NfsMitarbeiterRow> mitarbeiter;
  final NfsMitarbeiterRow? selected;
  final void Function(NfsMitarbeiterRow?) onSelected;
  final VoidCallback onCleared;

  const _SearchableMitarbeiterDropdown({
    required this.mitarbeiter,
    required this.selected,
    required this.onSelected,
    required this.onCleared,
  });

  @override
  State<_SearchableMitarbeiterDropdown> createState() =>
      _SearchableMitarbeiterDropdownState();
}

class _SearchableMitarbeiterDropdownState extends State<_SearchableMitarbeiterDropdown> {
  void _openDropdown() async {
    final result = await showDialog<NfsMitarbeiterRow>(
      context: context,
      builder: (ctx) => _SearchableMitarbeiterDialog(
        mitarbeiter: widget.mitarbeiter,
      ),
    );
    if (result != null) widget.onSelected(result);
  }

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: _openDropdown,
      borderRadius: BorderRadius.circular(4),
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: 'Name',
          hintText: 'Mitarbeiter auswählen',
          border: const OutlineInputBorder(),
          suffixIcon: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (widget.selected != null)
                IconButton(
                  icon: const Icon(Icons.clear, size: 20),
                  onPressed: () => widget.onCleared(),
                ),
              const Icon(Icons.arrow_drop_down),
            ],
          ),
        ),
        child: Text(
          widget.selected?.mitarbeiter.displayName ?? '',
          style: widget.selected != null
              ? null
              : TextStyle(color: Theme.of(context).hintColor),
        ),
      ),
    );
  }
}

class _SearchableMitarbeiterDialog extends StatefulWidget {
  final List<NfsMitarbeiterRow> mitarbeiter;

  const _SearchableMitarbeiterDialog({required this.mitarbeiter});

  @override
  State<_SearchableMitarbeiterDialog> createState() =>
      _SearchableMitarbeiterDialogState();
}

class _SearchableMitarbeiterDialogState extends State<_SearchableMitarbeiterDialog> {
  final _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<NfsMitarbeiterRow> get _filtered {
    final q = _searchController.text.toLowerCase().trim();
    if (q.isEmpty) return widget.mitarbeiter;
    return widget.mitarbeiter.where((r) {
      final name = r.mitarbeiter.displayName.toLowerCase();
      final email = (r.mitarbeiter.email ?? '').toLowerCase();
      return name.contains(q) || email.contains(q);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Mitarbeiter auswählen'),
      content: SizedBox(
        width: 400,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _searchController,
              decoration: const InputDecoration(
                hintText: 'Mitarbeiter suchen...',
                prefixIcon: Icon(Icons.search),
                border: OutlineInputBorder(),
              ),
              onChanged: (_) => setState(() {}),
              autofocus: true,
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 280,
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: _filtered.length,
                itemBuilder: (ctx, i) {
                  final r = _filtered[i];
                  return ListTile(
                    dense: true,
                    title: Text(r.mitarbeiter.displayName),
                    subtitle: r.standortName != null
                        ? Text(r.standortName!, style: const TextStyle(fontSize: 11))
                        : null,
                    onTap: () => Navigator.pop(context, r),
                  );
                },
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Abbrechen'),
        ),
      ],
    );
  }
}
