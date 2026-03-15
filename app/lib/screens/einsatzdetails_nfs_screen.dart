import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../services/alarmierung_nfs_service.dart';

const _einsatzindikationOptions = <(String?, String)>[
  ('utn', 'ÜTN - Überbringen Todesnachricht'),
  ('haeuslicher_todesfall', 'häuslicher Todesfall / akute Erkrankung'),
  ('frustrane_reanimation', 'frustrane Reanimation'),
  ('suizid', 'Suizid'),
  ('verkehrsunfall', 'Verkehrsunfall'),
  ('arbeitsunfall', 'Arbeitsunfall'),
  ('schuleinsatz', 'Schuleinsatz'),
  ('brand_explosion_unwetter', 'Brand / Explosion / Unwetter'),
  ('gewalt_verbrechen', 'Gewalttat / Verbrechen'),
  ('grosse_einsatzlage', 'Große Einsatzlage'),
  ('ploetzlicher_kindstod', 'plötzlicher Kindstod'),
  ('sonstiges', 'sonstiges'),
];

/// Einsatzdetails für alarmierte Mitarbeiter – nur Leseansicht + Statusgeber.
class EinsatzdetailsNfsScreen extends StatefulWidget {
  final String companyId;
  final String mitarbeiterId;
  final Map<String, dynamic> einsatz;
  final VoidCallback onBack;

  const EinsatzdetailsNfsScreen({
    super.key,
    required this.companyId,
    required this.mitarbeiterId,
    required this.einsatz,
    required this.onBack,
  });

  @override
  State<EinsatzdetailsNfsScreen> createState() => _EinsatzdetailsNfsScreenState();
}

class _EinsatzdetailsNfsScreenState extends State<EinsatzdetailsNfsScreen> {
  final _service = AlarmierungNfsService();
  bool _saving = false;

  int get _currentStatus {
    final map = widget.einsatz['alarmierteMitarbeiterStatus'];
    if (map is! Map) return 0;
    final v = map[widget.mitarbeiterId];
    return (v is int) ? v : 0;
  }

  String _indikationLabel(String? key) {
    if (key == null || key.isEmpty) return '';
    final found = _einsatzindikationOptions.where((e) => e.$1 == key).firstOrNull;
    return found?.$2 ?? key;
  }

  Future<void> _setStatus(int status) async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      final autoAbgeschlossen = await _service.setAlarmierterStatus(
        widget.companyId,
        widget.einsatz['id'] as String,
        widget.mitarbeiterId,
        status,
      );
      if (mounted) {
        if (autoAbgeschlossen) {
          Navigator.of(context).pop('abgeschlossen');
        } else {
          setState(() {
            widget.einsatz['alarmierteMitarbeiterStatus'] ??= {};
            (widget.einsatz['alarmierteMitarbeiterStatus'] as Map)[widget.mitarbeiterId] = status;
          });
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Status aktualisiert.')),
          );
        }
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
    final e = widget.einsatz;
    final docId = e['id'] as String? ?? '';
    final nr = e['einsatzNr'] as String? ?? '-';
    final laufendeNr = e['laufendeNr'] as String? ?? docId;
    final datum = e['einsatzDatum'] as String? ?? '';
    final uhrzeitBeginn = e['uhrzeitBeginn'] as String? ?? '';
    final name = e['nameBetroffener'] as String? ?? '';
    final strasse = e['strasse'] as String? ?? '';
    final hausNr = e['hausNr'] as String? ?? '';
    final plz = e['plz'] as String? ?? '';
    final ort = e['ort'] as String? ?? '';
    final indikation = _indikationLabel(e['einsatzindikation'] as String?);

    return Scaffold(
      backgroundColor: AppTheme.surfaceBg,
      appBar: AppBar(
        title: const Text('Einsatzdetails'),
        backgroundColor: AppTheme.primary,
        foregroundColor: Colors.white,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: widget.onBack,
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Card(
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(color: Colors.grey.shade200),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _readOnlyRow('Einsatz-Nr.', nr),
                    _readOnlyRow('Laufende-Nummer', laufendeNr),
                    _readOnlyRow('Einsatz-Datum', datum),
                    _readOnlyRow('Uhrzeit Beginn', uhrzeitBeginn),
                    _readOnlyRow('Name des Betroffenen', name),
                    _readOnlyRow('Straße, Haus-Nr.', '$strasse ${hausNr.isNotEmpty ? hausNr : ''}'.trim()),
                    _readOnlyRow('PLZ, Ort', '$plz $ort'.trim()),
                    _readOnlyRow('Einsatzindikation', indikation),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'Status',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: Colors.grey.shade800,
              ),
            ),
            const SizedBox(height: 12),
            _Statusgeber(
              currentStatus: _currentStatus,
              saving: _saving,
              onStatus: _setStatus,
            ),
          ],
        ),
      ),
    );
  }

  Widget _readOnlyRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
          ),
          const SizedBox(height: 2),
          Text(
            value.isEmpty ? '–' : value,
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
          ),
        ],
      ),
    );
  }
}

class _Statusgeber extends StatelessWidget {
  final int currentStatus;
  final bool saving;
  final void Function(int) onStatus;

  const _Statusgeber({
    required this.currentStatus,
    required this.saving,
    required this.onStatus,
  });

  static const _statusLabels = {
    3: 'Einsatz übernommen',
    4: 'Am Einsatzort',
    7: 'Einsatzstelle verlassen',
    2: 'Einsatz beendet',
  };

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final entry in _statusLabels.entries) ...[
              _StatusButton(
                status: entry.key,
                label: entry.value,
                isActive: currentStatus == entry.key,
                disabled: saving,
                onTap: () => onStatus(entry.key),
              ),
              if (entry.key != 2) const SizedBox(height: 8),
            ],
          ],
        ),
      ),
    );
  }
}

class _StatusButton extends StatelessWidget {
  final int status;
  final String label;
  final bool isActive;
  final bool disabled;
  final VoidCallback onTap;

  const _StatusButton({
    required this.status,
    required this.label,
    required this.isActive,
    required this.disabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: isActive ? Colors.red.shade50 : Colors.grey.shade50,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: disabled ? null : onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: isActive ? Colors.red.shade400 : Colors.grey.shade300,
              width: isActive ? 2 : 1,
            ),
          ),
          child: Row(
            children: [
              Icon(
                isActive ? Icons.radio_button_checked : Icons.radio_button_off,
                color: isActive ? Colors.red.shade700 : Colors.grey.shade600,
                size: 24,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: isActive ? FontWeight.w600 : FontWeight.w500,
                    color: isActive ? Colors.red.shade900 : Colors.grey.shade800,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
