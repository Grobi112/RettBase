import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../theme/app_theme.dart';
import '../models/checkliste_model.dart';
import '../services/checklisten_service.dart';
import 'checkliste_ausfuellung_druck_screen.dart';

/// Detail-Ansicht einer gespeicherten Checklisten-Ausfüllung (nur lesen)
class ChecklisteAusfuellungDetailScreen extends StatelessWidget {
  final String companyId;
  final ChecklisteAusfuellung ausfuellung;
  final VoidCallback onBack;

  const ChecklisteAusfuellungDetailScreen({
    super.key,
    required this.companyId,
    required this.ausfuellung,
    required this.onBack,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppTheme.buildModuleAppBar(
        title: ausfuellung.checklisteTitel,
        onBack: onBack,
        actions: [
          IconButton(
            icon: const Icon(Icons.print),
            tooltip: 'Drucken / PDF',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => ChecklisteAusfuellungDruckScreen(
                  companyId: companyId,
                  ausfuellung: ausfuellung,
                  onBack: () => Navigator.of(context).pop(),
                ),
              ),
            ),
          ),
        ],
      ),
      body: FutureBuilder<Checkliste?>(
        future: _loadCheckliste(context),
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator(color: AppTheme.primary));
          }
          final checkliste = snap.data;
          if (checkliste == null) {
            return Center(
              child: Text('Checkliste nicht gefunden.', style: TextStyle(color: Colors.grey[600])),
            );
          }
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _buildInfoCard(),
              const SizedBox(height: 16),
              if (ausfuellung.maengelSnapshot != null && ausfuellung.maengelSnapshot!.isNotEmpty) ...[
                _buildMaengelCard(),
                const SizedBox(height: 16),
              ],
              ...checkliste.sections.expand((s) => [
                Padding(
                  padding: const EdgeInsets.only(top: 20, bottom: 12),
                  child: Text(s.title, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: AppTheme.primary)),
                ),
                Card(
                  elevation: 0,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: Colors.grey.shade200)),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                    child: Column(children: s.items.map((item) => _buildItemCard(item)).toList()),
                  ),
                ),
              ]),
            ],
          );
        },
      ),
    );
  }

  Future<Checkliste?> _loadCheckliste(BuildContext context) async {
    try {
      final list = await ChecklistenService().loadChecklisten(companyId);
      final c = list.where((c) => c.id == ausfuellung.checklisteId).firstOrNull;
      return c?.ensureUniqueItemIds();
    } catch (_) {
      return null;
    }
  }

  Widget _infoRow(String label, String value, {bool showWhenEmpty = false}) {
    if (value.isEmpty && !showWhenEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 130,
            child: Text(label, style: TextStyle(fontSize: 13, color: Colors.grey[600])),
          ),
          Expanded(
            child: Text(value, style: TextStyle(fontSize: 14, color: Colors.grey[800], fontWeight: FontWeight.w500)),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoCard() {
    final d = ausfuellung.createdAt;
    final datum = d != null
        ? '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.${d.year} '
            '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}'
        : '';
    final createdBy = ausfuellung.createdByName?.trim() ?? '';
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: Colors.grey.shade200)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (datum.isNotEmpty) _infoRow('Ausgefüllt am', datum),
            if (createdBy.isNotEmpty) _infoRow('Ausgefüllt von', createdBy),
            if (ausfuellung.fahrer != null && ausfuellung.fahrer!.trim().isNotEmpty)
              _infoRow('Fahrer', ausfuellung.fahrer!.trim()),
            _infoRow('Beifahrer', ausfuellung.beifahrer?.trim() ?? '', showWhenEmpty: true),
            if (ausfuellung.praktikantAzubi != null && ausfuellung.praktikantAzubi!.trim().isNotEmpty)
              _infoRow('Praktikant / Azubi', ausfuellung.praktikantAzubi!.trim()),
            if (ausfuellung.kennzeichen != null && ausfuellung.kennzeichen!.trim().isNotEmpty)
              _infoRow('Kennzeichen', ausfuellung.kennzeichen!.trim()),
            if (ausfuellung.standort != null && ausfuellung.standort!.trim().isNotEmpty)
              _infoRow('Standort', ausfuellung.standort!.trim()),
            if (ausfuellung.wachbuchSchicht != null && ausfuellung.wachbuchSchicht!.trim().isNotEmpty)
              _infoRow('Wachbuch-Schicht', ausfuellung.wachbuchSchicht!.trim()),
            if (ausfuellung.kmStand != null)
              _infoRow('KM-Stand', '${ausfuellung.kmStand} km'),
          ],
        ),
      ),
    );
  }

  Widget _buildMaengelCard() {
    final list = ausfuellung.maengelSnapshot!;
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: Colors.grey.shade200)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Fahrzeugmangel', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: Colors.grey[800])),
            const SizedBox(height: 4),
            Text('Zum Zeitpunkt der Ausfüllung: ${list.length} offen/in Bearbeitung',
                style: TextStyle(fontSize: 13, color: Colors.grey[600])),
            const SizedBox(height: 16),
            ...list.asMap().entries.map((e) {
              final i = e.key;
              final m = e.value;
              final betreff = (m['betreff'] ?? '').toString().trim();
              final beschreibung = (m['beschreibung'] ?? '').toString();
              final desc = betreff.isNotEmpty ? betreff : (beschreibung.split('\n').isNotEmpty ? beschreibung.split('\n').first : beschreibung);
              final datumRaw = m['datum'];
              String datumStr = '–';
              if (datumRaw is Timestamp) {
                final d = datumRaw.toDate();
                datumStr = '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.${d.year}';
              }
              final melder = (m['melderName'] ?? '').toString();
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (i > 0) Divider(height: 24, color: Colors.grey.shade300),
                  Text(desc, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: Colors.grey[800])),
                  const SizedBox(height: 4),
                  Text('Erfasst $datumStr von ${melder.isEmpty ? 'Unbekannt' : melder}',
                      style: TextStyle(fontSize: 12, color: Colors.grey[600])),
                ],
              );
            }),
          ],
        ),
      ),
    );
  }

  bool _toBool(dynamic v) {
    if (v == null) return false;
    if (v is bool) return v;
    if (v is String) return v.toLowerCase() == 'true' || v == '1';
    if (v is num) return v != 0;
    return false;
  }

  Widget _buildItemCard(ChecklisteItem item) {
    final value = ausfuellung.values[item.id];
    String display;
    if (item.type == 'checkbox') {
      display = _toBool(value) ? 'Ja' : 'Nein';
    } else if (item.type == 'slider') {
      display = _toBool(value) ? 'Ja' : 'Nein';
    } else {
      final s = value?.toString() ?? '';
      display = s.trim().isEmpty ? '–' : s;
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 1,
            child: Text(item.label, style: TextStyle(fontSize: 14, color: Colors.grey[700])),
          ),
          Expanded(
            flex: 1,
            child: Text(display, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: Colors.grey[800])),
          ),
        ],
      ),
    );
  }
}
