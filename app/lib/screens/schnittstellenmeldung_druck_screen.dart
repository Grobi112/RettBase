import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../models/schnittstellenmeldung_model.dart';
import '../theme/app_theme.dart';

String _formatDate(DateTime? d) {
  if (d == null) return '-';
  return '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.${d.year}';
}

/// Druck-/PDF-Vorschau einer Schnittstellenmeldung
class SchnittstellenmeldungDruckScreen extends StatelessWidget {
  final Schnittstellenmeldung meldung;
  final VoidCallback onBack;

  const SchnittstellenmeldungDruckScreen({
    super.key,
    required this.meldung,
    required this.onBack,
  });

  static String _str(String? s) => (s ?? '').trim().isEmpty ? '-' : (s ?? '').trim();

  Future<Uint8List> _buildPdf(PdfPageFormat format) async {
    final pdf = pw.Document();
    const fs = 9.0;
    const fsTitle = 12.0;

    pw.Widget infoRow(String l, String v) => pw.Padding(
          padding: const pw.EdgeInsets.only(bottom: 6),
          child: pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.SizedBox(width: 100, child: pw.Text('$l:', style: const pw.TextStyle(fontSize: fs, fontWeight: pw.FontWeight.bold))),
              pw.Expanded(child: pw.Text(v, style: const pw.TextStyle(fontSize: fs))),
            ],
          ),
        );

    final children = <pw.Widget>[
      pw.Text('Schnittstellenmeldung', style: pw.TextStyle(fontSize: fsTitle, fontWeight: pw.FontWeight.bold)),
      pw.SizedBox(height: 16),
      pw.Container(
        padding: const pw.EdgeInsets.all(12),
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
                  infoRow('Datum', _formatDate(meldung.datum)),
                  infoRow('Einsatznummer', _str(meldung.einsatznummer)),
                  infoRow('FB-Nummer', _str(meldung.fbNummer)),
                  infoRow('RTW/MZF', _str(meldung.rtwMzf)),
                  infoRow('Besatzung', _str(meldung.besatzung)),
                ],
              ),
            ),
            pw.Expanded(
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  infoRow('Uhrzeit', _str(meldung.uhrzeit)),
                  infoRow('Leitstelle', _str(meldung.leitstelle)),
                  infoRow('Schn. Personal', _str(meldung.schnPersonal)),
                  infoRow('NEF', _str(meldung.nef)),
                  infoRow('Arzt', _str(meldung.arzt)),
                ],
              ),
            ),
          ],
        ),
      ),
      pw.SizedBox(height: 12),
      pw.Text('Vorkommnis', style: pw.TextStyle(fontSize: fs, fontWeight: pw.FontWeight.bold)),
      pw.SizedBox(height: 4),
      pw.Container(
        width: double.infinity,
        padding: const pw.EdgeInsets.all(10),
        decoration: pw.BoxDecoration(
          border: pw.Border.all(width: 0.5),
          borderRadius: pw.BorderRadius.circular(4),
        ),
        child: pw.Text(meldung.vorkommnis, style: const pw.TextStyle(fontSize: fs)),
      ),
      pw.SizedBox(height: 12),
      pw.Text('Erstellt von: ${_str(meldung.createdByName)} · ${_formatDate(meldung.createdAt)}', style: const pw.TextStyle(fontSize: fs - 1)),
    ];

    pdf.addPage(
      pw.MultiPage(
        pageFormat: format,
        margin: const pw.EdgeInsets.all(24),
        build: (context) => children,
      ),
    );

    return pdf.save();
  }

  @override
  Widget build(BuildContext context) {
    final pdfName = 'Schnittstellenmeldung_${_formatDate(meldung.datum).replaceAll('.', '-')}_${meldung.id}.pdf';

    return Scaffold(
      backgroundColor: Colors.grey.shade200,
      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: AppTheme.primary,
        elevation: 1,
        leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: onBack),
        title: Text('Schnittstellenmeldung drucken', style: TextStyle(color: AppTheme.primary, fontWeight: FontWeight.w600)),
        actions: [
          IconButton(
            icon: const Icon(Icons.print),
            tooltip: 'Drucken',
            onPressed: () async {
              await Printing.layoutPdf(
                onLayout: (format) => _buildPdf(format),
                name: pdfName,
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.share),
            tooltip: 'Als PDF speichern',
            onPressed: () async {
              final bytes = await _buildPdf(PdfPageFormat.a4);
              await Printing.sharePdf(bytes: bytes, filename: pdfName);
            },
          ),
        ],
      ),
      body: PdfPreview(
        build: (format) => _buildPdf(format),
        allowPrinting: false,
        allowSharing: false,
        useActions: false,
        canChangePageFormat: false,
        canChangeOrientation: false,
        canDebug: false,
        pdfFileName: pdfName,
        loadingWidget: const Center(child: CircularProgressIndicator()),
      ),
    );
  }
}
