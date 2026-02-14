import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../services/schichtanmeldung_service.dart';
import '../services/schichtplan_nfs_service.dart';
import '../services/mitarbeiter_service.dart';
import '../models/mitarbeiter_model.dart';
import 'schichtplan_nfs_stundenplan_screen.dart';

/// Einstellungen für den Bereitschaftsplan NFS – Menü mit Bereichen
class SchichtplanNfsEinstellungenScreen extends StatelessWidget {
  final String companyId;
  final String? userRole;
  final VoidCallback onBack;

  const SchichtplanNfsEinstellungenScreen({
    super.key,
    required this.companyId,
    this.userRole,
    required this.onBack,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.surfaceBg,
      appBar: AppTheme.buildModuleAppBar(
        title: 'Einstellungen',
        onBack: onBack,
      ),
      body: ListView(
        padding: EdgeInsets.all(Responsive.horizontalPadding(context)),
        children: [
          _MenuTile(
            icon: Icons.category,
            title: 'Bereitschafts-Typen',
            subtitle: 'Typen verwalten und Farben zuordnen',
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => _BereitschaftsTypenScreen(
                  companyId: companyId,
                  onBack: () => Navigator.pop(context),
                ),
              ),
            ),
          ),
          _MenuTile(
            icon: Icons.people,
            title: 'Mitarbeiter',
            subtitle: 'Mitglieder für den Bereitschaftsplan verwalten',
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => _NfsMitarbeiterScreen(
                  companyId: companyId,
                  userRole: userRole,
                  onBack: () => Navigator.pop(context),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MenuTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _MenuTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: AppTheme.primary.withOpacity(0.15),
          child: Icon(icon, color: AppTheme.primary),
        ),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text(subtitle, style: TextStyle(fontSize: 13, color: AppTheme.textMuted)),
        trailing: const Icon(Icons.chevron_right, color: AppTheme.textMuted),
        onTap: onTap,
      ),
    );
  }
}

/// Bereich: Bereitschafts-Typen
class _BereitschaftsTypenScreen extends StatefulWidget {
  final String companyId;
  final VoidCallback onBack;

  const _BereitschaftsTypenScreen({required this.companyId, required this.onBack});

  @override
  State<_BereitschaftsTypenScreen> createState() => _BereitschaftsTypenScreenState();
}

class _BereitschaftsTypenScreenState extends State<_BereitschaftsTypenScreen> {
  final _service = SchichtplanNfsService();
  List<BereitschaftsTyp> _typen = [];
  bool _loading = true;

  static const _typFarben = [
    0xFF0EA5E9, 0xFF10B981, 0xFFF59E0B, 0xFF8B5CF6,
    0xFFEF4444, 0xFF06B6D4, 0xFFEC4899, 0xFF84CC16,
    0xFF6366F1, 0xFF14B8A6, 0xFFF97316, 0xFFA855F7,
    0xFFEAB308,
  ];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final list = await _service.loadBereitschaftsTypen(widget.companyId);
    if (mounted) setState(() {
      _typen = list;
      _loading = false;
    });
  }

  void _openTypBearbeiten([BereitschaftsTyp? typ]) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => _BereitschaftsTypBearbeitenScreen(
          companyId: widget.companyId,
          typ: typ,
          farben: _typFarben,
          onSaved: () {
            _load();
            Navigator.pop(context);
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Bereitschafts-Typen'),
        leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: widget.onBack),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppTheme.primary))
          : ListView.builder(
              padding: EdgeInsets.all(Responsive.horizontalPadding(context)),
              itemCount: _typen.length,
              itemBuilder: (_, i) {
                final t = _typen[i];
                return Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: ListTile(
                    leading: CircleAvatar(
                      backgroundColor: t.color != null ? Color(t.color!) : AppTheme.primary,
                      radius: 20,
                    ),
                    title: Text(t.name),
                    subtitle: t.beschreibung != null ? Text(t.beschreibung!) : null,
                    trailing: const Icon(Icons.edit),
                    onTap: () => _openTypBearbeiten(t),
                  ),
                );
              },
            ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openTypBearbeiten(),
        icon: const Icon(Icons.add),
        label: const Text('Typ hinzufügen'),
      ),
    );
  }
}

/// Screen: Typ bearbeiten/neu
class _BereitschaftsTypBearbeitenScreen extends StatefulWidget {
  final String companyId;
  final BereitschaftsTyp? typ;
  final List<int> farben;
  final VoidCallback onSaved;

  const _BereitschaftsTypBearbeitenScreen({
    required this.companyId,
    this.typ,
    required this.farben,
    required this.onSaved,
  });

  @override
  State<_BereitschaftsTypBearbeitenScreen> createState() =>
      _BereitschaftsTypBearbeitenScreenState();
}

class _BereitschaftsTypBearbeitenScreenState
    extends State<_BereitschaftsTypBearbeitenScreen> {
  final _service = SchichtplanNfsService();
  final _nameCtrl = TextEditingController();
  final _beschreibungCtrl = TextEditingController();
  late int _color;

  @override
  void initState() {
    super.initState();
    _nameCtrl.text = widget.typ?.name ?? '';
    _beschreibungCtrl.text = widget.typ?.beschreibung ?? '';
    _color = widget.typ?.color ?? widget.farben.first;
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _beschreibungCtrl.dispose();
    super.dispose();
  }

  Future<void> _speichern() async {
    if (_nameCtrl.text.trim().isEmpty) return;
    if (widget.typ != null) {
      await _service.updateBereitschaftsTyp(
        widget.companyId,
        widget.typ!.id,
        name: _nameCtrl.text.trim(),
        beschreibung: _beschreibungCtrl.text.trim().isEmpty ? null : _beschreibungCtrl.text.trim(),
        color: _color,
      );
    } else {
      await _service.createBereitschaftsTyp(
        widget.companyId,
        _nameCtrl.text.trim(),
        _beschreibungCtrl.text.trim().isEmpty ? null : _beschreibungCtrl.text.trim(),
        _color,
      );
    }
    if (mounted) widget.onSaved();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.typ != null ? 'Typ bearbeiten' : 'Neuer Bereitschafts-Typ'),
        leading: IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)),
        actions: [
          FilledButton(
            onPressed: _speichern,
            child: Text(widget.typ != null ? 'Speichern' : 'Hinzufügen'),
          ),
          const SizedBox(width: 16),
        ],
      ),
      body: SingleChildScrollView(
        padding: EdgeInsets.all(Responsive.horizontalPadding(context)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _nameCtrl,
              decoration: const InputDecoration(
                labelText: 'Name',
                hintText: 'z.B. Einsatzkoordination',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _beschreibungCtrl,
              decoration: const InputDecoration(
                labelText: 'Beschreibung (optional)',
                border: OutlineInputBorder(),
              ),
              maxLines: 2,
            ),
            const SizedBox(height: 24),
            const Text('Farbe', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16)),
            const SizedBox(height: 12),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: widget.farben.map((c) => InkWell(
                onTap: () => setState(() => _color = c),
                borderRadius: BorderRadius.circular(24),
                child: Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: Color(c),
                    shape: BoxShape.circle,
                    border: _color == c ? Border.all(color: Colors.black, width: 3) : null,
                    boxShadow: _color == c ? [BoxShadow(color: Colors.black26, blurRadius: 4)] : null,
                  ),
                ),
              )).toList(),
            ),
          ],
        ),
      ),
    );
  }
}

/// Bereich: Mitarbeiter
class _NfsMitarbeiterScreen extends StatefulWidget {
  final String companyId;
  final String? userRole;
  final VoidCallback onBack;

  const _NfsMitarbeiterScreen({
    required this.companyId,
    this.userRole,
    required this.onBack,
  });

  static bool _canAddMitarbeiter(String? role) {
    if (role == null || role.isEmpty) return false;
    final r = role.trim().toLowerCase();
    return r == 'superadmin' || r == 'admin' || r == 'koordinator';
  }

  @override
  State<_NfsMitarbeiterScreen> createState() => _NfsMitarbeiterScreenState();
}

class _NfsMitarbeiterScreenState extends State<_NfsMitarbeiterScreen> {
  final _service = SchichtplanNfsService();
  List<SchichtplanMitarbeiter> _mitarbeiter = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final list = await _service.loadMitarbeiter(widget.companyId);
    if (mounted) setState(() {
      _mitarbeiter = list;
      _loading = false;
    });
  }

  String _rollenAnzeige(String role) {
    switch (role.toLowerCase()) {
      case 'admin': return 'Admin';
      case 'koordinator': return 'Koordinator';
      case 'user': return 'User';
      default: return role;
    }
  }

  String _initial(SchichtplanMitarbeiter m) {
    final v = (m.vorname ?? '').trim();
    final n = (m.nachname ?? '').trim();
    if (v.isNotEmpty) return v.substring(0, 1).toUpperCase();
    if (n.isNotEmpty) return n.substring(0, 1).toUpperCase();
    return '?';
  }

  void _openMitarbeiterBearbeiten([SchichtplanMitarbeiter? m]) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => _NfsMitarbeiterBearbeitenScreen(
          companyId: widget.companyId,
          mitarbeiter: m,
          onSaved: () {
            _load();
            Navigator.pop(context);
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.surfaceBg,
      appBar: AppTheme.buildModuleAppBar(
        title: 'Mitarbeiter',
        onBack: widget.onBack,
        actions: [
          if (_NfsMitarbeiterScreen._canAddMitarbeiter(widget.userRole))
            TextButton.icon(
              onPressed: () => _openMitarbeiterBearbeiten(),
              icon: const Icon(Icons.add),
              label: const Text('Mitarbeiter hinzufügen'),
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppTheme.primary))
          : ListView.builder(
              padding: EdgeInsets.all(Responsive.horizontalPadding(context)),
              itemCount: _mitarbeiter.length,
              itemBuilder: (_, i) {
                final m = _mitarbeiter[i];
                return Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: ListTile(
                    leading: CircleAvatar(
                      backgroundColor: AppTheme.primary.withOpacity(0.2),
                      child: Text(
                        _initial(m),
                        style: TextStyle(color: AppTheme.primary, fontWeight: FontWeight.w600),
                      ),
                    ),
                    title: Text(m.displayName),
                    subtitle: Text([
                      if (m.ort != null && m.ort!.isNotEmpty) m.ort!,
                      if (m.email != null && m.email!.isNotEmpty) m.email!,
                      if (m.role != null && m.role!.isNotEmpty) _rollenAnzeige(m.role!),
                    ].where((x) => x.isNotEmpty).join(' · ')),
                    trailing: const Icon(Icons.edit),
                    onTap: () => _openMitarbeiterBearbeiten(m),
                  ),
                );
              },
            ),
    );
  }
}

/// Screen: Mitarbeiter bearbeiten/neu
class _NfsMitarbeiterBearbeitenScreen extends StatefulWidget {
  final String companyId;
  final SchichtplanMitarbeiter? mitarbeiter;
  final VoidCallback onSaved;

  const _NfsMitarbeiterBearbeitenScreen({
    required this.companyId,
    this.mitarbeiter,
    required this.onSaved,
  });

  @override
  State<_NfsMitarbeiterBearbeitenScreen> createState() =>
      _NfsMitarbeiterBearbeitenScreenState();
}

class _NfsMitarbeiterBearbeitenScreenState
    extends State<_NfsMitarbeiterBearbeitenScreen> {
  final _nfsService = SchichtplanNfsService();
  final _mitarbeiterService = MitarbeiterService();
  final _personalnummerCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _vornameCtrl = TextEditingController();
  final _nachnameCtrl = TextEditingController();
  final _strasseCtrl = TextEditingController();
  final _hausnummerCtrl = TextEditingController();
  final _plzCtrl = TextEditingController();
  final _ortCtrl = TextEditingController();
  final _telefonCtrl = TextEditingController();
  String _rolle = 'user';

  @override
  void initState() {
    super.initState();
    final m = widget.mitarbeiter;
    if (m != null) {
      _personalnummerCtrl.text = m.personalnummer ?? '';
      _emailCtrl.text = m.email ?? '';
      _vornameCtrl.text = m.vorname ?? '';
      _nachnameCtrl.text = m.nachname ?? '';
      _strasseCtrl.text = m.strasse ?? '';
      _hausnummerCtrl.text = m.hausnummer ?? '';
      _plzCtrl.text = m.plz ?? '';
      _ortCtrl.text = m.ort ?? '';
      _telefonCtrl.text = m.telefonnummer ?? '';
      final r = (m.role ?? '').toLowerCase();
      _rolle = ['admin', 'koordinator', 'user'].contains(r) ? r : 'user';
    }
  }

  @override
  void dispose() {
    _personalnummerCtrl.dispose();
    _emailCtrl.dispose();
    _vornameCtrl.dispose();
    _nachnameCtrl.dispose();
    _strasseCtrl.dispose();
    _hausnummerCtrl.dispose();
    _plzCtrl.dispose();
    _ortCtrl.dispose();
    _telefonCtrl.dispose();
    super.dispose();
  }

  Future<void> _speichern() async {
    final email = _emailCtrl.text.trim();
    final vorname = _vornameCtrl.text.trim();
    final nachname = _nachnameCtrl.text.trim();
    if (email.isEmpty || vorname.isEmpty || nachname.isEmpty) return;
    final personalnummer = _personalnummerCtrl.text.trim().isEmpty ? null : _personalnummerCtrl.text.trim();
    final strasse = _strasseCtrl.text.trim().isEmpty ? null : _strasseCtrl.text.trim();
    final hausnummer = _hausnummerCtrl.text.trim().isEmpty ? null : _hausnummerCtrl.text.trim();
    final plz = _plzCtrl.text.trim().isEmpty ? null : _plzCtrl.text.trim();
    final ort = _ortCtrl.text.trim().isEmpty ? null : _ortCtrl.text.trim();
    final telefon = _telefonCtrl.text.trim().isEmpty ? null : _telefonCtrl.text.trim();
    final role = _rolle.trim().isEmpty ? null : _rolle;
    if (widget.mitarbeiter != null) {
      await _mitarbeiterService.updateMitarbeiterFields(
        widget.companyId,
        widget.mitarbeiter!.id,
        {
          'personalnummer': personalnummer,
          'email': email,
          'vorname': vorname,
          'nachname': nachname,
          'strasse': strasse,
          'hausnummer': hausnummer,
          'plz': plz,
          'ort': ort,
          'telefon': telefon,
          'role': role,
        },
      );
    } else {
      final mitarbeiter = Mitarbeiter(
        id: '',
        vorname: vorname,
        nachname: nachname,
        email: email,
        personalnummer: personalnummer,
        strasse: strasse,
        hausnummer: hausnummer,
        plz: plz,
        ort: ort,
        telefon: telefon,
        role: role,
      );
      await _mitarbeiterService.createMitarbeiter(widget.companyId, mitarbeiter);
    }
    if (mounted) widget.onSaved();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.mitarbeiter != null ? 'Mitarbeiter bearbeiten' : 'Neuer Mitarbeiter'),
        leading: IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)),
        actions: [
          FilledButton(
            onPressed: _speichern,
            child: Text(widget.mitarbeiter != null ? 'Speichern' : 'Hinzufügen'),
          ),
          const SizedBox(width: 16),
        ],
      ),
      body: SingleChildScrollView(
        padding: EdgeInsets.all(Responsive.horizontalPadding(context)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _personalnummerCtrl,
                    decoration: const InputDecoration(labelText: 'Personalnummer', border: OutlineInputBorder()),
                    keyboardType: TextInputType.number,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _emailCtrl,
                    decoration: const InputDecoration(labelText: 'E-Mail', border: OutlineInputBorder()),
                    keyboardType: TextInputType.emailAddress,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _vornameCtrl,
                    decoration: const InputDecoration(labelText: 'Vorname', border: OutlineInputBorder()),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _nachnameCtrl,
                    decoration: const InputDecoration(labelText: 'Name', border: OutlineInputBorder()),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  flex: 2,
                  child: TextField(
                    controller: _strasseCtrl,
                    decoration: const InputDecoration(labelText: 'Straße', border: OutlineInputBorder()),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _hausnummerCtrl,
                    decoration: const InputDecoration(labelText: 'Hausnummer', border: OutlineInputBorder()),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _plzCtrl,
                    decoration: const InputDecoration(labelText: 'PLZ', border: OutlineInputBorder()),
                    keyboardType: TextInputType.number,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: TextField(
                    controller: _ortCtrl,
                    decoration: const InputDecoration(labelText: 'Ort (Wohnort)', border: OutlineInputBorder()),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  flex: 2,
                  child: TextField(
                    controller: _telefonCtrl,
                    decoration: const InputDecoration(labelText: 'Telefonnummer', border: OutlineInputBorder()),
                    keyboardType: TextInputType.phone,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: DropdownButtonFormField<String>(
                    value: _rolle,
                    decoration: const InputDecoration(labelText: 'Rolle', border: OutlineInputBorder()),
                    items: const [
                      DropdownMenuItem(value: 'admin', child: Text('Admin')),
                      DropdownMenuItem(value: 'koordinator', child: Text('Koordinator')),
                      DropdownMenuItem(value: 'user', child: Text('User')),
                    ],
                    onChanged: (v) => setState(() => _rolle = v ?? 'user'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
