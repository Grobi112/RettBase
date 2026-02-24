import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../theme/app_theme.dart';
import '../services/einsatzprotokoll_nfs_service.dart';

String _str(dynamic v) {
  final s = (v == null || v.toString().trim().isEmpty) ? '-' : v.toString().trim();
  if (s == '-') return s;
  return s
      .replaceAll(RegExp(r'[\u2013\u2014]'), '-')
      .replaceAll(RegExp(r'[\u2022\u2610\u2611\u2612\u2713\u2714]'), '-')
      .replaceAll('\uFFFD', '-');
}

String _formatEinsatzindikation(String? v) {
  if (v == null || v.isEmpty) return '-';
  const map = {
    'utn': 'ÜTN - Überbringen Todesnachricht',
    'haeuslicher_todesfall': 'häuslicher Todesfall / akute Erkrankung',
    'frustrane_reanimation': 'frustrane Reanimation',
    'suizid': 'Suizid',
    'verkehrsunfall': 'Verkehrsunfall',
    'arbeitsunfall': 'Arbeitsunfall',
    'schuleinsatz': 'Schuleinsatz',
    'brand_explosion_unwetter': 'Brand / Explosion / Unwetter',
    'gewalt_verbrechen': 'Gewalttat / Verbrechen',
    'grosse_einsatzlage': 'Große Einsatzlage',
    'ploetzlicher_kindstod': 'plötzlicher Kindstod',
    'sonstiges': 'sonstiges',
  };
  return map[v] ?? v;
}

String _formatWeitereBetreuung(String? v) {
  if (v == null || v.isEmpty) return '-';
  const map = {
    'angehoerige': 'Angehörige',
    'freunde_nachbarn': 'Freunde / Nachbarn',
    'sonstige_fachdienste': 'sonstige Fachdienste',
    'sonstiges': 'sonstiges',
  };
  return map[v] ?? v;
}

String _formatEinsatznachbesprechung(String? v) {
  if (v == null || v.isEmpty) return '-';
  return v == 'sonstiges' ? 'sonstiges' : v;
}

/// PDF-Vorschau eines NFS-Einsatzprotokolls – kompakt auf DIN A4
class EinsatzprotokollNfsDruckScreen extends StatelessWidget {
  final String companyId;
  final String protokollId;
  final Map<String, dynamic> protokoll;
  final String userRole;
  final VoidCallback onBack;

  const EinsatzprotokollNfsDruckScreen({
    super.key,
    required this.companyId,
    required this.protokollId,
    required this.protokoll,
    required this.userRole,
    required this.onBack,
  });

  bool get _canDelete {
    final r = userRole.toLowerCase().trim();
    return r == 'superadmin' || r == 'admin';
  }

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
    const fs = 7.0;
    const fsTitle = 8.0;

    final styleBase = roboto != null ? pw.TextStyle(font: roboto, fontSize: fs) : const pw.TextStyle(fontSize: fs);
    final styleBaseGrey = roboto != null ? pw.TextStyle(font: roboto, fontSize: fs, color: PdfColors.grey700) : pw.TextStyle(fontSize: fs, color: PdfColors.grey700);
    final styleBold = roboto != null ? pw.TextStyle(font: roboto, fontSize: fs, fontWeight: pw.FontWeight.bold) : pw.TextStyle(fontSize: fs, fontWeight: pw.FontWeight.bold);
    final styleTitle = roboto != null ? pw.TextStyle(font: roboto, fontSize: fsTitle, fontWeight: pw.FontWeight.bold) : pw.TextStyle(fontSize: fsTitle, fontWeight: pw.FontWeight.bold);
    final styleHeader = roboto != null ? pw.TextStyle(font: roboto, fontSize: 10, fontWeight: pw.FontWeight.bold) : pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold);

    const labelW = 75.0;
    pw.Widget field(String label, String value, {double? labelWidth}) => pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 2),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.SizedBox(width: labelWidth ?? labelW, child: pw.Text('$label:', style: styleBaseGrey)),
          pw.Expanded(child: pw.Text(value, style: styleBase)),
        ],
      ),
    );

    pw.Widget sectionHeader(String title) => pw.Container(
      width: double.infinity,
      padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      decoration: pw.BoxDecoration(
        color: PdfColors.white,
        border: pw.Border.all(color: PdfColors.black, width: 0.8),
      ),
      child: pw.Text(title, style: styleTitle),
    );

    pw.Widget section(String title, List<pw.Widget> children) => pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: [
        sectionHeader(title),
        pw.Padding(
          padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 2),
          child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: children),
        ),
        pw.SizedBox(height: 2),
      ],
    );

    pw.Widget textBlock(String label, String value) => pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 2),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text('$label:', style: styleBaseGrey),
          pw.SizedBox(height: 1),
          pw.Paragraph(text: value, style: styleBase),
        ],
      ),
    );

    pw.Widget sectionWithFlow(String title, List<pw.Widget> children) => pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      mainAxisSize: pw.MainAxisSize.min,
      children: [
        sectionHeader(title),
        pw.Padding(
          padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 2),
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            mainAxisSize: pw.MainAxisSize.min,
            children: children,
          ),
        ),
        pw.SizedBox(height: 2),
      ],
    );

    final children = <pw.Widget>[
      pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text('Einsatzprotokoll Notfallseelsorge', style: styleHeader),
          pw.Text(companyName.isEmpty ? '-' : _str(companyName), style: styleHeader),
        ],
      ),
      pw.SizedBox(height: 4),
      sectionWithFlow('Einsatzdaten', [
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Expanded(
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  field('Laufende interne Nr.', _str(p['laufendeInterneNr'])),
                  field('Vor- und Nachname', _str(p['name'])),
                  field('Alarmierung durch', () {
                    final parts = <String>[];
                    if (p['alarmierungKoordinator'] == true) parts.add('Koordinator');
                    if (p['alarmierungSonstige'] == true) parts.add('sonstige');
                    return parts.isEmpty ? '-' : parts.join(', ');
                  }()),
                  field('Einsatzindikation', _formatEinsatzindikation(p['einsatzindikation'])),
                  field('Einsatz im', () {
                    final parts = <String>[];
                    if (p['einsatzOeffentlich'] == true) parts.add('öffentlicher Bereich');
                    if (p['einsatzPrivat'] == true) parts.add('privater Bereich');
                    return parts.isEmpty ? '-' : parts.join(', ');
                  }()),
                  field('NFS nachalarmiert', p['nfsNachalarmiertJa'] == true
                      ? (_str(p['nfsNachalarmiertNamen']) == '-'
                          ? 'Ja'
                          : 'Ja (${_str(p['nfsNachalarmiertNamen'])})')
                      : 'Nein'),
                ],
              ),
            ),
            pw.SizedBox(width: 12),
            pw.Expanded(
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  field('Einsatz-Datum', _str(p['einsatzDatum'])),
                  field('Einsatz-Nr.', _str(p['einsatzNr'])),
                  field('Alarmierungszeit', _str(p['alarmierungszeit']) == '-' ? '-' : '${_str(p['alarmierungszeit'])} Uhr'),
                  field('Eintreffen vor Ort', _str(p['eintreffenTime']) == '-' ? '-' : '${_str(p['eintreffenTime'])} Uhr'),
                  field('Abfahrt vom Einsatzort', _str(p['abfahrtTime']) == '-' ? '-' : '${_str(p['abfahrtTime'])} Uhr'),
                  field('Einsatzende', _str(p['einsatzendeTime']) == '-' ? '-' : '${_str(p['einsatzendeTime'])} Uhr'),
                  field('Einsatzdauer (HH.MM)', _str(p['einsatzdauer']) == '-' ? '-' : '${_str(p['einsatzdauer'])}'),
                  field('Gefahrene KM', _str(p['gefahreneKm'])),
                ],
              ),
            ),
          ],
        ),
      ]),
      sectionWithFlow('Einsatzbericht', [
        textBlock('Situation vor Ort', _str(p['situationVorOrt'])),
        textBlock('Meine Rolle / Aufgabe', _str(p['meineRolleAufgabe'])),
      ]),
      sectionWithFlow('Einsatzverlauf', [
        textBlock('Verlauf der Begleitung', _str(p['verlaufBegleitung'])),
        field('Weitere Betreuung durch', p['weitereBetreuungDurch'] == 'sonstiges'
            ? _str(p['weitereBetreuungSonstiges'])
            : _formatWeitereBetreuung(p['weitereBetreuungDurch'])),
        textBlock('Situation am Ende vor Ort', _str(p['situationAmEnde'])),
        field('Wurden weitere Dienste in den Einsatz einbezogen', p['weitereDiensteJa'] == true
            ? (_str(p['weitereDiensteNamen']) == '-'
                ? 'Ja'
                : 'Ja (${_str(p['weitereDiensteNamen'])})')
            : (p['weitereDiensteNein'] == true
                ? 'Nein'
                : _str(p['weitereDienste']))),
      ]),
      sectionWithFlow('Sonstiges', [
        textBlock('Was ist interessant für eine Fallbesprechung?', _str(p['fallbesprechung'])),
        field('Einsatznachbesprechung gewünscht', p['einsatznachbesprechungGewuenscht'] == 'sonstiges'
            ? _str(p['einsatznachbesprechungSonstiges'])
            : _formatEinsatznachbesprechung(p['einsatznachbesprechungGewuenscht']), labelWidth: 95),
      ]),
      pw.SizedBox(height: 4),
    ];

    pdf.addPage(
      pw.MultiPage(
        pageFormat: format,
        margin: const pw.EdgeInsets.all(14),
        header: (ctx) {
          if (ctx.pageNumber > 1) {
            return pw.Container(
              alignment: pw.Alignment.centerRight,
              margin: const pw.EdgeInsets.only(bottom: 6),
              child: pw.Text(
                'Einsatzprotokoll Notfallseelsorge (Fortsetzung)',
                style: styleBaseGrey,
              ),
            );
          }
          return pw.SizedBox.shrink();
        },
        build: (_) => children,
      ),
    );

    return pdf.save();
  }

  Future<void> _confirmDelete(BuildContext context, EinsatzprotokollNfsService service) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Protokoll löschen?'),
        content: Text('Möchten Sie Protokoll Nr. ${_str(protokoll['einsatzNr'])} wirklich unwiderruflich löschen?'),
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
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Protokoll Nr. ${_str(protokoll['einsatzNr'])} wurde gelöscht.')));
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
    final pdfName = 'Einsatzprotokoll_NFS_${_str(protokoll['einsatzNr'])}.pdf';
    final service = EinsatzprotokollNfsService();

    return Scaffold(
      backgroundColor: Colors.grey.shade200,
      appBar: AppTheme.buildModuleAppBar(
        title: 'Protokoll ${_str(protokoll['einsatzNr'])}',
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
          if (_canDelete)
            IconButton(
              icon: Icon(Icons.delete_outline, color: Colors.red[700]),
              tooltip: 'Protokoll löschen',
              onPressed: () => _confirmDelete(context, service),
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
        loadingWidget: const Center(child: CircularProgressIndicator(color: AppTheme.primary)),
      ),
    );
  }
}
