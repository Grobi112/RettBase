import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../models/checkliste_model.dart';
import '../services/checklisten_service.dart';
import '../services/auth_service.dart';

/// Formular zum Erstellen/Bearbeiten einer Checkliste
class ChecklisteErstellenScreen extends StatefulWidget {
  final String companyId;
  final Checkliste? checkliste;
  final VoidCallback onSaved;
  final VoidCallback onCancel;

  const ChecklisteErstellenScreen({
    super.key,
    required this.companyId,
    this.checkliste,
    required this.onSaved,
    required this.onCancel,
  });

  @override
  State<ChecklisteErstellenScreen> createState() => _ChecklisteErstellenScreenState();
}

class _ChecklisteErstellenScreenState extends State<ChecklisteErstellenScreen> {
  final _service = ChecklistenService();
  final _authService = AuthService();
  final _titleCtrl = TextEditingController();
  final List<_SectionState> _sections = [];
  final List<bool> _sectionExpanded = [];
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _titleCtrl.text = widget.checkliste?.title ?? '';
    for (final s in widget.checkliste?.sections ?? []) {
      _sections.add(_SectionState(
        title: s.title,
        items: s.items.map<_ItemState>((i) => _ItemState(label: i.label, type: i.type, isRequired: i.isRequired)).toList(),
      ));
      _sectionExpanded.add(false);
    }
    if (_sections.isEmpty) _addBereich();
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    for (final s in _sections) {
      s.titleCtrl.dispose();
      for (final i in s.items) i.labelCtrl.dispose();
    }
    super.dispose();
  }

  void _addBereich() {
    setState(() {
      _sections.add(_SectionState(title: '', items: []));
      _sectionExpanded.add(false);
    });
  }

  void _moveBereichUp(int sectionIndex) {
    if (sectionIndex <= 0 || sectionIndex >= _sections.length) return;
    setState(() {
      final tmp = _sections[sectionIndex];
      _sections[sectionIndex] = _sections[sectionIndex - 1];
      _sections[sectionIndex - 1] = tmp;
      final tmpExp = _sectionExpanded[sectionIndex];
      _sectionExpanded[sectionIndex] = _sectionExpanded[sectionIndex - 1];
      _sectionExpanded[sectionIndex - 1] = tmpExp;
    });
  }

  void _moveBereichDown(int sectionIndex) {
    if (sectionIndex < 0 || sectionIndex >= _sections.length - 1) return;
    setState(() {
      final tmp = _sections[sectionIndex];
      _sections[sectionIndex] = _sections[sectionIndex + 1];
      _sections[sectionIndex + 1] = tmp;
      final tmpExp = _sectionExpanded[sectionIndex];
      _sectionExpanded[sectionIndex] = _sectionExpanded[sectionIndex + 1];
      _sectionExpanded[sectionIndex + 1] = tmpExp;
    });
  }

  void _removeBereich(int sectionIndex) {
    if (_sections.length <= 1 || sectionIndex < 0 || sectionIndex >= _sections.length) return;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Bereich löschen'),
        content: const Text('Möchtest du diesen Bereich wirklich löschen?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Abbrechen'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Löschen', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    ).then((confirmed) {
      if (confirmed == true && mounted) {
        setState(() {
          if (_sections.length > 1 && sectionIndex >= 0 && sectionIndex < _sections.length) {
            final s = _sections[sectionIndex];
            s.titleCtrl.dispose();
            for (final i in s.items) i.labelCtrl.dispose();
            _sections.removeAt(sectionIndex);
            _sectionExpanded.removeAt(sectionIndex);
          }
        });
      }
    });
  }

  void _addPunkt(int sectionIndex) {
    setState(() {
      if (sectionIndex >= 0 && sectionIndex < _sections.length) {
        _sections[sectionIndex].items.add(_ItemState(label: '', type: 'checkbox', isRequired: false));
      }
    });
  }

  void _movePunktUp(int sectionIndex, int itemIndex) {
    if (itemIndex <= 0 || sectionIndex < 0 || sectionIndex >= _sections.length) return;
    final items = _sections[sectionIndex].items;
    if (itemIndex >= items.length) return;
    setState(() {
      final tmp = items[itemIndex];
      items[itemIndex] = items[itemIndex - 1];
      items[itemIndex - 1] = tmp;
    });
  }

  void _movePunktDown(int sectionIndex, int itemIndex) {
    if (sectionIndex < 0 || sectionIndex >= _sections.length) return;
    final items = _sections[sectionIndex].items;
    if (itemIndex < 0 || itemIndex >= items.length - 1) return;
    setState(() {
      final tmp = items[itemIndex];
      items[itemIndex] = items[itemIndex + 1];
      items[itemIndex + 1] = tmp;
    });
  }

  void _removePunkt(int sectionIndex, int itemIndex) {
    setState(() {
      if (sectionIndex >= 0 && sectionIndex < _sections.length) {
        final items = _sections[sectionIndex].items;
        if (itemIndex >= 0 && itemIndex < items.length) {
          items[itemIndex].labelCtrl.dispose();
          items.removeAt(itemIndex);
        }
      }
    });
  }

  Future<void> _save() async {
    final title = _titleCtrl.text.trim();
    if (title.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Bitte einen Titel eingeben.')));
      return;
    }
    final ts = DateTime.now().millisecondsSinceEpoch;
    final validSections = <ChecklisteSection>[];
    for (var si = 0; si < _sections.length; si++) {
      final s = _sections[si];
      final sectionTitle = s.titleCtrl.text.trim();
      if (sectionTitle.isEmpty) continue;
      final filtered = s.items.where((i) => i.labelCtrl.text.trim().isNotEmpty).toList();
      final items = List.generate(filtered.length, (i) {
        final item = filtered[i];
        return ChecklisteItem(id: '${ts}_${si}_$i', label: item.labelCtrl.text.trim(), type: item.type, isRequired: item.isRequired);
      });
      validSections.add(ChecklisteSection(id: '${ts}_$si', title: sectionTitle, items: items));
    }
    if (validSections.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Bitte mindestens einen Bereich mit Überschrift hinzufügen.')));
      return;
    }
    final hasPoints = validSections.any((s) => s.items.isNotEmpty);
    if (!hasPoints) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Bitte mindestens einen Punkt in einem Bereich hinzufügen.')));
      return;
    }

    setState(() => _saving = true);
    try {
      final uid = _authService.currentUser?.uid ?? '';
      final c = Checkliste(
        id: widget.checkliste?.id ?? '',
        title: title,
        sections: validSections,
        createdAt: widget.checkliste?.createdAt ?? DateTime.now(),
        createdBy: widget.checkliste?.createdBy ?? uid,
      );
      if (widget.checkliste != null) {
        await _service.updateCheckliste(widget.companyId, widget.checkliste!.id, c);
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Checkliste gespeichert.')));
      } else {
        await _service.createCheckliste(widget.companyId, c, uid);
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Checkliste erstellt.')));
      }
      widget.onSaved();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Fehler: $e')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _confirmDelete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Checkliste löschen'),
        content: const Text('Möchtest du diese Checkliste wirklich löschen?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Abbrechen')),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Löschen', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _saving = true);
    final messenger = ScaffoldMessenger.of(context);
    var didPop = false;
    try {
      await _service.deleteCheckliste(widget.companyId, widget.checkliste!.id);
      if (!mounted) return;
      messenger.showSnackBar(const SnackBar(content: Text('Checkliste gelöscht.')));
      widget.onSaved();
      didPop = true;
    } catch (e) {
      if (mounted) messenger.showSnackBar(SnackBar(content: Text('Fehler: $e')));
    } finally {
      if (mounted && !didPop) setState(() => _saving = false);
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
        leading: IconButton(icon: const Icon(Icons.close), onPressed: widget.onCancel),
        title: Text(
          widget.checkliste == null ? 'Neue Checkliste' : 'Checkliste bearbeiten',
          style: TextStyle(color: AppTheme.primary, fontWeight: FontWeight.w600),
        ),
        actions: [
          TextButton(onPressed: widget.onCancel, child: const Text('Abbrechen')),
          FilledButton(
            onPressed: _saving ? null : _save,
            style: FilledButton.styleFrom(backgroundColor: AppTheme.primary),
            child: _saving ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Text('Speichern'),
          ),
          const SizedBox(width: 16),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextFormField(
              controller: _titleCtrl,
              decoration: const InputDecoration(
                labelText: 'Titel der Checkliste',
                hintText: 'z.B. Fahrzeug-Check vor Fahrtantritt',
                border: OutlineInputBorder(),
              ),
              textCapitalization: TextCapitalization.none,
            ),
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Bereiche', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Colors.grey[800])),
                TextButton.icon(
                  onPressed: _addBereich,
                  icon: const Icon(Icons.folder_open, size: 20),
                  label: const Text('Bereich hinzufügen'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            ...List.generate(_sections.length, (i) => _buildBereich(i)),
            if (widget.checkliste != null) ...[
              const SizedBox(height: 24),
              OutlinedButton.icon(
                onPressed: _saving ? null : _confirmDelete,
                icon: const Icon(Icons.delete, color: Colors.red, size: 20),
                label: const Text('Checkliste löschen', style: TextStyle(color: Colors.red)),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildBereich(int sectionIndex) {
    final section = _sections[sectionIndex];
    final isExpanded = sectionIndex < _sectionExpanded.length ? _sectionExpanded[sectionIndex] : false;
    return Card(
      margin: const EdgeInsets.only(bottom: 20),
      elevation: 2,
      color: isExpanded ? Colors.grey[300]! : Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: AppTheme.primary.withOpacity(0.3), width: 1),
      ),
      child: ExpansionTile(
        initiallyExpanded: isExpanded,
        onExpansionChanged: (expanded) {
          if (sectionIndex < _sectionExpanded.length) {
            setState(() => _sectionExpanded[sectionIndex] = expanded);
          }
        },
        collapsedShape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        childrenPadding: const EdgeInsets.only(left: 24, right: 16, bottom: 16),
        title: Row(
          children: [
            Expanded(
              child: TextFormField(
                controller: section.titleCtrl,
                decoration: InputDecoration(
                  labelText: 'Überschrift Bereich ${sectionIndex + 1}',
                  hintText: 'z.B. Technische Ausstattung',
                  border: const OutlineInputBorder(),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  isDense: true,
                ),
                textCapitalization: TextCapitalization.none,
              ),
            ),
            const SizedBox(width: 4),
            IconButton(
              icon: const Icon(Icons.arrow_upward, size: 20),
              onPressed: sectionIndex > 0 ? () => _moveBereichUp(sectionIndex) : null,
              tooltip: 'Bereich nach oben verschieben',
            ),
            IconButton(
              icon: const Icon(Icons.arrow_downward, size: 20),
              onPressed: sectionIndex < _sections.length - 1 ? () => _moveBereichDown(sectionIndex) : null,
              tooltip: 'Bereich nach unten verschieben',
            ),
            IconButton(
              icon: const Icon(Icons.delete_outline, color: Colors.red, size: 22),
              onPressed: _sections.length > 1 ? () => _removeBereich(sectionIndex) : null,
              tooltip: 'Bereich entfernen',
            ),
          ],
        ),
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Punkte', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Colors.grey[800])),
              TextButton.icon(
                onPressed: () => _addPunkt(sectionIndex),
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Punkt'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ...List.generate(section.items.length, (i) => _buildPunktRow(sectionIndex, i)),
          if (section.items.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(
                'Keine Punkte. Klicken Sie auf „Punkt" um Punkte hinzuzufügen.',
                style: TextStyle(fontSize: 13, color: Colors.grey[600]),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildPunktRow(int sectionIndex, int itemIndex) {
    final item = _sections[sectionIndex].items[itemIndex];
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.grey[50],
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: Colors.grey[300]!),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: TextFormField(
                  controller: item.labelCtrl,
                  decoration: InputDecoration(
                    labelText: 'Bezeichnung',
                    hintText: 'z.B. Reifendruck prüfen',
                    border: const OutlineInputBorder(),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    isDense: true,
                  ),
                  textCapitalization: TextCapitalization.none,
                ),
              ),
              const SizedBox(width: 4),
              IconButton(
                icon: const Icon(Icons.arrow_upward, size: 18),
                onPressed: itemIndex > 0 ? () => _movePunktUp(sectionIndex, itemIndex) : null,
                tooltip: 'Punkt nach oben verschieben',
              ),
              IconButton(
                icon: const Icon(Icons.arrow_downward, size: 18),
                onPressed: itemIndex < _sections[sectionIndex].items.length - 1 ? () => _movePunktDown(sectionIndex, itemIndex) : null,
                tooltip: 'Punkt nach unten verschieben',
              ),
              IconButton(
                icon: const Icon(Icons.delete_outline, color: Colors.red, size: 20),
                onPressed: () => _removePunkt(sectionIndex, itemIndex),
                tooltip: 'Punkt entfernen',
              ),
              const SizedBox(width: 8),
              Text('Pflichtfeld', style: TextStyle(fontSize: 14)),
              const SizedBox(width: 4),
              Switch(
                value: item.isRequired,
                onChanged: (v) => setState(() => item.isRequired = v ?? false),
                activeColor: AppTheme.primary,
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text('Anzeige:', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: Colors.grey[600])),
          const SizedBox(height: 4),
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'checkbox', icon: Icon(Icons.check_box_outlined), label: Text('Checkbox')),
              ButtonSegment(value: 'slider', icon: Icon(Icons.toggle_on), label: Text('Schalter')),
              ButtonSegment(value: 'text', icon: Icon(Icons.text_fields), label: Text('Eingabefeld')),
            ],
            selected: {item.type},
            onSelectionChanged: (v) => setState(() => item.type = v.first),
          ),
        ],
      ),
    );
  }
}

class _SectionState {
  final TextEditingController titleCtrl = TextEditingController();
  final List<_ItemState> items;

  _SectionState({required String title, required this.items}) {
    titleCtrl.text = title;
  }
}

class _ItemState {
  final TextEditingController labelCtrl = TextEditingController();
  String type;
  bool isRequired;

  _ItemState({required String label, required this.type, this.isRequired = false}) {
    labelCtrl.text = label;
  }
}
