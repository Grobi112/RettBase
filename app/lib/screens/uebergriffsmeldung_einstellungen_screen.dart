import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../services/uebergriffsmeldung_config_service.dart';

/// Einstellungen für Übergriffsmeldung – QM-Beauftragter E-Mail-Adressen
class UebergriffsmeldungEinstellungenScreen extends StatefulWidget {
  final String companyId;
  final VoidCallback? onBack;

  const UebergriffsmeldungEinstellungenScreen({
    super.key,
    required this.companyId,
    this.onBack,
  });

  @override
  State<UebergriffsmeldungEinstellungenScreen> createState() =>
      _UebergriffsmeldungEinstellungenScreenState();
}

class _UebergriffsmeldungEinstellungenScreenState
    extends State<UebergriffsmeldungEinstellungenScreen> {
  final _service = UebergriffsmeldungConfigService();
  final _emails = <TextEditingController>[];
  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final c in _emails) c.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final list = await _service.loadQmEmails(widget.companyId);
    if (mounted) {
      for (final c in _emails) c.dispose();
      _emails.clear();
      if (list.isEmpty) {
        _emails.add(TextEditingController());
      } else {
        _emails.addAll(list.map((e) => TextEditingController(text: e)));
      }
      setState(() => _loading = false);
    }
  }

  Future<void> _speichern() async {
    final emails = _emails
        .map((c) => c.text.trim())
        .where((e) => e.isNotEmpty)
        .toList();

    setState(() => _saving = true);
    try {
      await _service.saveQmEmails(widget.companyId, emails);
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Einstellungen gespeichert.')),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Fehler: $e')),
        );
      }
    }
  }

  void _addField() {
    setState(() => _emails.add(TextEditingController()));
  }

  void _removeField(int index) {
    if (_emails.length <= 1) return;
    setState(() {
      _emails[index].dispose();
      _emails.removeAt(index);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.surfaceBg,
      appBar: AppTheme.buildModuleAppBar(
        title: 'QM-Beauftragter E-Mails',
        onBack: widget.onBack ?? () => Navigator.of(context).pop(),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppTheme.primary))
          : SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'E-Mail-Adressen des QM-Beauftragten',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.primary,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Bei neuen Übergriffsmeldungen können diese Adressen benachrichtigt werden.',
                    style: TextStyle(fontSize: 14, color: AppTheme.textSecondary),
                  ),
                  const SizedBox(height: 20),
                  ...List.generate(_emails.length, (i) {
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Row(
                        children: [
                          Expanded(
                            child: TextFormField(
                              controller: _emails[i],
                              keyboardType: TextInputType.emailAddress,
                              decoration: const InputDecoration(
                                labelText: 'E-Mail-Adresse',
                                hintText: 'beispiel@firma.de',
                                border: OutlineInputBorder(),
                                filled: true,
                                fillColor: Colors.white,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          IconButton(
                            icon: Icon(Icons.remove_circle_outline, color: _emails.length > 1 ? Colors.red : Colors.grey),
                            onPressed: _emails.length > 1 ? () => _removeField(i) : null,
                            tooltip: 'Entfernen',
                          ),
                        ],
                      ),
                    );
                  }),
                  TextButton.icon(
                    onPressed: _addField,
                    icon: const Icon(Icons.add),
                    label: const Text('Weitere E-Mail-Adresse'),
                  ),
                  const SizedBox(height: 24),
                  FilledButton.icon(
                    onPressed: _saving ? null : _speichern,
                    icon: _saving
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : const Icon(Icons.save),
                    label: Text(_saving ? 'Wird gespeichert...' : 'Speichern'),
                    style: FilledButton.styleFrom(backgroundColor: AppTheme.primary),
                  ),
                ],
              ),
            ),
    );
  }
}
