import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../theme/app_theme.dart';
import '../models/fleet_model.dart';
import '../services/fleet_service.dart';
import '../services/auth_data_service.dart';
import '../services/auth_service.dart';
import '../services/maengelmelder_config_service.dart';
import 'schnittstellenmeldung_screen.dart';
import 'uebergriffsmeldung_screen.dart';

/// Mängelmelder – Übersicht mit Menüpunkten
class MaengelmelderScreen extends StatefulWidget {
  final String companyId;
  final String userId;
  final String userRole;
  final VoidCallback onBack;

  const MaengelmelderScreen({
    required this.companyId,
    required this.userId,
    required this.userRole,
    required this.onBack,
  });

  @override
  State<MaengelmelderScreen> createState() => _MaengelmelderScreenState();
}

class _MaengelmelderScreenState extends State<MaengelmelderScreen> {
  final _configService = MaengelmelderConfigService();
  List<String> _menuOrder = List.from(MaengelmelderConfigService.defaultOrder);
  bool _loading = true;

  static const _menuItems = {
    'fahrzeugmangel': _MenuInfo('Fahrzeugmangel erfassen', 'Fahrzeugmangel melden', Icons.build),
    'mpg-mangel': _MenuInfo('MPG-Mangel', 'MPG-relevante Mängel melden', Icons.medical_services_outlined),
    'digitalfunk': _MenuInfo('Digitalfunk', 'Digitalfunk-Mängel melden', Icons.router),
    'sonstiger-mangel': _MenuInfo('Sonstiger Mangel', 'Andere Mängel melden', Icons.miscellaneous_services),
    'schnittstellenmeldung': _MenuInfo('Schnittstellenmeldung', 'Schnittstellen-Vorkommnisse melden', Icons.cable),
    'uebergriffsmeldung': _MenuInfo('Übergriffsmeldung', 'Übergriffe und Sachbeschädigungen melden', Icons.warning_amber),
  };

  static const _reorderRoles = ['admin', 'superadmin', 'geschaeftsfuehrung', 'leiterssd', 'koordinator'];

  bool get _canReorder => _reorderRoles.contains(widget.userRole.toLowerCase().trim());

  @override
  void initState() {
    super.initState();
    _loadOrder();
  }

  Future<void> _loadOrder() async {
    final order = await _configService.loadMenuOrder(widget.companyId, widget.userId);
    if (mounted) setState(() {
      _menuOrder = order;
      _loading = false;
    });
  }

  Future<void> _moveUp(int index) async {
    if (index <= 0) return;
    final order = List<String>.from(_menuOrder);
    final tmp = order[index];
    order[index] = order[index - 1];
    order[index - 1] = tmp;
    await _configService.saveMenuOrder(widget.companyId, widget.userId, order);
    if (mounted) setState(() => _menuOrder = order);
  }

  Future<void> _moveDown(int index) async {
    if (index >= _menuOrder.length - 1) return;
    final order = List<String>.from(_menuOrder);
    final tmp = order[index];
    order[index] = order[index + 1];
    order[index + 1] = tmp;
    await _configService.saveMenuOrder(widget.companyId, widget.userId, order);
    if (mounted) setState(() => _menuOrder = order);
  }

  void _openItem(String id) {
    if (id == 'uebergriffsmeldung') {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => UebergriffsmeldungScreen(
            companyId: widget.companyId,
            userRole: widget.userRole,
            onBack: () => Navigator.of(context).pop(),
          ),
        ),
      );
    } else if (id == 'schnittstellenmeldung') {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => SchnittstellenmeldungScreen(
            companyId: widget.companyId,
            userRole: widget.userRole,
            onBack: () => Navigator.of(context).pop(),
          ),
        ),
      );
    } else if (id == 'fahrzeugmangel') {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => FahrzeugmangelErfassenScreen(
            companyId: widget.companyId,
            onBack: () => Navigator.of(context).pop(),
          ),
        ),
      );
    } else {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => SonstigerMangelErfassenScreen(
            companyId: widget.companyId,
            mangelTyp: id,
            onBack: () => Navigator.of(context).pop(),
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.surfaceBg,
      appBar: AppTheme.buildModuleAppBar(
        title: 'Mängelmelder',
        onBack: widget.onBack,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView.builder(
              padding: const EdgeInsets.all(20),
              itemCount: _menuOrder.length,
              itemBuilder: (_, i) {
                final id = _menuOrder[i];
                final info = _menuItems[id];
                if (info == null) return const SizedBox.shrink();
                return Card(
                  child: ListTile(
                    leading: CircleAvatar(
                      backgroundColor: AppTheme.primary.withOpacity(0.15),
                      child: Icon(info.icon, color: AppTheme.primary),
                    ),
                    title: Text(info.label, style: const TextStyle(fontWeight: FontWeight.w500)),
                    subtitle: Text(info.subtitle),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (_canReorder) ...[
                          IconButton(
                            icon: Icon(Icons.arrow_upward, size: 20, color: i > 0 ? AppTheme.primary : Colors.grey[400]),
                            onPressed: i > 0 ? () => _moveUp(i) : null,
                          ),
                          IconButton(
                            icon: Icon(Icons.arrow_downward, size: 20, color: i < _menuOrder.length - 1 ? AppTheme.primary : Colors.grey[400]),
                            onPressed: i < _menuOrder.length - 1 ? () => _moveDown(i) : null,
                          ),
                        ],
                        const Icon(Icons.chevron_right),
                      ],
                    ),
                    onTap: () => _openItem(id),
                  ),
                );
              },
            ),
    );
  }
}

class _MenuInfo {
  final String label;
  final String subtitle;
  final IconData icon;
  const _MenuInfo(this.label, this.subtitle, this.icon);
}

const _mangelKategorien = ['Getriebe', 'Motor', 'Bremsen', 'Elektrik', 'Bereifung', 'Karosserie', 'Innenausstattung', 'Sonstiges'];

/// Fahrzeugmangel erfassen – Formular für neue Mängelmeldung
class FahrzeugmangelErfassenScreen extends StatefulWidget {
  final String companyId;
  final VoidCallback onBack;

  const FahrzeugmangelErfassenScreen({required this.companyId, required this.onBack});

  @override
  State<FahrzeugmangelErfassenScreen> createState() => _FahrzeugmangelErfassenScreenState();
}

class _FahrzeugmangelErfassenScreenState extends State<FahrzeugmangelErfassenScreen> {
  final _fleetService = FleetService();
  final _authDataService = AuthDataService();
  final _authService = AuthService();

  late TextEditingController _betreffController;
  late TextEditingController _beschreibungController;
  late TextEditingController _kilometerstandController;
  String _melderName = '';
  late DateTime _datum;
  String _status = 'offen';
  String _prioritaet = 'niedrig';
  String _kategorie = _mangelKategorien.first;
  Fahrzeug? _selectedFahrzeug;
  bool _saving = false;
  List<XFile> _pickedImages = [];
  List<Fahrzeug> _fahrzeuge = [];

  @override
  void initState() {
    super.initState();
    _betreffController = TextEditingController();
    _beschreibungController = TextEditingController();
    _kilometerstandController = TextEditingController();
    _datum = DateTime.now();
    _loadInitialData();
  }

  Future<void> _loadInitialData() async {
    final fahrzeuge = await _fleetService.streamFahrzeuge(widget.companyId).first;
    final user = _authService.currentUser;
    String melderName = '';
    if (user != null) {
      final authData = await _authDataService.getAuthData(user.uid, user.email ?? '', widget.companyId);
      melderName = authData.displayName ?? user.email?.split('@').first ?? '';
    }
    if (mounted) {
      setState(() {
        _fahrzeuge = fahrzeuge;
        _melderName = melderName;
      });
    }
  }

  @override
  void dispose() {
    _betreffController.dispose();
    _beschreibungController.dispose();
    _kilometerstandController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_selectedFahrzeug == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Bitte Fahrzeug (Kennzeichen) auswählen.')));
      return;
    }
    final betreff = _betreffController.text.trim();
    final beschreibung = _beschreibungController.text.trim();
    if (beschreibung.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Bitte Mangelbeschreibung angeben.')));
      return;
    }
    final km = int.tryParse(_kilometerstandController.text.trim());
    if (km == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Bitte Kilometerstand angeben.')));
      return;
    }

    setState(() => _saving = true);
    try {
      final f = _selectedFahrzeug!;
      final user = _authService.currentUser;
      final mangel = FahrzeugMangel(
        id: '',
        fahrzeugId: f.id,
        fahrzeugRufname: f.displayName,
        kennzeichen: f.kennzeichen,
        betreff: betreff.isEmpty ? null : betreff,
        beschreibung: beschreibung,
        kategorie: _kategorie,
        melderName: _melderName.isEmpty ? null : _melderName,
        melderUid: user?.uid,
        status: _status,
        prioritaet: _prioritaet,
        datum: _datum,
        kilometerstand: km,
        bilder: const [],
        createdAt: DateTime.now(),
        updatedAt: null,
      );

      final mangelId = await _fleetService.createMangel(widget.companyId, mangel);

      if (_pickedImages.isNotEmpty) {
        final bytesList = <Uint8List>[];
        final namesList = <String>[];
        for (final x in _pickedImages) {
          final b = await x.readAsBytes();
          bytesList.add(b);
          namesList.add(x.name);
        }
        final urls = await _fleetService.uploadMangelBilder(widget.companyId, mangelId, bytesList, namesList);
        final updated = mangel.copyWith(id: mangelId, bilder: urls);
        await _fleetService.updateMangel(widget.companyId, updated);
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Mangel erfasst.')));
        widget.onBack();
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Fehler: $e')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _pickImages() async {
    try {
      final picker = ImagePicker();
      final files = await picker.pickMultiImage();
      if (files.isEmpty) return;
      if (mounted) setState(() {
        final remaining = 10 - _pickedImages.length;
        _pickedImages.addAll(files.take(remaining));
      });
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Fehler: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppTheme.buildModuleAppBar(
        title: 'Fahrzeugmangel erfassen',
        onBack: widget.onBack,
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _buildDateField(),
                    const SizedBox(height: 16),
                    _buildKennzeichenDropdown(),
                    const SizedBox(height: 16),
                    _buildKategorieDropdown(),
                    const SizedBox(height: 16),
                    _buildReadOnlyField('Melder', _melderName),
                  ],
                ),
              ),
              const SizedBox(width: 24),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _buildStatusDropdown(),
                    const SizedBox(height: 16),
                    _buildTextField(_kilometerstandController, 'Kilometerstand *', keyboardType: TextInputType.number, hint: 'z.B. 50000'),
                    const SizedBox(height: 16),
                    _buildPrioritaetDropdown(),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          _buildTextField(_betreffController, 'Mangel (Kurzbeschreibung/Betreff) *', hint: 'Kurze Beschreibung des Mangels'),
          const SizedBox(height: 16),
          _buildTextField(_beschreibungController, 'Mangelbeschreibung *', maxLines: 5, hint: 'Beschreiben Sie den Mangel...'),
          const SizedBox(height: 24),
          _buildImageUploadSection(),
          const SizedBox(height: 32),
          FilledButton.icon(
            onPressed: _saving ? null : _submit,
            icon: _saving
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.check),
            label: Text(_saving ? 'Wird erfasst...' : 'Mangel erfassen'),
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
            ),
          ),
        ],
      ),
    );
  }

  static const _inputDecoration = InputDecoration(
    filled: true,
    fillColor: Color(0xFFF5F5F5),
    border: OutlineInputBorder(borderSide: BorderSide(color: Color(0xFFE5E7EB))),
    contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 16),
    isDense: true,
  );

  static const _singleLineFieldHeight = 56.0;

  Widget _buildDateField() {
    return SizedBox(
      height: _singleLineFieldHeight,
      child: InputDecorator(
        decoration: _inputDecoration.copyWith(labelText: 'Datum'),
        child: Align(
          alignment: Alignment.centerLeft,
          child: Text(
            '${_datum.day.toString().padLeft(2, '0')}.${_datum.month.toString().padLeft(2, '0')}.${_datum.year}',
            style: const TextStyle(fontSize: 16),
          ),
        ),
      ),
    );
  }

  Widget _buildReadOnlyField(String label, String value) {
    return SizedBox(
      height: _singleLineFieldHeight,
      child: InputDecorator(
        decoration: _inputDecoration.copyWith(labelText: label),
        child: Align(
          alignment: Alignment.centerLeft,
          child: Text(
            value.isEmpty ? '–' : value,
            style: TextStyle(fontSize: 16, color: value.isEmpty ? Colors.grey[600] : null),
          ),
        ),
      ),
    );
  }

  Widget _buildKennzeichenDropdown() {
    return SizedBox(
      height: _singleLineFieldHeight,
      child: InputDecorator(
        decoration: _inputDecoration.copyWith(labelText: 'Kennzeichen *'),
        child: DropdownButtonHideUnderline(
          child: DropdownButton<Fahrzeug?>(
            value: _selectedFahrzeug,
            isExpanded: true,
            hint: const Text('Bitte auswählen ...'),
            items: [
              const DropdownMenuItem<Fahrzeug?>(value: null, child: Text('Bitte auswählen ...')),
              ..._fahrzeuge.map((f) => DropdownMenuItem<Fahrzeug?>(
                value: f,
                child: Text(f.kennzeichen ?? f.rufname ?? f.displayName),
              )),
            ],
            onChanged: (v) => setState(() => _selectedFahrzeug = v),
          ),
        ),
      ),
    );
  }

  Widget _buildKategorieDropdown() {
    return SizedBox(
      height: _singleLineFieldHeight,
      child: InputDecorator(
        decoration: _inputDecoration.copyWith(labelText: 'Kategorie *'),
        child: DropdownButtonHideUnderline(
          child: DropdownButton<String>(
            value: _kategorie,
            isExpanded: true,
            items: _mangelKategorien.map((k) => DropdownMenuItem(value: k, child: Text(k))).toList(),
            onChanged: (v) => setState(() => _kategorie = v ?? _mangelKategorien.first),
          ),
        ),
      ),
    );
  }

  Widget _buildStatusDropdown() {
    return SizedBox(
      height: _singleLineFieldHeight,
      child: InputDecorator(
        decoration: _inputDecoration.copyWith(labelText: 'Status'),
        child: DropdownButtonHideUnderline(
          child: DropdownButton<String>(
            value: _status,
            isExpanded: true,
            items: const [
              DropdownMenuItem(value: 'offen', child: Text('Offen')),
              DropdownMenuItem(value: 'inBearbeitung', child: Text('In Bearbeitung')),
              DropdownMenuItem(value: 'repariert', child: Text('Repariert')),
              DropdownMenuItem(value: 'abgeschlossen', child: Text('Abgeschlossen')),
            ],
            onChanged: (v) => setState(() => _status = v ?? 'offen'),
          ),
        ),
      ),
    );
  }

  Widget _buildPrioritaetDropdown() {
    return SizedBox(
      height: _singleLineFieldHeight,
      child: InputDecorator(
        decoration: _inputDecoration.copyWith(labelText: 'Priorität'),
        child: DropdownButtonHideUnderline(
          child: DropdownButton<String>(
            value: _prioritaet,
            isExpanded: true,
            items: const [
              DropdownMenuItem(value: 'niedrig', child: Text('Niedrig')),
              DropdownMenuItem(value: 'mittel', child: Text('Mittel')),
              DropdownMenuItem(value: 'hoch', child: Text('Hoch')),
            ],
            onChanged: (v) => setState(() => _prioritaet = v ?? 'niedrig'),
          ),
        ),
      ),
    );
  }

  Widget _buildTextField(TextEditingController ctrl, String label, {int maxLines = 1, TextInputType? keyboardType, String? hint}) {
    final field = TextFormField(
      controller: ctrl,
      maxLines: maxLines,
      keyboardType: keyboardType,
      decoration: _inputDecoration.copyWith(labelText: label, hintText: hint),
    );
    if (maxLines <= 1) {
      return SizedBox(height: _singleLineFieldHeight, child: field);
    }
    return field;
  }

  Widget _buildImageUploadSection() {
    final totalCount = _pickedImages.length;
    final canAdd = totalCount < 10;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Bilder (max. 10)', style: TextStyle(fontSize: 14, color: Colors.grey[700], fontWeight: FontWeight.w500)),
        const SizedBox(height: 8),
        if (_pickedImages.isNotEmpty) ...[
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: List.generate(_pickedImages.length, (i) => _buildPickedThumbnail(_pickedImages[i], () => setState(() => _pickedImages.removeAt(i)))),
          ),
          const SizedBox(height: 12),
        ],
        if (canAdd)
          GestureDetector(
            onTap: _pickImages,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 16),
              decoration: BoxDecoration(
                color: AppTheme.primary.withOpacity(0.08),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppTheme.primary, width: 2),
              ),
              child: Column(
                children: [
                  Icon(Icons.image_outlined, size: 48, color: AppTheme.primary.withOpacity(0.7)),
                  const SizedBox(height: 12),
                  Text(
                    totalCount == 0 ? 'Bilder hier ablegen oder' : '${totalCount} Bild(er) – weitere hinzufügen',
                    style: TextStyle(fontSize: 14, color: Colors.grey[700]),
                  ),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    onPressed: _pickImages,
                    icon: const Icon(Icons.add_photo_alternate, size: 18),
                    label: const Text('Dateien auswählen'),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildPickedThumbnail(XFile file, VoidCallback onRemove) {
    return Stack(
      children: [
        FutureBuilder<Uint8List>(
          future: file.readAsBytes(),
          builder: (ctx, snap) {
            if (!snap.hasData) return const SizedBox(width: 80, height: 80, child: Center(child: CircularProgressIndicator()));
            return ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.memory(
                snap.data!,
                width: 80,
                height: 80,
                fit: BoxFit.cover,
              ),
            );
          },
        ),
        Positioned(
          top: 4,
          right: 4,
          child: GestureDetector(
            onTap: onRemove,
            child: Container(
              padding: const EdgeInsets.all(4),
              decoration: const BoxDecoration(color: Colors.red, shape: BoxShape.circle),
              child: const Icon(Icons.close, size: 16, color: Colors.white),
            ),
          ),
        ),
      ],
    );
  }
}

/// Vereinfachtes Formular für MPG-Mangel, Digitalfunk, Sonstiger Mangel (ohne Fahrzeug)
class SonstigerMangelErfassenScreen extends StatefulWidget {
  final String companyId;
  final String mangelTyp; // mpg-mangel | digitalfunk | sonstiger-mangel
  final VoidCallback onBack;

  const SonstigerMangelErfassenScreen({
    required this.companyId,
    required this.mangelTyp,
    required this.onBack,
  });

  @override
  State<SonstigerMangelErfassenScreen> createState() => _SonstigerMangelErfassenScreenState();
}

class _SonstigerMangelErfassenScreenState extends State<SonstigerMangelErfassenScreen> {
  final _fleetService = FleetService();
  final _authDataService = AuthDataService();
  final _authService = AuthService();

  late TextEditingController _betreffController;
  late TextEditingController _beschreibungController;
  String _melderName = '';
  late DateTime _datum;
  String _status = 'offen';
  String _prioritaet = 'niedrig';
  bool _saving = false;
  List<XFile> _pickedImages = [];

  static const _labels = {
    'mpg-mangel': 'MPG-Mangel erfassen',
    'digitalfunk': 'Digitalfunk-Mangel erfassen',
    'sonstiger-mangel': 'Sonstiger Mangel erfassen',
  };

  String get _title => _labels[widget.mangelTyp] ?? 'Mangel erfassen';

  @override
  void initState() {
    super.initState();
    _betreffController = TextEditingController();
    _beschreibungController = TextEditingController();
    _datum = DateTime.now();
    _loadMelderName();
  }

  Future<void> _loadMelderName() async {
    final user = _authService.currentUser;
    if (user != null) {
      final authData = await _authDataService.getAuthData(user.uid, user.email ?? '', widget.companyId);
      if (mounted) setState(() => _melderName = authData.displayName ?? user.email?.split('@').first ?? '');
    }
  }

  @override
  void dispose() {
    _betreffController.dispose();
    _beschreibungController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final betreff = _betreffController.text.trim();
    final beschreibung = _beschreibungController.text.trim();
    if (beschreibung.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Bitte Mangelbeschreibung angeben.')));
      return;
    }

    setState(() => _saving = true);
    try {
      final user = _authService.currentUser;
      final mangel = FahrzeugMangel(
        id: '',
        mangelTyp: widget.mangelTyp,
        fahrzeugId: '',
        fahrzeugRufname: _title,
        betreff: betreff.isEmpty ? null : betreff,
        beschreibung: beschreibung,
        kategorie: widget.mangelTyp,
        melderName: _melderName.isEmpty ? null : _melderName,
        melderUid: user?.uid,
        status: _status,
        prioritaet: _prioritaet,
        datum: _datum,
        kilometerstand: null,
        bilder: const [],
        createdAt: DateTime.now(),
        updatedAt: null,
      );

      final mangelId = await _fleetService.createMangel(widget.companyId, mangel);

      if (_pickedImages.isNotEmpty) {
        final bytesList = <Uint8List>[];
        final namesList = <String>[];
        for (final x in _pickedImages) {
          bytesList.add(await x.readAsBytes());
          namesList.add(x.name);
        }
        final urls = await _fleetService.uploadMangelBilder(widget.companyId, mangelId, bytesList, namesList);
        await _fleetService.updateMangel(widget.companyId, mangel.copyWith(id: mangelId, bilder: urls));
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Mangel erfasst.')));
        widget.onBack();
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Fehler: $e')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _pickImages() async {
    try {
      final files = await ImagePicker().pickMultiImage();
      if (files.isEmpty) return;
      if (mounted) setState(() {
        _pickedImages.addAll(files.take(10 - _pickedImages.length));
      });
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Fehler: $e')));
    }
  }

  static const _inputDecoration = InputDecoration(
    filled: true,
    fillColor: Color(0xFFF5F5F5),
    border: OutlineInputBorder(borderSide: BorderSide(color: Color(0xFFE5E7EB))),
    contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 16),
    isDense: true,
  );

  static const _singleLineFieldHeight = 56.0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppTheme.buildModuleAppBar(
        title: _title,
        onBack: widget.onBack,
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: SizedBox(
                  height: _singleLineFieldHeight,
                  child: InputDecorator(
                    decoration: _inputDecoration.copyWith(labelText: 'Datum'),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        '${_datum.day.toString().padLeft(2, '0')}.${_datum.month.toString().padLeft(2, '0')}.${_datum.year}',
                        style: const TextStyle(fontSize: 16),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 24),
              Expanded(
                child: SizedBox(
                  height: _singleLineFieldHeight,
                  child: InputDecorator(
                    decoration: _inputDecoration.copyWith(labelText: 'Melder'),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(_melderName.isEmpty ? '–' : _melderName, style: const TextStyle(fontSize: 16)),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: SizedBox(
                  height: _singleLineFieldHeight,
                  child: InputDecorator(
                    decoration: _inputDecoration.copyWith(labelText: 'Status'),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        value: _status,
                        isExpanded: true,
                        items: const [
                          DropdownMenuItem(value: 'offen', child: Text('Offen')),
                          DropdownMenuItem(value: 'inBearbeitung', child: Text('In Bearbeitung')),
                          DropdownMenuItem(value: 'repariert', child: Text('Repariert')),
                          DropdownMenuItem(value: 'abgeschlossen', child: Text('Abgeschlossen')),
                        ],
                        onChanged: (v) => setState(() => _status = v ?? 'offen'),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 24),
              Expanded(
                child: SizedBox(
                  height: _singleLineFieldHeight,
                  child: InputDecorator(
                    decoration: _inputDecoration.copyWith(labelText: 'Priorität'),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        value: _prioritaet,
                        isExpanded: true,
                        items: const [
                          DropdownMenuItem(value: 'niedrig', child: Text('Niedrig')),
                          DropdownMenuItem(value: 'mittel', child: Text('Mittel')),
                          DropdownMenuItem(value: 'hoch', child: Text('Hoch')),
                        ],
                        onChanged: (v) => setState(() => _prioritaet = v ?? 'niedrig'),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          SizedBox(
            height: _singleLineFieldHeight,
            child: TextFormField(
              controller: _betreffController,
              decoration: _inputDecoration.copyWith(labelText: 'Betreff / Kurzbeschreibung', hintText: 'Kurze Beschreibung'),
            ),
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _beschreibungController,
            maxLines: 5,
            decoration: _inputDecoration.copyWith(labelText: 'Mangelbeschreibung *', hintText: 'Beschreiben Sie den Mangel...'),
          ),
          const SizedBox(height: 24),
          _buildImageUploadSection(),
          const SizedBox(height: 32),
          FilledButton.icon(
            onPressed: _saving ? null : _submit,
            icon: _saving
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.check),
            label: Text(_saving ? 'Wird erfasst...' : 'Mangel erfassen'),
            style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16)),
          ),
        ],
      ),
    );
  }

  Widget _buildImageUploadSection() {
    final totalCount = _pickedImages.length;
    final canAdd = totalCount < 10;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Bilder (max. 10)', style: TextStyle(fontSize: 14, color: Colors.grey[700], fontWeight: FontWeight.w500)),
        const SizedBox(height: 8),
        if (_pickedImages.isNotEmpty) ...[
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: List.generate(_pickedImages.length, (i) {
              final file = _pickedImages[i];
              return Stack(
                children: [
                  FutureBuilder<Uint8List>(
                    future: file.readAsBytes(),
                    builder: (_, snap) {
                      if (!snap.hasData) return const SizedBox(width: 80, height: 80, child: Center(child: CircularProgressIndicator()));
                      return ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Image.memory(snap.data!, width: 80, height: 80, fit: BoxFit.cover),
                      );
                    },
                  ),
                  Positioned(
                    top: 4,
                    right: 4,
                    child: GestureDetector(
                      onTap: () => setState(() => _pickedImages.removeAt(i)),
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: const BoxDecoration(color: Colors.red, shape: BoxShape.circle),
                        child: const Icon(Icons.close, size: 16, color: Colors.white),
                      ),
                    ),
                  ),
                ],
              );
            }),
          ),
          const SizedBox(height: 12),
        ],
        if (canAdd)
          GestureDetector(
            onTap: _pickImages,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 16),
              decoration: BoxDecoration(
                color: AppTheme.primary.withOpacity(0.08),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppTheme.primary, width: 2),
              ),
              child: Column(
                children: [
                  Icon(Icons.image_outlined, size: 48, color: AppTheme.primary.withOpacity(0.7)),
                  const SizedBox(height: 12),
                  Text(
                    totalCount == 0 ? 'Bilder hier ablegen oder' : '${totalCount} Bild(er) – weitere hinzufügen',
                    style: TextStyle(fontSize: 14, color: Colors.grey[700]),
                  ),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    onPressed: _pickImages,
                    icon: const Icon(Icons.add_photo_alternate, size: 18),
                    label: const Text('Dateien auswählen'),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}
