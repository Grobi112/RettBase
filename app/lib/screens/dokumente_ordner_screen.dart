import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:url_launcher/url_launcher.dart';
import '../theme/app_theme.dart';
import '../models/dokumente_model.dart';
import '../services/dokumente_service.dart';
import '../services/auth_data_service.dart';
import '../services/auth_service.dart';

String _formatDate(DateTime d) {
  final day = d.day.toString().padLeft(2, '0');
  final mon = d.month.toString().padLeft(2, '0');
  return '$day.$mon.${d.year}';
}

/// Inhalt eines Ordners: Unterordner, Dokumente, Upload
class DokumenteOrdnerScreen extends StatefulWidget {
  final String companyId;
  final DokumenteOrdner folder;
  final List<DokumenteOrdner> breadcrumbs;
  final String? userRole;
  final VoidCallback? onBack;

  const DokumenteOrdnerScreen({
    super.key,
    required this.companyId,
    required this.folder,
    required this.breadcrumbs,
    this.userRole,
    this.onBack,
  });

  @override
  State<DokumenteOrdnerScreen> createState() => _DokumenteOrdnerScreenState();
}

class _DokumenteOrdnerScreenState extends State<DokumenteOrdnerScreen> {
  final _service = DokumenteService();
  final _authService = AuthService();
  final _authDataService = AuthDataService();

  List<DokumenteOrdner> _ordner = [];
  List<DokumenteDatei> _dokumente = [];
  Map<String, bool> _gelesen = {};
  bool _loading = true;
  bool _uploading = false;
  String? _currentUserId;

  @override
  void initState() {
    super.initState();
    _loadUser();
    _load();
  }

  Future<void> _loadUser() async {
    final user = _authService.currentUser;
    if (user != null) setState(() => _currentUserId = user.uid);
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final allOrdner = await _service.loadOrdner(widget.companyId);
      final docs = await _service.loadDokumente(widget.companyId, widget.folder.id);
      final gelesen = <String, bool>{};
      if (_currentUserId != null) {
        for (final d in docs.where((x) => x.lesebestaetigungNoetig)) {
          gelesen[d.id] = await _service.hasUserRead(widget.companyId, d.id, _currentUserId!);
        }
      }
      if (mounted) {
        setState(() {
          _ordner = allOrdner;
          _dokumente = docs;
          _gelesen = gelesen;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _navigateToParent() {
    if (widget.breadcrumbs.length <= 1) {
      if (widget.onBack != null) {
        widget.onBack!();
      } else {
        Navigator.of(context).pop();
      }
    } else {
      final parent = widget.breadcrumbs[widget.breadcrumbs.length - 2];
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => DokumenteOrdnerScreen(
            companyId: widget.companyId,
            folder: parent,
            breadcrumbs: widget.breadcrumbs.sublist(0, widget.breadcrumbs.length - 1),
            userRole: widget.userRole,
            onBack: widget.onBack,
          ),
        ),
      );
    }
  }

  void _openSubfolder(DokumenteOrdner sub) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => DokumenteOrdnerScreen(
          companyId: widget.companyId,
          folder: sub,
          breadcrumbs: [...widget.breadcrumbs, sub],
          userRole: widget.userRole,
          onBack: widget.onBack,
        ),
      ),
    ).then((_) => _load());
  }

  Future<void> _uploadDocument() async {
    final user = _authService.currentUser;
    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Nicht angemeldet.')));
      return;
    }
    final authData = await _authDataService.getAuthData(user.uid, user.email ?? '', widget.companyId);
    final displayName = authData.displayName ?? user.email ?? 'Unbekannt';

    if (!mounted) return;
    final res = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (ctx) => _UploadDialog(
        onUpload: (file, priority, lesebestaetigungNoetig) async {
          setState(() => _uploading = true);
          try {
            await _service.uploadDokument(
              companyId: widget.companyId,
              folderId: widget.folder.id,
              file: file,
              priority: priority,
              lesebestaetigungNoetig: lesebestaetigungNoetig,
              createdBy: user.uid,
              createdByName: displayName,
            );
            if (mounted) {
              setState(() => _uploading = false);
              _load();
              Navigator.of(ctx).pop();
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Dokument hochgeladen.')));
            }
          } catch (e) {
            if (mounted) {
              setState(() => _uploading = false);
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Fehler: $e')));
            }
          }
        },
      ),
    );
    if (res != null && mounted) _load();
  }

  Future<void> _openDocument(DokumenteDatei doc) async {
    final uri = Uri.parse(doc.fileUrl);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (doc.lesebestaetigungNoetig && _currentUserId != null && !(_gelesen[doc.id] ?? false)) {
        await _service.markAsRead(widget.companyId, doc.id, _currentUserId!);
        setState(() => _gelesen[doc.id] = true);
      }
    }
  }

  Future<void> _markAsRead(DokumenteDatei doc) async {
    if (_currentUserId == null) return;
    await _service.markAsRead(widget.companyId, doc.id, _currentUserId!);
    setState(() => _gelesen[doc.id] = true);
  }

  @override
  Widget build(BuildContext context) {
    final subFolders = _service.getChildFolders(_ordner, widget.folder.id);

    return Scaffold(
      backgroundColor: AppTheme.surfaceBg,
      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: AppTheme.primary,
        elevation: 1,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            if (widget.breadcrumbs.length <= 1) {
              if (widget.onBack != null) {
                widget.onBack!();
              } else {
                Navigator.of(context).pop();
              }
            } else {
              _navigateToParent();
            }
          },
        ),
        title: Text(widget.folder.name, style: TextStyle(color: AppTheme.primary, fontWeight: FontWeight.w600)),
        actions: [
          IconButton(
            icon: _uploading ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.primary)) : const Icon(Icons.upload_file),
            tooltip: 'Dokument hochladen',
            onPressed: _uploading ? null : _uploadDocument,
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppTheme.primary))
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  color: Colors.grey[200],
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  child: Row(
                    children: [
                      InkWell(
                        onTap: _navigateToParent,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.folder, color: Colors.grey[600], size: 20),
                            const SizedBox(width: 8),
                            Text('Zurück', style: TextStyle(color: AppTheme.textSecondary, fontSize: 14)),
                          ],
                        ),
                      ),
                      ...widget.breadcrumbs.asMap().entries.map((e) {
                        if (e.key == 0) return const SizedBox.shrink();
                        return Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(' / ', style: TextStyle(color: Colors.grey[600])),
                            Text(e.value.name, style: TextStyle(color: AppTheme.textPrimary, fontSize: 14)),
                          ],
                        );
                      }),
                    ],
                  ),
                ),
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      ...subFolders.map((f) => Card(
                            margin: const EdgeInsets.only(bottom: 12),
                            child: ListTile(
                              leading: Icon(Icons.folder, color: Colors.amber[700]),
                              title: Text(f.name, style: TextStyle(fontWeight: FontWeight.w500)),
                              trailing: const Icon(Icons.chevron_right),
                              onTap: () => _openSubfolder(f),
                            ),
                          )),
                      ..._dokumente.map((d) => _buildDokumentRow(d)),
                    ],
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildDokumentRow(DokumenteDatei d) {
    final isPdf = d.name.toLowerCase().endsWith('.pdf');
    final icon = isPdf ? Icons.picture_as_pdf : Icons.description;
    final priorityStyle = _getPriorityStyle(d.priority);
    final hasRead = _gelesen[d.id] ?? false;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        leading: Icon(icon, color: isPdf ? Colors.red : Colors.blue),
        title: GestureDetector(
          onTap: () => _openDocument(d),
          child: Text(
            d.name,
            style: TextStyle(color: Colors.blue, fontWeight: FontWeight.w500, decoration: TextDecoration.none),
          ),
        ),
        subtitle: Text(
          '${d.createdByName} (${_formatDate(d.createdAt)})',
          style: TextStyle(fontSize: 12, color: AppTheme.textMuted),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: priorityStyle.color,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                _priorityLabel(d.priority),
                style: TextStyle(fontSize: 12, color: priorityStyle.textColor, fontWeight: FontWeight.w500),
              ),
            ),
            const SizedBox(width: 8),
            if (d.lesebestaetigungNoetig)
              hasRead
                  ? Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.check_circle, color: Colors.green[600], size: 20),
                        const SizedBox(width: 4),
                        Text('gelesen', style: TextStyle(fontSize: 12, color: Colors.green[600])),
                      ],
                    )
                  : InkWell(
                      onTap: () => _markAsRead(d),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.radio_button_unchecked, color: Colors.grey[600], size: 20),
                          const SizedBox(width: 4),
                          Text('Als gelesen markieren', style: TextStyle(fontSize: 12, color: Colors.grey[600])),
                        ],
                      ),
                    ),
          ],
        ),
        isThreeLine: true,
        onTap: () => _openDocument(d),
      ),
    );
  }

  ({Color color, Color textColor}) _getPriorityStyle(String p) {
    switch (p) {
      case 'wichtig':
        return (color: Colors.red, textColor: Colors.white);
      case 'mittel':
        return (color: Colors.amber, textColor: Colors.black);
      case 'niedrig':
        return (color: Colors.green, textColor: Colors.white);
      default:
        return (color: Colors.grey, textColor: Colors.white);
    }
  }

  String _priorityLabel(String p) {
    switch (p) {
      case 'wichtig': return 'wichtig';
      case 'mittel': return 'mittel';
      case 'niedrig': return 'niedrig';
      default: return p;
    }
  }
}

typedef _UploadCallback = Future<void> Function(File file, String priority, bool lesebestaetigungNoetig);

class _UploadDialog extends StatefulWidget {
  final _UploadCallback onUpload;

  const _UploadDialog({required this.onUpload});

  @override
  State<_UploadDialog> createState() => _UploadDialogState();
}

class _UploadDialogState extends State<_UploadDialog> {
  File? _selectedFile;
  String _priority = 'mittel';
  bool _lesebestaetigungNoetig = false;
  bool _uploading = false;

  Future<void> _pickFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf', 'doc', 'docx'],
      allowMultiple: false,
    );
    if (result == null || result.files.isEmpty || result.files.single.path == null) return;
    if (mounted) setState(() => _selectedFile = File(result.files.single.path!));
  }

  Future<void> _doUpload() async {
    final file = _selectedFile;
    if (file == null) return;
    setState(() => _uploading = true);
    await widget.onUpload(file, _priority, _lesebestaetigungNoetig);
    if (mounted) setState(() => _uploading = false);
  }

  @override
  Widget build(BuildContext context) {
    final fileName = _selectedFile?.path.split(RegExp(r'[/\\]')).last ?? '';

    final width = MediaQuery.of(context).size.width;
    final dialogWidth = (width * 0.92).clamp(440.0, 600.0);

    return AlertDialog(
      title: const Text('Dokument hochladen'),
      contentPadding: const EdgeInsets.fromLTRB(28, 24, 28, 28),
      content: SingleChildScrollView(
        child: SizedBox(
          width: dialogWidth,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Datei', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppTheme.primary)),
              const SizedBox(height: 8),
              GestureDetector(
                onTap: _uploading ? null : _pickFile,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
                  decoration: BoxDecoration(
                    color: Colors.grey[100],
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: _selectedFile != null ? AppTheme.primary : Colors.grey[400]!, width: 1.5),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.upload_file, color: _selectedFile != null ? AppTheme.primary : Colors.grey[600], size: 36),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _selectedFile != null ? fileName : 'Tippen zum Durchsuchen oder Datei hierher ziehen',
                              style: TextStyle(
                                fontSize: 14,
                                color: _selectedFile != null ? AppTheme.textPrimary : AppTheme.textSecondary,
                                fontWeight: _selectedFile != null ? FontWeight.w500 : FontWeight.normal,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            if (_selectedFile != null)
                              Text('Tippen für andere Datei', style: TextStyle(fontSize: 12, color: AppTheme.textMuted)),
                          ],
                        ),
                      ),
                      if (_selectedFile != null)
                        IconButton(
                          icon: const Icon(Icons.close, size: 20),
                          onPressed: _uploading ? null : () => setState(() => _selectedFile = null),
                          tooltip: 'Datei entfernen',
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 20),
              DropdownButtonFormField<String>(
                value: _priority,
                decoration: const InputDecoration(labelText: 'Priorität', border: OutlineInputBorder()),
                items: const [
                  DropdownMenuItem(value: 'wichtig', child: Text('wichtig')),
                  DropdownMenuItem(value: 'mittel', child: Text('mittel')),
                  DropdownMenuItem(value: 'niedrig', child: Text('niedrig')),
                ],
                onChanged: _uploading ? null : (v) => setState(() => _priority = v ?? _priority),
              ),
              const SizedBox(height: 12),
              CheckboxListTile(
                value: _lesebestaetigungNoetig,
                onChanged: _uploading ? null : (v) => setState(() => _lesebestaetigungNoetig = v ?? false),
                title: const Text('Lesebestätigung nötig?'),
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _uploading ? null : () => Navigator.of(context).pop(),
          child: const Text('Abbrechen'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: AppTheme.primary),
          onPressed: (_selectedFile != null && !_uploading) ? _doUpload : null,
          child: _uploading
              ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : const Text('Hochladen'),
        ),
      ],
    );
  }
}
