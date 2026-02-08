import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../models/uebergriffsmeldung_model.dart';
import '../theme/app_theme.dart';

String _formatDate(DateTime? d) {
  if (d == null) return '-';
  return '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.${d.year}';
}

/// Druck-/PDF-Vorschau einer Übergriffsmeldung
class UebergriffsmeldungDruckScreen extends StatelessWidget {
  final Uebergriffsmeldung meldung;
  final VoidCallback onBack;

  const UebergriffsmeldungDruckScreen({
    super.key,
    required this.meldung,
    required this.onBack,
  });

  static String _str(String? s) => (s ?? '').trim().isEmpty ? '-' : (s ?? '').trim();
  static String _bool(bool? v) => v == null ? '-' : (v ? 'Ja' : 'Nein');

  Future<Uint8List> _buildPdf(PdfPageFormat format) async {
    final pdf = pw.Document();
    const fs = 8.0;
    const fsTitle = 11.0;

    pw.Widget infoRow(String l, String v) => pw.Padding(
          padding: const pw.EdgeInsets.only(bottom: 4),
          child: pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.SizedBox(width: 90, child: pw.Text('$l:', style: pw.TextStyle(fontSize: fs, fontWeight: pw.FontWeight.bold))),
              pw.Expanded(child: pw.Text(v, style: const pw.TextStyle(fontSize: fs))),
            ],
          ),
        );

    pw.Widget section(String title, List<pw.Widget> rows) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(title, style: pw.TextStyle(fontSize: fsTitle, fontWeight: pw.FontWeight.bold)),
            pw.SizedBox(height: 6),
            pw.Container(
              padding: const pw.EdgeInsets.all(10),
              decoration: pw.BoxDecoration(border: pw.Border.all(width: 0.5), borderRadius: pw.BorderRadius.circular(4)),
              child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: rows),
            ),
            pw.SizedBox(height: 12),
          ],
        );

    final children = <pw.Widget>[
      pw.Text('Uebergriffsmeldung', style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
      pw.SizedBox(height: 12),
      section('Einsatzdaten', [
        infoRow('Zusammenhang mit Einsatz', _bool(meldung.einsatzZusammenhang)),
      ]),
      section('Persoenliche Daten', [
        infoRow('Melder', _str(meldung.melderName)),
      ]),
      section('Ort und Zeitpunkt', [
        infoRow('Ort', _str(meldung.ort)),
        infoRow('Datum/Uhrzeit', _str(meldung.datumUhrzeit)),
      ]),
      section('Arten des Uebergriffs', [
        infoRow('Beleidigung', _str(meldung.beleidigungWortlaut)),
        infoRow('Bedrohung', _str(meldung.bedrohung)),
        infoRow('Bedrohung Beschreibung', _str(meldung.bedrohungBeschreibung)),
        infoRow('Sachbeschaedigung', _str(meldung.sachbeschaedigung)),
        infoRow('Koerperliche Gewalt', _str(meldung.koerperlicheGewalt)),
        infoRow('Koerperliche Gewalt Beschreibung', _str(meldung.koerperlicheGewaltBeschreibung)),
        infoRow('Sonstiges', _str(meldung.sonstiges)),
      ]),
      section('Weitere Angaben', [
        infoRow('Polizeilich registriert', _bool(meldung.polizeilichRegistriert)),
        infoRow('Zeugen Kollegen', _str(meldung.zeugenKollegen)),
        infoRow('Zeugen andere', _str(meldung.zeugenAndere)),
      ]),
      pw.Text('Tatverdaechtige', style: pw.TextStyle(fontSize: fsTitle, fontWeight: pw.FontWeight.bold)),
      pw.SizedBox(height: 4),
      pw.Text('Anzahl: ${meldung.anzahlTatverdaechtige}', style: const pw.TextStyle(fontSize: fs)),
      pw.Text('Wahrnehmung: ${_str(meldung.tatverdaechtigWahrnehmung)}', style: const pw.TextStyle(fontSize: fs)),
      pw.Text('Auffaelligkeiten: ${_str(meldung.auffaelligkeitenAllgemein)}', style: const pw.TextStyle(fontSize: fs)),
      pw.SizedBox(height: 8),
      ...meldung.tatverdaechtigePersonen.asMap().entries.map((e) {
        final i = e.key + 1;
        final p = e.value;
        return pw.Container(
          margin: const pw.EdgeInsets.only(bottom: 8),
          padding: const pw.EdgeInsets.all(8),
          decoration: pw.BoxDecoration(border: pw.Border.all(width: 0.5), borderRadius: pw.BorderRadius.circular(4)),
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text('Person $i', style: pw.TextStyle(fontSize: fs, fontWeight: pw.FontWeight.bold)),
              infoRow('Daten', _str(p.persoenlicheDaten)),
              infoRow('Auffaelligkeiten', _str(p.auffaelligkeiten)),
              infoRow('Art', _str(p.artDesUebergriffs)),
            ],
          ),
        );
      }),
      pw.SizedBox(height: 12),
      pw.Text('Beschreibung', style: pw.TextStyle(fontSize: fsTitle, fontWeight: pw.FontWeight.bold)),
      pw.SizedBox(height: 4),
      pw.Container(
        width: double.infinity,
        padding: const pw.EdgeInsets.all(10),
        decoration: pw.BoxDecoration(border: pw.Border.all(width: 0.5), borderRadius: pw.BorderRadius.circular(4)),
        child: pw.Text(_str(meldung.beschreibung), style: const pw.TextStyle(fontSize: fs)),
      ),
      pw.SizedBox(height: 8),
      pw.Text('Weitere Hinweise: ${_str(meldung.weitereHinweise)}', style: const pw.TextStyle(fontSize: fs)),
      pw.SizedBox(height: 12),
      pw.Text('Erstellt von: ${_str(meldung.createdByName)} - ${_formatDate(meldung.createdAt)}', style: const pw.TextStyle(fontSize: fs - 1)),
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
    final datumPart = (meldung.datumUhrzeit ?? '').split(' ').first.replaceAll('.', '-');
    final pdfName = 'Uebergriffsmeldung_${datumPart}_${meldung.id}.pdf';

    return Scaffold(
      backgroundColor: Colors.grey.shade200,
      appBar: AppTheme.buildModuleAppBar(
        title: 'Übergriffsmeldung drucken',
        onBack: onBack,
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
