import 'dart:typed_data';

import 'package:flutter/material.dart';
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
    final pdf = pw.Document();
    const fs = 8.0;
    const fsTitle = 9.0;

    const labelW = 95.0;
    pw.Widget field(String label, String value, {double? labelWidth}) {
      final w = labelWidth ?? labelW;
      return pw.Padding(
        padding: const pw.EdgeInsets.only(bottom: 3),
        child: pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.SizedBox(width: w, child: pw.Text('$label:', style: pw.TextStyle(fontSize: fs, color: PdfColors.grey700))),
            pw.Expanded(child: pw.Text(value, style: const pw.TextStyle(fontSize: fs))),
          ],
        ),
      );
    }
    
    pw.Widget checkRow(List<({String label, bool value})> items) => pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 2),
      child: pw.Row(
        children: items.map((e) => pw.Expanded(
          child: pw.Text('${e.label}: ${e.value ? "Ja" : "-"}', style: const pw.TextStyle(fontSize: fs)),
        )).toList(),
      ),
    );

    pw.Widget checkLine(String label, bool value) => pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 2),
      child: pw.Text('$label: ${value ? "Ja" : "-"}', style: const pw.TextStyle(fontSize: fs)),
    );

    pw.Widget sectionHeader(String title) => pw.Container(
      width: double.infinity,
      padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      color: PdfColors.blue900,
      child: pw.Text(title, style: pw.TextStyle(fontSize: fsTitle, fontWeight: pw.FontWeight.bold, color: PdfColors.white)),
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
      pw.Center(child: pw.Text('Einsatzprotokoll Schulsanitätsdienst', style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold))),
      pw.SizedBox(height: 8),
      section('Rettungstechnische Daten', [
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Expanded(child: field('Protokoll-Nr.', _str(p['protokollNr']))),
            pw.Row(
              mainAxisSize: pw.MainAxisSize.min,
              children: [
                pw.Text('Datum: ${_str(p['datumEinsatz'])}', style: const pw.TextStyle(fontSize: fs)),
                pw.SizedBox(width: 16),
                pw.Text('Uhrzeit: ${_str(p['uhrzeit'])} Uhr', style: const pw.TextStyle(fontSize: fs)),
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
          children: [
            pw.Expanded(child: field('Vorname', _str(p['vornameErkrankter']))),
            pw.Expanded(child: field('Name', _str(p['nameErkrankter']))),
            pw.Expanded(child: field('Geburtsdatum', _str(p['geburtsdatum']))),
            pw.Expanded(child: field('Klasse', _str(p['klasse']))),
          ],
        ),
      ]),
      section('Angaben zur Erkrankung/Verletzung', [
        checkRow([
          (label: 'Erkrankung', value: p['erkrankung'] == true),
          (label: 'Unfall', value: p['unfall'] == true),
        ]),
        if (p['erkrankung'] == true) field('Art der Erkrankung', _str(p['artErkrankung'])),
        if (p['unfall'] == true) field('Unfallort', _str(p['unfallOrt'])),
        checkRow([
          (label: 'Sportunterricht', value: p['sportunterricht'] == true),
          (label: 'Sonstiger Unterricht', value: p['sonstigerUnterricht'] == true),
          (label: 'Pause', value: p['pause'] == true),
          (label: 'Schulweg', value: p['schulweg'] == true),
          (label: 'Sonstiges', value: p['sonstigesAktivitaet'] == true),
        ]),
        field('Schilderung', _str(p['schilderung'])),
      ]),
      section('Erstbefund', [
        pw.Row(
          children: [
            pw.Expanded(child: field('Schmerzen', _str(p['schmerzen']))),
            pw.SizedBox(width: 8),
            if (koerperImg != null)
              pw.Image(pw.MemoryImage(koerperImg), width: 100, height: 100, fit: pw.BoxFit.contain)
            else
              pw.SizedBox(width: 100, height: 100, child: pw.Center(child: pw.Text('-', style: pw.TextStyle(fontSize: fs, color: PdfColors.grey600)))),
          ],
        ),
        checkRow([
          (label: 'Prellung', value: p['verletzungPrellung'] == true),
          (label: 'Bruch', value: p['verletzungBruch'] == true),
          (label: 'Wunde', value: p['verletzungWunde'] == true),
          (label: 'Sonstiges', value: p['verletzungSonstiges'] == true),
        ]),
        checkRow([
          (label: 'Atmung spontan', value: p['atmungSpontan'] == true),
          (label: 'Hyperventilation', value: p['atmungHyperventilation'] == true),
          (label: 'Atemnot', value: p['atmungAtemnot'] == true),
        ]),
        pw.Row(
          children: [
            pw.Expanded(child: field('Puls', _str(p['puls']))),
            pw.Expanded(child: field('SpO2', _str(p['spo2']))),
            pw.Expanded(child: field('Blutdruck', _str(p['blutdruck']))),
          ],
        ),
        field('Beschwerden', _str(p['beschwerden'])),
      ]),
      section('Getroffene Maßnahmen', [
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Expanded(
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text('Maßnahmen:', style: pw.TextStyle(fontSize: fs, fontWeight: pw.FontWeight.bold)),
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
                  pw.Text('Informiert:', style: pw.TextStyle(fontSize: fs, fontWeight: pw.FontWeight.bold)),
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
                  pw.Text('Schulsanitäter/in 1', style: pw.TextStyle(fontSize: fs, fontWeight: pw.FontWeight.bold)),
                  pw.SizedBox(height: 2),
                  if (sig1Img != null)
                    pw.Image(pw.MemoryImage(sig1Img), height: 35, fit: pw.BoxFit.contain)
                  else
                    pw.SizedBox(height: 35, child: pw.Center(child: pw.Text('-', style: pw.TextStyle(fontSize: fs, color: PdfColors.grey600)))),
                ],
              ),
            ),
            pw.SizedBox(width: 12),
            pw.Expanded(
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text('Schulsanitäter/in 2', style: pw.TextStyle(fontSize: fs, fontWeight: pw.FontWeight.bold)),
                  pw.SizedBox(height: 2),
                  if (sig2Img != null)
                    pw.Image(pw.MemoryImage(sig2Img), height: 35, fit: pw.BoxFit.contain)
                  else
                    pw.SizedBox(height: 35, child: pw.Center(child: pw.Text('-', style: pw.TextStyle(fontSize: fs, color: PdfColors.grey600)))),
                ],
              ),
            ),
          ],
        ),
        pw.SizedBox(height: 4),
        pw.Text('Erstellt von: ${_str(p['createdByName'])}', style: pw.TextStyle(fontSize: fs - 1, color: PdfColors.grey700)),
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
