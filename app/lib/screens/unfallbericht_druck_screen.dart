import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../models/unfallbericht_model.dart';
import '../theme/app_theme.dart';

/// Druck-/PDF-Vorschau für Unfallbericht – DIN A4, gerichtstauglich
/// Unterstützt ungespeicherte Formulardaten (unterschriftBytes, bilderBytes).
class UnfallberichtDruckScreen extends StatelessWidget {
  final Unfallbericht bericht;
  final VoidCallback onBack;
  /// Optional: Unterschrift als Bytes (z.B. aus Formular vor dem Speichern)
  final Uint8List? unterschriftBytes;
  /// Optional: Bilder/Skizze als Bytes (Skizze zuerst, dann Fotos)
  final List<Uint8List>? bilderBytes;

  const UnfallberichtDruckScreen({
    super.key,
    required this.bericht,
    required this.onBack,
    this.unterschriftBytes,
    this.bilderBytes,
  });

  static String _fmt(DateTime? d) {
    if (d == null) return '';
    return '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.${d.year}';
  }

  static String _str(String? s) => s?.trim().isEmpty != false ? '' : (s ?? '');

  static String _bool(bool v) => v ? 'Ja' : 'Nein';

  Future<Uint8List> _buildPdf(PdfPageFormat format) async {
    final pdf = pw.Document();
    const fs = 9.0;
    const fsTitle = 11.0;
    const spacing = 6.0;

    pw.Widget _section(String title, List<pw.Widget> children) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(title, style: pw.TextStyle(fontSize: fsTitle, fontWeight: pw.FontWeight.bold)),
            pw.SizedBox(height: 4),
            ...children,
            pw.SizedBox(height: spacing),
          ],
        );

    pw.Widget _row(String label, String value) => pw.Padding(
          padding: const pw.EdgeInsets.only(bottom: 2),
          child: pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.SizedBox(width: 140, child: pw.Text('$label:', style: const pw.TextStyle(fontSize: fs))),
              pw.Expanded(child: pw.Text(value, style: const pw.TextStyle(fontSize: fs))),
            ],
          ),
        );

    // Seite 1: Stammdaten – alle Felder immer sichtbar
    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(28),
        build: (ctx) => [
          pw.Center(
            child: pw.Text('Unfallbericht', style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold)),
          ),
          pw.SizedBox(height: 16),
          _section('Eigenes Fahrzeug', [
            _row('Schadentag', _fmt(bericht.schadentag)),
            _row('Schadenuhrzeit', _str(bericht.schadenuhrzeit)),
            _row('Schadenort', _str(bericht.schadenort)),
            _row('Polizei am Unfallort', _bool(bericht.polizeiAmUnfallort)),
            _row('Dienststelle/Tagebuchnummer', _str(bericht.dienststelleTagebuchnummer)),
            _row('Kilometerstand', bericht.kilometerstand?.toString() ?? ''),
            _row('Fahrzeug', _str(bericht.fahrzeugDisplay)),
            _row('Anhänger Kennzeichen', _str(bericht.anhangerKennzeichen)),
            _row('Schadenhöhe', _str(bericht.schadenhoehe)),
            _row('Schaden (eigenes Fahrzeug)', _str(bericht.schadenEigenesFahrzeug)),
          ]),
          _section('Fahrer eigenes Fahrzeug', [
            _row('Vorname', _str(bericht.vornameFahrer)),
            _row('Nachname', _str(bericht.nachnameFahrer)),
            _row('Telefon', _str(bericht.telefonFahrer)),
            _row('Straße', _str(bericht.strasseFahrer)),
            _row('PLZ', _str(bericht.plzFahrer)),
            _row('Ort', _str(bericht.ortFahrer)),
            _row('Führerscheinklasse', _str(bericht.fuehrerscheinklasse)),
            _row('Ausstellungsdatum', _fmt(bericht.ausstellungsdatum)),
            _row('Behörde', _str(bericht.behoerde)),
            _row('Alkoholgenuss oder andere berauschende Mittel', _bool(bericht.alkoholgenuss)),
            _row('Blutprobe entnommen', _bool(bericht.blutprobeEntnommen)),
            _row('Blutprobe Ergebnis', _str(bericht.blutprobeErgebnis)),
          ]),
          _section('Gegnerisches Fahrzeug', [
            _row('Kennzeichen', _str(bericht.kennzeichenGegner)),
            _row('Versicherungsschein-Nr.', _str(bericht.versicherungsscheinNr)),
            _row('Geschätzte Schadenhöhe', _str(bericht.geschaetzteSchadenhoeheGegner)),
            _row('Schaden Gegner', _str(bericht.schadenGegner)),
          ]),
          _section('Fahrer gegnerisches Fahrzeug', [
            _row('Vorname', _str(bericht.vornameGegner)),
            _row('Nachname', _str(bericht.nachnameGegner)),
            _row('Telefon', _str(bericht.telefonGegner)),
            _row('Straße', _str(bericht.strasseGegner)),
            _row('PLZ', _str(bericht.plzGegner)),
            _row('Ort', _str(bericht.ortGegner)),
            _row('Kurze Schadenschilderung', _str(bericht.kurzeSchadenschilderung)),
          ]),
          _section('Fahrzeughalter', [
            _row('Vorname', _str(bericht.vornameFahrzeughalter)),
            _row('Nachname', _str(bericht.nachnameFahrzeughalter)),
            _row('Straße', _str(bericht.strasseFahrzeughalter)),
            _row('PLZ', _str(bericht.plzFahrzeughalter)),
            _row('Ort', _str(bericht.ortFahrzeughalter)),
          ]),
        ],
      ),
    );

    // Seite 2: Abschließend, Kurze Bemerkung, Ausführlicher Bericht, Unterschrift, Skizze, Fotos
    // Alle Abschnitte immer sichtbar
    final page2Children = <pw.Widget>[];

    page2Children.add(_section('Kurze Bemerkung', [
      pw.Text(_str(bericht.kurzeBemerkung), style: const pw.TextStyle(fontSize: fs)),
    ]));

    page2Children.add(_section('Ausführlicher Schadensbericht', [
      pw.Text(_str(bericht.ausfuehrlicherSchadensbericht), style: const pw.TextStyle(fontSize: fs)),
    ]));

    // Unterschrift – immer anzeigen (Bild oder Platzhalter)
    Uint8List? unterschriftImg;
    if (unterschriftBytes != null && unterschriftBytes!.isNotEmpty) {
      unterschriftImg = unterschriftBytes;
    } else if (bericht.unterschriftUrl != null && bericht.unterschriftUrl!.isNotEmpty) {
      try {
        final resp = await http.get(Uri.parse(bericht.unterschriftUrl!));
        if (resp.statusCode == 200 && resp.bodyBytes.isNotEmpty) unterschriftImg = resp.bodyBytes;
      } catch (_) {}
    }
    page2Children.add(_section('Unterschrift', [
      if (unterschriftImg != null)
        pw.Image(pw.MemoryImage(unterschriftImg), width: 180, height: 60, fit: pw.BoxFit.contain)
      else
        pw.Text('', style: const pw.TextStyle(fontSize: fs)),
    ]));

    // Skizze – immer anzeigen (Bild oder Platzhalter)
    page2Children.add(pw.Text('Skizze', style: pw.TextStyle(fontSize: fsTitle, fontWeight: pw.FontWeight.bold)));
    page2Children.add(pw.SizedBox(height: 4));
    bool skizzeAdded = false;
    if (bilderBytes != null && bilderBytes!.isNotEmpty) {
      page2Children.add(pw.Padding(
        padding: const pw.EdgeInsets.only(bottom: 8),
        child: pw.Image(pw.MemoryImage(bilderBytes!.first), width: 200, height: 150, fit: pw.BoxFit.contain),
      ));
      skizzeAdded = true;
    } else if (bericht.bilderDokumente.isNotEmpty) {
      try {
        final resp = await http.get(Uri.parse(bericht.bilderDokumente.first));
        if (resp.statusCode == 200 && resp.bodyBytes.isNotEmpty) {
          page2Children.add(pw.Padding(
            padding: const pw.EdgeInsets.only(bottom: 8),
            child: pw.Image(pw.MemoryImage(resp.bodyBytes), width: 200, height: 150, fit: pw.BoxFit.contain),
          ));
          skizzeAdded = true;
        }
      } catch (_) {}
    }
    if (!skizzeAdded) {
      page2Children.add(pw.Text('', style: const pw.TextStyle(fontSize: fs)));
    }
    page2Children.add(pw.SizedBox(height: spacing));

    // Weitere Anhänge (Fotos) – immer anzeigen
    page2Children.add(pw.Text('Weitere Anhänge (Fotos)', style: pw.TextStyle(fontSize: fsTitle, fontWeight: pw.FontWeight.bold)));
    page2Children.add(pw.SizedBox(height: 4));
    bool fotosAdded = false;
    if (bilderBytes != null && bilderBytes!.length > 1) {
      for (var i = 1; i < bilderBytes!.length && i - 1 < 5; i++) {
        page2Children.add(pw.Padding(
          padding: const pw.EdgeInsets.only(bottom: 8),
          child: pw.Image(pw.MemoryImage(bilderBytes![i]), width: 200, height: 150, fit: pw.BoxFit.contain),
        ));
        fotosAdded = true;
      }
    } else if (bericht.bilderDokumente.length > 1) {
      for (var i = 1; i < bericht.bilderDokumente.length && i - 1 < 5; i++) {
        try {
          final resp = await http.get(Uri.parse(bericht.bilderDokumente[i]));
          if (resp.statusCode == 200 && resp.bodyBytes.isNotEmpty) {
            page2Children.add(pw.Padding(
              padding: const pw.EdgeInsets.only(bottom: 8),
              child: pw.Image(pw.MemoryImage(resp.bodyBytes), width: 200, height: 150, fit: pw.BoxFit.contain),
            ));
            fotosAdded = true;
          }
        } catch (_) {}
      }
    }
    if (!fotosAdded) {
      page2Children.add(pw.Text('', style: const pw.TextStyle(fontSize: fs)));
    }
    page2Children.add(pw.SizedBox(height: spacing));

    if (page2Children.isNotEmpty) {
      pdf.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(28),
          build: (_) => page2Children,
        ),
      );
    }

    return pdf.save();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade200,
      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: AppTheme.primary,
        elevation: 1,
        leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: onBack),
        title: Text('Unfallbericht – Drucken / PDF', style: TextStyle(color: AppTheme.primary, fontWeight: FontWeight.w600)),
      ),
      body: PdfPreview(
        build: _buildPdf,
        allowPrinting: true,
        allowSharing: true,
        canChangePageFormat: false,
        canChangeOrientation: false,
        pdfFileName: 'Unfallbericht_${_fmt(bericht.schadentag)}_${bericht.fahrzeugDisplay ?? 'Unfall'}.pdf',
        loadingWidget: const Center(child: CircularProgressIndicator()),
      ),
    );
  }
}
