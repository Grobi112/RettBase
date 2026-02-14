import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../services/auth_service.dart';
import '../services/schichtanmeldung_service.dart';
import '../services/schichtplan_nfs_service.dart';
import '../utils/schichtplan_nfs_bereitschaftstyp_utils.dart';

/// Dialog „Verfügbarkeit angeben“: aktueller User meldet sich für Zeitraum an
class SchichtplanNfsOffeneSchichtMeldenSheet extends StatefulWidget {
  final String companyId;
  final VoidCallback onSaved;
  final VoidCallback? onCancel;
  final DateTime? initialDate;

  const SchichtplanNfsOffeneSchichtMeldenSheet({
    super.key,
    required this.companyId,
    required this.onSaved,
    this.onCancel,
    this.initialDate,
  });

  @override
  State<SchichtplanNfsOffeneSchichtMeldenSheet> createState() =>
      _SchichtplanNfsOffeneSchichtMeldenSheetState();
}

class _SchichtplanNfsOffeneSchichtMeldenSheetState
    extends State<SchichtplanNfsOffeneSchichtMeldenSheet> {
  final _service = SchichtplanNfsService();
  final _authService = AuthService();
  late DateTime _datumVon;
  late DateTime _datumBis;
  int _uhrzeitVon = 8;
  int _uhrzeitBis = 12;
  String? _typId;
  SchichtplanMitarbeiter? _mitarbeiter;
  List<BereitschaftsTyp> _typen = [];
  bool _loading = true;
  bool _saving = false;
  String? _error;

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
      final user = _authService.currentUser;
      final email = user?.email ?? '';
      final uid = user?.uid ?? '';
      SchichtplanMitarbeiter? m;
      if (email.isNotEmpty) {
        m = await _service.findMitarbeiterByEmail(widget.companyId, email);
      }
      if (m == null && uid.isNotEmpty) {
        m = await _service.findMitarbeiterByUid(widget.companyId, uid);
      }
      final alleTypen = await _service.loadBereitschaftsTypen(widget.companyId);
      final typen = SchichtplanNfsBereitschaftstypUtils.filterAndSortS1S2B(
        alleTypen,
      );
      if (mounted) {
        setState(() {
          _mitarbeiter = m;
          _typen = typen;
          _loading = false;
          if (_typId == null && typen.isNotEmpty) _typId = typen.first.id;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _save() async {
    if (_mitarbeiter == null) {
      setState(() => _error = 'Keine Mitarbeiter-Zuordnung gefunden.');
      return;
    }
    if (_typId == null || _typId!.isEmpty) return;
    if (_uhrzeitBis <= _uhrzeitVon) return;
    if (_datumBis.isBefore(_datumVon)) return;
    setState(() => _saving = true);
    setState(() => _error = null);
    try {
      await _service.saveMeldung(
        widget.companyId,
        mitarbeiterId: _mitarbeiter!.id,
        vorname: _mitarbeiter!.vorname ?? '',
        nachname: _mitarbeiter!.nachname ?? '',
        ort: _mitarbeiter!.ort,
        datumVon: _datumVon,
        datumBis: _datumBis,
        uhrzeitVon: _uhrzeitVon,
        uhrzeitBis: _uhrzeitBis,
        typId: _typId!,
      );
      if (mounted) {
        widget.onSaved();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Ihre Meldung wurde gespeichert und erscheint im Reiter „Meldungen“. Ein Koordinator muss sie noch annehmen.',
            ),
            duration: Duration(seconds: 4),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = e.toString();
        });
      }
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
    if (_mitarbeiter == null) {
      return Card(
        margin: const EdgeInsets.symmetric(horizontal: 24),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Verfügbarkeit angeben',
                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 18),
              ),
              const SizedBox(height: 16),
              Text(
                'Keine Mitarbeiter-Zuordnung gefunden. Bitte stellen Sie sicher, dass Sie in der Mitgliederverwaltung mit Ihrer E-Mail oder UID hinterlegt sind.',
                style: TextStyle(fontSize: 14, color: AppTheme.textMuted),
              ),
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () =>
                        widget.onCancel != null ? widget.onCancel!() : Navigator.pop(context),
                    child: const Text('Schließen'),
                  ),
                ],
              ),
            ],
          ),
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
                'Verfügbarkeit angeben',
                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 18),
              ),
              const SizedBox(height: 8),
              Text(
                _mitarbeiter!.displayName,
                style: TextStyle(fontSize: 14, color: AppTheme.textMuted),
              ),
              const SizedBox(height: 20),
              if (_error != null) ...[
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.red.shade50,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    _error!,
                    style: TextStyle(fontSize: 13, color: Colors.red.shade800),
                  ),
                ),
                const SizedBox(height: 16),
              ],
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
                          initialDate: _datumBis.isBefore(_datumVon)
                              ? _datumVon
                              : _datumBis,
                          firstDate: _datumVon,
                          lastDate: DateTime(2030),
                        );
                        if (picked != null && mounted) {
                          setState(() => _datumBis = picked);
                        }
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
                            if (_uhrzeitBis <= _uhrzeitVon) {
                              _uhrzeitBis = _uhrzeitVon < 23 ? _uhrzeitVon + 1 : 24;
                            }
                          });
                        }
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: DropdownButtonFormField<int>(
                      value: _uhrzeitBis > _uhrzeitVon
                          ? _uhrzeitBis
                          : (_uhrzeitVon < 23 ? _uhrzeitVon + 1 : 24),
                      decoration: const InputDecoration(
                        labelText: 'Uhrzeit bis',
                        border: OutlineInputBorder(),
                      ),
                      items: [
                        for (var v = _uhrzeitVon + 1; v <= 24; v++)
                          DropdownMenuItem(
                            value: v,
                            child: Text(
                              v == 24
                                  ? '24:00'
                                  : '${v.toString().padLeft(2, '0')}:00',
                            ),
                          ),
                      ],
                      onChanged: (v) =>
                          setState(() => _uhrzeitBis = v ?? _uhrzeitVon + 1),
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
                                    color: SchichtplanNfsBereitschaftstypUtils
                                        .colorForTyp(t),
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
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: _saving
                        ? null
                        : () => widget.onCancel != null
                            ? widget.onCancel!()
                            : Navigator.pop(context),
                    child: const Text('Abbrechen'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: (_saving ||
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
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white),
                          )
                        : const Text('Melden'),
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
