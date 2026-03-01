import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../services/module_variants_service.dart';

/// Einstellungen: Modul-Varianten – kundenspezifische Varianten (z.B. Fahrtenbuch V1/V2).
class EinstellungenModulvariantenScreen extends StatefulWidget {
  final String companyId;
  final VoidCallback onBack;

  const EinstellungenModulvariantenScreen({
    super.key,
    required this.companyId,
    required this.onBack,
  });

  @override
  State<EinstellungenModulvariantenScreen> createState() =>
      _EinstellungenModulvariantenScreenState();
}

class _EinstellungenModulvariantenScreenState
    extends State<EinstellungenModulvariantenScreen> {
  final _service = ModuleVariantsService();
  Map<String, String> _variants = {};
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
      final v = await _service.getModuleVariants(widget.companyId);
      if (mounted) {
        setState(() {
          _variants = Map.from(v);
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
      final toSave = Map<String, String>.from(_variants);
      if (!toSave.containsKey('fahrtenbuch')) toSave['fahrtenbuch'] = 'v1';
      await _service.setModuleVariants(widget.companyId, toSave);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Modul-Varianten gespeichert.')),
        );
        setState(() => _saving = false);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Fehler: $e'), backgroundColor: Colors.red),
        );
        setState(() => _saving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.surfaceBg,
      appBar: AppTheme.buildModuleAppBar(
        title: 'Modul-Varianten',
        onBack: widget.onBack,
        actions: [
          if (!_loading)
            TextButton(
              onPressed: _saving ? null : _save,
              child: _saving
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Speichern'),
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppTheme.primary))
          : ListView(
              padding: const EdgeInsets.all(20),
              children: [
                Text(
                  'Kundenspezifische Modul-Varianten',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: Colors.grey[700],
                        fontWeight: FontWeight.w500,
                      ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Wählen Sie pro Modul die gewünschte Version. Diese Einstellung gilt für Ihre Firma.',
                  style: TextStyle(fontSize: 14, color: Colors.grey[600]),
                ),
                const SizedBox(height: 24),
                _buildVariantCard(
                  moduleId: 'fahrtenbuch',
                  label: 'Fahrtenbuch',
                  options: const {
                    'v1': 'Version 1 (Standard)',
                    'v2': 'Version 2 (erweiterte Felder)',
                  },
                ),
              ],
            ),
    );
  }

  Widget _buildVariantCard({
    required String moduleId,
    required String label,
    required Map<String, String> options,
  }) {
    final current = _variants[moduleId] ?? 'v1';
    final validValue = options.containsKey(current) ? current : (options.keys.firstOrNull ?? 'v1');
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              value: validValue,
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: 'Variante',
                border: OutlineInputBorder(),
              ),
              items: options.entries
                  .map((e) => DropdownMenuItem(
                        value: e.key,
                        child: Text(e.value, overflow: TextOverflow.ellipsis, maxLines: 1),
                      ))
                  .toList(),
              onChanged: (v) {
                setState(() {
                  _variants[moduleId] = v ?? 'v1';
                });
              },
            ),
          ],
        ),
      ),
    );
  }
}
