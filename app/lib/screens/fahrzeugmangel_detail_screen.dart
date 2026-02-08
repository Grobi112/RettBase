import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../models/fleet_model.dart';

/// Vollbild-Detailansicht eines Fahrzeugmangels (read-only)
class FahrzeugmangelDetailScreen extends StatelessWidget {
  final FahrzeugMangel mangel;
  final VoidCallback onBack;

  const FahrzeugmangelDetailScreen({
    super.key,
    required this.mangel,
    required this.onBack,
  });

  String _formatDateTime(DateTime? d) {
    if (d == null) return '–';
    return '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.${d.year} ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
  }

  String _shortDesc(FahrzeugMangel m) =>
      m.betreff?.trim().isNotEmpty == true ? m.betreff! : (m.beschreibung.split('\n').isNotEmpty ? m.beschreibung.split('\n').first : m.beschreibung);

  @override
  Widget build(BuildContext context) {
    final m = mangel;
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppTheme.buildModuleAppBar(
        title: _shortDesc(m),
        onBack: onBack,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            margin: const EdgeInsets.only(bottom: 16),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _detailRow('Erfasst am', _formatDateTime(m.datum ?? m.createdAt)),
                  _detailRow('Erfasst von', m.melderName ?? '–'),
                  _detailRow('Fahrzeug', m.displayLabel),
                  if (m.kategorie != null && m.kategorie!.isNotEmpty) _detailRow('Kategorie', m.kategorie!),
                  if (m.status.isNotEmpty) _detailRow('Status', m.status),
                  if (m.prioritaet != null && m.prioritaet!.isNotEmpty) _detailRow('Priorität', m.prioritaet!),
                ],
              ),
            ),
          ),
          const Padding(
            padding: EdgeInsets.only(bottom: 8),
            child: Text('Beschreibung', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
          ),
          Card(
            margin: const EdgeInsets.only(bottom: 16),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Text(m.beschreibung, style: TextStyle(fontSize: 14, color: Colors.grey[800])),
            ),
          ),
          if (m.bilder.isNotEmpty) ...[
            const Padding(
              padding: EdgeInsets.only(bottom: 8),
              child: Text('Bilder', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
            ),
            Card(
              margin: const EdgeInsets.only(bottom: 16),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: m.bilder.map((url) => ClipRRect(borderRadius: BorderRadius.circular(8), child: Image.network(url, width: 80, height: 80, fit: BoxFit.cover))).toList(),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _detailRow(String label, String value) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(width: 120, child: Text('$label:', style: TextStyle(fontSize: 14, color: Colors.grey[600]))),
            Expanded(child: Text(value, style: const TextStyle(fontSize: 14))),
          ],
        ),
      );
}
