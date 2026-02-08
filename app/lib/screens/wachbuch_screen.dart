import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../services/wachbuch_service.dart';
import '../services/auth_service.dart';
import '../services/auth_data_service.dart';
import 'wachbuch_uebersicht_screen.dart';

/// Wachbuch – analog Einsatztagebuch-OVD
class WachbuchScreen extends StatefulWidget {
  final String companyId;
  final VoidCallback onBack;

  const WachbuchScreen({
    required this.companyId,
    required this.onBack,
  });

  @override
  State<WachbuchScreen> createState() => _WachbuchScreenState();
}

class _WachbuchScreenState extends State<WachbuchScreen> {
  final _service = WachbuchService();
  final _authService = AuthService();
  final _authDataService = AuthDataService();

  String _dayId = WachbuchService.getCurrentDayId();
  WachbuchTag? _dayDoc;
  List<WachbuchEintrag> _eintraege = [];
  List<WachbuchEreignis> _ereignisse = [];
  WachbuchConfig _config = WachbuchConfig(editAllowedRoles: ['superadmin', 'admin', 'leiterssd']);
  String? _error;
  bool _loading = true;

  String get _eintragendePerson {
    final auth = _authData;
    if (auth?.displayName != null && auth!.displayName!.isNotEmpty) return auth.displayName!;
    if (auth?.vorname != null && auth!.vorname!.isNotEmpty) return auth.vorname!;
    return _authService.currentUser?.email ?? 'Unbekannt';
  }

  AuthData? _authData;

  bool get _canEdit {
    if (_authData == null) return false;
    final role = (_authData!.role).toLowerCase();
    if (_config.editAllowedRoles.any((r) => r.toLowerCase() == role)) return true;
    if (_service.isPastDay(_dayId) || _service.isDayClosed(_dayDoc)) return false;
    return true;
  }

  /// Nur eigene Einträge können bearbeitet werden. Fremde Einträge nur von Admin, Geschäftsführung, Rettungsdienstleitung, Wachleitung.
  bool _canEditEintrag(WachbuchEintrag e) {
    if (!_canEdit) return false;
    final uid = _authService.currentUser?.uid;
    final role = (_authData?.role ?? '').toLowerCase();
    const privilegedRoles = ['admin', 'geschaeftsfuehrung', 'rettungsdienstleitung', 'wachleitung'];
    if (privilegedRoles.contains(role)) return true;
    return uid != null && e.createdBy != null && uid == e.createdBy;
  }

  bool get _canManageEvents {
    final role = (_authData?.role ?? '').toLowerCase();
    return ['superadmin', 'admin', 'leiterssd', 'koordinator'].contains(role);
  }

  @override
  void initState() {
    super.initState();
    _loadAuth();
  }

  Future<void> _loadAuth() async {
    final user = _authService.currentUser;
    if (user == null) {
      setState(() => _loading = false);
      return;
    }
    final auth = await _authDataService.getAuthData(user.uid, user.email ?? '', widget.companyId);
    if (mounted) {
      setState(() => _authData = auth);
      _load();
    }
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final user = _authService.currentUser;
      final uid = user?.uid ?? '';
      final name = _eintragendePerson;

      final config = await _service.loadConfig(widget.companyId);
      final dayDoc = await _service.ensureDay(widget.companyId, _dayId, uid, name);
      final ereignisse = await _service.loadEreignisse(widget.companyId);

      if (mounted) {
        setState(() {
          _config = config;
          _dayDoc = dayDoc;
          _ereignisse = ereignisse;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: AppTheme.primary,
        elevation: 1,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: widget.onBack,
        ),
        title: Text('Wachbuch', style: TextStyle(color: AppTheme.primary, fontWeight: FontWeight.w600)),
        actions: [
          PopupMenuButton<String>(
            icon: Icon(Icons.more_vert, color: AppTheme.primary),
            onSelected: (v) {
              if (v == 'uebersicht') {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => WachbuchUebersichtScreen(
                      companyId: widget.companyId,
                      onBack: () => Navigator.of(context).pop(),
                      onSelectDay: (dayId) {
                        Navigator.of(context).pop();
                        setState(() {
                          _dayId = dayId;
                          _load();
                        });
                      },
                    ),
                  ),
                );
              } else if (v == 'ereignisse' && _canManageEvents) {
                _openEreignisseVerwalten();
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem(value: 'uebersicht', child: Text('Übersicht')),
              if (_canManageEvents) const PopupMenuItem(value: 'ereignisse', child: Text('Ereignisse verwalten')),
            ],
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (_error != null)
                      Container(
                        padding: const EdgeInsets.all(12),
                        margin: const EdgeInsets.only(bottom: 16),
                        decoration: BoxDecoration(color: AppTheme.errorBg, borderRadius: BorderRadius.circular(8), border: Border.all(color: AppTheme.errorBorder)),
                        child: Text(_error!, style: const TextStyle(color: Colors.red)),
                      ),
                    _buildDateSelector(),
                    const SizedBox(height: 16),
                    _buildHeader(),
                    const SizedBox(height: 12),
                    _buildEintraegeList(),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildDateSelector() {
    final parts = _dayId.split('.');
    DateTime picked = DateTime.now();
    if (parts.length == 3) {
      final day = int.tryParse(parts[0]) ?? DateTime.now().day;
      final month = int.tryParse(parts[1]) ?? DateTime.now().month;
      final year = int.tryParse(parts[2]) ?? DateTime.now().year;
      picked = DateTime(year, month, day);
    }
    String toDayId(DateTime d) => '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.${d.year}';

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Datum auswählen', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
            const SizedBox(height: 8),
            Row(
              children: [
                IconButton(
                  onPressed: () {
                    final prev = picked.subtract(const Duration(days: 1));
                    setState(() {
                      _dayId = toDayId(prev);
                      _load();
                    });
                  },
                  icon: const Icon(Icons.chevron_left),
                  style: IconButton.styleFrom(backgroundColor: Colors.grey.shade100),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton(
                    onPressed: () async {
                      final date = await showDatePicker(context: context, initialDate: picked, firstDate: DateTime(2020), lastDate: DateTime(2030));
                      if (date != null) {
                        setState(() {
                          _dayId = toDayId(date);
                          _load();
                        });
                      }
                    },
                    style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 12)),
                    child: Text(_dayId, style: const TextStyle(fontSize: 16)),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  onPressed: () {
                    final next = picked.add(const Duration(days: 1));
                    setState(() {
                      _dayId = toDayId(next);
                      _load();
                    });
                  },
                  icon: const Icon(Icons.chevron_right),
                  style: IconButton.styleFrom(backgroundColor: Colors.grey.shade100),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        const Text('Wachbuch', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppTheme.textPrimary)),
        if (_canEdit)
          FilledButton(
            onPressed: _openAddEintrag,
            style: FilledButton.styleFrom(backgroundColor: AppTheme.primary, foregroundColor: Colors.white),
            child: const Text('Ereignis hinzufügen'),
          ),
      ],
    );
  }

  Widget _buildEintraegeList() {
    return StreamBuilder<List<WachbuchEintrag>>(
      stream: _service.streamEintraege(widget.companyId, _dayId),
      builder: (context, snapshot) {
        final list = snapshot.data ?? _eintraege;
        if (list.isEmpty) {
          return Card(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Center(
                child: Column(
                  children: [
                    Icon(Icons.book_outlined, size: 48, color: AppTheme.textMuted),
                    const SizedBox(height: 12),
                    Text('Keine Einträge für $_dayId', style: TextStyle(color: AppTheme.textMuted)),
                    if (_canEdit)
                      Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: Text('Klicken Sie auf "Ereignis hinzufügen" um einen Eintrag anzulegen', style: TextStyle(fontSize: 13, color: AppTheme.textMuted)),
                      ),
                  ],
                ),
              ),
            ),
          );
        }

        return Card(
          child: ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: list.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, i) {
              final e = list[i];
              String uhrzeit = e.uhrzeit;
              if (uhrzeit.contains('.')) uhrzeit = uhrzeit.replaceAll('.', ':');
              if (uhrzeit.length > 5) uhrzeit = uhrzeit.substring(0, 5);
              final canEditThis = _canEditEintrag(e);
              return ListTile(
                onTap: canEditThis ? () => _openEditEintrag(e) : null,
                title: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(width: 55, child: Text(uhrzeit, style: const TextStyle(fontWeight: FontWeight.w600))),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(e.ereignis, style: const TextStyle(fontWeight: FontWeight.w500)),
                          if (e.text.isNotEmpty) Text(e.text, style: TextStyle(fontSize: 13, color: AppTheme.textSecondary), maxLines: 2, overflow: TextOverflow.ellipsis),
                          const SizedBox(height: 4),
                          Text(e.eintragendePerson, style: TextStyle(fontSize: 12, color: AppTheme.textMuted)),
                        ],
                      ),
                    ),
                    if (canEditThis)
                      IconButton(
                        icon: const Icon(Icons.delete_outline, color: Colors.red, size: 20),
                        onPressed: () => _deleteEintrag(e),
                      ),
                  ],
                ),
              );
            },
          ),
        );
      },
    );
  }

  void _openAddEintrag() {
    _showEintragDialog();
  }

  void _openEditEintrag(WachbuchEintrag e) {
    if (!_canEditEintrag(e)) return;
    _showEintragDialog(eintrag: e);
  }

  Future<void> _showEintragDialog({WachbuchEintrag? eintrag}) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (ctx) => _EintragFormScreen(
          eintrag: eintrag,
          dayId: _dayId,
          ereignisse: _ereignisse,
          eintragendePerson: _eintragendePerson,
          onSave: (data) async {
            Navigator.of(ctx).pop();
            await _saveEintrag(eintrag?.id, data);
          },
          onCancel: () => Navigator.of(ctx).pop(),
        ),
      ),
    );
  }

  Future<void> _saveEintrag(String? eintragId, WachbuchEintragData data) async {
    try {
      final uid = _authService.currentUser?.uid ?? '';
      if (eintragId != null) {
        await _service.updateEintrag(widget.companyId, _dayId, eintragId, data, uid);
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Eintrag aktualisiert.')));
      } else {
        await _service.saveEintrag(widget.companyId, _dayId, data, uid, _eintragendePerson);
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Eintrag hinzugefügt.')));
      }
      _load();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Fehler: $e')));
    }
  }

  Future<void> _deleteEintrag(WachbuchEintrag e) async {
    if (!_canEditEintrag(e)) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Eintrag löschen'),
        content: const Text('Möchten Sie diesen Eintrag wirklich löschen?'),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Abbrechen')),
          FilledButton(onPressed: () => Navigator.of(ctx).pop(true), style: FilledButton.styleFrom(backgroundColor: Colors.red), child: const Text('Löschen')),
        ],
      ),
    );
    if (ok == true) {
      try {
        await _service.deleteEintrag(widget.companyId, _dayId, e.id);
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Eintrag gelöscht.')));
        _load();
      } catch (e) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Fehler: $e')));
      }
    }
  }

  void _openEreignisseVerwalten() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (ctx) => _EreignisseVerwaltenScreen(
          companyId: widget.companyId,
          ereignisse: _ereignisse,
          onSaved: () async {
            final list = await _service.loadEreignisse(widget.companyId);
            if (mounted) setState(() => _ereignisse = list);
          },
        ),
      ),
    );
  }
}

class _EintragFormScreen extends StatefulWidget {
  final WachbuchEintrag? eintrag;
  final String dayId;
  final List<WachbuchEreignis> ereignisse;
  final String eintragendePerson;
  final void Function(WachbuchEintragData data) onSave;
  final VoidCallback onCancel;

  const _EintragFormScreen({
    this.eintrag,
    required this.dayId,
    required this.ereignisse,
    required this.eintragendePerson,
    required this.onSave,
    required this.onCancel,
  });

  @override
  State<_EintragFormScreen> createState() => _EintragFormScreenState();
}

class _EintragFormScreenState extends State<_EintragFormScreen> {
  late final TextEditingController _datumCtrl;
  late final TextEditingController _uhrzeitCtrl;
  late final TextEditingController _textCtrl;
  late final TextEditingController _ereignisCtrl;
  String? _selectedEreignis;

  @override
  void initState() {
    super.initState();
    final e = widget.eintrag;
    _datumCtrl = TextEditingController(text: e?.datum ?? widget.dayId);
    String uhrzeit = e?.uhrzeit ?? '';
    if (uhrzeit.contains(':')) uhrzeit = uhrzeit.replaceAll(':', '.');
    if (uhrzeit.length > 5) uhrzeit = uhrzeit.substring(0, 5);
    _uhrzeitCtrl = TextEditingController(
      text: uhrzeit.isEmpty ? '${DateTime.now().hour.toString().padLeft(2, '0')}.${DateTime.now().minute.toString().padLeft(2, '0')}' : uhrzeit,
    );
    _textCtrl = TextEditingController(text: e?.text ?? '');
    final existingEvent = e?.ereignis ?? '';
    final isInDropdown = widget.ereignisse.any((x) => x.active && x.name == existingEvent);
    if (isInDropdown) {
      _selectedEreignis = existingEvent;
      _ereignisCtrl = TextEditingController();
    } else {
      _selectedEreignis = null;
      _ereignisCtrl = TextEditingController(text: existingEvent);
    }
  }

  @override
  void dispose() {
    _datumCtrl.dispose();
    _uhrzeitCtrl.dispose();
    _textCtrl.dispose();
    _ereignisCtrl.dispose();
    super.dispose();
  }

  void _save() {
    final datum = _datumCtrl.text.trim();
    final uhrzeit = _uhrzeitCtrl.text.trim().replaceAll(':', '.');
    final manualEreignis = _ereignisCtrl.text.trim();
    final dropdownEreignis = _selectedEreignis != null && _selectedEreignis!.isNotEmpty ? _selectedEreignis!.trim() : '';
    final ereignis = manualEreignis.isNotEmpty ? manualEreignis : dropdownEreignis;
    final text = _textCtrl.text.trim();
    if (datum.isEmpty || uhrzeit.isEmpty || text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Bitte alle Pflichtfelder ausfüllen.')));
      return;
    }
    if (ereignis.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Bitte ein Ereignis auswählen oder manuell eingeben.')));
      return;
    }
    widget.onSave(WachbuchEintragData(
      datum: datum,
      uhrzeit: uhrzeit,
      ereignis: ereignis,
      text: text,
      eintragendePerson: widget.eintragendePerson,
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: AppTheme.primary,
        elevation: 1,
        leading: IconButton(icon: const Icon(Icons.close), onPressed: widget.onCancel),
        title: Text(widget.eintrag == null ? 'Neues Ereignis' : 'Ereignis bearbeiten', style: TextStyle(color: AppTheme.primary, fontWeight: FontWeight.w600)),
        actions: [
          TextButton(onPressed: widget.onCancel, child: const Text('Abbrechen')),
          FilledButton(onPressed: _save, child: const Text('Speichern')),
          const SizedBox(width: 16),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _datumCtrl,
                    decoration: const InputDecoration(labelText: 'Datum (TT.MM.JJJJ)'),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: TextFormField(
                    controller: _uhrzeitCtrl,
                    decoration: const InputDecoration(labelText: 'Uhrzeit (HH.MM)'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: DropdownButtonFormField<String?>(
                    value: _selectedEreignis,
                    decoration: InputDecoration(
                      labelText: 'Ereignis *',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide(color: Colors.grey.shade300),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: const BorderSide(color: AppTheme.primary, width: 2),
                      ),
                      filled: true,
                      fillColor: Colors.grey.shade50,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                    ),
                    borderRadius: BorderRadius.circular(10),
                    dropdownColor: Colors.white,
                    icon: Icon(Icons.keyboard_arrow_down_rounded, color: AppTheme.primary),
                    items: [
                      const DropdownMenuItem<String?>(value: null, child: Text('Bitte wählen')),
                      ...widget.ereignisse.where((x) => x.active).map((e) => DropdownMenuItem<String?>(value: e.name, child: Text(e.name))),
                    ],
                    onChanged: (v) => setState(() {
                      _selectedEreignis = v;
                      if (v != null && v.isNotEmpty) _ereignisCtrl.clear();
                    }),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: TextFormField(
                    controller: _ereignisCtrl,
                    decoration: const InputDecoration(labelText: 'Ereignis manuell eingeben'),
                    onChanged: (_) => setState(() {
                      if (_ereignisCtrl.text.trim().isNotEmpty) _selectedEreignis = null;
                    }),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _textCtrl,
              decoration: const InputDecoration(labelText: 'Text *'),
              maxLines: 6,
              minLines: 4,
            ),
            const SizedBox(height: 16),
            TextFormField(
              initialValue: widget.eintragendePerson,
              decoration: const InputDecoration(labelText: 'Eintragende Person'),
              readOnly: true,
              enabled: false,
            ),
          ],
        ),
      ),
    );
  }
}

class _EreignisseVerwaltenScreen extends StatefulWidget {
  final String companyId;
  final List<WachbuchEreignis> ereignisse;
  final VoidCallback onSaved;

  const _EreignisseVerwaltenScreen({required this.companyId, required this.ereignisse, required this.onSaved});

  @override
  State<_EreignisseVerwaltenScreen> createState() => _EreignisseVerwaltenScreenState();
}

class _EreignisseVerwaltenScreenState extends State<_EreignisseVerwaltenScreen> {
  final _service = WachbuchService();
  late List<WachbuchEreignis> _list;
  final _newNameCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _list = List.from(widget.ereignisse);
  }

  @override
  void dispose() {
    _newNameCtrl.dispose();
    super.dispose();
  }

  Future<void> _add() async {
    final name = _newNameCtrl.text.trim();
    if (name.isEmpty) return;
    try {
      final maxOrder = _list.isEmpty ? 0 : _list.map((e) => e.order).reduce((a, b) => a > b ? a : b);
      await _service.saveEreignis(widget.companyId, name, maxOrder + 1);
      _newNameCtrl.clear();
      widget.onSaved();
      if (mounted) setState(() => _list = [..._list, WachbuchEreignis(id: name, name: name, order: maxOrder + 1)]);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Fehler: $e')));
    }
  }

  Future<void> _delete(WachbuchEreignis e) async {
    try {
      await _service.deleteEreignis(widget.companyId, e.id);
      widget.onSaved();
      if (mounted) setState(() => _list = _list.where((x) => x.id != e.id).toList());
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Fehler: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: AppTheme.primary,
        elevation: 1,
        leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => Navigator.of(context).pop()),
        title: Text('Ereignisse verwalten', style: TextStyle(color: AppTheme.primary, fontWeight: FontWeight.w600)),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _newNameCtrl,
                    decoration: const InputDecoration(labelText: 'Neues Ereignis'),
                    onSubmitted: (_) => _add(),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton(onPressed: _add, child: const Text('Hinzufügen')),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: ListView.builder(
              itemCount: _list.length,
              itemBuilder: (context, i) {
                final e = _list[i];
                return ListTile(
                  title: Text(e.name),
                  trailing: IconButton(icon: const Icon(Icons.delete_outline, color: Colors.red), onPressed: () => _delete(e)),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
