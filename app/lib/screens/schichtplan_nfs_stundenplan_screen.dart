import 'package:flutter/material.dart';
import '../utils/schichtplan_nfs_bereitschaftstyp_utils.dart';
import '../theme/app_theme.dart';
import '../services/schichtanmeldung_service.dart';
import '../services/schichtplan_nfs_service.dart';
import 'schichtplan_nfs_einstellungen_screen.dart';
import 'schichtplan_nfs_schichten_screen.dart';

bool _canSchichtenHinzufuegen(String? role) {
  if (role == null || role.isEmpty) return false;
  final r = role.trim().toLowerCase();
  return r == 'superadmin' || r == 'admin' || r == 'koordinator';
}

/// Monatsübersicht als Kalender-Grid
class SchichtplanNfsMonatsuebersichtBody extends StatefulWidget {
  final String companyId;
  final String? userRole;
  final void Function(void Function() refresh)? onRegisterRefresh;

  const SchichtplanNfsMonatsuebersichtBody({
    super.key,
    required this.companyId,
    this.userRole,
    this.onRegisterRefresh,
  });

  @override
  State<SchichtplanNfsMonatsuebersichtBody> createState() =>
      _SchichtplanNfsMonatsuebersichtBodyState();
}

class _SchichtplanNfsMonatsuebersichtBodyState
    extends State<SchichtplanNfsMonatsuebersichtBody> {
  final _service = SchichtplanNfsService();
  int _month = DateTime.now().month;
  int _year = DateTime.now().year;
  Map<String, String> _tageStatus = {};
  bool _loading = true;
  String? _error;

  static const _monthNames = [
    'Januar', 'Februar', 'März', 'April', 'Mai', 'Juni',
    'Juli', 'August', 'September', 'Oktober', 'November', 'Dezember'
  ];
  static const _wochentage = ['Mo', 'Di', 'Mi', 'Do', 'Fr', 'Sa', 'So'];

  String _dayId(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.${d.year}';

  @override
  void initState() {
    super.initState();
    widget.onRegisterRefresh?.call(_load);
    _load();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final status =
          await _service.loadTageStatusForMonth(widget.companyId, _month, _year);
      if (mounted) {
        setState(() {
          _tageStatus = status;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() { _error = e.toString(); _loading = false; });
      }
    }
  }

  void _navMonth(int delta) {
    var m = _month + delta;
    var y = _year;
    while (m > 12) { m -= 12; y++; }
    while (m < 1) { m += 12; y--; }
    setState(() { _month = m; _year = y; });
    _load();
  }

  void _openSchichten(DateTime date) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => SchichtplanNfsSchichtenScreen(
          companyId: widget.companyId,
          selectedDate: date,
          userRole: widget.userRole,
          onBack: () => Navigator.pop(context),
        ),
      ),
    ).then((_) {
      if (mounted) _load();
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator(color: AppTheme.primary));
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

    final firstOfMonth = DateTime(_year, _month, 1);
    final daysInMonth = DateTime(_year, _month + 1, 0).day;
    var startWeekday = firstOfMonth.weekday - 1;
    if (startWeekday < 0) startWeekday = 0;
    final leadingEmpty = startWeekday;
    final totalCells = leadingEmpty + daysInMonth;
    final rows = (totalCells / 7).ceil();

    return RefreshIndicator(
      onRefresh: _load,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.all(Responsive.horizontalPadding(context)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(vertical: 12),
              color: Colors.white,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  IconButton(
                    icon: const Icon(Icons.chevron_left),
                    onPressed: () => _navMonth(-1),
                  ),
                  Text(
                    '${_monthNames[_month - 1]} $_year',
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 18,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.chevron_right),
                    onPressed: () => _navMonth(1),
                  ),
                ],
              ),
            ),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  children: [
                    Row(
                      children: _wochentage
                          .map((w) => Expanded(
                                child: Center(
                                  child: Text(
                                    w,
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                      color: AppTheme.textMuted,
                                    ),
                                  ),
                                ),
                              ))
                          .toList(),
                    ),
                    for (var row = 0; row < rows; row++)
                      Row(
                        children: List.generate(7, (col) {
                          final idx = row * 7 + col;
                          if (idx < leadingEmpty) {
                            return const Expanded(child: SizedBox(height: 44));
                          }
                          final day = idx - leadingEmpty + 1;
                          if (day > daysInMonth) {
                            return const Expanded(child: SizedBox(height: 44));
                          }
                          final d = DateTime(_year, _month, day);
                          final dayId = _dayId(d);
                          final status = _tageStatus[dayId] ?? 'neutral';
                          final isToday = DateTime.now().year == _year &&
                              DateTime.now().month == _month &&
                              DateTime.now().day == day;
                          Color? bgColor;
                          if (status == 'red') {
                            bgColor = Colors.red.shade100;
                          } else if (status == 'green') {
                            bgColor = Colors.green.shade100;
                          } else if (isToday) {
                            bgColor = AppTheme.primary.withOpacity(0.08);
                          }
                          return Expanded(
                            child: Padding(
                              padding: const EdgeInsets.all(2),
                              child: InkWell(
                                onTap: () => _openSchichten(d),
                                borderRadius: BorderRadius.circular(8),
                                child: Container(
                                  height: 44,
                                  decoration: BoxDecoration(
                                    color: bgColor,
                                    borderRadius: BorderRadius.circular(8),
                                    border: isToday
                                        ? Border.all(
                                            color: AppTheme.primary,
                                            width: 2,
                                          )
                                        : null,
                                  ),
                                  child: Center(
                                    child: Text(
                                      '$day',
                                      style: TextStyle(
                                        fontSize: 14,
                                        fontWeight: isToday
                                            ? FontWeight.w700
                                            : FontWeight.w500,
                                        color: status == 'red'
                                            ? Colors.red.shade800
                                            : (status == 'green'
                                                ? Colors.green.shade800
                                                : null),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          );
                        }),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Body-Widget für den Bereitschaftsplan (Mitglieder-Karten mit Zeitblöcken).
class SchichtplanNfsBereitschaftsplanBody extends StatefulWidget {
  final String companyId;
  final String? userRole;
  final void Function(void Function() refresh)? onRegisterRefresh;

  const SchichtplanNfsBereitschaftsplanBody({
    super.key,
    required this.companyId,
    this.userRole,
    this.onRegisterRefresh,
  });

  @override
  State<SchichtplanNfsBereitschaftsplanBody> createState() =>
      _SchichtplanNfsBereitschaftsplanBodyState();
}

class _SchichtplanNfsBereitschaftsplanBodyState
    extends State<SchichtplanNfsBereitschaftsplanBody> {
  final _service = SchichtplanNfsService();

  List<BereitschaftsTyp> _typen = [];
  List<NfsMitarbeiterRow> _mitarbeiter = [];
  /// dayId -> (mitarbeiterId_stunde -> typId)
  Map<String, Map<String, String>> _eintraegePerDay = {};
  DateTime _weekStart = DateTime.now();
  bool _loading = true;
  String? _error;

  static const _wochentage = [
    'Mo', 'Di', 'Mi', 'Do', 'Fr', 'Sa', 'So'
  ];

  String _dayId(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.${d.year}';

  DateTime _mondayOf(DateTime d) {
    final wd = d.weekday - 1; // Mon=0, Sun=6
    return DateTime(d.year, d.month, d.day - wd);
  }

  DateTime _dayAt(int index) => _weekStart.add(Duration(days: index));

  @override
  void initState() {
    super.initState();
    _weekStart = _mondayOf(DateTime.now());
    widget.onRegisterRefresh?.call(_load);
    _load();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final alleTypen = await _service.loadBereitschaftsTypen(widget.companyId);
      final typen = SchichtplanNfsBereitschaftstypUtils.filterAndSortS1S2B(
        alleTypen,
      );
      final ma = await _service.loadMitarbeiterMitStandort(widget.companyId);
      final perDay = <String, Map<String, String>>{};
      for (var i = 0; i < 7; i++) {
        final d = _dayAt(i);
        final e = await _service.loadStundenplanEintraege(
          widget.companyId,
          _dayId(d),
        );
        perDay[_dayId(d)] = e;
      }
      if (mounted) {
        setState(() {
          _typen = typen;
          _mitarbeiter = ma;
          _eintraegePerDay = perDay;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() { _error = e.toString(); _loading = false; });
      }
    }
  }

  Future<void> _loadEintraegeForDay(String dayId) async {
    final e = await _service.loadStundenplanEintraege(widget.companyId, dayId);
    if (mounted) setState(() => _eintraegePerDay[dayId] = e);
  }

  String? _getTyp(String dayId, String mitarbeiterId, int stunde) =>
      _eintraegePerDay[dayId]?['${mitarbeiterId}_$stunde'];

  Color _colorForTyp(String id) =>
      SchichtplanNfsBereitschaftstypUtils.colorForTypId(id, _typen);

  String _mitarbeiterName(String id) {
    final row = _mitarbeiter.where((r) => r.mitarbeiter.id == id).firstOrNull;
    return row?.mitarbeiter.displayName ?? id;
  }

  void _navWeek(int delta) {
    setState(() => _weekStart = _weekStart.add(Duration(days: 7 * delta)));
    _load();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator(color: AppTheme.primary));
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

    return RefreshIndicator(
      onRefresh: _load,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildLegend(),
          _buildWeekNav(),
          Expanded(
            child: _buildWeekContent(),
          ),
        ],
      ),
    );
  }

  /// Zeitblöcke für ein Mitglied an einem Tag
  List<({int start, int end, String typId})> _getBlocksForMember(
      String dayId, String mitarbeiterId) {
    final blocks = <({int start, int end, String typId})>[];
    for (var h = 0; h < 24; h++) {
      final t = _getTyp(dayId, mitarbeiterId, h);
      if (t != null) {
        if (blocks.isNotEmpty && blocks.last.end == h && blocks.last.typId == t) {
          blocks[blocks.length - 1] = (start: blocks.last.start, end: h + 1, typId: t);
        } else {
          blocks.add((start: h, end: h + 1, typId: t));
        }
      }
    }
    return blocks;
  }

  List<NfsMitarbeiterRow> _mitarbeiterMitEintraegen(String dayId) {
    final eintraege = _eintraegePerDay[dayId] ?? {};
    final ids = <String>{};
    for (final k in eintraege.keys) {
      if (eintraege[k]?.trim().isNotEmpty == true) {
        final parts = k.split('_');
        if (parts.length == 2) ids.add(parts[0]);
      }
    }
    return _mitarbeiter.where((r) => ids.contains(r.mitarbeiter.id)).toList();
  }

  /// 'red' = offene Schichten, 'green' = alle 24h mit S1 belegt, 'neutral' = sonst
  String _dayStatus(String dayId) {
    final e = _eintraegePerDay[dayId] ?? {};
    final s1Typ = _typen.where((t) => t.name.trim().toLowerCase() == 's1').firstOrNull;
    final s1TypId = s1Typ?.id;
    final belegt = <int>{};
    final typenProStunde = <int, Set<String>>{};
    for (var h = 0; h < 24; h++) typenProStunde[h] = {};
    for (final entry in e.entries) {
      if (entry.value.trim().isEmpty) continue;
      final parts = entry.key.split('_');
      if (parts.length != 2) continue;
      final h = int.tryParse(parts[1]);
      if (h == null || h < 0 || h >= 24) continue;
      belegt.add(h);
      typenProStunde[h]!.add(entry.value.trim());
    }
    final freieStunden = [for (var h = 0; h < 24; h++) if (!belegt.contains(h)) h];
    if (freieStunden.isNotEmpty) return 'red';
    if (s1TypId != null &&
        typenProStunde.values.every((t) => t.length == 1 && t.contains(s1TypId))) {
      return 'green';
    }
    return 'neutral';
  }

  Widget _buildWeekContent() {
    return ListView(
      padding: EdgeInsets.symmetric(
        horizontal: Responsive.horizontalPadding(context),
        vertical: 12,
      ),
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        for (var i = 0; i < 7; i++) _buildDaySection(i),
      ],
    );
  }

  Widget _buildDaySection(int dayIndex) {
    final d = _dayAt(dayIndex);
    final dayId = _dayId(d);
    final wd = _wochentage[dayIndex];
    final datum =
        '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}';
    final mitarbeiter = _mitarbeiterMitEintraegen(dayId);
    final status = _dayStatus(dayId);

    Color? cardColor;
    if (status == 'red') cardColor = Colors.red.shade100;
    if (status == 'green') cardColor = Colors.green.shade100;

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      color: cardColor,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            onTap: () => _openSchichten(d),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  Text(
                    '$wd $datum.',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 16,
                      color: status == 'red'
                          ? Colors.red.shade800
                          : (status == 'green'
                              ? Colors.green.shade800
                              : null),
                    ),
                  ),
                  const Spacer(),
                  Icon(Icons.list_alt, size: 18, color: AppTheme.primary),
                ],
              ),
            ),
          ),
          if (mitarbeiter.isEmpty)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Text(
                    'Keine Einträge',
                    style: TextStyle(fontSize: 14, color: AppTheme.textMuted),
                  ),
                  const Spacer(),
                  TextButton.icon(
                    onPressed: () => _openSchichten(d),
                    icon: Icon(Icons.add, size: 18, color: AppTheme.primary),
                    label: Text('Schichten', style: TextStyle(color: AppTheme.primary)),
                  ),
                ],
              ),
            )
          else
            ...mitarbeiter.expand((row) => [
                  Divider(height: 1),
                  _buildMemberCard(dayId, d, row),
                ]).skip(1),
        ],
      ),
    );
  }

  Widget _buildMemberCard(
      String dayId, DateTime date, NfsMitarbeiterRow row) {
    final m = row.mitarbeiter;
    final blocks = _getBlocksForMember(dayId, m.id);

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
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
                    if (row.standortName != null)
                      Text(
                        row.standortName!,
                        style: TextStyle(fontSize: 12, color: AppTheme.textMuted),
                      ),
                  ],
                ),
              ),
              if (_canSchichtenHinzufuegen(widget.userRole))
                IconButton(
                  icon: const Icon(Icons.add_circle_outline, size: 22),
                  tooltip: 'Bereitschaft eintragen',
                  onPressed: () => _showAddForMember(dayId, m.id),
                ),
            ],
          ),
          if (blocks.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                'Keine Bereitschaft eingetragen',
                style: TextStyle(fontSize: 13, color: AppTheme.textMuted),
              ),
            )
          else
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: blocks.map((b) {
                final typName = _typen.where((t) => t.id == b.typId).firstOrNull?.name ?? b.typId;
                final color = _colorForTyp(b.typId);
                final label = b.start + 1 == b.end
                    ? '${b.start.toString().padLeft(2, '0')}:00 $typName'
                    : '${b.start.toString().padLeft(2, '0')}–${b.end.toString().padLeft(2, '0')} Uhr $typName';
                return InkWell(
                  onTap: () => _showEditBlock(dayId, m.id, b.start, b.end, b.typId),
                    borderRadius: BorderRadius.circular(6),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: color.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: color.withOpacity(0.5)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            label,
                            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: color),
                          ),
                          const SizedBox(width: 4),
                          Icon(Icons.edit, size: 14, color: color),
                        ],
                      ),
                    ),
                  );
                }).toList(),
              ),
        ],
      ),
    );
  }

  Future<void> _showEditBlock(
      String dayId, String mitarbeiterId, int start, int end, String currentTypId) async {
    final choice = await showGeneralDialog<String>(
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
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    '${start.toString().padLeft(2, '0')}–${end.toString().padLeft(2, '0')} Uhr – ${_mitarbeiterName(mitarbeiterId)}',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
                ListTile(
                  leading: const Icon(Icons.remove_circle_outline),
                  title: const Text('Gesamten Zeitraum entfernen'),
                  onTap: () => Navigator.pop(ctx, '__remove__'),
                ),
                ..._typen.map((t) => ListTile(
                      leading: Icon(Icons.schedule, color: _colorForTyp(t.id)),
                      title: Text(t.name),
                      onTap: () => Navigator.pop(ctx, t.id),
                    )),
                const SizedBox(height: 16),
              ],
            ),
          ),
        ),
      ),
    );
    if (choice != null && mounted) {
      if (choice == '__remove__') {
        for (var h = start; h < end; h++) {
          await _service.saveStundenplanEintrag(
              widget.companyId, dayId, mitarbeiterId, h, '');
        }
      } else {
        for (var h = start; h < end; h++) {
          await _service.saveStundenplanEintrag(
              widget.companyId, dayId, mitarbeiterId, h, choice);
        }
      }
      await _loadEintraegeForDay(dayId);
    }
  }

  Future<void> _showAddForMember(String dayId, String mitarbeiterId) async {
    final result = await showGeneralDialog<({int from, int to, String typId})>(
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
              child: _AddBereitschaftSheet(
                mitarbeiterName: _mitarbeiterName(mitarbeiterId),
                typen: _typen,
                colorForTyp: _colorForTyp,
              ),
            ),
          ),
        ),
      ),
    );
    if (result != null && mounted) {
      for (var h = result.from; h < result.to; h++) {
        await _service.saveStundenplanEintrag(
            widget.companyId, dayId, mitarbeiterId, h, result.typId);
      }
      await _loadEintraegeForDay(dayId);
    }
  }

  Widget _buildLegend() {
    if (_typen.isEmpty) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: Colors.white,
      child: Wrap(
        spacing: 16,
        runSpacing: 4,
        children: _typen.map((t) => Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 12, height: 12,
                  decoration: BoxDecoration(color: _colorForTyp(t.id), borderRadius: BorderRadius.circular(2)),
                ),
                const SizedBox(width: 6),
                Text('${t.name}${t.beschreibung != null ? ': ${t.beschreibung}' : ''}', style: const TextStyle(fontSize: 12)),
              ],
            )).toList(),
      ),
    );
  }

  void _openSchichten(DateTime date) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => SchichtplanNfsSchichtenScreen(
          companyId: widget.companyId,
          selectedDate: date,
          userRole: widget.userRole,
          onBack: () => Navigator.pop(context),
        ),
      ),
    ).then((_) {
      if (mounted) _load();
    });
  }

  Widget _buildWeekNav() {
    final end = _dayAt(6);
    final von =
        '${_weekStart.day.toString().padLeft(2, '0')}.${_weekStart.month.toString().padLeft(2, '0')}.${_weekStart.year}';
    final bis =
        '${end.day.toString().padLeft(2, '0')}.${end.month.toString().padLeft(2, '0')}.${end.year}';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      color: Colors.white,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          IconButton(
            icon: const Icon(Icons.chevron_left),
            onPressed: () => _navWeek(-1),
          ),
          Text(
            'Woche $von – $bis',
            style: const TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: 16,
            ),
          ),
          IconButton(
            icon: const Icon(Icons.chevron_right),
            onPressed: () => _navWeek(1),
          ),
        ],
      ),
    );
  }

}

/// Sheet zum Eintragen eines Zeitraums (von–bis + Typ)
class _AddBereitschaftSheet extends StatefulWidget {
  final String mitarbeiterName;
  final List<BereitschaftsTyp> typen;
  final Color Function(String id) colorForTyp;

  const _AddBereitschaftSheet({
    required this.mitarbeiterName,
    required this.typen,
    required this.colorForTyp,
  });

  @override
  State<_AddBereitschaftSheet> createState() => _AddBereitschaftSheetState();
}

class _AddBereitschaftSheetState extends State<_AddBereitschaftSheet> {
  int _from = 8;
  int _to = 12;
  String? _typId;

  @override
  void initState() {
    super.initState();
    if (widget.typen.isNotEmpty) _typId = widget.typen.first.id;
  }

  @override
  Widget build(BuildContext context) {
    if (widget.typen.isNotEmpty && _typId == null) _typId = widget.typen.first.id;
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
              'Bereitschaft eintragen – ${widget.mitarbeiterName}',
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<int>(
                    value: _from,
                    decoration: const InputDecoration(labelText: 'Von', border: OutlineInputBorder()),
                    items: List.generate(24, (i) => DropdownMenuItem(value: i, child: Text('${i.toString().padLeft(2, '0')}:00'))),
                    onChanged: (v) {
                      if (v != null) {
                        setState(() {
                          _from = v;
                          if (_to <= _from) _to = _from + 1;
                        });
                      }
                    },
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: DropdownButtonFormField<int>(
                    value: _to > _from ? _to : (_from < 23 ? _from + 1 : 24),
                    decoration: const InputDecoration(labelText: 'Bis', border: OutlineInputBorder()),
                    items: [
                      for (var v = _from + 1; v <= 24; v++)
                        DropdownMenuItem(
                          value: v,
                          child: Text(v == 24 ? '24:00' : '${v.toString().padLeft(2, '0')}:00'),
                        ),
                    ],
                    onChanged: (v) => setState(() => _to = v ?? _from + 1),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (widget.typen.isNotEmpty)
              DropdownButtonFormField<String>(
                value: _typId ?? widget.typen.first.id,
                decoration: const InputDecoration(labelText: 'Bereitschafts-Typ', border: OutlineInputBorder()),
                items: widget.typen.map((t) => DropdownMenuItem(
                      value: t.id,
                      child: Row(
                        children: [
                          Container(
                            width: 12,
                            height: 12,
                            decoration: BoxDecoration(color: widget.colorForTyp(t.id), borderRadius: BorderRadius.circular(2)),
                          ),
                          const SizedBox(width: 8),
                          Text(t.name),
                        ],
                      ),
                    )).toList(),
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
                  onPressed: (_typId != null && _typId!.isNotEmpty && _to > _from)
                      ? () => Navigator.pop(context, (from: _from, to: _to, typId: _typId!))
                      : null,
                  child: const Text('Eintragen'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Eigenständiger Screen für Bereitschaftsplan NFS (falls direkt angesteuert).
class SchichtplanNfsStundenplanScreen extends StatelessWidget {
  final String companyId;
  final VoidCallback onBack;

  const SchichtplanNfsStundenplanScreen({
    super.key,
    required this.companyId,
    required this.onBack,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.surfaceBg,
      appBar: AppTheme.buildModuleAppBar(
        title: 'Schichtplan',
        onBack: onBack,
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            tooltip: 'Einstellungen',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => SchichtplanNfsEinstellungenScreen(
                  companyId: companyId,
                  onBack: () => Navigator.pop(context),
                ),
              ),
            ),
          ),
        ],
      ),
      body: SchichtplanNfsBereitschaftsplanBody(companyId: companyId),
    );
  }
}
