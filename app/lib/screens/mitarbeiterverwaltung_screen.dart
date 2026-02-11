import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../theme/app_theme.dart';
import '../models/mitarbeiter_model.dart';
import '../services/mitarbeiter_service.dart';
import '../app_config.dart';

/// Native Mitarbeiterverwaltung (Mitgliederverwaltung) – Liste, Anlegen, Bearbeiten, Löschen.
/// Nur für Superadmin, Admin, LeiterSSD.
class MitarbeiterverwaltungScreen extends StatefulWidget {
  final String companyId;
  final String? userRole;
  final VoidCallback? onBack;
  final bool hideAppBar;

  const MitarbeiterverwaltungScreen({
    super.key,
    required this.companyId,
    this.userRole,
    this.onBack,
    this.hideAppBar = false,
  });

  @override
  State<MitarbeiterverwaltungScreen> createState() => _MitarbeiterverwaltungScreenState();
}

class _MitarbeiterverwaltungScreenState extends State<MitarbeiterverwaltungScreen> {
  final _service = MitarbeiterService();
  final _searchController = TextEditingController();
  final _functions = FirebaseFunctions.instanceFor(region: 'europe-west1');

  List<Mitarbeiter> _allMitarbeiter = [];
  bool _loading = true;
  String? _error;

  static const _roles = ['user', 'ovd', 'wachleitung', 'leiterssd', 'supervisor', 'admin'];
  static const _qualifikationen = ['RH', 'RS', 'RA', 'NFS'];
  static const _vertraege = ['Vollzeit', 'Teilzeit', 'GfB', 'Ausbildung', 'Ehrenamt'];
  static const _fuehrerscheinklassen = ['', 'A', 'A1', 'A2', 'AM', 'B', 'BE', 'C', 'CE', 'C1', 'C1E', 'D', 'DE', 'D1', 'D1E', 'L', 'T'];
  static const _roleLabels = {
    'user': 'User',
    'ovd': 'OVD',
    'wachleitung': 'Wachleitung',
    'leiterssd': 'LeiterSSD',
    'supervisor': 'Supervisor',
    'admin': 'Admin',
    'superadmin': 'Superadmin',
  };

  List<String> get _rolesForCompany {
    final r = List<String>.from(_roles);
    if (widget.companyId == 'admin') r.add('superadmin');
    return r;
  }

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() => setState(() {}));
    _load();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      var list = await _service.loadMitarbeiter(widget.companyId);
      if (mounted && widget.companyId == 'admin' && list.isEmpty) {
        final cu = FirebaseAuth.instance.currentUser;
        if (cu != null && cu.email != null && cu.email!.isNotEmpty) {
          list = [
            Mitarbeiter(
              id: cu.uid,
              uid: cu.uid,
              email: cu.email,
              role: widget.userRole ?? 'superadmin',
              active: true,
              fromUsersOnly: true,
            ),
          ];
        }
      }
      if (mounted) {
        setState(() {
          _allMitarbeiter = list;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = 'Fehler beim Laden: $e';
        });
      }
    }
  }

  List<Mitarbeiter> _getFiltered() {
    final q = _searchController.text.trim().toLowerCase();
    if (q.isEmpty) return _allMitarbeiter;
    return _allMitarbeiter.where((m) {
      final name = '${m.vorname ?? ''} ${m.nachname ?? ''}'.toLowerCase();
      final email = (m.email ?? '').toLowerCase();
      final quali = (m.qualifikation ?? []).join(' ').toLowerCase();
      return name.contains(q) || email.contains(q) || quali.contains(q) ||
          (m.personalnummer ?? '').toLowerCase().contains(q);
    }).toList();
  }

  Future<void> _toggleActive(Mitarbeiter m) async {
    try {
      if (m.fromUsersOnly && m.uid != null) {
        await _functions.httpsCallable('saveUsersDoc').call({
          'companyId': widget.companyId,
          'uid': m.uid!,
          'data': {'status': !m.active},
        });
      } else {
        await _functions.httpsCallable('saveMitarbeiterDoc').call({
          'companyId': widget.companyId,
          'docId': m.id,
          'data': {'active': !m.active},
        });
      }
      if (mounted) _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Fehler: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _openCreate() async {
    final result = await Navigator.of(context, rootNavigator: true).push<Mitarbeiter?>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (ctx) => _MitarbeiterFormScreen(
          companyId: widget.companyId,
          roles: _rolesForCompany,
          roleLabels: _roleLabels,
          qualifikationen: _qualifikationen,
          vertraege: _vertraege,
          fuehrerscheinklassen: _fuehrerscheinklassen,
          existingPersonalnummern: _allMitarbeiter
              .map((e) => e.personalnummer)
              .whereType<String>()
              .where((s) => s.isNotEmpty)
              .toSet(),
          existingEmails: _allMitarbeiter
              .map((e) => e.email)
              .whereType<String>()
              .where((s) => s.isNotEmpty && !s.endsWith('.${AppConfig.rootDomain}'))
              .toSet(),
        ),
      ),
    );
    if (result != null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Mitarbeiter angelegt.')));
      _load();
    }
  }

  Future<void> _openEdit(Mitarbeiter m) async {
    final result = await Navigator.of(context, rootNavigator: true).push<Mitarbeiter?>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (ctx) => _MitarbeiterFormScreen(
          companyId: widget.companyId,
          mitarbeiter: m,
          roles: _rolesForCompany,
          roleLabels: _roleLabels,
          qualifikationen: _qualifikationen,
          vertraege: _vertraege,
          fuehrerscheinklassen: _fuehrerscheinklassen,
          existingPersonalnummern: _allMitarbeiter
              .where((e) => e.id != m.id)
              .map((e) => e.personalnummer)
              .whereType<String>()
              .where((s) => s.isNotEmpty)
              .toSet(),
          existingEmails: _allMitarbeiter
              .where((e) => e.id != m.id)
              .map((e) => e.email)
              .whereType<String>()
              .where((s) => s.isNotEmpty && !s.endsWith('.${AppConfig.rootDomain}'))
              .toSet(),
        ),
      ),
    );
    if (result != null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Mitarbeiter gespeichert.')));
      _load();
    }
  }

  Future<void> _confirmDelete(Mitarbeiter m) async {
    if (widget.companyId == 'admin' && m.role == 'superadmin') {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Superadmin darf nicht gelöscht werden.'), backgroundColor: Colors.orange),
      );
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Mitarbeiter löschen?'),
        content: Text(
          'Sind Sie sicher, dass Sie „${m.displayName}" löschen möchten? '
          'Die Stammdaten werden entfernt.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Abbrechen')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Löschen'),
          ),
        ],
      ),
    );
    if (ok == true) {
      try {
        if (m.fromUsersOnly && m.uid != null) {
          await _service.deleteUsersDoc(widget.companyId, m.uid!);
        } else {
          await _service.deleteMitarbeiter(widget.companyId, m.id);
          if (m.uid != null) {
            await _service.deleteUsersDoc(widget.companyId, m.uid!);
          }
        }
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Mitarbeiter gelöscht.')));
          _load();
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Fehler: $e'), backgroundColor: Colors.red),
          );
        }
      }
    }
  }

  Future<void> _resetPassword(Mitarbeiter m) async {
    final email = m.email;
    if (email == null || email.isEmpty || email.endsWith('.${AppConfig.rootDomain}')) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Passwort zurücksetzen nur bei echter E-Mail möglich.')),
      );
      return;
    }
    final passCtrl = TextEditingController();
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Passwort zurücksetzen'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Neues Passwort für ${m.displayName} ($email):'),
            const SizedBox(height: 12),
            TextField(
              controller: passCtrl,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: 'Neues Passwort (min. 6 Zeichen)',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Abbrechen')),
          FilledButton(
            onPressed: () {
              if (passCtrl.text.length >= 6) Navigator.of(ctx).pop(true);
            },
            child: const Text('Speichern'),
          ),
        ],
      ),
    );
    if (result == true && passCtrl.text.length >= 6) {
      try {
        await _functions.httpsCallable('updateMitarbeiterPassword').call({
          'uid': m.uid,
          'email': email,
          'newPassword': passCtrl.text,
        });
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Passwort aktualisiert.')));
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Fehler: $e'), backgroundColor: Colors.red),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final scaffold = Scaffold(
      backgroundColor: AppTheme.surfaceBg,
      appBar: AppTheme.buildModuleAppBar(
        title: 'Mitgliederverwaltung',
        onBack: widget.onBack ?? () => Navigator.of(context).pop(),
        actions: [
          if (widget.userRole != null && ['superadmin', 'admin', 'leiterssd'].contains(widget.userRole!))
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: MediaQuery.sizeOf(context).width < 400
                  ? IconButton(
                      onPressed: _openCreate,
                      icon: const Icon(Icons.add),
                      style: IconButton.styleFrom(backgroundColor: AppTheme.primary, foregroundColor: Colors.white),
                      tooltip: 'Neuer Mitarbeiter',
                    )
                  : FilledButton.icon(
                      onPressed: _openCreate,
                      icon: const Icon(Icons.add, size: 20),
                      label: const Text('Neuer Mitarbeiter'),
                      style: FilledButton.styleFrom(backgroundColor: AppTheme.primary),
                    ),
            ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: EdgeInsets.all(Responsive.horizontalPadding(context)),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Mitarbeiter suchen…',
                prefixIcon: const Icon(Icons.search),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                filled: true,
                fillColor: Colors.white,
              ),
            ),
          ),
          Expanded(child: _buildBody()),
        ],
      ),
    );

    if (widget.hideAppBar && widget.onBack != null) {
      return PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) widget.onBack!();
        },
        child: scaffold,
      );
    }
    return scaffold;
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator(color: AppTheme.primary));
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.error_outline, size: 48, color: Colors.red[400]),
              const SizedBox(height: 16),
              Text(_error!, textAlign: TextAlign.center, style: TextStyle(color: Colors.red[700])),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: _load,
                icon: const Icon(Icons.refresh),
                label: const Text('Erneut versuchen'),
                style: FilledButton.styleFrom(backgroundColor: AppTheme.primary),
              ),
            ],
          ),
        ),
      );
    }

    final list = _getFiltered();
    list.sort((a, b) {
      final na = (a.nachname ?? '').toLowerCase();
      final nb = (b.nachname ?? '').toLowerCase();
      final c = na.compareTo(nb);
      if (c != 0) return c;
      return ((a.vorname ?? '').toLowerCase()).compareTo((b.vorname ?? '').toLowerCase());
    });

    if (list.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            _allMitarbeiter.isEmpty ? 'Keine Mitarbeiter vorhanden.' : 'Keine Treffer für Ihre Suche.',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppTheme.textMuted, fontSize: 16),
          ),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _load,
      color: AppTheme.primary,
      child: ListView.builder(
        padding: EdgeInsets.fromLTRB(
          Responsive.horizontalPadding(context),
          0,
          Responsive.horizontalPadding(context),
          24,
        ),
        itemCount: list.length,
        itemBuilder: (_, i) {
          final m = list[i];
          final canDelete = widget.userRole != null &&
              ['admin', 'superadmin'].contains(widget.userRole!) &&
              !(widget.companyId == 'admin' && m.role == 'superadmin');
          return Card(
            margin: const EdgeInsets.only(bottom: 12),
            child: InkWell(
              onTap: () => _openEdit(m),
              borderRadius: BorderRadius.circular(12),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text(
                                m.displayName,
                                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                              ),
                              if (m.role != null && m.role!.isNotEmpty) ...[
                                const SizedBox(width: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: AppTheme.primary.withOpacity(0.15),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Text(
                                    _roleLabels[m.role] ?? m.role!,
                                    style: TextStyle(fontSize: 11, color: AppTheme.primary),
                                  ),
                                ),
                              ],
                            ],
                          ),
                          if ((m.qualifikation ?? []).isNotEmpty)
                            Text(
                              (m.qualifikation!).join(', '),
                              style: TextStyle(fontSize: 13, color: AppTheme.textMuted),
                            ),
                        ],
                      ),
                    ),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: Icon(m.active ? Icons.check_circle : Icons.cancel, color: m.active ? Colors.green : Colors.red),
                          onPressed: () => _toggleActive(m),
                          tooltip: m.active ? 'Deaktivieren' : 'Aktivieren',
                        ),
                        if (m.email != null && !m.email!.endsWith('.${AppConfig.rootDomain}'))
                          IconButton(
                            icon: const Icon(Icons.lock_reset),
                            onPressed: () => _resetPassword(m),
                            tooltip: 'Passwort zurücksetzen',
                          ),
                        IconButton(
                          icon: const Icon(Icons.edit),
                          onPressed: () => _openEdit(m),
                          tooltip: 'Bearbeiten',
                        ),
                        if (canDelete)
                          IconButton(
                            icon: Icon(Icons.delete, color: Colors.red[700]),
                            onPressed: () => _confirmDelete(m),
                            tooltip: 'Löschen',
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _MitarbeiterFormScreen extends StatefulWidget {
  final String companyId;
  final Mitarbeiter? mitarbeiter;
  final List<String> roles;
  final Map<String, String> roleLabels;
  final List<String> qualifikationen;
  final List<String> vertraege;
  final List<String> fuehrerscheinklassen;
  final Set<String> existingPersonalnummern;
  final Set<String> existingEmails;

  const _MitarbeiterFormScreen({
    required this.companyId,
    this.mitarbeiter,
    required this.roles,
    required this.roleLabels,
    required this.qualifikationen,
    required this.vertraege,
    required this.fuehrerscheinklassen,
    required this.existingPersonalnummern,
    required this.existingEmails,
  });

  @override
  State<_MitarbeiterFormScreen> createState() => _MitarbeiterFormScreenState();
}

class _MitarbeiterFormScreenState extends State<_MitarbeiterFormScreen> {
  late final TextEditingController _personalnummerCtrl;
  late final TextEditingController _emailCtrl;
  late final TextEditingController _vornameCtrl;
  late final TextEditingController _nachnameCtrl;
  late final TextEditingController _strasseCtrl;
  late final TextEditingController _hausnummerCtrl;
  late final TextEditingController _plzCtrl;
  late final TextEditingController _ortCtrl;
  late final TextEditingController _telefonCtrl;
  late final TextEditingController _passwordCtrl;

  late String _fuehrerschein;
  late String _role;
  late bool _active;
  DateTime? _geburtsdatum;
  late List<String> _qualifikation;
  late List<String> _angestelltenverhaeltnis;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final m = widget.mitarbeiter;
    _personalnummerCtrl = TextEditingController(text: m?.personalnummer ?? '');
    _emailCtrl = TextEditingController(text: m?.email != null && !(m!.email!.endsWith('.${AppConfig.rootDomain}')) ? m.email : '');
    _vornameCtrl = TextEditingController(text: m?.vorname ?? '');
    _nachnameCtrl = TextEditingController(text: m?.nachname ?? '');
    _strasseCtrl = TextEditingController(text: m?.strasse ?? '');
    _hausnummerCtrl = TextEditingController(text: m?.hausnummer ?? '');
    _plzCtrl = TextEditingController(text: m?.plz ?? '');
    _ortCtrl = TextEditingController(text: m?.ort ?? '');
    _telefonCtrl = TextEditingController(text: m?.telefon ?? '');
    _passwordCtrl = TextEditingController();
    final fs = m?.fuehrerschein ?? '';
    _fuehrerschein = widget.fuehrerscheinklassen.contains(fs) ? fs : '';
    _role = m?.role ?? 'user';
    _active = m?.active ?? true;
    _geburtsdatum = m?.geburtsdatum;
    _qualifikation = List<String>.from(m?.qualifikation ?? []);
    _angestelltenverhaeltnis = (m?.angestelltenverhaeltnis ?? [])
        .where((v) => widget.vertraege.contains(v))
        .toList();
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
    _passwordCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final nachname = _nachnameCtrl.text.trim();
    if (nachname.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Nachname ist erforderlich.')));
      return;
    }
    if (_role.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Bitte Rolle wählen.')));
      return;
    }
    if (widget.companyId != 'admin' && _role == 'superadmin') {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Superadmin nur in admin-Firma.')));
      return;
    }

    final personalnummer = _personalnummerCtrl.text.trim();
    final email = _emailCtrl.text.trim();
    if (personalnummer.isEmpty && email.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Personalnummer oder E-Mail erforderlich.'),
      ));
      return;
    }

    if (personalnummer.isNotEmpty && widget.existingPersonalnummern.contains(personalnummer)) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Personalnummer existiert bereits.')));
      return;
    }
    if (email.isNotEmpty && !email.endsWith('.${AppConfig.rootDomain}') && widget.existingEmails.contains(email)) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('E-Mail existiert bereits.')));
      return;
    }

    final isCreate = widget.mitarbeiter == null;
    if (isCreate && (email.isNotEmpty || personalnummer.isNotEmpty)) {
      final needsAuth = email.isNotEmpty && !email.endsWith('.${AppConfig.rootDomain}');
      if (needsAuth && _passwordCtrl.text.length < 6) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Passwort mindestens 6 Zeichen für E-Mail-Login.'),
        ));
        return;
      }
    }

    setState(() => _saving = true);

    final functions = FirebaseFunctions.instanceFor(region: 'europe-west1');

    try {
      String? emailForAuth = email.isNotEmpty && !email.endsWith('.${AppConfig.rootDomain}') ? email : null;
      String? pseudoEmail;
      if (personalnummer.isNotEmpty) {
        pseudoEmail = '$personalnummer@${widget.companyId}.${AppConfig.rootDomain}';
      }

      String? uid;
      if (isCreate) {
        if (emailForAuth != null && _passwordCtrl.text.length >= 6) {
          final result = await functions.httpsCallable('createAuthUser').call({
            'email': emailForAuth,
            'password': _passwordCtrl.text,
          });
          uid = result.data['uid'] as String?;
        } else if (pseudoEmail != null) {
          final tempPass = _passwordCtrl.text.length >= 6 ? _passwordCtrl.text : 'RettBase${DateTime.now().millisecondsSinceEpoch}';
          final result = await functions.httpsCallable('createAuthUser').call({
            'email': pseudoEmail,
            'password': tempPass,
          });
          uid = result.data['uid'] as String?;
        }
      } else {
        uid = widget.mitarbeiter!.uid;
      }

      final mitarbeiter = Mitarbeiter(
        id: widget.mitarbeiter?.id ?? 'temp',
        uid: uid,
        email: emailForAuth ?? pseudoEmail ?? widget.mitarbeiter?.email,
        pseudoEmail: pseudoEmail ?? widget.mitarbeiter?.pseudoEmail,
        vorname: _vornameCtrl.text.trim().isEmpty ? null : _vornameCtrl.text.trim(),
        nachname: nachname,
        personalnummer: personalnummer.isEmpty ? null : personalnummer,
        role: _role,
        telefon: _telefonCtrl.text.trim().isEmpty ? null : _telefonCtrl.text.trim(),
        handynummer: null,
        strasse: _strasseCtrl.text.trim().isEmpty ? null : _strasseCtrl.text.trim(),
        hausnummer: _hausnummerCtrl.text.trim().isEmpty ? null : _hausnummerCtrl.text.trim(),
        plz: _plzCtrl.text.trim().isEmpty ? null : _plzCtrl.text.trim(),
        ort: _ortCtrl.text.trim().isEmpty ? null : _ortCtrl.text.trim(),
        fuehrerschein: _fuehrerschein.isEmpty ? null : _fuehrerschein,
        qualifikation: _qualifikation.isEmpty ? null : _qualifikation,
        angestelltenverhaeltnis: _angestelltenverhaeltnis.isEmpty ? null : _angestelltenverhaeltnis,
        geburtsdatum: _geburtsdatum,
        active: _active,
      );

      if (isCreate) {
        final docData = mitarbeiter.copyWith(id: '').toFirestore();
        final name = '${mitarbeiter.nachname ?? ''}, ${mitarbeiter.vorname ?? ''}'.trim();
        if (name.isNotEmpty) docData['name'] = name;
        if (docData['geburtsdatum'] != null && docData['geburtsdatum'] is Timestamp) {
          docData['geburtsdatum'] = (docData['geburtsdatum'] as Timestamp).millisecondsSinceEpoch;
        }
        final createRes = await functions.httpsCallable('createMitarbeiterDoc').call({
          'companyId': widget.companyId,
          'data': docData,
        });
        final newId = createRes.data['docId'] as String;
        if (uid != null) {
          final usersData = <String, dynamic>{
            'email': mitarbeiter.email ?? pseudoEmail ?? '',
            'role': _role,
            'companyId': widget.companyId,
            'status': true,
            'mitarbeiterDocId': newId,
          };
          if (mitarbeiter.vorname != null && mitarbeiter.vorname!.isNotEmpty) usersData['vorname'] = mitarbeiter.vorname;
          if (mitarbeiter.nachname != null && mitarbeiter.nachname!.isNotEmpty) usersData['nachname'] = mitarbeiter.nachname;
          await functions.httpsCallable('saveUsersDoc').call({
            'companyId': widget.companyId,
            'uid': uid,
            'data': usersData,
          });
        }
        if (mounted) Navigator.of(context).pop(mitarbeiter.copyWith(id: newId));
      } else {
        final updates = <String, dynamic>{
          'vorname': mitarbeiter.vorname,
          'nachname': mitarbeiter.nachname,
          'personalnummer': mitarbeiter.personalnummer,
          'role': mitarbeiter.role,
          'email': mitarbeiter.email,
          'pseudoEmail': mitarbeiter.pseudoEmail,
          'telefon': mitarbeiter.telefon,
          'handynummer': null,
          'strasse': mitarbeiter.strasse,
          'hausnummer': mitarbeiter.hausnummer,
          'plz': mitarbeiter.plz,
          'ort': mitarbeiter.ort,
          'fuehrerschein': mitarbeiter.fuehrerschein,
          'qualifikation': _qualifikation.isEmpty ? null : _qualifikation,
          'angestelltenverhaeltnis': _angestelltenverhaeltnis.isEmpty ? null : _angestelltenverhaeltnis,
          'active': mitarbeiter.active,
        };
        if (_geburtsdatum != null) updates['geburtsdatum'] = _geburtsdatum!.millisecondsSinceEpoch;
        if (widget.mitarbeiter!.fromUsersOnly && widget.mitarbeiter!.uid != null) {
          updates['status'] = mitarbeiter.active;
          updates['vorname'] = mitarbeiter.vorname;
          updates['nachname'] = mitarbeiter.nachname;
          await functions.httpsCallable('saveUsersDoc').call({
            'companyId': widget.companyId,
            'uid': widget.mitarbeiter!.uid!,
            'data': updates,
          });
        } else {
          await functions.httpsCallable('saveMitarbeiterDoc').call({
            'companyId': widget.companyId,
            'docId': widget.mitarbeiter!.id,
            'data': updates,
          });
        }
        if (mounted) Navigator.of(context).pop(mitarbeiter);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Fehler: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isCreate = widget.mitarbeiter == null;
    return Scaffold(
      backgroundColor: AppTheme.surfaceBg,
      appBar: AppBar(
        title: Text(isCreate ? 'Neuer Mitarbeiter' : 'Mitarbeiter bearbeiten'),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.of(context).pop(),
        ),
        backgroundColor: AppTheme.headerBg,
        foregroundColor: Colors.white,
      ),
      body: ListView(
        padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        children: [
          Padding(
            padding: EdgeInsets.all(Responsive.horizontalPadding(context)),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minWidth: 500),
              child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // 1. Personalnummer und E-Mail auf einer Ebene
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _personalnummerCtrl,
                        decoration: const InputDecoration(labelText: 'Personalnummer'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextField(
                        controller: _emailCtrl,
                        decoration: const InputDecoration(labelText: 'E-Mail'),
                        keyboardType: TextInputType.emailAddress,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                // 2. Vorname und Nachname auf einer Ebene
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _vornameCtrl,
                        decoration: const InputDecoration(labelText: 'Vorname'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextField(
                        controller: _nachnameCtrl,
                        decoration: const InputDecoration(labelText: 'Nachname *'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                // 3. Geburtsdatum mit Label (wie die anderen)
                InkWell(
                  onTap: () async {
                    final d = await showDatePicker(
                      context: context,
                      initialDate: _geburtsdatum ?? DateTime(1990),
                      firstDate: DateTime(1900),
                      lastDate: DateTime.now(),
                    );
                    if (d != null) setState(() => _geburtsdatum = d);
                  },
                  child: InputDecorator(
                    decoration: const InputDecoration(
                      labelText: 'Geburtsdatum',
                      border: OutlineInputBorder(),
                    ),
                    child: Text(
                      _geburtsdatum != null
                          ? '${_geburtsdatum!.day.toString().padLeft(2, '0')}.${_geburtsdatum!.month.toString().padLeft(2, '0')}.${_geburtsdatum!.year}'
                          : '–',
                      style: TextStyle(color: _geburtsdatum != null ? null : Colors.grey[600]),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                // 4. Straße und Hausnummer auf einer Ebene
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      flex: 2,
                      child: TextField(
                        controller: _strasseCtrl,
                        decoration: const InputDecoration(labelText: 'Straße'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextField(
                        controller: _hausnummerCtrl,
                        decoration: const InputDecoration(labelText: 'Hausnummer'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                // 5. PLZ und Ort auf einer Ebene
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _plzCtrl,
                        decoration: const InputDecoration(labelText: 'PLZ'),
                        keyboardType: TextInputType.number,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 2,
                      child: TextField(
                        controller: _ortCtrl,
                        decoration: const InputDecoration(labelText: 'Ort'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                // 6. Telefon (bleibt so)
                TextField(
                  controller: _telefonCtrl,
                  decoration: const InputDecoration(labelText: 'Telefon'),
                  keyboardType: TextInputType.phone,
                ),
                const SizedBox(height: 12),
                // 8. Führerscheinklasse (Dropdown)
                DropdownButtonFormField<String>(
                  value: _fuehrerschein,
                  decoration: const InputDecoration(labelText: 'Führerscheinklasse'),
                  items: [
                    const DropdownMenuItem(value: '', child: Text('–')),
                    ...widget.fuehrerscheinklassen.where((c) => c.isNotEmpty).map((c) => DropdownMenuItem(value: c, child: Text(c))),
                  ],
                  onChanged: (v) => setState(() => _fuehrerschein = v ?? ''),
                ),
                const SizedBox(height: 12),
                // 9. Qualifikation und Vertrag auf einer Ebene
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: InputDecorator(
                        decoration: const InputDecoration(
                          labelText: 'Qualifikation',
                          border: OutlineInputBorder(),
                          contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                        ),
                        child: Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: widget.qualifikationen.map((q) {
                            final selected = _qualifikation.contains(q);
                            return FilterChip(
                              label: Text(q),
                              selected: selected,
                              onSelected: (v) {
                                setState(() {
                                  if (v) _qualifikation.add(q);
                                  else _qualifikation.remove(q);
                                  _qualifikation = List.from(_qualifikation);
                                });
                              },
                            );
                          }).toList(),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: InputDecorator(
                        decoration: const InputDecoration(
                          labelText: 'Vertrag',
                          border: OutlineInputBorder(),
                          contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                        ),
                        child: Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: widget.vertraege.map((a) {
                            final selected = _angestelltenverhaeltnis.contains(a);
                            return FilterChip(
                              label: Text(a),
                              selected: selected,
                              onSelected: (v) {
                                setState(() {
                                  if (v) _angestelltenverhaeltnis.add(a);
                                  else _angestelltenverhaeltnis.remove(a);
                                  _angestelltenverhaeltnis = List.from(_angestelltenverhaeltnis);
                                });
                              },
                            );
                          }).toList(),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                // 10. Rolle und Status (Aktiv) auf einer Ebene
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        value: _role,
                        decoration: const InputDecoration(labelText: 'Rolle'),
                        items: widget.roles.map((r) => DropdownMenuItem(value: r, child: Text(widget.roleLabels[r] ?? r))).toList(),
                        onChanged: (v) => setState(() => _role = v ?? 'user'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Text('Aktiv', style: TextStyle(fontSize: 14)),
                          const SizedBox(width: 8),
                          Switch(
                            value: _active,
                            onChanged: (v) => setState(() => _active = v),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                if (isCreate) ...[
                  const SizedBox(height: 12),
                  TextField(
                    controller: _passwordCtrl,
                    obscureText: true,
                    decoration: const InputDecoration(
                      labelText: 'Passwort (für Login, min. 6 Zeichen)',
                      hintText: 'Nur bei E-Mail/Personalnummer',
                    ),
                  ),
                ],
                const SizedBox(height: 24),
                FilledButton(
                  onPressed: _saving ? null : _save,
                  style: FilledButton.styleFrom(
                    backgroundColor: AppTheme.primary,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  child: _saving ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Text('Speichern'),
                ),
              ],
            ),
            ),
          ),
        ],
      ),
    );
  }
}
