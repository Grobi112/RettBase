import 'dart:io';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import '../theme/app_theme.dart';
import '../services/auth_service.dart';
import '../services/profile_service.dart';
import 'schnellstart_screen.dart';

/// Profil – bearbeitbare Felder inkl. Passbild und Adresse.
class ProfileScreen extends StatefulWidget {
  final String companyId;
  final VoidCallback? onBack;
  final VoidCallback? onSchnellstartChanged;
  final bool hideAppBar;

  const ProfileScreen({
    super.key,
    required this.companyId,
    this.onBack,
    this.onSchnellstartChanged,
    this.hideAppBar = false,
  });

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final _authService = AuthService();
  final _profileService = ProfileService();
  final _formKey = GlobalKey<FormState>();

  final _nameCtrl = TextEditingController();
  final _vornameCtrl = TextEditingController();
  final _strasseCtrl = TextEditingController();
  final _hausnrCtrl = TextEditingController();
  final _plzCtrl = TextEditingController();
  final _ortCtrl = TextEditingController();
  final _telefonCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();

  DateTime? _geburtsdatum;
  String? _fotoUrl;
  String? _personalnummer;
  File? _fotoFile;
  bool _fotoRemoved = false;
  String? _profileDocId;
  bool _fromUsers = false;
  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _vornameCtrl.dispose();
    _strasseCtrl.dispose();
    _hausnrCtrl.dispose();
    _plzCtrl.dispose();
    _ortCtrl.dispose();
    _telefonCtrl.dispose();
    _emailCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final user = _authService.currentUser;
    if (user == null) {
      if (mounted) setState(() => _loading = false);
      return;
    }
    try {
      final profile = await _profileService.loadProfile(
        widget.companyId,
        user.uid,
        user.email ?? '',
      ).timeout(
        const Duration(seconds: 15),
        onTimeout: () => null,
      );
      if (mounted && profile != null) {
        final d = profile.data;
        _profileDocId = profile.docId;
        _fromUsers = profile.fromUsers;
        _personalnummer = d['personalnummer']?.toString();
        _nameCtrl.text = d['nachname']?.toString() ?? '';
        _vornameCtrl.text = d['vorname']?.toString() ?? '';
        _strasseCtrl.text = d['strasse']?.toString() ?? '';
        _hausnrCtrl.text = d['hausnummer']?.toString() ?? '';
        _plzCtrl.text = d['plz']?.toString() ?? '';
        _ortCtrl.text = d['ort']?.toString() ?? '';
        _telefonCtrl.text = d['telefon']?.toString() ?? d['telefonnummer']?.toString() ?? '';
        _emailCtrl.text = d['email']?.toString() ?? user.email ?? '';
        _fotoUrl = d['fotoUrl']?.toString() ?? d['profilfoto']?.toString();
        final gb = d['geburtsdatum'];
        if (gb != null) {
          if (gb is DateTime) _geburtsdatum = gb;
          else if (gb.runtimeType.toString().contains('Timestamp')) {
            _geburtsdatum = (gb as dynamic).toDate();
          }
        }
      } else if (mounted) {
        _emailCtrl.text = user.email ?? '';
      }
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _pickImageFromGallery() async {
    final picker = ImagePicker();
    final x = await picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 600,
      maxHeight: 800,
      imageQuality: 85,
    );
    if (x != null) {
      setState(() {
        _fotoFile = File(x.path);
        _fotoUrl = null;
      });
    }
  }

  Future<void> _pickImageFromFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      allowMultiple: false,
    );
    if (result != null && result.files.single.path != null) {
      setState(() {
        _fotoFile = File(result.files.single.path!);
        _fotoUrl = null;
      });
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final user = _authService.currentUser;
    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Nicht angemeldet.')),
      );
      return;
    }
    final docId = _profileDocId ?? user.uid;
    setState(() => _saving = true);
    try {
      String? fotoUrl = _fotoRemoved ? null : _fotoUrl;
      if (_fotoFile != null) {
        fotoUrl = await _profileService.uploadProfilePhoto(
          widget.companyId,
          user.uid,
          _fotoFile!,
        );
      }
      final updates = <String, dynamic>{
        'nachname': _nameCtrl.text.trim(),
        'vorname': _vornameCtrl.text.trim(),
        'geburtsdatum': _geburtsdatum != null ? Timestamp.fromDate(_geburtsdatum!) : null,
        'strasse': _strasseCtrl.text.trim(),
        'hausnummer': _hausnrCtrl.text.trim(),
        'plz': _plzCtrl.text.trim(),
        'ort': _ortCtrl.text.trim(),
        'telefon': _telefonCtrl.text.trim(),
        'email': _emailCtrl.text.trim(),
        'fotoUrl': fotoUrl ?? FieldValue.delete(),
      };
      await _profileService.saveProfile(
        widget.companyId,
        docId,
        _fromUsers,
        updates,
        user.uid,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Profil gespeichert.')),
        );
        _load();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Fehler: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _selectDate() async {
    final d = await showDatePicker(
      context: context,
      initialDate: _geburtsdatum ?? DateTime(1990),
      firstDate: DateTime(1900),
      lastDate: DateTime.now(),
    );
    if (d != null) setState(() => _geburtsdatum = d);
  }

  String _formatDate(DateTime? d) {
    if (d == null) return '';
    return '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.${d.year}';
  }

  @override
  Widget build(BuildContext context) {
    final scaffold = Scaffold(
      backgroundColor: AppTheme.surfaceBg,
      appBar: AppTheme.buildModuleAppBar(
        title: 'Profil',
        onBack: widget.onBack ?? () => Navigator.of(context).pop(),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppTheme.primary))
          : Form(
              key: _formKey,
              child: ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildPhotoSection(),
                          const SizedBox(height: 12),
                          _buildWeitereDetailsDropdown(),
                        ],
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _buildReadOnlyField('Personalnummer', _personalnummer ?? '—'),
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                Expanded(child: _buildField('Vorname', _vornameCtrl, TextInputType.name)),
                                const SizedBox(width: 12),
                                Expanded(child: _buildField('Name', _nameCtrl, TextInputType.name)),
                              ],
                            ),
                            const SizedBox(height: 8),
                            _buildDateField(),
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                Expanded(child: _buildField('Straße', _strasseCtrl, TextInputType.streetAddress)),
                                const SizedBox(width: 12),
                                Expanded(child: _buildField('Haus-Nr.', _hausnrCtrl, TextInputType.text)),
                              ],
                            ),
                            Row(
                              children: [
                                Expanded(child: _buildField('PLZ', _plzCtrl, TextInputType.number)),
                                const SizedBox(width: 12),
                                Expanded(child: _buildField('Ort', _ortCtrl, TextInputType.streetAddress)),
                              ],
                            ),
                            Row(
                              children: [
                                Expanded(child: _buildField('Telefonnummer', _telefonCtrl, TextInputType.phone)),
                                const SizedBox(width: 12),
                                Expanded(child: _buildField('E-Mail', _emailCtrl, TextInputType.emailAddress)),
                              ],
                            ),
                            const SizedBox(height: 24),
                            FilledButton(
                              onPressed: _saving ? null : _save,
                              style: FilledButton.styleFrom(
                                backgroundColor: AppTheme.primary,
                                padding: const EdgeInsets.symmetric(vertical: 14),
                              ),
                              child: _saving ? const SizedBox(height: 24, width: 24, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Text('Speichern'),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
    );
    if (widget.hideAppBar && widget.onBack != null) {
      return PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) widget.onBack!();
        },
        child: scaffold,
      );
    }
    return scaffold;
  }

  Widget _buildPhotoSection() {
    const aspectRatio = 35 / 45;
    const boxWidth = 160.0;
    const boxHeight = boxWidth / aspectRatio;

    return InkWell(
        onTap: () async {
          final choice = await showModalBottomSheet<String>(
            context: context,
            builder: (ctx) => SafeArea(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ListTile(leading: const Icon(Icons.photo_library), title: const Text('Aus Galerie wählen'), onTap: () => Navigator.pop(ctx, 'gallery')),
                  ListTile(leading: const Icon(Icons.folder_open), title: const Text('Aus Datei wählen'), onTap: () => Navigator.pop(ctx, 'file')),
                  if (_fotoFile != null || _fotoUrl != null)
                    ListTile(leading: const Icon(Icons.delete), title: const Text('Foto entfernen'), onTap: () => Navigator.pop(ctx, 'remove')),
                ],
              ),
            ),
          );
          if (choice == 'gallery') await _pickImageFromGallery();
          if (choice == 'file') await _pickImageFromFile();
          if (choice == 'remove') setState(() {
            _fotoFile = null;
            _fotoUrl = null;
            _fotoRemoved = true;
          });
        },
        borderRadius: BorderRadius.circular(8),
        child: Container(
          width: boxWidth,
          height: boxHeight,
          decoration: BoxDecoration(
            color: Colors.grey[200],
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: AppTheme.border),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: _fotoFile != null
                ? Image.file(_fotoFile!, fit: BoxFit.cover)
                : _fotoUrl != null && _fotoUrl!.isNotEmpty
                    ? Image.network(_fotoUrl!, fit: BoxFit.cover)
                    : Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.add_a_photo, size: 32, color: Colors.grey[600]),
                          const SizedBox(height: 4),
                          Text('Foto hochladen', style: TextStyle(fontSize: 12, color: Colors.grey[600])),
                          Text('Tippen zum Hochladen', style: TextStyle(fontSize: 10, color: Colors.grey[500])),
                        ],
                      ),
          ),
        ),
    );
  }

  Widget _buildWeitereDetailsDropdown() {
    return SizedBox(
      width: 160,
      child: DropdownButtonFormField<String>(
        value: null,
        isExpanded: true,
        hint: const Text('Weitere Details', overflow: TextOverflow.ellipsis),
        decoration: InputDecoration(
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          filled: true,
          fillColor: Colors.white,
          contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        ),
        items: const [
          DropdownMenuItem(value: 'schnellstart', child: Text('Schnellstart')),
        ],
        onChanged: (value) {
          if (value == 'schnellstart') {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => SchnellstartScreen(
                  companyId: widget.companyId,
                  onSaved: widget.onSchnellstartChanged,
                ),
              ),
            ).then((_) => widget.onSchnellstartChanged?.call());
          }
        },
      ),
    );
  }

  Widget _buildReadOnlyField(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          filled: true,
          fillColor: Colors.grey[100],
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: AppTheme.border),
          ),
        ),
        child: Text(value, style: const TextStyle(color: AppTheme.textPrimary)),
      ),
    );
  }

  Widget _buildField(String label, TextEditingController ctrl, TextInputType type) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: TextFormField(
        controller: ctrl,
        keyboardType: type,
        decoration: InputDecoration(
          labelText: label,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          filled: true,
          fillColor: Colors.white,
        ),
      ),
    );
  }

  Widget _buildDateField() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: InkWell(
        onTap: _selectDate,
        borderRadius: BorderRadius.circular(12),
        child: InputDecorator(
          decoration: InputDecoration(
            labelText: 'Geburtsdatum',
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            filled: true,
            fillColor: Colors.white,
            suffixIcon: const Icon(Icons.calendar_today),
          ),
          child: Text(_formatDate(_geburtsdatum).isEmpty ? 'Datum wählen' : _formatDate(_geburtsdatum)),
        ),
      ),
    );
  }
}
