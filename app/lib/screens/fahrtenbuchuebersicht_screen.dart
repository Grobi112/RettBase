import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../theme/app_theme.dart';
import '../models/fahrtenbuch_model.dart';
import '../services/fahrtenbuch_service.dart';
import 'fahrtenbuch_screen.dart';
import 'fahrtenbuch_druck_screen.dart';

/// Fahrtenbuchübersicht – Übersicht aller Fahrtenbücher und Einträge
class FahrtenbuchuebersichtScreen extends StatefulWidget {
  final String companyId;
  final VoidCallback onBack;

  const FahrtenbuchuebersichtScreen({
    required this.companyId,
    required this.onBack,
  });

  @override
  State<FahrtenbuchuebersichtScreen> createState() => _FahrtenbuchuebersichtScreenState();
}

class _FahrtenbuchuebersichtScreenState extends State<FahrtenbuchuebersichtScreen> {
  final _service = FahrtenbuchService();
  FahrtenbuchUebersichtItem? _selectedFahrzeug;
  String? _cleanupDoneForVehicle;
  DateTime? _filterVon;
  DateTime? _filterBis;
  String? _filterEinsatzart;
  String? _filterFahrer;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.surfaceBg,
      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: AppTheme.primary,
        elevation: 1,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            if (_selectedFahrzeug != null) {
              setState(() => _selectedFahrzeug = null);
            } else {
              widget.onBack();
            }
          },
        ),
        title: Text(
          _selectedFahrzeug?.displayLabel ?? 'Fahrtenbuchübersicht',
          style: TextStyle(color: AppTheme.primary, fontWeight: FontWeight.w600, fontSize: 18),
        ),
      ),
      body: _selectedFahrzeug == null ? _buildUebersicht() : _buildFahrzeugEintraege(),
    );
  }

  Widget _buildUebersicht() {
    return FutureBuilder<List<FahrtenbuchUebersichtItem>>(
      future: _service.loadFahrtenbuecherAusFlotte(widget.companyId),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator(color: AppTheme.primary));
        }
        final list = snap.data ?? [];
        if (list.isEmpty) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.directions_car_outlined, size: 64, color: Colors.grey[400]),
                const SizedBox(height: 16),
                Text(
                  'Keine Fahrzeuge im Flottenmanagement vorhanden.',
                  style: TextStyle(color: Colors.grey[600]),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  'Legen Sie Fahrzeuge im Flottenmanagement an.',
                  style: TextStyle(color: Colors.grey[500], fontSize: 13),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          );
        }
        final isWide = MediaQuery.of(context).size.width >= 600;
        return RefreshIndicator(
          onRefresh: () async => setState(() {}),
          child: LayoutBuilder(
            builder: (_, constraints) {
              if (isWide && constraints.maxWidth > 700) {
                final crossCount = (constraints.maxWidth / 350).floor().clamp(1, 3);
                return GridView.builder(
                  padding: EdgeInsets.fromLTRB(16, 16, 16, MediaQuery.of(context).padding.bottom + 16),
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: crossCount,
                    childAspectRatio: 3.5,
                    crossAxisSpacing: 12,
                    mainAxisSpacing: 12,
                  ),
                  itemCount: list.length,
                  itemBuilder: (_, i) {
                    final item = list[i];
                    return Card(
                      child: ListTile(
                        dense: true,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                        leading: CircleAvatar(
                          radius: 20,
                          backgroundColor: AppTheme.primary.withOpacity(0.15),
                          child: Icon(Icons.directions_car, color: AppTheme.primary, size: 20),
                        ),
                        title: Text(item.displayLabel, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                        subtitle: Text(
                          (item.hasManuelleKmKorrektur == true) ? '${item.anzahl} Einträge · KM-Korrektur (Fahrt nicht eingetragen)' : '${item.anzahl} Einträge',
                          style: TextStyle(fontSize: 12, color: (item.hasManuelleKmKorrektur == true) ? Colors.orange[800] : null),
                        ),
                        trailing: const Icon(Icons.chevron_right, size: 22),
                        onTap: () => setState(() => _selectedFahrzeug = item),
                      ),
                    );
                  },
                );
              }
              return ListView.builder(
                padding: EdgeInsets.fromLTRB(16, 16, 16, MediaQuery.of(context).padding.bottom + 16),
                itemCount: list.length,
                itemBuilder: (_, i) {
                  final item = list[i];
                  return Card(
                    margin: const EdgeInsets.only(bottom: 8),
                    child: ListTile(
                      dense: true,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                      leading: CircleAvatar(
                        radius: 20,
                        backgroundColor: AppTheme.primary.withOpacity(0.15),
                        child: Icon(Icons.directions_car, color: AppTheme.primary, size: 20),
                      ),
                      title: Text(item.displayLabel, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                      subtitle: Text(
                        (item.hasManuelleKmKorrektur == true) ? '${item.anzahl} Einträge · KM-Korrektur (Fahrt nicht eingetragen)' : '${item.anzahl} Einträge',
                        style: TextStyle(fontSize: 12, color: (item.hasManuelleKmKorrektur == true) ? Colors.orange[800] : null),
                      ),
                      trailing: const Icon(Icons.chevron_right, size: 22),
                      onTap: () => setState(() => _selectedFahrzeug = item),
                    ),
                  );
                },
              );
            },
          ),
        );
      },
    );
  }

  List<FahrtenbuchEintrag> _filterEintraege(List<FahrtenbuchEintrag> list) {
    var result = list;
    if (_filterVon != null) {
      result = result.where((e) => e.datum != null && !e.datum!.isBefore(DateTime(_filterVon!.year, _filterVon!.month, _filterVon!.day))).toList();
    }
    if (_filterBis != null) {
      result = result.where((e) => e.datum != null && !e.datum!.isAfter(DateTime(_filterBis!.year, _filterBis!.month, _filterBis!.day, 23, 59, 59))).toList();
    }
    if (_filterEinsatzart != null && _filterEinsatzart!.isNotEmpty && _filterEinsatzart != 'Alle') {
      result = result.where((e) => (e.einsatzart ?? '').trim() == _filterEinsatzart).toList();
    }
    if (_filterFahrer != null && _filterFahrer!.isNotEmpty && _filterFahrer != 'Alle') {
      result = result.where((e) => (e.nameFahrer ?? '').trim() == _filterFahrer).toList();
    }
    result.sort((a, b) => (b.datum ?? DateTime(0)).compareTo(a.datum ?? DateTime(0)));
    return result;
  }

  Widget _buildFahrzeugEintraege() {
    final item = _selectedFahrzeug!;
    final key = item.vehicleKey;
    return StreamBuilder<List<FahrtenbuchEintrag>>(
      stream: _service.streamEintraegeFuerFahrzeug(widget.companyId, key),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting && !snap.hasData) {
          return const Center(child: CircularProgressIndicator(color: AppTheme.primary));
        }
        final all = snap.data ?? [];
        if (all.isNotEmpty && _cleanupDoneForVehicle != item.vehicleKey) {
          _cleanupDoneForVehicle = item.vehicleKey;
          _service.cleanupObsoleteKmKorrekturen(widget.companyId);
        }
        final list = _filterEintraege(all);
        final einsatzarten = all.map((e) => e.einsatzart?.trim()).whereType<String>().where((s) => s.isNotEmpty).toSet().toList()..sort();
        final fahrer = all.map((e) => e.nameFahrer?.trim()).whereType<String>().where((s) => s.isNotEmpty).toSet().toList()..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));

        final hasFilter = _filterVon != null || _filterBis != null ||
            (_filterEinsatzart != null && _filterEinsatzart != 'Alle') ||
            (_filterFahrer != null && _filterFahrer != 'Alle');

        return Column(
          children: [
            _buildFilterBar(einsatzarten, fahrer, list),
            if (hasFilter && list.isNotEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    '${list.length} von ${all.length} Einträgen',
                    style: TextStyle(color: Colors.grey[600], fontSize: 12),
                  ),
                ),
              ),
            Expanded(
              child: list.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.filter_list_off, size: 64, color: Colors.grey[400]),
                          const SizedBox(height: 16),
                          Text(
                            all.isEmpty ? 'Keine Einträge für dieses Fahrzeug.' : 'Keine Einträge passen zu den Filtern.',
                            style: TextStyle(color: Colors.grey[600]),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    )
                  : RefreshIndicator(
                      onRefresh: () async {
                        await _service.cleanupObsoleteKmKorrekturen(widget.companyId);
                        setState(() {});
                      },
                      child: ListView.builder(
                        padding: EdgeInsets.fromLTRB(16, 8, 16, MediaQuery.of(context).padding.bottom + 16),
                        itemCount: list.length,
                        itemBuilder: (_, i) => _buildEintragCard(list[i]),
                      ),
                    ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildFilterBar(List<String> einsatzarten, List<String> fahrer, List<FahrtenbuchEintrag> filteredList) {
    final isWide = MediaQuery.of(context).size.width >= 600;
    return Container(
      width: double.infinity,
      color: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Icon(Icons.filter_list, size: 20, color: AppTheme.primary),
            const SizedBox(width: 8),
            Text('Filter', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15, color: Colors.grey[800])),
            if (_filterVon != null || _filterBis != null || (_filterEinsatzart != null && _filterEinsatzart != 'Alle') || (_filterFahrer != null && _filterFahrer != 'Alle')) ...[
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(color: AppTheme.primary.withOpacity(0.2), borderRadius: BorderRadius.circular(8)),
                child: Text('aktiv', style: TextStyle(fontSize: 11, color: AppTheme.primary)),
              ),
            ],
            const SizedBox(width: 12),
            _dateChip('Von', _filterVon, (d) => setState(() => _filterVon = d)),
            const SizedBox(width: 12),
            _dateChip('Bis', _filterBis, (d) => setState(() => _filterBis = d)),
            const SizedBox(width: 12),
            ConstrainedBox(
              constraints: BoxConstraints(maxWidth: isWide ? 160 : 140),
              child: DropdownButtonFormField<String>(
                value: _filterEinsatzart ?? 'Alle',
                decoration: const InputDecoration(
                  labelText: 'Einsatzart',
                  border: OutlineInputBorder(),
                  contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                  isDense: true,
                  floatingLabelBehavior: FloatingLabelBehavior.never,
                ),
                isExpanded: true,
                items: ['Alle', ...einsatzarten].map((v) => DropdownMenuItem(value: v, child: Text(v, overflow: TextOverflow.ellipsis, maxLines: 1))).toList(),
                onChanged: (v) => setState(() => _filterEinsatzart = v),
              ),
            ),
            const SizedBox(width: 12),
            ConstrainedBox(
              constraints: BoxConstraints(maxWidth: isWide ? 160 : 140),
              child: DropdownButtonFormField<String>(
                value: _filterFahrer ?? 'Alle',
                decoration: const InputDecoration(
                  labelText: 'Fahrer',
                  border: OutlineInputBorder(),
                  contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                  isDense: true,
                  floatingLabelBehavior: FloatingLabelBehavior.never,
                ),
                isExpanded: true,
                items: ['Alle', ...fahrer].map((v) => DropdownMenuItem(value: v, child: Text(v, overflow: TextOverflow.ellipsis, maxLines: 1))).toList(),
                onChanged: (v) => setState(() => _filterFahrer = v),
              ),
            ),
            const SizedBox(width: 8),
            TextButton.icon(
              onPressed: () {
                setState(() {
                  _filterVon = null;
                  _filterBis = null;
                  _filterEinsatzart = 'Alle';
                  _filterFahrer = 'Alle';
                });
              },
              icon: const Icon(Icons.clear_all, size: 18),
              label: const Text('Zurücksetzen'),
            ),
            const SizedBox(width: 8),
            Tooltip(
              message: 'Drucken / Als PDF speichern',
              child: IconButton(
                onPressed: filteredList.isEmpty
                    ? null
                    : () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => FahrtenbuchDruckScreen(
                              eintraege: filteredList,
                              kennzeichen: _selectedFahrzeug?.displayLabel ?? 'Fahrtenbuch',
                              filterVon: _filterVon,
                              filterBis: _filterBis,
                              onBack: () => Navigator.of(context).pop(),
                            ),
                          ),
                        );
                      },
                icon: SvgPicture.asset(
                  'img/icon_print.svg',
                  width: 24,
                  height: 24,
                  colorFilter: ColorFilter.mode(
                    filteredList.isEmpty ? Colors.grey : AppTheme.primary,
                    BlendMode.srcIn,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 24),
          ],
        ),
      ),
    );
  }

  Widget _dateChip(String label, DateTime? value, void Function(DateTime?) onSelect) {
    return ActionChip(
      avatar: Icon(value != null ? Icons.check_circle : Icons.calendar_today, size: 18, color: value != null ? AppTheme.primary : null),
      label: Text(value != null ? '${label}: ${value.day.toString().padLeft(2, '0')}.${value.month.toString().padLeft(2, '0')}.${value.year}' : '$label wählen'),
      onPressed: () async {
        final d = await showDatePicker(
          context: context,
          initialDate: value ?? DateTime.now(),
          firstDate: DateTime(2020),
          lastDate: DateTime.now().add(const Duration(days: 365)),
        );
        if (d != null) onSelect(d);
      },
    );
  }

  Widget _buildEintragCard(FahrtenbuchEintrag e) {
    final isWide = MediaQuery.of(context).size.width >= 600;
    final datumStr = e.datum != null
        ? '${e.datum!.day.toString().padLeft(2, '0')}.${e.datum!.month.toString().padLeft(2, '0')}.${e.datum!.year}'
        : '–';
    final alarmEnde = [e.alarm, e.ende].where((x) => x != null && x.toString().trim().isNotEmpty).join(' – ');
    final fahrzeugkennung = e.fahrzeugkennung?.trim();
    final kennzeichen = e.kennzeichen?.trim();
    final von = e.einsatzort?.trim();
    final nach = e.transportziel?.trim();
    final streckeStr = (von != null && nach != null) ? '$von – $nach' : (von ?? nach ?? null);
    final einsatzNrZweck = e.einsatznummer?.trim().isNotEmpty == true ? e.einsatznummer! : (e.einsatzart?.trim().isNotEmpty == true ? e.einsatzart! : null);
    final gesamtKm = e.gesamtKm ?? (e.kmEnde != null && e.kmAnfang != null ? e.kmEnde! - e.kmAnfang! : null);

    return Card(
      margin: EdgeInsets.only(bottom: isWide ? 12 : 8),
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        onTap: () => _openEintragBearbeiten(e),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: EdgeInsets.all(isWide ? 16 : 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (e.manuellKmKorrektur == true)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.orange.shade100,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      (e.einsatzort ?? '').contains('Hier fehlen') ? e.einsatzort! : 'Fehlender Fahrtenbucheintrag (Fahrt nicht eingetragen)',
                      style: TextStyle(fontSize: 11, color: Colors.orange[900], fontWeight: FontWeight.w500),
                    ),
                  ),
                ),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    flex: 1,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(datumStr, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
                        if (alarmEnde.isNotEmpty) ...[
                          const SizedBox(height: 2),
                          Text(alarmEnde, style: TextStyle(color: Colors.grey[700], fontSize: 13)),
                        ],
                        if (einsatzNrZweck != null) ...[
                          const SizedBox(height: 4),
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text('Einsatz-Nr./Zweck: ', style: TextStyle(color: Colors.grey[600], fontSize: 12, fontWeight: FontWeight.w500)),
                              Flexible(child: Text(einsatzNrZweck, style: TextStyle(color: Colors.grey[800], fontSize: 13), overflow: TextOverflow.ellipsis)),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                  SizedBox(width: isWide ? 16 : 12),
                  Expanded(
                    flex: 1,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if ((fahrzeugkennung != null && fahrzeugkennung.isNotEmpty) || (kennzeichen != null && kennzeichen.isNotEmpty))
                          Text(
                            [fahrzeugkennung, kennzeichen].whereType<String>().where((s) => s.isNotEmpty).join(' · '),
                            style: TextStyle(color: Colors.grey[800], fontSize: 13, fontWeight: FontWeight.w500),
                          ),
                        if (e.nameFahrer != null && e.nameFahrer!.trim().isNotEmpty) ...[
                          const SizedBox(height: 2),
                          Text('Fahrer: ${e.nameFahrer}', style: TextStyle(color: Colors.grey[700], fontSize: 13), overflow: TextOverflow.ellipsis),
                        ],
                        if (e.nameBeifahrer != null && e.nameBeifahrer!.trim().isNotEmpty) ...[
                          const SizedBox(height: 2),
                          Text('Beifahrer: ${e.nameBeifahrer}', style: TextStyle(color: Colors.grey[600], fontSize: 13), overflow: TextOverflow.ellipsis),
                        ],
                      ],
                    ),
                  ),
                  SizedBox(width: isWide ? 16 : 12),
                  Expanded(
                    flex: 1,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (von != null || nach != null)
                          Text('Einsatzort – Zielort', style: TextStyle(color: Colors.grey[600], fontSize: 12, fontWeight: FontWeight.w500)),
                        if (streckeStr != null) ...[
                          const SizedBox(height: 2),
                          Text(streckeStr, style: TextStyle(color: Colors.grey[700], fontSize: 13), maxLines: 2, overflow: TextOverflow.ellipsis),
                        ],
                      ],
                    ),
                  ),
                  if (gesamtKm != null) ...[
                    SizedBox(width: isWide ? 12 : 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                      decoration: BoxDecoration(
                        color: AppTheme.primary.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text('Gefahrene KM', style: TextStyle(color: AppTheme.primary, fontSize: 11, fontWeight: FontWeight.w500)),
                          Text('$gesamtKm km', style: TextStyle(color: AppTheme.primary, fontWeight: FontWeight.w600, fontSize: 14)),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _openEintragBearbeiten(FahrtenbuchEintrag e) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => FahrtenbuchScreen(
          companyId: widget.companyId,
          onBack: () => Navigator.of(context).pop(),
          initialVorlage: null,
          initialEintrag: e,
        ),
      ),
    ).then((_) => setState(() {}));
  }
}
