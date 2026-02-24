import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme/app_theme.dart';
import '../services/auth_service.dart';
import '../services/auth_data_service.dart';

String _formatDate(DateTime d) =>
    '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.${d.year}';

String _formatTime(TimeOfDay t) =>
    '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

/// Gelbe Füllung für leere Pflichtfelder; wird weiß bei ausgefüllt
const _pflichtfeldGelb = Color(0xFFFFF9C4); // Amber 100

const _inputDecoration = InputDecoration(
  filled: true,
  fillColor: Colors.white,
  border: OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(10))),
  enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(10)), borderSide: BorderSide(color: AppTheme.border)),
  focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(10)), borderSide: BorderSide(color: AppTheme.primary, width: 1.5)),
  contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 14),
);

const _einsatzindikationOptions = <(String?, String)>[
  (null, 'bitte auswählen ...'),
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

/// Einsatzprotokoll Notfallseelsorge – Formular mit 4 Bereichen
class EinsatzprotokollNfsScreen extends StatefulWidget {
  final String companyId;
  final String? title;
  final VoidCallback onBack;

  const EinsatzprotokollNfsScreen({
    super.key,
    required this.companyId,
    this.title,
    required this.onBack,
  });

  @override
  State<EinsatzprotokollNfsScreen> createState() => _EinsatzprotokollNfsScreenState();
}

class _EinsatzprotokollNfsScreenState extends State<EinsatzprotokollNfsScreen> {
  final _authService = AuthService();
  final _authDataService = AuthDataService();

  final _nameCtrl = TextEditingController();
  DateTime? _einsatzDatum;
  final _einsatzNrCtrl = TextEditingController();
  TimeOfDay? _eintreffenTime;
  TimeOfDay? _abfahrtTime;
  TimeOfDay? _einsatzendeTime;

  bool _alarmierungKoordinator = false;
  bool _alarmierungSonstige = false;
  String? _einsatzindikation;
  bool _einsatzOeffentlich = false;
  bool _einsatzPrivat = false;

  bool _einsatzdatenExpanded = true;
  bool _einsatzberichtExpanded = true;
  bool _einsatzverlaufExpanded = true;
  bool _sonstigesExpanded = true;

  @override
  void initState() {
    super.initState();
    _loadAuth();
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _einsatzNrCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadAuth() async {
    final user = _authService.currentUser;
    if (user == null) return;
    final auth = await _authDataService.getAuthData(user.uid, user.email ?? '', widget.companyId);
    if (mounted) {
      setState(() {
        _nameCtrl.text = _formatNameVornameZuerst(auth.displayName);
      });
    }
  }

  /// "Nachname, Vorname" → "Vorname Nachname"
  String _formatNameVornameZuerst(String? displayName) {
    if (displayName == null || displayName.isEmpty) return '';
    final parts = displayName.split(',');
    if (parts.length >= 2) {
      final nachname = parts[0].trim();
      final vorname = parts[1].trim();
      if (vorname.isNotEmpty && nachname.isNotEmpty) return '$vorname $nachname';
    }
    return displayName;
  }

  Future<void> _pickDatum() async {
    final d = await showDatePicker(
      context: context,
      initialDate: _einsatzDatum ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (d != null) setState(() => _einsatzDatum = d);
  }

  Future<void> _pickUhrzeit(ValueChanged<TimeOfDay> onPicked, {TimeOfDay? initial}) async {
    final start = initial ?? TimeOfDay.now();
    final t = await showTimePicker(
      context: context,
      initialTime: start,
      initialEntryMode: TimePickerEntryMode.input,
      builder: (context, child) {
        return MediaQuery(
          data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true),
          child: child!,
        );
      },
    );
    if (t != null) {
      setState(() => onPicked(t));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.surfaceBg,
      appBar: AppTheme.buildModuleAppBar(
        title: widget.title ?? 'Einsatzprotokoll Notfallseelsorge',
        onBack: widget.onBack,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _buildSection(
            title: 'Einsatzdaten',
            expanded: _einsatzdatenExpanded,
            onExpansionChanged: (v) => setState(() => _einsatzdatenExpanded = v),
            child: _buildEinsatzdatenContent(),
          ),
          const SizedBox(height: 16),
          _buildSection(
            title: 'Einsatzbericht',
            expanded: _einsatzberichtExpanded,
            onExpansionChanged: (v) => setState(() => _einsatzberichtExpanded = v),
            child: const Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                'Inhalt folgt.',
                style: TextStyle(color: Colors.grey),
              ),
            ),
          ),
          const SizedBox(height: 16),
          _buildSection(
            title: 'Einsatzverlauf',
            expanded: _einsatzverlaufExpanded,
            onExpansionChanged: (v) => setState(() => _einsatzverlaufExpanded = v),
            child: const Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                'Inhalt folgt.',
                style: TextStyle(color: Colors.grey),
              ),
            ),
          ),
          const SizedBox(height: 16),
          _buildSection(
            title: 'Sonstiges',
            expanded: _sonstigesExpanded,
            onExpansionChanged: (v) => setState(() => _sonstigesExpanded = v),
            child: const Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                'Inhalt folgt.',
                style: TextStyle(color: Colors.grey),
              ),
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _buildSection({
    required String title,
    required bool expanded,
    required ValueChanged<bool> onExpansionChanged,
    required Widget child,
  }) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          initiallyExpanded: expanded,
          onExpansionChanged: onExpansionChanged,
          tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          childrenPadding: EdgeInsets.zero,
          collapsedBackgroundColor: AppTheme.primary,
          backgroundColor: AppTheme.primary,
          textColor: Colors.white,
          collapsedTextColor: Colors.white,
          iconColor: Colors.white,
          collapsedIconColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          collapsedShape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          title: Text(
            title,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: Colors.white,
            ),
          ),
          children: [
            Container(
              color: Theme.of(context).colorScheme.surface,
              child: child,
            ),
          ],
        ),
      ),
    );
  }

  Widget _field(TextEditingController ctrl, String label, {List<TextInputFormatter>? inputFormatters, String? hintText, bool required = false}) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: TextField(
          controller: ctrl,
          inputFormatters: inputFormatters,
          onChanged: required ? (_) => setState(() {}) : null,
          decoration: _inputDecoration.copyWith(
            labelText: label,
            hintText: hintText,
            fillColor: required && ctrl.text.trim().isEmpty ? _pflichtfeldGelb : Colors.white,
          ),
        ),
      );

  Widget _uhrzeitField(String label, TimeOfDay? value, ValueChanged<TimeOfDay> onPicked, {bool required = false, VoidCallback? onPick}) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: InkWell(
          onTap: onPick ?? () => _pickUhrzeit(onPicked),
          child: InputDecorator(
            decoration: _inputDecoration.copyWith(
              labelText: label,
              fillColor: required && value == null ? _pflichtfeldGelb : Colors.white,
            ),
            child: Text(value != null ? _formatTime(value) : 'Uhrzeit eingeben'),
          ),
        ),
      );

  Widget _fieldReadOnly(TextEditingController ctrl, String label, {bool required = false}) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: TextField(
          controller: ctrl,
          readOnly: true,
          decoration: _inputDecoration.copyWith(
            labelText: label,
            fillColor: required && ctrl.text.trim().isEmpty ? _pflichtfeldGelb : Colors.grey.shade100,
          ),
        ),
      );

  Widget _checkboxRow(String label, bool value, ValueChanged<bool> onChanged, {bool required = false, bool groupFulfilled = true}) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 24,
              height: 24,
              child: Checkbox(
                value: value,
                onChanged: (v) => onChanged(v ?? false),
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                fillColor: (required && !groupFulfilled)
                    ? WidgetStateProperty.resolveWith((states) => states.contains(WidgetState.selected) ? null : _pflichtfeldGelb)
                    : null,
              ),
            ),
            const SizedBox(width: 8),
            Flexible(child: Text(label, style: const TextStyle(fontSize: 14), overflow: TextOverflow.ellipsis)),
          ],
        ),
      );

  Widget _buildEinsatzdatenContent() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isNarrow = constraints.maxWidth < 600;
        return Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (isNarrow) ...[
                _fieldReadOnly(_nameCtrl, 'Vor- und Nachname', required: true),
                const SizedBox(height: 4),
                Text('Alarmierung durch:', style: TextStyle(fontSize: 13, color: Colors.grey.shade700)),
                _checkboxRow('Koordinator', _alarmierungKoordinator, (v) => setState(() => _alarmierungKoordinator = v), required: true, groupFulfilled: _alarmierungKoordinator || _alarmierungSonstige),
                _checkboxRow('sonstige', _alarmierungSonstige, (v) => setState(() => _alarmierungSonstige = v), required: true, groupFulfilled: _alarmierungKoordinator || _alarmierungSonstige),
                const SizedBox(height: 12),
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: InkWell(
                    onTap: _pickDatum,
                    child: InputDecorator(
                      decoration: _inputDecoration.copyWith(
                        labelText: 'Einsatz-Datum',
                        fillColor: _einsatzDatum == null ? _pflichtfeldGelb : Colors.white,
                      ),
                      child: Text(_einsatzDatum != null ? _formatDate(_einsatzDatum!) : 'Datum wählen'),
                    ),
                  ),
                ),
                _field(_einsatzNrCtrl, 'Einsatz-Nr.', inputFormatters: [FilteringTextInputFormatter.digitsOnly], required: true),
                _uhrzeitField('Eintreffen vor Ort (HH:MM)', _eintreffenTime, (t) => _eintreffenTime = t, required: true, onPick: () => _pickUhrzeit((t) => _eintreffenTime = t, initial: _eintreffenTime)),
                _uhrzeitField('Abfahrt vom Einsatzort (HH:MM)', _abfahrtTime, (t) => _abfahrtTime = t, required: true, onPick: () => _pickUhrzeit((t) => _abfahrtTime = t, initial: _abfahrtTime)),
                _uhrzeitField('Einsatzende (HH:MM)', _einsatzendeTime, (t) => _einsatzendeTime = t, required: true, onPick: () => _pickUhrzeit((t) => _einsatzendeTime = t, initial: _einsatzendeTime)),
              ] else
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _fieldReadOnly(_nameCtrl, 'Vor- und Nachname', required: true),
                          const SizedBox(height: 4),
                          Text('Alarmierung durch:', style: TextStyle(fontSize: 13, color: Colors.grey.shade700)),
                          _checkboxRow('Koordinator', _alarmierungKoordinator, (v) => setState(() => _alarmierungKoordinator = v), required: true, groupFulfilled: _alarmierungKoordinator || _alarmierungSonstige),
                          _checkboxRow('sonstige', _alarmierungSonstige, (v) => setState(() => _alarmierungSonstige = v), required: true, groupFulfilled: _alarmierungKoordinator || _alarmierungSonstige),
                        ],
                      ),
                    ),
                    const SizedBox(width: 24),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: InkWell(
                              onTap: _pickDatum,
                              child: InputDecorator(
                                decoration: _inputDecoration.copyWith(
                                  labelText: 'Einsatz-Datum',
                                  fillColor: _einsatzDatum == null ? _pflichtfeldGelb : Colors.white,
                                ),
                                child: Text(_einsatzDatum != null ? _formatDate(_einsatzDatum!) : 'Datum wählen'),
                              ),
                            ),
                          ),
                          _field(_einsatzNrCtrl, 'Einsatz-Nr.', inputFormatters: [FilteringTextInputFormatter.digitsOnly], required: true),
                          _uhrzeitField('Eintreffen vor Ort (HH:MM)', _eintreffenTime, (t) => _eintreffenTime = t, required: true, onPick: () => _pickUhrzeit((t) => _eintreffenTime = t, initial: _eintreffenTime)),
                          _uhrzeitField('Abfahrt vom Einsatzort (HH:MM)', _abfahrtTime, (t) => _abfahrtTime = t, required: true, onPick: () => _pickUhrzeit((t) => _abfahrtTime = t, initial: _abfahrtTime)),
                          _uhrzeitField('Einsatzende (HH:MM)', _einsatzendeTime, (t) => _einsatzendeTime = t, required: true, onPick: () => _pickUhrzeit((t) => _einsatzendeTime = t, initial: _einsatzendeTime)),
                        ],
                      ),
                    ),
                  ],
                ),
              const SizedBox(height: 20),
              DropdownButtonFormField<String?>(
                value: _einsatzindikation,
                decoration: _inputDecoration.copyWith(
                  labelText: 'Einsatzindikation',
                  fillColor: (_einsatzindikation == null || (_einsatzindikation ?? '').trim().isEmpty) ? _pflichtfeldGelb : Colors.white,
                ),
                items: _einsatzindikationOptions
                    .map((e) => DropdownMenuItem<String?>(value: e.$1, child: Text(e.$2)))
                    .toList(),
                onChanged: (v) => setState(() => _einsatzindikation = v),
              ),
              const SizedBox(height: 16),
              Text('Einsatz im:', style: TextStyle(fontSize: 13, color: Colors.grey.shade700)),
              _checkboxRow('öffentlichen Bereich', _einsatzOeffentlich, (v) => setState(() => _einsatzOeffentlich = v), required: true, groupFulfilled: _einsatzOeffentlich || _einsatzPrivat),
              _checkboxRow('privaten Bereich', _einsatzPrivat, (v) => setState(() => _einsatzPrivat = v), required: true, groupFulfilled: _einsatzOeffentlich || _einsatzPrivat),
            ],
          ),
        );
      },
    );
  }
}
