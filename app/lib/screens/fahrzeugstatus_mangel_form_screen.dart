import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../services/fahrzeugstatus_service.dart';
import '../services/auth_data_service.dart';
import '../services/auth_service.dart';

/// Vollbild-Formular für Neuer Mangel / Mangel bearbeiten.
/// Wie Fahrtenbuch: neues Fenster statt Popup.
class FahrzeugstatusMangelFormScreen extends StatefulWidget {
  final String companyId;
  final String fahrzeugId;
  final FahrzeugstatusMangel? mangel;
  final VoidCallback onSaved;

  const FahrzeugstatusMangelFormScreen({
    super.key,
    required this.companyId,
    required this.fahrzeugId,
    this.mangel,
    required this.onSaved,
  });

  bool get isEdit => mangel != null;

  @override
  State<FahrzeugstatusMangelFormScreen> createState() =>
      _FahrzeugstatusMangelFormScreenState();
}

class _FahrzeugstatusMangelFormScreenState
    extends State<FahrzeugstatusMangelFormScreen> {
  final _service = FahrzeugstatusService();
  final _authService = AuthService();
  final _authDataService = AuthDataService();
  final _titelController = TextEditingController();
  final _beschreibungController = TextEditingController();
  bool _maengelmelderGemeldet = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    if (widget.mangel != null) {
      _titelController.text = widget.mangel!.titel;
      _beschreibungController.text = widget.mangel!.beschreibung ?? '';
      _maengelmelderGemeldet = widget.mangel!.maengelmelderGemeldet ?? false;
    }
  }

  @override
  void dispose() {
    _titelController.dispose();
    _beschreibungController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final titel = _titelController.text.trim();
    if (titel.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Bitte einen Titel eingeben.')),
      );
      return;
    }
    setState(() => _saving = true);
    try {
      if (widget.isEdit) {
        await _service.updateMangel(
          widget.companyId,
          widget.fahrzeugId,
          widget.mangel!.id,
          titel: titel,
          beschreibung: _beschreibungController.text.trim().isEmpty
              ? null
              : _beschreibungController.text.trim(),
          maengelmelderGemeldet: _maengelmelderGemeldet,
        );
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Mangel gespeichert.')),
          );
          widget.onSaved();
        }
      } else {
        final user = _authService.currentUser;
        String? createdByNachname;
        if (user != null) {
          final authData = await _authDataService.getAuthData(
            user.uid,
            user.email ?? '',
            widget.companyId,
          );
          final dn = authData.displayName?.trim();
          if (dn != null && dn.isNotEmpty) {
            createdByNachname =
                dn.contains(',') ? dn.split(',').first.trim() : dn;
          }
          if (createdByNachname == null || createdByNachname.isEmpty) {
            createdByNachname = user.email?.split('@').first;
          }
        }
        await _service.createMangel(
          widget.companyId,
          widget.fahrzeugId,
          titel,
          beschreibung: _beschreibungController.text.trim().isEmpty
              ? null
              : _beschreibungController.text.trim(),
          maengelmelderGemeldet: _maengelmelderGemeldet,
          createdBy: user?.uid,
          createdByName: createdByNachname,
        );
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Mangel erfasst.')),
          );
          widget.onSaved();
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Fehler: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _delete() async {
    if (widget.mangel == null) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Mangel löschen'),
        content: Text(
          'Möchten Sie den Mangel „${widget.mangel!.titel}" als behoben markieren und löschen?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Abbrechen'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Löschen'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _saving = true);
    try {
      await _service.deleteMangel(
        widget.companyId,
        widget.fahrzeugId,
        widget.mangel!.id,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Mangel gelöscht.')),
        );
        widget.onSaved();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Fehler: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.surfaceBg,
      appBar: AppTheme.buildModuleAppBar(
        title: widget.isEdit ? 'Eintrag bearbeiten' : 'Neuer Eintrag',
        onBack: () => Navigator.of(context).pop(),
        actions: [
          if (widget.isEdit)
            IconButton(
              icon: Icon(Icons.delete_outline, color: Colors.red.shade700),
              tooltip: 'Als behoben löschen',
              onPressed: _saving ? null : _delete,
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          TextField(
            controller: _titelController,
            decoration: const InputDecoration(
              labelText: 'Titel / Kurzbeschreibung',
              hintText: 'z.B. Bremsbelag verschlissen',
              border: OutlineInputBorder(),
            ),
            textCapitalization: TextCapitalization.sentences,
            autofocus: !widget.isEdit,
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _beschreibungController,
            decoration: const InputDecoration(
              labelText: 'Weitere Details (optional)',
              hintText: 'Zusätzliche Informationen zum Mangel',
              border: OutlineInputBorder(),
              alignLabelWithHint: true,
            ),
            maxLines: 6,
            textCapitalization: TextCapitalization.sentences,
          ),
          const SizedBox(height: 16),
          CheckboxListTile(
            value: _maengelmelderGemeldet,
            onChanged: (v) => setState(() => _maengelmelderGemeldet = v ?? false),
            title: const Text(
              'Mangel wurde an Mängelmelder gemeldet',
              style: TextStyle(fontSize: 15),
            ),
            controlAffinity: ListTileControlAffinity.leading,
            contentPadding: EdgeInsets.zero,
          ),
          const SizedBox(height: 32),
          FilledButton(
            onPressed: _saving ? null : _submit,
            style: FilledButton.styleFrom(
              backgroundColor: AppTheme.primary,
              padding: const EdgeInsets.symmetric(vertical: 16),
            ),
            child: _saving
                ? const SizedBox(
                    height: 24,
                    width: 24,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Text('Eintrag speichern'),
          ),
          const SizedBox(height: 12),
          TextButton(
            onPressed: _saving ? null : () => Navigator.of(context).pop(),
            child: const Text('Abbrechen'),
          ),
        ],
      ),
    );
  }
}
