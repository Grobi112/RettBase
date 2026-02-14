import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../services/schichtanmeldung_service.dart';
import '../services/schichtplan_nfs_service.dart';
import '../utils/schichtplan_nfs_bereitschaftstyp_utils.dart';

/// Body für Tab "Meldungen": Liste der Meldungen von "Verfügbarkeit angeben"
/// Mit Annehmen/Ablehnen
class SchichtplanNfsMeldungenBody extends StatefulWidget {
  final String companyId;
  final String? userRole;
  final void Function(void Function() refresh)? onRegisterRefresh;
  /// Wird aufgerufen, wenn eine Meldung angenommen wurde (andere Tabs sollen sich aktualisieren)
  final VoidCallback? onMeldungAngenommen;

  const SchichtplanNfsMeldungenBody({
    super.key,
    required this.companyId,
    this.userRole,
    this.onRegisterRefresh,
    this.onMeldungAngenommen,
  });

  @override
  State<SchichtplanNfsMeldungenBody> createState() =>
      _SchichtplanNfsMeldungenBodyState();
}

class _SchichtplanNfsMeldungenBodyState extends State<SchichtplanNfsMeldungenBody> {
  final _service = SchichtplanNfsService();
  List<NfsMeldung> _meldungen = [];
  List<BereitschaftsTyp> _typen = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    widget.onRegisterRefresh?.call(_load);
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
      final list = await _service.loadMeldungen(widget.companyId);
      if (mounted) {
        setState(() {
          _typen = typen;
          _meldungen = list;
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

  String _typName(String typId) =>
      _typen.where((t) => t.id == typId).firstOrNull?.name ?? typId;

  Color _typColor(String typId) =>
      SchichtplanNfsBereitschaftstypUtils.colorForTypId(typId, _typen);

  String _formatZeitraum(NfsMeldung m) {
    final von =
        '${m.datumVon.day.toString().padLeft(2, '0')}.${m.datumVon.month.toString().padLeft(2, '0')}.${m.datumVon.year}';
    final bis =
        '${m.datumBis.day.toString().padLeft(2, '0')}.${m.datumBis.month.toString().padLeft(2, '0')}.${m.datumBis.year}';
    final uVon = '${m.uhrzeitVon.toString().padLeft(2, '0')}:00';
    final uBis =
        m.uhrzeitBis == 24 ? '24:00' : '${m.uhrzeitBis.toString().padLeft(2, '0')}:00';
    if (von == bis) {
      return '$von, $uVon–$uBis';
    }
    return '$von – $bis, $uVon–$uBis';
  }

  void _showAnnehmenAblehnen(NfsMeldung meldung) {
    showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Schließen',
      barrierColor: Colors.black54,
      transitionDuration: const Duration(milliseconds: 200),
      pageBuilder: (ctx, _, __) => Center(
        child: Material(
          color: Colors.transparent,
          child: Card(
            margin: const EdgeInsets.symmetric(horizontal: 24),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    meldung.displayName,
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 18,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _formatZeitraum(meldung),
                    style: TextStyle(fontSize: 14, color: AppTheme.textMuted),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Wohnort: ${meldung.wohnort}',
                    style: TextStyle(fontSize: 14, color: AppTheme.textMuted),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Container(
                        width: 14,
                        height: 14,
                        decoration: BoxDecoration(
                          color: _typColor(meldung.typId),
                          borderRadius: BorderRadius.circular(3),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Bereitschaftstyp: ${_typName(meldung.typId)}',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          color: _typColor(meldung.typId),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () async {
                            Navigator.pop(ctx);
                            try {
                              await _service.rejectMeldung(widget.companyId, meldung.id);
                              if (mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('Meldung abgelehnt')),
                                );
                                _load();
                              }
                            } catch (e) {
                              if (mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text('Fehler: $e')),
                                );
                              }
                            }
                          },
                          icon: const Icon(Icons.close),
                          label: const Text('Ablehnen'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.red,
                            side: BorderSide(color: Colors.red.shade400),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: () async {
                            Navigator.pop(ctx);
                            try {
                              await _service.acceptMeldung(widget.companyId, meldung);
                              if (mounted) {
                                widget.onMeldungAngenommen?.call();
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text('Meldung angenommen und in den Kalender eingetragen'),
                                  ),
                                );
                                _load();
                              }
                            } catch (e) {
                              if (mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text('Fehler: $e')),
                                );
                              }
                            }
                          },
                          icon: const Icon(Icons.check),
                          label: const Text('Annehmen'),
                        ),
                      ),
                    ],
                  ),
                ],
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
      return const Center(
        child: CircularProgressIndicator(color: AppTheme.primary),
      );
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.error_outline, size: 48, color: Colors.red[400]),
              const SizedBox(height: 16),
              Text(_error!, textAlign: TextAlign.center),
              const SizedBox(height: 16),
              FilledButton(onPressed: _load, child: const Text('Erneut versuchen')),
            ],
          ),
        ),
      );
    }
    if (_meldungen.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.inbox_outlined, size: 64, color: AppTheme.textMuted),
              const SizedBox(height: 16),
              Text(
                'Keine offenen Meldungen',
                style: TextStyle(
                  fontSize: 16,
                  color: AppTheme.textMuted,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                'Meldungen erscheinen hier, sobald sich Mitarbeitende über „Verfügbarkeit angeben“ angemeldet haben.',
                style: TextStyle(
                  fontSize: 14,
                  color: AppTheme.textMuted,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _meldungen.length,
        itemBuilder: (context, index) {
          final m = _meldungen[index];
          return Card(
            margin: const EdgeInsets.only(bottom: 12),
            child: ListTile(
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 12,
              ),
              title: Text(
                m.displayName,
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 16,
                ),
              ),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 4),
                  Text(
                    _formatZeitraum(m),
                    style: TextStyle(fontSize: 14, color: AppTheme.textMuted),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Wohnort: ${m.wohnort}',
                    style: TextStyle(fontSize: 13, color: AppTheme.textMuted),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Container(
                        width: 12,
                        height: 12,
                        decoration: BoxDecoration(
                          color: _typColor(m.typId),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        _typName(m.typId),
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: _typColor(m.typId),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => _showAnnehmenAblehnen(m),
            ),
          );
        },
      ),
    );
  }
}
