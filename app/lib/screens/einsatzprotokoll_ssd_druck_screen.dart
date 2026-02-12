import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../theme/app_theme.dart';
import '../services/einsatzprotokoll_ssd_service.dart';

String _str(dynamic v) {
  final s = (v == null || v.toString().trim().isEmpty) ? '-' : v.toString().trim();
  if (s == '-') return s;
  return s.replaceAll(RegExp(r'[\u2610\u2612\u2713\u2714]'), '-').replaceAll('\u2013', '-');
}

String _formatUebergabe(String v) {
  if (v.isEmpty || v == '-') return '-';
  switch (v) {
    case 'zurueck_unterricht': return 'zurück in den Unterricht';
    case 'eltern': return 'Eltern';
    case 'rettungsdienst': return 'Rettungsdienst';
    default: return v;
  }
}

/// Druck-/PDF-Vorschau eines Einsatzprotokolls – gleiche Formatierung wie Eingabefelder,
/// mit Figur, Unterschriften, sofort druckbar.
class EinsatzprotokollSsdDruckScreen extends StatelessWidget {
  final String companyId;
  final String protokollId;
  final Map<String, dynamic> protokoll;
  final String userRole;
  final VoidCallback onBack;

  const EinsatzprotokollSsdDruckScreen({
    super.key,
    required this.companyId,
    required this.protokollId,
    required this.protokoll,
    required this.userRole,
    required this.onBack,
  });

  bool get _isSuperadmin => (userRole).toLowerCase().trim() == 'superadmin';

  Future<Uint8List> _buildPdf(PdfPageFormat format) async {
    final p = protokoll;
    pw.Font? roboto;
    try {
      final robotoData = await rootBundle.load('fonts/Roboto-Regular.ttf');
      roboto = pw.Font.ttf(robotoData);
    } catch (_) {}
    final pdf = pw.Document(theme: roboto != null ? pw.ThemeData.withFont(base: roboto, bold: roboto) : null);
    String companyName = '';
    try {
      final doc = await FirebaseFirestore.instance.collection('kunden').doc(companyId).get();
      companyName = (doc.data()?['name'] ?? '').toString().trim();
    } catch (_) {}
    const fs = 8.0;
    const fsTitle = 9.0;

    final styleBase = roboto != null ? pw.TextStyle(font: roboto, fontSize: fs) : const pw.TextStyle(fontSize: fs);
    final styleBaseGrey = roboto != null ? pw.TextStyle(font: roboto, fontSize: fs, color: PdfColors.grey700) : pw.TextStyle(fontSize: fs, color: PdfColors.grey700);
    final styleBaseGrey600 = roboto != null ? pw.TextStyle(font: roboto, fontSize: fs, color: PdfColors.grey600) : pw.TextStyle(fontSize: fs, color: PdfColors.grey600);
    final styleSmallGrey = roboto != null ? pw.TextStyle(font: roboto, fontSize: fs - 1, color: PdfColors.grey700) : pw.TextStyle(fontSize: fs - 1, color: PdfColors.grey700);
    final styleBold = roboto != null ? pw.TextStyle(font: roboto, fontSize: fs, fontWeight: pw.FontWeight.bold) : pw.TextStyle(fontSize: fs, fontWeight: pw.FontWeight.bold);
    final styleTitle = roboto != null ? pw.TextStyle(font: roboto, fontSize: fsTitle, fontWeight: pw.FontWeight.bold, color: PdfColors.black) : pw.TextStyle(fontSize: fsTitle, fontWeight: pw.FontWeight.bold, color: PdfColors.black);
    final styleHeader = roboto != null ? pw.TextStyle(font: roboto, fontSize: 12, fontWeight: pw.FontWeight.bold) : pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold);

    const labelW = 95.0;
    pw.Widget field(String label, String value, {double? labelWidth}) {
      final w = labelWidth ?? labelW;
      return pw.Padding(
        padding: const pw.EdgeInsets.only(bottom: 3),
        child: pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.SizedBox(width: w, child: pw.Text('$label:', style: styleBaseGrey)),
            pw.Expanded(child: pw.Text(value, style: styleBase)),
          ],
        ),
      );
    }
    
    pw.Widget checkRow(List<({String label, bool value})> items) => pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 2),
      child: pw.Row(
        children: items.map((e) => pw.Expanded(
          child: pw.Text('${e.label}: ${e.value ? "Ja" : "-"}', style: styleBase),
        )).toList(),
      ),
    );

    pw.Widget checkLine(String label, bool value) => pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 2),
      child: pw.Text('$label: ${value ? "Ja" : "-"}', style: styleBase),
    );

    pw.Widget sectionHeader(String title) => pw.Container(
      width: double.infinity,
      padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: pw.BoxDecoration(
        color: PdfColors.white,
        border: pw.Border.all(color: PdfColors.black, width: 1),
      ),
      child: pw.Text(title, style: styleTitle),
    );

    pw.Widget section(String title, List<pw.Widget> children) => pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: [
        sectionHeader(title),
        pw.Padding(
          padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 4),
          child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: children),
        ),
        pw.SizedBox(height: 4),
      ],
    );

    // Körper-Skizze laden
    Uint8List? koerperImg;
    final koerperUrl = (p['koerperSkizzeUrl'] ?? '').toString().trim();
    if (koerperUrl.isNotEmpty) {
      try {
        final resp = await http.get(Uri.parse(koerperUrl));
        if (resp.statusCode == 200 && resp.bodyBytes.isNotEmpty) koerperImg = resp.bodyBytes;
      } catch (_) {}
    }

    // Unterschriften laden
    Uint8List? sig1Img;
    Uint8List? sig2Img;
    final sig1Url = (p['unterschriftUrl1'] ?? '').toString().trim();
    final sig2Url = (p['unterschriftUrl2'] ?? '').toString().trim();
    if (sig1Url.isNotEmpty) {
      try {
        final resp = await http.get(Uri.parse(sig1Url));
        if (resp.statusCode == 200 && resp.bodyBytes.isNotEmpty) sig1Img = resp.bodyBytes;
      } catch (_) {}
    }
    if (sig2Url.isNotEmpty) {
      try {
        final resp = await http.get(Uri.parse(sig2Url));
        if (resp.statusCode == 200 && resp.bodyBytes.isNotEmpty) sig2Img = resp.bodyBytes;
      } catch (_) {}
    }

    final children = <pw.Widget>[
      pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text('Einsatzprotokoll Schulsanitätsdienst', style: styleHeader),
          pw.Text(companyName.isEmpty ? '-' : companyName, style: styleHeader),
        ],
      ),
      pw.SizedBox(height: 8),
      section('Rettungstechnische Daten', [
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Expanded(child: field('Protokoll-Nr.', _str(p['protokollNr']))),
            pw.Row(
              mainAxisSize: pw.MainAxisSize.min,
              children: [
                pw.Text('Datum: ${_str(p['datumEinsatz'])}', style: styleBase),
                pw.SizedBox(width: 16),
                pw.Text('Uhrzeit: ${_str(p['uhrzeit'])} Uhr', style: styleBase),
              ],
            ),
          ],
        ),
        pw.Row(
          children: [
            pw.Expanded(child: field('Schulsanitäter/in 1', '${_str(p['vornameHelfer1'])} ${_str(p['nameHelfer1'])}')),
            pw.Expanded(child: field('Schulsanitäter/in 2', '${_str(p['vornameHelfer2'])} ${_str(p['nameHelfer2'])}')),
          ],
        ),
        field('Einsatzort', _str(p['einsatzort'])),
      ]),
      section('Patientendaten', [
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Expanded(
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  field('Vorname', _str(p['vornameErkrankter']), labelWidth: 60),
                  field('Name', _str(p['nameErkrankter']), labelWidth: 60),
                ],
              ),
            ),
            pw.SizedBox(width: 24),
            pw.Expanded(
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  field('Geburtsdatum', _str(p['geburtsdatum']), labelWidth: 60),
                  field('Klasse', _str(p['klasse']), labelWidth: 60),
                ],
              ),
            ),
          ],
        ),
      ]),
      section('Angaben zur Erkrankung/Verletzung', [
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Expanded(
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  if (p['erkrankung'] == true) ...[
                    checkLine('Erkrankung', true),
                    field('Art der Erkrankung', _str(p['artErkrankung']), labelWidth: 60),
                  ] else ...[
                    checkLine('Erkrankung', false),
                  ],
                  if (p['unfall'] == true) ...[
                    checkLine('Unfall', true),
                    field('Unfallort', _str(p['unfallOrt']), labelWidth: 60),
                  ] else ...[
                    checkLine('Unfall', false),
                  ],
                ],
              ),
            ),
            pw.SizedBox(width: 24),
            pw.Expanded(
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text('Was hat der Verletzte zum Unfallzeitpunkt gemacht:', style: styleBold),
                  pw.SizedBox(height: 2),
                  checkLine('Sportunterricht', p['sportunterricht'] == true),
                  checkLine('Sonstiger Unterricht', p['sonstigerUnterricht'] == true),
                  checkLine('Pause', p['pause'] == true),
                  checkLine('Schulweg', p['schulweg'] == true),
                  checkLine('Sonstiges', p['sonstigesAktivitaet'] == true),
                ],
              ),
            ),
          ],
        ),
        pw.SizedBox(height: 6),
        field('Schilderung', _str(p['schilderung'])),
      ]),
      section('Erstbefund', [
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Expanded(
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  field('Schmerzen', _str(p['schmerzen']), labelWidth: 60),
                  pw.SizedBox(height: 4),
                  pw.Text('Welche Verletzung liegt vermutlich vor:', style: styleBold),
                  pw.SizedBox(height: 2),
                  checkLine('Prellung', p['verletzungPrellung'] == true),
                  checkLine('Bruch', p['verletzungBruch'] == true),
                  checkLine('Wunde', p['verletzungWunde'] == true),
                  checkLine('Sonstiges', p['verletzungSonstiges'] == true),
                ],
              ),
            ),
            pw.SizedBox(width: 12),
            pw.Expanded(
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  if (koerperImg != null)
                    pw.Image(pw.MemoryImage(koerperImg), width: 100, height: 100, fit: pw.BoxFit.contain)
                  else
                    pw.SizedBox(width: 100, height: 100, child: pw.Center(child: pw.Text('-', style: styleBaseGrey600))),
                ],
              ),
            ),
            pw.SizedBox(width: 12),
            pw.Expanded(
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text('Atmung:', style: styleBold),
                  pw.SizedBox(height: 2),
                  checkLine('spontan / frei', p['atmungSpontan'] == true),
                  checkLine('Hyperventilation', p['atmungHyperventilation'] == true),
                  checkLine('Atemnot', p['atmungAtemnot'] == true),
                ],
              ),
            ),
            pw.SizedBox(width: 12),
            pw.Expanded(
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  field('Puls', _str(p['puls']), labelWidth: 65),
                  field('SpO2', _str(p['spo2']) == '-' ? '-' : '${_str(p['spo2'])} %', labelWidth: 65),
                  field('Blutdruck', _str(p['blutdruck']) == '-' ? '-' : '${_str(p['blutdruck'])} mmHg', labelWidth: 65),
                ],
              ),
            ),
          ],
        ),
        pw.SizedBox(height: 6),
        pw.Text('Der/die Erkrankte/Verletzte klagt über:', style: styleBold),
        pw.SizedBox(height: 2),
        pw.Text(_str(p['beschwerden']), style: styleBase),
      ]),
      section('Getroffene Maßnahmen', [
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Expanded(
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text('Maßnahmen:', style: styleBold),
                  pw.SizedBox(height: 2),
                  checkLine('Betreuung', p['massnahmeBetreuung'] == true),
                  checkLine('Pflaster', p['massnahmePflaster'] == true),
                  checkLine('Verband', p['massnahmeVerband'] == true),
                  checkLine('Kühlung', p['massnahmeKuehlung'] == true),
                  checkLine('Sonstiges', p['massnahmeSonstiges'] == true),
                  if (p['massnahmeSonstiges'] == true) field('  Sonstiges Angabe', _str(p['massnahmeSonstigesText'])),
                  checkLine('Elternbrief mitgegeben', p['elternbriefMitgegeben'] == true),
                  checkLine('Arztbesuch empfohlen', p['arztbesuchEmpfohlen'] == true),
                ],
              ),
            ),
            pw.SizedBox(width: 24),
            pw.Expanded(
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text('Informiert:', style: styleBold),
                  pw.SizedBox(height: 2),
                  checkLine('Sekretariat', p['sekretariatInformiert'] == true),
                  checkLine('Schulleitung', p['schulleitungInformiert'] == true),
                  checkLine('Lehrer', p['lehrerInformiert'] == true),
                  checkLine('Leiter SSD', p['leiterSSDInformiert'] == true),
                ],
              ),
            ),
            if (p['notruf'] == true || p['elternBenachrichtigt'] == true) ...[
              pw.SizedBox(width: 24),
              pw.Expanded(
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    if (p['notruf'] == true) field('Notruf abgesetzt um', _str(p['notrufZeitstempel'])),
                    if (p['elternBenachrichtigt'] == true) field('Eltern benachrichtigt um', _str(p['elternBenachrichtigtZeitstempel'])),
                  ],
                ),
              ),
            ],
          ],
        ),
        pw.SizedBox(height: 4),
        field('Verlaufsbeschreibung', _str(p['verlaufsbeschreibung'])),
      ]),
      section('Einsatzabschluss', [
        field('Übergabe an', _formatUebergabe(_str(p['uebergabeAn']))),
        pw.SizedBox(height: 12),
        pw.Row(
          children: [
            pw.Expanded(
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text('Schulsanitäter/in 1', style: styleBold),
                  pw.SizedBox(height: 2),
                  if (sig1Img != null)
                    pw.Image(pw.MemoryImage(sig1Img), height: 35, fit: pw.BoxFit.contain)
                  else
                    pw.SizedBox(height: 35, child: pw.Center(child: pw.Text('-', style: styleBaseGrey600))),
                ],
              ),
            ),
            pw.SizedBox(width: 12),
            pw.Expanded(
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text('Schulsanitäter/in 2', style: styleBold),
                  pw.SizedBox(height: 2),
                  if (sig2Img != null)
                    pw.Image(pw.MemoryImage(sig2Img), height: 35, fit: pw.BoxFit.contain)
                  else
                    pw.SizedBox(height: 35, child: pw.Center(child: pw.Text('-', style: styleBaseGrey600))),
                ],
              ),
            ),
          ],
        ),
        pw.SizedBox(height: 4),
        pw.Text('Erstellt von: ${_str(p['createdByName'])}', style: styleSmallGrey),
      ]),
    ];

    pdf.addPage(
      pw.MultiPage(
        pageFormat: format,
        margin: const pw.EdgeInsets.all(18),
        build: (_) => children,
      ),
    );

    return pdf.save();
  }

  Future<void> _editProtokollNr(BuildContext context, EinsatzprotokollSsdService service) async {
    final ctrl = TextEditingController(text: _str(protokoll['protokollNr']));
    const inputDecoration = InputDecoration(
      filled: true,
      fillColor: Colors.white,
      border: OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(10))),
      contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    );
    final newNr = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Einsatz-Nr. bearbeiten'),
        content: TextField(
          controller: ctrl,
          decoration: inputDecoration.copyWith(labelText: 'Einsatz-Nr. (z.B. 20260001)'),
          autofocus: true,
          onSubmitted: (v) => Navigator.of(ctx).pop(v.trim()),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Abbrechen')),
          FilledButton(onPressed: () => Navigator.of(ctx).pop(ctrl.text.trim()), child: const Text('Speichern')),
        ],
      ),
    );
    if (newNr == null || newNr.isEmpty || !context.mounted) return;
    try {
      await service.updateProtokollNr(companyId, protokollId, newNr);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Einsatz-Nr. wurde auf $newNr geändert.')));
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Fehler: $e'), backgroundColor: Colors.red));
      }
    }
  }

  Future<void> _confirmDelete(BuildContext context, EinsatzprotokollSsdService service) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Protokoll löschen?'),
        content: Text('Möchten Sie Protokoll Nr. ${_str(protokoll['protokollNr'])} wirklich unwiderruflich löschen?'),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Abbrechen')),
          FilledButton(style: FilledButton.styleFrom(backgroundColor: Colors.red), onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Löschen')),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    try {
      await service.delete(companyId, protokollId);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Protokoll Nr. ${_str(protokoll['protokollNr'])} wurde gelöscht.')));
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Fehler beim Löschen: $e'), backgroundColor: Colors.red));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final pdfName = 'Einsatzprotokoll_${_str(protokoll['protokollNr'])}.pdf';
    final service = EinsatzprotokollSsdService();

    return Scaffold(
      backgroundColor: Colors.grey.shade200,
      appBar: AppTheme.buildModuleAppBar(
        title: _isSuperadmin ? 'Protokoll ${_str(protokoll['protokollNr'])}' : null,
        titleWidget: _isSuperadmin
            ? null
            : Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Protokoll ${_str(protokoll['protokollNr'])}', style: TextStyle(color: AppTheme.primary, fontWeight: FontWeight.w600, fontSize: 18)),
                  Text('Nur Ansicht', style: TextStyle(fontSize: 12, fontWeight: FontWeight.normal, color: Colors.grey.shade600)),
                ],
              ),
        onBack: onBack,
        actions: [
          IconButton(
            icon: const Icon(Icons.print),
            tooltip: 'Drucken',
            onPressed: () async {
              await Printing.layoutPdf(onLayout: (format) => _buildPdf(format), name: pdfName);
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
          if (_isSuperadmin) ...[
            IconButton(icon: const Icon(Icons.edit), tooltip: 'Einsatz-Nr. bearbeiten', onPressed: () => _editProtokollNr(context, service)),
            IconButton(icon: Icon(Icons.delete_outline, color: Colors.red[700]), tooltip: 'Protokoll löschen', onPressed: () => _confirmDelete(context, service)),
          ],
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
        loadingWidget: const Center(child: CircularProgressIndicator(color: AppTheme.primary)),
      ),
    );
  }
}
