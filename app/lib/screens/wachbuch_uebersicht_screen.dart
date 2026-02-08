import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../theme/app_theme.dart';
import '../services/wachbuch_service.dart';

/// Wachbuch Übersicht – Monat/Jahr auswählen, Tage mit Einträgen anzeigen
class WachbuchUebersichtScreen extends StatefulWidget {
  final String companyId;
  final VoidCallback onBack;
  final void Function(String dayId)? onSelectDay;

  const WachbuchUebersichtScreen({
    required this.companyId,
    required this.onBack,
    this.onSelectDay,
  });

  @override
  State<WachbuchUebersichtScreen> createState() => _WachbuchUebersichtScreenState();
}

class _WachbuchUebersichtScreenState extends State<WachbuchUebersichtScreen> {
  final _service = WachbuchService();
  final _db = FirebaseFirestore.instance;

  int _month = DateTime.now().month;
  int _year = DateTime.now().year;
  List<_DayInfo> _days = [];
  bool _loading = false;

  static const _monthNames = [
    'Januar', 'Februar', 'März', 'April', 'Mai', 'Juni',
    'Juli', 'August', 'September', 'Oktober', 'November', 'Dezember'
  ];

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final tageRef = _db.collection('kunden').doc(widget.companyId).collection('wachbuchTage');
      final snap = await tageRef.get();
      final daysInMonth = DateTime(_year, _month + 1, 0).day;
      final monthDays = <_DayInfo>[];

      for (var day = 1; day <= daysInMonth; day++) {
        final dayId = '${day.toString().padLeft(2, '0')}.${_month.toString().padLeft(2, '0')}.$_year';
        final dayDoc = snap.docs.where((d) => d.id == dayId).firstOrNull;
        if (dayDoc == null) continue;
        final eintraegeSnap = await dayDoc.reference.collection('eintraege').get();
        final hasEintraege = eintraegeSnap.docs.isNotEmpty;
        if (hasEintraege) {
          monthDays.add(_DayInfo(
            dayId: dayId,
            day: day,
            month: _month,
            year: _year,
          ));
        }
      }

      if (mounted) {
        setState(() {
          _days = monthDays;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _days = [];
          _loading = false;
        });
      }
    }
  }

  String _formatDate(int day, int month, int year) {
    return '${day.toString().padLeft(2, '0')}. ${_monthNames[month - 1]} $year';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppTheme.buildModuleAppBar(
        title: 'Wachbuch Übersicht',
        onBack: widget.onBack,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Monat und Jahr auswählen', style: TextStyle(fontWeight: FontWeight.w600)),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: DropdownButtonFormField<int>(
                            value: _month,
                            decoration: const InputDecoration(labelText: 'Monat'),
                            items: List.generate(12, (i) => DropdownMenuItem(value: i + 1, child: Text(_monthNames[i]))),
                            onChanged: (v) => setState(() => _month = v ?? _month),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: TextFormField(
                            initialValue: _year.toString(),
                            decoration: const InputDecoration(labelText: 'Jahr'),
                            keyboardType: TextInputType.number,
                            onChanged: (v) => setState(() => _year = int.tryParse(v) ?? _year),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: _loading ? null : _load,
                        child: _loading ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('Laden'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),
            if (_days.isEmpty && !_loading)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: Center(
                    child: Text(
                      'Keine Wachbuch-Einträge für ${_monthNames[_month - 1]} $_year',
                      style: TextStyle(color: AppTheme.textMuted),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
              )
            else if (_days.isNotEmpty)
              ..._days.map((d) => Card(
                    margin: const EdgeInsets.only(bottom: 8),
                    child: ListTile(
                      leading: const Icon(Icons.book_outlined),
                      title: Text(_formatDate(d.day, d.month, d.year)),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () {
                        widget.onSelectDay?.call(d.dayId);
                      },
                    ),
                  )),
          ],
        ),
      ),
    );
  }
}

class _DayInfo {
  final String dayId;
  final int day;
  final int month;
  final int year;

  _DayInfo({required this.dayId, required this.day, required this.month, required this.year});
}
