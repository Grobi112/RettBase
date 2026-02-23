import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../services/auth_data_service.dart';
import '../services/auth_service.dart';
import 'schichtplan_nfs_stundenplan_screen.dart';
import 'schichtplan_nfs_meldungen_body.dart';
import 'schichtplan_nfs_einstellungen_screen.dart';
import 'schichtplan_nfs_schicht_anlegen_sheet.dart';
import 'schichtplan_nfs_offene_schicht_melden_sheet.dart';

bool _canEditEinstellungen(String? role) {
  if (role == null || role.isEmpty) return false;
  final r = role.trim().toLowerCase();
  return r == 'superadmin' || r == 'admin' || r == 'koordinator';
}

/// Reiter "Meldungen" nur für Admin, Koordinator, Superadmin – User darf ihn nicht sehen
bool _canSeeMeldungen(String? role) {
  if (role == null || role.isEmpty) return false;
  final r = role.trim().toLowerCase();
  return r == 'superadmin' || r == 'admin' || r == 'koordinator';
}

/// Schichtplan NFS (Notfallseelsorge) – Bereitschaftsplan mit Wochen- und Monatsübersicht
class SchichtplanNfsScreen extends StatefulWidget {
  final String companyId;
  final String? userRole;
  final String? title;
  final VoidCallback onBack;

  const SchichtplanNfsScreen({
    super.key,
    required this.companyId,
    this.userRole,
    this.title,
    required this.onBack,
  });

  @override
  State<SchichtplanNfsScreen> createState() => _SchichtplanNfsScreenState();
}

class _SchichtplanNfsScreenState extends State<SchichtplanNfsScreen>
    with SingleTickerProviderStateMixin {
  final List<void Function()> _refreshCallbacks = [];
  late TabController _tabController;
  final _authService = AuthService();
  final _authDataService = AuthDataService();
  String? _effectiveRole;

  void _refreshAllBodies() {
    for (final cb in _refreshCallbacks) {
      cb();
    }
  }

  @override
  void initState() {
    super.initState();
    // Zunächst restriktiv (nur Monat) – Rolle wird asynchron geladen
    _tabController = TabController(length: 1, vsync: this, initialIndex: 0);
    _tabController.addListener(() => setState(() {}));
    _loadRole();
  }

  Future<void> _loadRole() async {
    final user = _authService.currentUser;
    if (user == null) {
      if (mounted) setState(() => _effectiveRole = widget.userRole);
      return;
    }
    final authData = await _authDataService.getAuthData(
      user.uid,
      user.email ?? '',
      widget.companyId,
    );
    if (!mounted) return;
    final newRole = authData.role;
    final hadMeldungen = _canSeeMeldungen(_effectiveRole ?? widget.userRole);
    final hasMeldungen = _canSeeMeldungen(newRole);
    setState(() => _effectiveRole = newRole);
    if (hadMeldungen != hasMeldungen) {
      _tabController.dispose();
      _tabController = TabController(length: hasMeldungen ? 2 : 1, vsync: this, initialIndex: 0);
      _tabController.addListener(() => setState(() {}));
    }
  }

  String? get _role => _effectiveRole ?? widget.userRole;

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  void _openEinstellungen() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => SchichtplanNfsEinstellungenScreen(
          companyId: widget.companyId,
          userRole: _role,
          onBack: () => Navigator.pop(context),
        ),
      ),
    );
  }

  void _openOffeneSchichtMelden() {
    showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Schließen',
      barrierColor: Colors.black54,
      transitionDuration: const Duration(milliseconds: 200),
      pageBuilder: (ctx, _, __) => Center(
        child: Material(
          color: Colors.transparent,
          child: SchichtplanNfsOffeneSchichtMeldenSheet(
            companyId: widget.companyId,
            onSaved: () {
              Navigator.pop(ctx);
              _refreshAllBodies();
            },
            onCancel: () => Navigator.pop(ctx),
          ),
        ),
      ),
    );
  }

  void _openSchichtAnlegen() {
    showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Schließen',
      barrierColor: Colors.black54,
      transitionDuration: const Duration(milliseconds: 200),
      pageBuilder: (ctx, _, __) => Center(
        child: Material(
          color: Colors.transparent,
          child: SchichtAnlegenSheet(
            companyId: widget.companyId,
            onSaved: () {
              Navigator.pop(ctx);
              _refreshAllBodies();
            },
            onCancel: () => Navigator.pop(ctx),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.surfaceBg,
      appBar: AppTheme.buildModuleAppBar(
        title: widget.title ?? 'Schichtplan',
        onBack: widget.onBack,
        actions: [
          TextButton.icon(
            onPressed: _openOffeneSchichtMelden,
            icon: const Icon(Icons.person_add_outlined, size: 20),
            label: const Text('Verfügbarkeit angeben'),
          ),
          if (_canEditEinstellungen(_role)) ...[
            TextButton.icon(
              onPressed: _openSchichtAnlegen,
              icon: const Icon(Icons.add_circle_outline, size: 20),
              label: const Text('Schicht anlegen'),
            ),
            IconButton(
              icon: const Icon(Icons.settings),
              tooltip: 'Einstellungen',
              onPressed: _openEinstellungen,
            ),
          ],
        ],
      ),
      body: Column(
        children: [
          if (_canSeeMeldungen(_role))
            TabBar(
              controller: _tabController,
              labelColor: AppTheme.primary,
              unselectedLabelColor: AppTheme.textMuted,
              indicatorColor: AppTheme.primary,
              tabs: const [
                Tab(text: 'Monat'),
                Tab(text: 'Meldungen'),
              ],
            )
          else
            const SizedBox.shrink(),
          Expanded(
            child: _canSeeMeldungen(_role)
                ? TabBarView(
                    controller: _tabController,
                    children: [
                      SchichtplanNfsMonatsuebersichtBody(
                        companyId: widget.companyId,
                        userRole: _role,
                        onRegisterRefresh: (fn) => _refreshCallbacks.add(fn),
                      ),
                      SchichtplanNfsMeldungenBody(
                        companyId: widget.companyId,
                        userRole: _role,
                        onRegisterRefresh: (fn) => _refreshCallbacks.add(fn),
                        onMeldungAngenommen: _refreshAllBodies,
                      ),
                    ],
                  )
                : SchichtplanNfsMonatsuebersichtBody(
                    companyId: widget.companyId,
                    userRole: _role,
                    onRegisterRefresh: (fn) => _refreshCallbacks.add(fn),
                  ),
          ),
        ],
      ),
    );
  }
}
