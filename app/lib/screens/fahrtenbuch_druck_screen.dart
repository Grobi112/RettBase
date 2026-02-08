import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../models/fahrtenbuch_model.dart';
import '../theme/app_theme.dart';

/// Druck-/PDF-Vorschau für gefilterte Fahrtenbuch-Einträge
class FahrtenbuchDruckScreen extends StatelessWidget {
  final List<FahrtenbuchEintrag> eintraege;
  final String kennzeichen;
  final DateTime? filterVon;
  final DateTime? filterBis;
  final VoidCallback onBack;

  const FahrtenbuchDruckScreen({
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

  /// Nachname extrahieren: "Nachname, Vorname" -> Nachname, "Vorname Nachname" -> Nachname
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
          _th('Fahrtbeginn', fsHeader),
          _th('Fahrtende', fsHeader),
          _th('Einsatz-Nr./Zweck', fsHeader),
          _th('Fahrtstrecke', fsHeader),
          _th('KM-Stand Beginn', fsHeader),
          _th('KM-Stand Ende', fsHeader),
          _th('Gesamt-KM', fsHeader),
          _th('Fahrer', fsHeader),
        ],
      );

  pw.TableRow _buildDataRow(FahrtenbuchEintrag e, double fs) {
    final datumStr = _fmt(e.datum);
    final alarmStr = _str(e.alarm);
    final endeStr = _str(e.ende);
    final einsatzStr = _str(e.einsatznummer?.isNotEmpty == true ? e.einsatznummer : e.einsatzart);
    final von = _str(e.einsatzort);
    final nach = _str(e.transportziel);
    final streckeStr = (von != _empty || nach != _empty) ? '$von - $nach' : _empty;
    final kmAnfangStr = e.kmAnfang != null ? '${e.kmAnfang}' : _empty;
    final kmEndeStr = e.kmEnde != null ? '${e.kmEnde}' : _empty;
    final gesamtKm = e.gesamtKm ?? (e.kmAnfang != null && e.kmEnde != null ? e.kmEnde! - e.kmAnfang! : null);
    final gesamtKmStr = gesamtKm != null ? '${gesamtKm}' : _empty;
    final fahrerStr = _nachname(e.nameFahrer);
    return pw.TableRow(
      children: [
        _td(datumStr, fs),
        _td(alarmStr, fs),
        _td(endeStr, fs),
        _td(einsatzStr, fs),
        _td(streckeStr, fs),
        _td(kmAnfangStr, fs),
        _td(kmEndeStr, fs),
        _td(gesamtKmStr, fs),
        _td(fahrerStr, fs),
      ],
    );
  }

  Future<Uint8List> _buildPdf(PdfPageFormat format) async {
    final pdf = pw.Document();
    const fs = 8.0;
    const fsHeader = 10.0;
    const fsTitle = 12.0;

    final vonStr = _fmt(filterVon);
    final bisStr = _fmt(filterBis);
    final filterStr = (filterVon != null || filterBis != null)
        ? ' ($vonStr - $bisStr)'
        : '';

    final columnWidths = {
      0: const pw.FlexColumnWidth(1.2),
      1: const pw.FlexColumnWidth(1),
      2: const pw.FlexColumnWidth(1),
      3: const pw.FlexColumnWidth(1.8),
      4: const pw.FlexColumnWidth(2.2),
      5: const pw.FlexColumnWidth(0.9),
      6: const pw.FlexColumnWidth(0.9),
      7: const pw.FlexColumnWidth(0.8),
      8: const pw.FlexColumnWidth(1.2),
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
                    'Fahrtenbuch $kennzeichen$filterStr',
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
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text(
                    'Fahrtenbuch $kennzeichen$filterStr',
                    style: pw.TextStyle(fontSize: fsTitle, fontWeight: pw.FontWeight.bold),
                  ),
                  pw.Row(
                    mainAxisSize: pw.MainAxisSize.min,
                    children: [
                      pw.Text('Erstellt: ${_fmt(DateTime.now())}', style: const pw.TextStyle(fontSize: fs)),
                      pw.SizedBox(width: 16),
                      pw.Text('Seite 1 von 1', style: pw.TextStyle(fontSize: fs, fontWeight: pw.FontWeight.bold)),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
      );
    }

    return pdf.save();
  }

  pw.Widget _th(String text, double fs) => pw.Padding(
        padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 6),
        child: pw.Center(
          child: pw.Text(text, style: pw.TextStyle(fontSize: fs, fontWeight: pw.FontWeight.bold), textAlign: pw.TextAlign.center),
        ),
      );

  pw.Widget _td(String text, double fs) => pw.Padding(
        padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        child: pw.Center(
          child: pw.Text(text, style: pw.TextStyle(fontSize: fs), textAlign: pw.TextAlign.center, maxLines: 2, overflow: pw.TextOverflow.clip),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final vonStr = _fmt(filterVon);
    final bisStr = _fmt(filterBis);
    final pdfName = 'Fahrtenbuch_${kennzeichen.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '_')}_${vonStr}_${bisStr}.pdf';

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
