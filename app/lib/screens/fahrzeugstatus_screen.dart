import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../services/fahrzeugstatus_service.dart';
import '../services/schicht_status_service.dart';
import '../services/schichtanmeldung_service.dart';
import 'fahrzeugstatus_mangel_form_screen.dart';

/// Fahrzeugstatus – Übergabeprotokoll für Fahrer und Beifahrer.
/// Zeigt Mängel des aktuell zugeordneten Fahrzeugs (aus Schichtanmeldung).
class FahrzeugstatusScreen extends StatefulWidget {
  final String companyId;
  final String? title;
  final VoidCallback onBack;
  /// Wird bei Hinweis „Keine Schicht“ / „Kein Fahrzeug“ angezeigt – öffnet Schichtanmeldung
  final VoidCallback? onOpenSchichtanmeldung;

  const FahrzeugstatusScreen({
    super.key,
    required this.companyId,
    this.title,
    required this.onBack,
    this.onOpenSchichtanmeldung,
  });

  @override
  State<FahrzeugstatusScreen> createState() => _FahrzeugstatusScreenState();
}

class _FahrzeugstatusScreenState extends State<FahrzeugstatusScreen> {
  final _statusService = SchichtStatusService();
  final _schichtService = SchichtanmeldungService();
  final _fahrzeugstatusService = FahrzeugstatusService();

  SchichtanmeldungEintrag? _aktiveSchicht;
  String? _fahrzeugDisplayName;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final schicht = await _statusService.getAktiveSchicht(widget.companyId);
      String? fahrzeugDisplayName;
      if (schicht != null &&
          schicht.fahrzeugId.isNotEmpty &&
          schicht.fahrzeugId != 'alle') {
        final fahrzeuge = await _schichtService.loadFahrzeuge(widget.companyId);
        final fz = fahrzeuge.where((f) => f.id == schicht.fahrzeugId).firstOrNull;
        fahrzeugDisplayName = fz?.displayName ?? schicht.fahrzeugId;
      }
      if (mounted) {
        setState(() {
          _aktiveSchicht = schicht;
          _fahrzeugDisplayName = fahrzeugDisplayName;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _openMangelForm({FahrzeugstatusMangel? mangel}) {
    if (_aktiveSchicht == null ||
        _aktiveSchicht!.fahrzeugId.isEmpty ||
        _aktiveSchicht!.fahrzeugId == 'alle') {
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (ctx) => FahrzeugstatusMangelFormScreen(
          companyId: widget.companyId,
          fahrzeugId: _aktiveSchicht!.fahrzeugId,
          mangel: mangel,
          onSaved: () => Navigator.of(ctx).pop(),
        ),
      ),
    );
  }

  void _confirmDelete(FahrzeugstatusMangel m) {
    if (_aktiveSchicht == null) return;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Mangel löschen'),
        content: Text(
          'Möchten Sie den Mangel „${m.titel}" als behoben markieren und löschen?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Abbrechen'),
          ),
          FilledButton(
            onPressed: () async {
              Navigator.of(ctx).pop();
              try {
                await _fahrzeugstatusService.deleteMangel(
                  widget.companyId,
                  _aktiveSchicht!.fahrzeugId,
                  m.id,
                );
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Mangel gelöscht.')),
                  );
                }
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Fehler: $e')),
                  );
                }
              }
            },
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Löschen'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.surfaceBg,
      appBar: AppTheme.buildModuleAppBar(
        title: widget.title ?? 'Fahrzeugstatus',
        onBack: widget.onBack,
        actions: _canAddMangel
            ? [
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: AppTheme.headerPrimaryButton(
                    label: 'Neuer Eintrag',
                    onPressed: () => _openMangelForm(),
                  ),
                ),
              ]
            : null,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppTheme.primary))
          : _buildBody(),
    );
  }

  bool get _canAddMangel =>
      _aktiveSchicht != null &&
      _aktiveSchicht!.fahrzeugId.isNotEmpty &&
      _aktiveSchicht!.fahrzeugId != 'alle';

  Widget _buildBody() {
    if (_aktiveSchicht == null) {
      return _buildHinweis(
        icon: Icons.schedule,
        title: 'Keine aktive Schicht',
        text: 'Bitte melden Sie sich zuerst in der Schichtanmeldung für eine Schicht an.',
        actionLabel: 'Zur Schichtanmeldung',
        onAction: widget.onOpenSchichtanmeldung,
      );
    }
    if (_aktiveSchicht!.fahrzeugId.isEmpty || _aktiveSchicht!.fahrzeugId == 'alle') {
      return _buildHinweis(
        icon: Icons.directions_car_outlined,
        title: 'Kein Fahrzeug zugeordnet',
        text: 'Bitte wählen Sie in der Schichtanmeldung ein konkretes Fahrzeug (nicht „Alle“).',
        actionLabel: 'Zur Schichtanmeldung',
        onAction: widget.onOpenSchichtanmeldung,
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  CircleAvatar(
                    backgroundColor: AppTheme.primary.withValues(alpha: 0.15),
                    child: Icon(Icons.directions_car, color: AppTheme.primary),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Aktuelles Fahrzeug',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey[600],
                          ),
                        ),
                        Text(
                          _fahrzeugDisplayName ?? _aktiveSchicht!.fahrzeugId,
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        Expanded(
          child: StreamBuilder<List<FahrzeugstatusMangel>>(
            stream: _fahrzeugstatusService.streamMaengel(
              widget.companyId,
              _aktiveSchicht!.fahrzeugId,
            ),
            builder: (context, snap) {
              if (snap.connectionState == ConnectionState.waiting && !snap.hasData) {
                return const Center(child: CircularProgressIndicator(color: AppTheme.primary));
              }
              final list = snap.data ?? [];
              if (list.isEmpty) {
                return _buildHinweis(
                  icon: Icons.check_circle_outline,
                  title: 'Keine Mängel',
                  text: 'Für dieses Fahrzeug sind keine Mängel eingetragen. '
                      'Nutzen Sie „Neuer Eintrag" um einen Eintrag anzulegen.',
                );
              }
              return ListView.separated(
                padding: EdgeInsets.fromLTRB(
                  16,
                  8,
                  16,
                  MediaQuery.of(context).padding.bottom + 24,
                ),
                itemCount: list.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (_, i) {
                  final m = list[i];
                  return Card(
                    child: InkWell(
                      onTap: () => _openMangelForm(mangel: m),
                      borderRadius: BorderRadius.circular(12),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 14,
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Row(
                                children: [
                                  Text(
                                    m.titel,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w600,
                                      fontSize: 14,
                                      color: Colors.black87,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  const SizedBox(width: 20),
                                  Expanded(
                                    child: Text(
                                      m.beschreibung != null &&
                                              m.beschreibung!.trim().isNotEmpty
                                          ? _firstLine(m.beschreibung!)
                                          : '',
                                      style: TextStyle(
                                        fontSize: 14,
                                        color: Colors.grey[700],
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                      maxLines: 1,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Padding(
                              padding: const EdgeInsets.only(left: 12, right: 8),
                              child: Text(
                                [
                                  if (m.createdAt != null) _formatDate(m.createdAt!),
                                  if ((m.createdByName ?? '').trim().isNotEmpty)
                                    _erstellerNachname(m.createdByName!),
                                ].join(' · '),
                                style: TextStyle(
                                  fontSize: 13,
                                  color: Colors.grey[600],
                                ),
                              ),
                            ),
                            IconButton(
                              icon: Icon(Icons.delete_outline, color: Colors.red[700]),
                              tooltip: 'Als behoben löschen',
                              onPressed: () => _confirmDelete(m),
                            ),
                            const Icon(Icons.chevron_right, color: AppTheme.primary),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildHinweis({
    required IconData icon,
    required String title,
    required String text,
    String? actionLabel,
    VoidCallback? onAction,
  }) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 64, color: Colors.grey[400]),
            const SizedBox(height: 16),
            Text(
              title,
              style: Theme.of(context).textTheme.titleLarge,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            Text(
              text,
              style: TextStyle(color: Colors.grey[600], fontSize: 15),
              textAlign: TextAlign.center,
            ),
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: onAction,
                icon: const Icon(Icons.schedule, size: 20),
                label: Text(actionLabel),
                style: FilledButton.styleFrom(
                  backgroundColor: AppTheme.primary,
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

String _formatDate(DateTime d) {
  final day = d.day.toString().padLeft(2, '0');
  final mon = d.month.toString().padLeft(2, '0');
  return '$day.$mon.${d.year}';
}

/// Erste Zeile bzw. erster Teil des Inhalts (bis Zeilenumbruch oder max. 120 Zeichen)
String _firstLine(String text) {
  final trimmed = text.trim();
  if (trimmed.isEmpty) return trimmed;
  final firstLine = trimmed.split('\n').first.trim();
  return firstLine.length > 120 ? '${firstLine.substring(0, 120)}…' : firstLine;
}

/// Nur Nachname aus createdByName (falls "Nachname, Vorname" gespeichert)
String _erstellerNachname(String s) {
  final t = s.trim();
  if (t.isEmpty) return t;
  return t.contains(',') ? t.split(',').first.trim() : t;
}
