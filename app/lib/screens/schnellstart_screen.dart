import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../models/app_module.dart';
import '../models/kunde_model.dart';
import '../services/modules_service.dart';
import '../services/auth_data_service.dart';
import '../services/auth_service.dart';
import '../services/kundenverwaltung_service.dart';

/// Schnellstart-Bearbeitung: 6 Dropdowns für die Dashboard-Kacheln (1–6).
class SchnellstartScreen extends StatefulWidget {
  final String companyId;
  final VoidCallback? onBack;
  final VoidCallback? onSaved;

  const SchnellstartScreen({
    super.key,
    required this.companyId,
    this.onBack,
    this.onSaved,
  });

  @override
  State<SchnellstartScreen> createState() => _SchnellstartScreenState();
}

class _SchnellstartScreenState extends State<SchnellstartScreen> {
  final _modulesService = ModulesService();
  final _authService = AuthService();
  final _authDataService = AuthDataService();
  final _kundenService = KundenverwaltungService();

  List<AppModule> _allModules = [];
  List<String?> _slots = [null, null, null, null, null, null];
  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final user = _authService.currentUser;
      if (user == null) {
        if (mounted) setState(() => _loading = false);
        return;
      }
      final authData = await _authDataService.getAuthData(
        user.uid,
        user.email ?? '',
        widget.companyId,
      );
      final bereich = await _kundenService.getCompanyBereich(widget.companyId)
          ?? KundenBereich.rettungsdienst;
      final modules = await _modulesService.getModulesForCompany(
        widget.companyId,
        authData.role,
        bereich: bereich,
      );
      final slotIds = await _modulesService.getSchnellstartSlotIds(
        widget.companyId,
        authData.role,
        bereich: bereich,
      );
      if (mounted) {
        setState(() {
          _allModules = modules;
          _slots = List.generate(6, (i) => i < slotIds.length ? slotIds[i] : null);
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await _modulesService.saveSchnellstartSlots(widget.companyId, _slots);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Schnellstart gespeichert.')),
        );
        widget.onSaved?.call();
        Navigator.of(context).pop();
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.surfaceBg,
      appBar: AppTheme.buildModuleAppBar(
        title: 'Schnellstart',
        onBack: widget.onBack ?? () => Navigator.of(context).pop(),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppTheme.primary))
          : ListView(
              padding: const EdgeInsets.all(20),
              children: [
                Text(
                  'Wählen Sie für jede Position (1–6) den Menüpunkt, der auf der Hauptseite angezeigt werden soll.',
                  style: TextStyle(
                    fontSize: 14,
                    color: AppTheme.textSecondary,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 24),
                ...List.generate(6, (i) {
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: DropdownButtonFormField<String>(
                      value: _slots[i] != null && _slots[i]!.isNotEmpty ? _slots[i] : null,
                      isExpanded: true,
                      decoration: InputDecoration(
                        labelText: 'Position ${i + 1}',
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                        filled: true,
                        fillColor: Colors.white,
                      ),
                      items: [
                        const DropdownMenuItem<String>(
                          value: null,
                          child: Text('— Kein Modul —'),
                        ),
                        ..._allModules.map((m) => DropdownMenuItem<String>(
                              value: m.id,
                              child: Text(m.label, overflow: TextOverflow.ellipsis),
                            )),
                      ],
                      onChanged: (v) {
                        setState(() => _slots[i] = v);
                      },
                    ),
                  );
                }),
                const SizedBox(height: 24),
                FilledButton(
                  onPressed: _saving ? null : _save,
                  style: FilledButton.styleFrom(
                    backgroundColor: AppTheme.primary,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  child: _saving
                      ? const SizedBox(
                          height: 24,
                          width: 24,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : const Text('Speichern'),
                ),
              ],
            ),
    );
  }
}
