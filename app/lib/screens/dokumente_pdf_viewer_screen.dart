import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:internet_file/internet_file.dart';
import 'package:printing/printing.dart';
import '../theme/app_theme.dart';

/// Druckvorschau für PDF-Dokumente – zeigt PDF mit Druck- und Speichern-Optionen
class DokumentePdfViewerScreen extends StatefulWidget {
  final String title;
  final String fileUrl;
  final VoidCallback? onBack;
  final VoidCallback? onRead; // Lesebestätigung nach Anzeigen

  const DokumentePdfViewerScreen({
    super.key,
    required this.title,
    required this.fileUrl,
    this.onBack,
    this.onRead,
  });

  @override
  State<DokumentePdfViewerScreen> createState() => _DokumentePdfViewerScreenState();
}

class _DokumentePdfViewerScreenState extends State<DokumentePdfViewerScreen> {
  Uint8List? _bytes;
  String? _error;

  String get _pdfName =>
      widget.title.toLowerCase().endsWith('.pdf') ? widget.title : '${widget.title}.pdf';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final bytes = await InternetFile.get(widget.fileUrl);
      if (mounted) {
        setState(() {
          _bytes = bytes;
          _error = null;
        });
        widget.onRead?.call();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _bytes = null;
        });
      }
    }
  }

  Future<void> _printPdf() async {
    final bytes = _bytes;
    if (bytes == null) return;
    try {
      await Printing.layoutPdf(
        onLayout: (_) async => bytes,
        name: _pdfName,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Drucken fehlgeschlagen: $e')),
        );
      }
    }
  }

  Future<void> _sharePdf() async {
    final bytes = _bytes;
    if (bytes == null) return;
    try {
      await Printing.sharePdf(bytes: bytes, filename: _pdfName);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Speichern fehlgeschlagen: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade200,
      appBar: AppTheme.buildModuleAppBar(
        title: widget.title,
        onBack: widget.onBack ?? () => Navigator.of(context).pop(),
        actions: [
          if (_bytes != null) ...[
            IconButton(
              icon: const Icon(Icons.print),
              tooltip: 'Drucken',
              onPressed: _printPdf,
            ),
            IconButton(
              icon: const Icon(Icons.save),
              tooltip: 'Als PDF speichern',
              onPressed: _sharePdf,
            ),
          ],
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.error_outline, size: 48, color: Colors.grey[400]),
              const SizedBox(height: 16),
              Text(
                'PDF konnte nicht geladen werden.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey[600], fontSize: 16),
              ),
              const SizedBox(height: 8),
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey[500], fontSize: 12),
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: _load,
                child: const Text('Erneut laden'),
              ),
            ],
          ),
        ),
      );
    }

    if (_bytes == null) {
      return const Center(
        child: CircularProgressIndicator(color: AppTheme.primary),
      );
    }

    final bytes = _bytes!;
    return PdfPreview(
      build: (format) async => bytes,
      allowPrinting: false,
      allowSharing: false,
      useActions: false,
      canChangePageFormat: false,
      canChangeOrientation: false,
      canDebug: false,
      pdfFileName: _pdfName,
      loadingWidget: const Center(child: CircularProgressIndicator(color: AppTheme.primary)),
      onError: (_, __) => Center(
        child: Text(
          'PDF konnte nicht geladen werden.',
          style: TextStyle(color: Colors.grey[600]),
        ),
      ),
    );
  }
}
