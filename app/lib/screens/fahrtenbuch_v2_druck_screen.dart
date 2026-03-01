import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../models/fahrtenbuch_v2_model.dart';
import '../theme/app_theme.dart';

/// Druck-/PDF-Vorschau für Fahrtenbuch V2 Einträge
class FahrtenbuchV2DruckScreen extends StatelessWidget {
  final List<FahrtenbuchV2Eintrag> eintraege;
  final String kennzeichen;
  final DateTime? filterVon;
  final DateTime? filterBis;
  final VoidCallback onBack;

  const FahrtenbuchV2DruckScreen({
    super.key,
    required this.eintraege,
    required this.kennzeichen,
    this.filterVon,
    this.filterBis,
    required this.onBack,
  });

  static const String _empty = '-';

  static String _fmt(DateTime? d) {
    if (d == null) return _empty;
    return '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.${d.year}';
  }

  static String _str(String? s) => (s ?? '').trim().isEmpty ? _empty : (s ?? '').trim();

  static String _nachname(String? s) {
    final n = (s ?? '').trim();
    if (n.isEmpty) return _empty;
    if (n.contains(',')) {
      final beforeComma = n.split(',').first.trim();
      return beforeComma.isNotEmpty ? beforeComma : n;
    }
    final parts = n.split(RegExp(r'\s+'));
    return parts.length > 1 ? parts.last : n;
  }

  static const int _rowsPerPage = 22;

  pw.TableRow _buildTableHeader(double fsHeader) => pw.TableRow(
        decoration: pw.BoxDecoration(color: PdfColors.grey300),
        children: [
          _th('Datum', fsHeader),
          _th('Fahrzeit von', fsHeader),
          _th('Fahrzeit bis', fsHeader),
          _th('Fahrt von', fsHeader),
          _th('Fahrt-Ziel', fsHeader),
          _th('Grund', fsHeader),
          _th('KM Beginn', fsHeader),
          _th('KM Ende', fsHeader),
          _th('KM dienstl.', fsHeader),
          _th('KM Wohn.-Arb.', fsHeader),
          _th('KM privat', fsHeader),
          _th('Fahrer', fsHeader),
          _th('Kosten', fsHeader),
        ],
      );

  pw.TableRow _buildDataRow(FahrtenbuchV2Eintrag e, double fs) {
    final kostenStr = e.kostenBetrag != null
        ? '${e.kostenBetrag}${(e.kostenArt ?? '').trim().isNotEmpty ? ' (${e.kostenArt})' : ''}'
        : _empty;
    return pw.TableRow(
      children: [
        _td(_fmt(e.datum), fs),
        _td(_str(e.fahrzeitVon), fs),
        _td(_str(e.fahrzeitBis), fs),
        _td(_str(e.fahrtVon), fs),
        _td(_str(e.ziel), fs),
        _td(_str(e.grundDerFahrt), fs),
        _td(e.kmAnfang != null ? '${e.kmAnfang}' : _empty, fs),
        _td(e.kmEnde != null ? '${e.kmEnde}' : _empty, fs),
        _td(e.kmDienstlich != null ? '${e.kmDienstlich}' : _empty, fs),
        _td(e.kmWohnortArbeit != null ? '${e.kmWohnortArbeit}' : _empty, fs),
        _td(e.kmPrivat != null ? '${e.kmPrivat}' : _empty, fs),
        _td(_nachname(e.nameFahrer), fs),
        _td(kostenStr, fs),
      ],
    );
  }

  Future<Uint8List> _buildPdf(PdfPageFormat format) async {
    final pdf = pw.Document();
    const fs = 7.0;
    const fsHeader = 9.0;
    const fsTitle = 12.0;

    final title = kennzeichen.startsWith('Fahrtenbuch für') ? kennzeichen : 'Fahrtenbuch V2 $kennzeichen';

    final columnWidths = {
      for (var i = 0; i < 13; i++) i: const pw.FlexColumnWidth(1),
    };

    final totalPages = eintraege.isEmpty ? 1 : ((eintraege.length + _rowsPerPage - 1) / _rowsPerPage).ceil();

    for (var i = 0; i < eintraege.length; i += _rowsPerPage) {
      final chunk = eintraege.skip(i).take(_rowsPerPage).toList();
      final pageNum = (i / _rowsPerPage).floor() + 1;
      pdf.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4.landscape,
          margin: const pw.EdgeInsets.all(20),
          build: (ctx) => pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text(
                    title,
                    style: pw.TextStyle(fontSize: fsTitle, fontWeight: pw.FontWeight.bold),
                  ),
                  pw.Row(
                    mainAxisSize: pw.MainAxisSize.min,
                    children: [
                      pw.Text('Erstellt: ${_fmt(DateTime.now())}', style: const pw.TextStyle(fontSize: fs)),
                      pw.SizedBox(width: 16),
                      pw.Text('Seite $pageNum von $totalPages', style: pw.TextStyle(fontSize: fs, fontWeight: pw.FontWeight.bold)),
                    ],
                  ),
                ],
              ),
              pw.SizedBox(height: 16),
              pw.Table(
                border: pw.TableBorder.all(width: 0.5),
                columnWidths: columnWidths,
                children: [
                  _buildTableHeader(fsHeader),
                  ...chunk.map((e) => _buildDataRow(e, fs)),
                ],
              ),
            ],
          ),
        ),
      );
    }

    if (eintraege.isEmpty) {
      pdf.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4.landscape,
          margin: const pw.EdgeInsets.all(20),
          build: (ctx) => pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(
                title,
                style: pw.TextStyle(fontSize: fsTitle, fontWeight: pw.FontWeight.bold),
              ),
              pw.SizedBox(height: 16),
              pw.Text('Keine Einträge.', style: pw.TextStyle(fontSize: fs)),
            ],
          ),
        ),
      );
    }

    return pdf.save();
  }

  pw.Widget _th(String text, double fs) => pw.Padding(
        padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 4),
        child: pw.Center(
          child: pw.Text(text, style: pw.TextStyle(fontSize: fs, fontWeight: pw.FontWeight.bold), textAlign: pw.TextAlign.center),
        ),
      );

  pw.Widget _td(String text, double fs) => pw.Padding(
        padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 3),
        child: pw.Center(
          child: pw.Text(text, style: pw.TextStyle(fontSize: fs), textAlign: pw.TextAlign.center, maxLines: 2, overflow: pw.TextOverflow.clip),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final vonStr = _fmt(filterVon);
    final bisStr = _fmt(filterBis);
    final pdfName = 'Fahrtenbuch_V2_${kennzeichen.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '_')}_${vonStr}_${bisStr}.pdf';

    return Scaffold(
      backgroundColor: Colors.grey.shade200,
      appBar: AppTheme.buildModuleAppBar(
        title: 'Fahrtenbuch drucken / PDF',
        onBack: onBack,
      ),
      body: eintraege.isEmpty
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.description_outlined, size: 64, color: Colors.grey[400]),
                  const SizedBox(height: 16),
                  Text(
                    'Keine Einträge zum Drucken.',
                    style: TextStyle(color: Colors.grey[600]),
                  ),
                ],
              ),
            )
          : PdfPreview(
              build: _buildPdf,
              allowPrinting: true,
              allowSharing: false,
              canChangePageFormat: false,
              canChangeOrientation: false,
              canDebug: false,
              pdfFileName: pdfName,
              loadingWidget: const Center(child: CircularProgressIndicator()),
              actions: [
                IconButton(
                  icon: const Icon(Icons.save),
                  tooltip: 'Als PDF speichern',
                  onPressed: () async {
                    final bytes = await _buildPdf(PdfPageFormat.a4.landscape);
                    await Printing.sharePdf(bytes: bytes, filename: pdfName);
                  },
                ),
              ],
            ),
    );
  }
}
