import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../models/checkliste_model.dart';
import '../services/checklisten_service.dart';
import '../theme/app_theme.dart';

/// Druck-/PDF-Vorschau einer gespeicherten Checkliste – DIN A4, eine Seite
class ChecklisteAusfuellungDruckScreen extends StatelessWidget {
  final String companyId;
  final ChecklisteAusfuellung ausfuellung;
  final VoidCallback onBack;

  const ChecklisteAusfuellungDruckScreen({
    super.key,
    required this.companyId,
    required this.ausfuellung,
    required this.onBack,
  });

  static const String _empty = '-';

  static String _fmt(DateTime? d) {
    if (d == null) return _empty;
    return '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.${d.year} '
        '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
  }

  static String _str(String? s) => (s ?? '').trim().isEmpty ? _empty : (s ?? '').trim();

  bool _toBool(dynamic v) {
    if (v == null) return false;
    if (v is bool) return v;
    if (v is String) return v.toLowerCase() == 'true' || v == '1';
    if (v is num) return v != 0;
    return false;
  }

  String _itemDisplay(ChecklisteItem item) {
    final value = ausfuellung.values[item.id];
    if (item.type == 'checkbox' || item.type == 'slider') {
      return _toBool(value) ? 'Ja' : 'Nein';
    }
    final s = value?.toString() ?? '';
    return s.trim().isEmpty ? _empty : s.trim();
  }

  Future<Uint8List> _buildPdf(Checkliste checkliste, PdfPageFormat format) async {
    final pdf = pw.Document();
    const fs = 7.0;
    const fsSection = 8.0;
    const fsTitle = 10.0;
    const lineH = 4.0;
    const pad = 3.0;

    final datum = _fmt(ausfuellung.createdAt);
    final createdBy = _str(ausfuellung.createdByName);
    final fahrer = _str(ausfuellung.fahrer);
    final beifahrer = _str(ausfuellung.beifahrer);
    final praktikant = _str(ausfuellung.praktikantAzubi);
    final kennz = _str(ausfuellung.kennzeichen);
    final standort = _str(ausfuellung.standort);
    final schicht = _str(ausfuellung.wachbuchSchicht);
    final kmStr = ausfuellung.kmStand != null ? '${ausfuellung.kmStand} km' : _empty;

    // Kompakte Info-Zeilen (2 Spalten)
    pw.Widget infoRow(String l, String v) => pw.Padding(
          padding: pw.EdgeInsets.only(bottom: pad),
          child: pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.SizedBox(width: 65, child: pw.Text('$l:', style: const pw.TextStyle(fontSize: fs))),
              pw.Expanded(child: pw.Text(v, style: const pw.TextStyle(fontSize: fs))),
            ],
          ),
        );

    final children = <pw.Widget>[
      pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(ausfuellung.checklisteTitel,
              style: pw.TextStyle(fontSize: fsTitle, fontWeight: pw.FontWeight.bold)),
          pw.Text('Erstellt: ${_fmt(DateTime.now())}', style: const pw.TextStyle(fontSize: fs - 1)),
        ],
      ),
      pw.SizedBox(height: lineH + 2),
      pw.Container(
        padding: const pw.EdgeInsets.all(8),
        decoration: pw.BoxDecoration(
          border: pw.Border.all(width: 0.5),
          borderRadius: pw.BorderRadius.circular(4),
        ),
        child: pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Expanded(
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  infoRow('Ausgefüllt am', datum),
                  infoRow('Ausgefüllt von', createdBy),
                  infoRow('Fahrer', fahrer),
                  infoRow('Beifahrer', beifahrer),
                  if (praktikant != _empty) infoRow('Praktikant/Azubi', praktikant),
                  infoRow('Kennzeichen', kennz),
                ],
              ),
            ),
            pw.Expanded(
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  infoRow('Standort', standort),
                  infoRow('Wachbuch-Schicht', schicht),
                  infoRow('KM-Stand', kmStr),
                ],
              ),
            ),
          ],
        ),
      ),
      pw.SizedBox(height: lineH + 4),
    ];

    // Mängel (kompakt)
    if (ausfuellung.maengelSnapshot != null && ausfuellung.maengelSnapshot!.isNotEmpty) {
      final list = ausfuellung.maengelSnapshot!;
      children.add(pw.Text('Fahrzeugmangel (${list.length})',
          style: pw.TextStyle(fontSize: fsSection, fontWeight: pw.FontWeight.bold)));
      children.add(pw.SizedBox(height: 2));
      for (final m in list.take(5)) {
        final betreff = (m['betreff'] ?? '').toString().trim();
        final beschreibung = (m['beschreibung'] ?? '').toString();
        final desc = betreff.isNotEmpty
            ? betreff
            : (beschreibung.split('\n').isNotEmpty ? beschreibung.split('\n').first : beschreibung);
        if (desc.isNotEmpty) {
          children.add(pw.Padding(
            padding: pw.EdgeInsets.only(left: 6, bottom: 2),
            child: pw.Text('- $desc', style: const pw.TextStyle(fontSize: fs - 0.5)),
          ));
        }
      }
      if (list.length > 5) {
        children.add(pw.Padding(
          padding: const pw.EdgeInsets.only(left: 6),
          child: pw.Text('… und ${list.length - 5} weitere', style: const pw.TextStyle(fontSize: fs - 0.5)),
        ));
      }
      children.add(pw.SizedBox(height: lineH + 4));
    }

    // Checklisten-Bereiche – kompakt, 2 Spalten pro Section
    final c = checkliste.ensureUniqueItemIds();
    for (final section in c.sections) {
      children.add(pw.Text(section.title,
          style: pw.TextStyle(fontSize: fsSection, fontWeight: pw.FontWeight.bold)));
      children.add(pw.SizedBox(height: 2));

      final items = section.items;
      final half = (items.length / 2).ceil();
      final leftItems = items.take(half).toList();
      final rightItems = items.skip(half).take(half).toList();

      pw.Widget itemRow(ChecklisteItem item) => pw.Padding(
            padding: pw.EdgeInsets.only(bottom: 1),
            child: pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Expanded(
                  flex: 2,
                  child: pw.Text(item.label,
                      style: const pw.TextStyle(fontSize: fs),
                      maxLines: 2,
                      overflow: pw.TextOverflow.clip),
                ),
                pw.Expanded(
                  flex: 1,
                  child: pw.Text(_itemDisplay(item), style: const pw.TextStyle(fontSize: fs)),
                ),
              ],
            ),
          );

      children.add(
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Expanded(
              child: pw.Container(
                padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                decoration: pw.BoxDecoration(
                  border: pw.Border.all(width: 0.3),
                  borderRadius: pw.BorderRadius.circular(2),
                ),
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: leftItems.map((i) => itemRow(i)).toList(),
                ),
              ),
            ),
            pw.SizedBox(width: 6),
            pw.Expanded(
              child: pw.Container(
                padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                decoration: pw.BoxDecoration(
                  border: pw.Border.all(width: 0.3),
                  borderRadius: pw.BorderRadius.circular(2),
                ),
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: rightItems.map((i) => itemRow(i)).toList(),
                ),
              ),
            ),
          ],
        ),
      );
      children.add(pw.SizedBox(height: lineH + 2));
    }

    // DIN A4, eine Seite – kompaktes Layout mit Skalierung falls nötig
    const margin = 16.0;
    final availableW = format.width - margin * 2;
    final availableH = format.height - margin * 2;

    pdf.addPage(
      pw.Page(
        pageFormat: format,
        margin: const pw.EdgeInsets.all(16),
        build: (ctx) => pw.SizedBox(
          width: availableW,
          height: availableH,
          child: pw.FittedBox(
            fit: pw.BoxFit.contain,
            alignment: pw.Alignment.topLeft,
            child: pw.SizedBox(
              width: availableW,
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                mainAxisSize: pw.MainAxisSize.min,
                children: children,
              ),
            ),
          ),
        ),
      ),
    );

    return pdf.save();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Checkliste?>(
      future: _loadCheckliste(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return Scaffold(
            backgroundColor: Colors.grey.shade200,
            appBar: AppTheme.buildModuleAppBar(title: 'Checkliste drucken', onBack: onBack),
            body: const Center(child: CircularProgressIndicator(color: AppTheme.primary)),
          );
        }
        final checkliste = snap.data;
        if (checkliste == null) {
          return Scaffold(
            backgroundColor: Colors.grey.shade200,
            appBar: AppTheme.buildModuleAppBar(title: 'Checkliste drucken', onBack: onBack),
            body: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.error_outline, size: 48, color: Colors.grey[600]),
                  const SizedBox(height: 16),
                  Text('Checkliste nicht gefunden.', style: TextStyle(color: Colors.grey[600])),
                ],
              ),
            ),
          );
        }

        final pdfName =
            'Checkliste_${ausfuellung.checklisteTitel.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '_')}_${_fmt(ausfuellung.createdAt).replaceAll(RegExp(r'[\s:]'), '-')}.pdf';

        return Scaffold(
          backgroundColor: Colors.grey.shade200,
          appBar: AppTheme.buildModuleAppBar(
            title: 'Checkliste drucken / PDF',
            onBack: onBack,
            actions: [
              IconButton(
                icon: const Icon(Icons.print),
                tooltip: 'Drucken',
                onPressed: () async {
                  await Printing.layoutPdf(
                    onLayout: (format) => _buildPdf(checkliste, format),
                    name: pdfName,
                  );
                },
              ),
              IconButton(
                icon: const Icon(Icons.save),
                tooltip: 'Als PDF speichern',
                onPressed: () async {
                  final bytes = await _buildPdf(checkliste, PdfPageFormat.a4);
                  await Printing.sharePdf(bytes: bytes, filename: pdfName);
                },
              ),
            ],
          ),
          body: PdfPreview(
            build: (format) => _buildPdf(checkliste, format),
            allowPrinting: false,
            allowSharing: false,
            useActions: false,
            canChangePageFormat: false,
            canChangeOrientation: false,
            canDebug: false,
            pdfFileName: pdfName,
            loadingWidget: const Center(child: CircularProgressIndicator()),
            onError: (_, __) => Center(
              child: Text('PDF konnte nicht geladen werden.', style: TextStyle(color: Colors.grey[600])),
            ),
          ),
        );
      },
    );
  }

  Future<Checkliste?> _loadCheckliste() async {
    try {
      final list = await ChecklistenService().loadChecklisten(companyId);
      final c = list.where((c) => c.id == ausfuellung.checklisteId).firstOrNull;
      return c?.ensureUniqueItemIds();
    } catch (_) {
      return null;
    }
  }
}
