import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../services/schichtanmeldung_service.dart';
import '../services/auth_data_service.dart';
import '../services/auth_service.dart';

/// Erlaubte Rollen für die Schichtübersicht
const _erlaubteRollen = [
  'superadmin',
  'admin',
  'wachleitung',
  'rettungsdienstleitung',
  'geschaeftsfuehrung',
  'leiterrettungsdienst',
  'leiterssd',
  'koordinator',
];

/// Rollen die Anmeldungen löschen dürfen
const _loeschenRollen = [
  'superadmin',
  'admin',
  'rettungsdienstleitung',
  'geschaeftsfuehrung',
  'leiterrettungsdienst',
  'leiterssd',
];

/// Schichtübersicht – wer hat sich wann angemeldet (für Führungskräfte)
class SchichtuebersichtScreen extends StatefulWidget {
  final String companyId;
  final VoidCallback onBack;

  const SchichtuebersichtScreen({
    required this.companyId,
    required this.onBack,
  });

  @override
  State<SchichtuebersichtScreen> createState() => _SchichtuebersichtScreenState();
}

class _SchichtuebersichtScreenState extends State<SchichtuebersichtScreen> {
  final _service = SchichtanmeldungService();
  final _authService = AuthService();
  final _authDataService = AuthDataService();

  List<SchichtanmeldungEintrag> _anmeldungen = [];
  List<Standort> _standorte = [];
  List<SchichtTyp> _schichten = [];
  Map<String, SchichtplanMitarbeiter> _mitarbeiterMap = {};

  DateTime _selectedDate = DateTime.now();
  bool _loading = true;
  String? _error;
  bool _zugriffVerweigert = false;
  String _userRole = '';

  String get _dayId =>
      '${_selectedDate.day.toString().padLeft(2, '0')}.${_selectedDate.month.toString().padLeft(2, '0')}.${_selectedDate.year}';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
      _zugriffVerweigert = false;
    });

    final user = _authService.currentUser;
    if (user == null) {
      setState(() {
        _loading = false;
        _error = 'Nicht angemeldet';
      });
      return;
    }

    final authData = await _authDataService.getAuthData(
      user.uid,
      user.email ?? '',
      widget.companyId,
    );
    final role = (authData.role ?? 'user').toLowerCase().trim();
    if (!_erlaubteRollen.contains(role)) {
      setState(() {
        _loading = false;
        _zugriffVerweigert = true;
      });
      return;
    }

    try {
      final standorte = await _service.loadStandorte(widget.companyId);
      final schichten = await _service.loadSchichten(widget.companyId);
      final anmeldungen = await _service.loadSchichtanmeldungenForDateRange(
        widget.companyId,
        _selectedDate,
        _selectedDate,
      );
      final mitarbeiter = await _service.loadSchichtplanMitarbeiter(widget.companyId);
      final mitarbeiterMap = {for (final m in mitarbeiter) m.id: m};

      if (mounted) {
        setState(() {
          _standorte = standorte;
          _schichten = schichten;
          _anmeldungen = anmeldungen;
          _mitarbeiterMap = mitarbeiterMap;
          _userRole = role;
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

  String _standortName(String? id) {
    if (id == null || id.isEmpty) return '–';
    final s = _standorte.where((x) => x.id == id || x.name == id).firstOrNull;
    return s?.name ?? id;
  }

  String _schichtName(String? id) {
    if (id == null || id.isEmpty) return '–';
    final s = _schichten.where((x) => x.id == id).firstOrNull;
    return s?.name ?? id;
  }

  String _mitarbeiterName(String? id) {
    if (id == null || id.isEmpty) return '–';
    final m = _mitarbeiterMap[id];
    return m?.displayName ?? id;
  }

  /// Gruppierung: datum|wacheId|schichtId -> Liste Anmeldungen (gleiche Schicht am gleichen Tag zusammen)
  Map<String, List<SchichtanmeldungEintrag>> get _gruppiert {
    final map = <String, List<SchichtanmeldungEintrag>>{};
    for (final a in _anmeldungen) {
      final key = '${a.datum}|${a.wacheId}|${a.schichtId}';
      map.putIfAbsent(key, () => []).add(a);
    }
    for (final list in map.values) {
      list.sort((a, b) {
        final na = _mitarbeiterName(a.mitarbeiterId);
        final nb = _mitarbeiterName(b.mitarbeiterId);
        return na.compareTo(nb);
      });
    }
    return map;
  }

  List<MapEntry<String, List<SchichtanmeldungEintrag>>> _gruppenFuerTag(String tag) {
    final entries = _gruppiert.entries.where((e) => e.key.startsWith('$tag|')).toList();
    entries.sort((a, b) {
      final wa = _standortName(a.value.first.wacheId);
      final wb = _standortName(b.value.first.wacheId);
      if (wa != wb) return wa.compareTo(wb);
      final sa = _schichtName(a.value.first.schichtId);
      final sb = _schichtName(b.value.first.schichtId);
      return sa.compareTo(sb);
    });
    return entries;
  }

  String _formatDatum(String dayId) {
    try {
      final p = dayId.split('.');
      if (p.length != 3) return dayId;
      final d = DateTime(int.parse(p[2]), int.parse(p[1]), int.parse(p[0]));
      const wochentage = ['Mo', 'Di', 'Mi', 'Do', 'Fr', 'Sa', 'So'];
      final w = wochentage[(d.weekday + 6) % 7];
      return '$w $dayId';
    } catch (_) {
      return dayId;
    }
  }

  void _goPrevDay() {
    setState(() => _selectedDate = _selectedDate.subtract(const Duration(days: 1)));
    _load();
  }

  void _goNextDay() {
    setState(() => _selectedDate = _selectedDate.add(const Duration(days: 1)));
    _load();
  }

  Future<void> _pickDate() async {
    final d = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (d != null && mounted) {
      setState(() => _selectedDate = DateTime(d.year, d.month, d.day));
      _load();
    }
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
        title: Text('Schichtübersicht', style: TextStyle(color: AppTheme.primary, fontWeight: FontWeight.w600)),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _zugriffVerweigert
              ? _buildZugriffVerweigert()
              : _error != null
                  ? _buildError()
                  : _buildContent(),
    );
  }

  Widget _buildZugriffVerweigert() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.lock_outline, size: 64, color: Colors.grey[400]),
            const SizedBox(height: 16),
            Text(
              'Kein Zugriff',
              style: Theme.of(context).textTheme.titleLarge,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            Text(
              'Die Schichtübersicht steht nur Superadmin, Admin, Wachleitung, '
              'Rettungsdienstleitung und Geschäftsführung zur Verfügung.',
              style: TextStyle(color: Colors.grey[600]),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildError() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, size: 64, color: Colors.red[300]),
            const SizedBox(height: 16),
            Text(_error!, textAlign: TextAlign.center, style: TextStyle(color: Colors.red[700])),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _load,
              style: FilledButton.styleFrom(backgroundColor: AppTheme.primary),
              child: const Text('Erneut laden'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildContent() {
    final gruppen = _gruppenFuerTag(_dayId);

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          _buildDaySelector(),
          const SizedBox(height: 20),

          if (gruppen.isEmpty)
            Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.event_busy, size: 48, color: Colors.grey[400]),
                    const SizedBox(height: 12),
                    Text(
                      'Keine Schichtanmeldungen am $_dayId',
                      style: TextStyle(color: Colors.grey[600]),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            )
          else
            _buildTagCard(_dayId),
        ],
      ),
    );
  }

  Widget _buildDaySelector() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.border),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          IconButton(
            icon: const Icon(Icons.chevron_left),
            onPressed: _goPrevDay,
            color: AppTheme.primary,
            iconSize: 28,
          ),
          Expanded(
            child: InkWell(
              onTap: _pickDate,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.calendar_today, size: 20, color: AppTheme.primary),
                    const SizedBox(width: 8),
                    Text(
                      _formatDatum(_dayId),
                      style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.chevron_right),
            onPressed: _goNextDay,
            color: AppTheme.primary,
            iconSize: 28,
          ),
        ],
      ),
    );
  }

  Widget _buildTagCard(String tag) {
    final gruppen = _gruppenFuerTag(tag);

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: gruppen.map((e) => _buildSchichtGruppe(e.value)).toList(),
        ),
      ),
    );
  }

  bool get _kannLoeschen => _loeschenRollen.contains(_userRole);

  Future<void> _loeschenAnmeldung(SchichtanmeldungEintrag e) async {
    final bestaetigt = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Anmeldung löschen'),
        content: Text(
          'Anmeldung von ${_mitarbeiterName(e.mitarbeiterId)} wirklich löschen?',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Abbrechen')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Löschen'),
          ),
        ],
      ),
    );
    if (bestaetigt != true || !mounted) return;
    try {
      await _service.deleteSchichtanmeldung(widget.companyId, e.id);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Anmeldung gelöscht.')));
        _load();
      }
    } catch (err) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Fehler: $err')));
      }
    }
  }

  Future<void> _loeschenGesamteSchicht(List<SchichtanmeldungEintrag> list) async {
    final first = list.first;
    final standort = _standortName(first.wacheId);
    final schicht = _schichtName(first.schichtId);
    final bestaetigt = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Gesamte Schicht löschen'),
        content: Text(
          'Alle Anmeldungen für $standort - $schicht wirklich löschen?',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Abbrechen')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Löschen'),
          ),
        ],
      ),
    );
    if (bestaetigt != true || !mounted) return;
    try {
      for (final e in list) {
        await _service.deleteSchichtanmeldung(widget.companyId, e.id);
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Schicht gelöscht.')));
        _load();
      }
    } catch (err) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Fehler: $err')));
      }
    }
  }

  void _zeigeSchichtPopup(BuildContext context, List<SchichtanmeldungEintrag> list) {
    if (!_kannLoeschen) return;
    final first = list.first;
    final standort = _standortName(first.wacheId);
    final schicht = _schichtName(first.schichtId);

    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Schließen',
      barrierColor: Colors.black54,
      anchorPoint: const Offset(0.5, 0),
      transitionBuilder: (ctx, a1, a2, child) {
        return SlideTransition(
          position: Tween(begin: const Offset(0, -1), end: Offset.zero).animate(a1),
          child: Align(
            alignment: Alignment.topCenter,
            child: child,
          ),
        );
      },
      pageBuilder: (ctx, a1, a2) {
        return Material(
          color: Colors.transparent,
          child: SafeArea(
            child: Container(
              margin: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(color: Colors.black.withOpacity(0.2), blurRadius: 12, offset: const Offset(0, 4)),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(
                      '$standort – $schicht',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.textPrimary,
                      ),
                    ),
                  ),
                  const Divider(height: 1),
                  ...list.map((a) => ListTile(
                        title: Text(
                          '${_mitarbeiterName(a.mitarbeiterId)} (${a.rolle == 'fahrer' ? 'Fahrer' : 'Beifahrer'})',
                        ),
                        trailing: IconButton(
                          icon: Icon(Icons.delete_outline, color: Colors.red[700]),
                          onPressed: () {
                            Navigator.pop(ctx);
                            _loeschenAnmeldung(a);
                          },
                        ),
                      )),
                  const Divider(height: 1),
                  ListTile(
                    leading: Icon(Icons.delete_forever, color: Colors.red[700]),
                    title: Text('Gesamte Schicht löschen', style: TextStyle(color: Colors.red[700], fontWeight: FontWeight.w600)),
                    onTap: () {
                      Navigator.pop(ctx);
                      _loeschenGesamteSchicht(list);
                    },
                  ),
                  const SizedBox(height: 8),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildSchichtGruppe(List<SchichtanmeldungEintrag> list) {
    if (list.isEmpty) return const SizedBox.shrink();
    final first = list.first;
    final standort = _standortName(first.wacheId);
    final schicht = _schichtName(first.schichtId);

    final fahrerNamen = list.where((a) => a.rolle == 'fahrer').map((a) => _mitarbeiterName(a.mitarbeiterId)).join(', ');
    final beifahrerNamen = list.where((a) => a.rolle != 'fahrer').map((a) => _mitarbeiterName(a.mitarbeiterId)).join(', ');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          standort,
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: AppTheme.textPrimary,
          ),
        ),
        const SizedBox(height: 8),
        InkWell(
          onTap: _kannLoeschen ? () => _zeigeSchichtPopup(context, list) : null,
          borderRadius: BorderRadius.circular(8),
          child: Container(
            margin: const EdgeInsets.only(bottom: 16),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppTheme.surfaceBg,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppTheme.border),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Text(
                  schicht,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.textPrimary,
                  ),
                ),
                const SizedBox(width: 48),
                Expanded(
                  child: Center(
                    child: RichText(
                      textAlign: TextAlign.center,
                      text: TextSpan(
                        style: TextStyle(fontSize: 15, color: AppTheme.textPrimary),
                        children: [
                          TextSpan(text: 'Fahrer: ', style: TextStyle(fontWeight: FontWeight.bold)),
                          TextSpan(text: fahrerNamen.isNotEmpty ? fahrerNamen : '–'),
                        ],
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: Center(
                    child: RichText(
                      textAlign: TextAlign.center,
                      text: TextSpan(
                        style: TextStyle(fontSize: 15, color: AppTheme.textPrimary),
                        children: [
                          TextSpan(text: 'Beifahrer: ', style: TextStyle(fontWeight: FontWeight.bold)),
                          TextSpan(text: beifahrerNamen.isNotEmpty ? beifahrerNamen : '–'),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
