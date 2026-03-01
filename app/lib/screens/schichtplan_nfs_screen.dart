import 'dart:async';
import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../services/auth_data_service.dart';
import '../services/auth_service.dart';
import '../services/schichtplan_nfs_service.dart';
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

class _SchichtplanNfsScreenState extends State<SchichtplanNfsScreen> {
  final List<void Function()> _refreshCallbacks = [];
  int _selectedTabIndex = 0; // 0 = Monat, 1 = Meldungen
  final _authService = AuthService();
  final _authDataService = AuthDataService();
  final _schichtplanService = SchichtplanNfsService();
  String? _effectiveRole;
  int _meldungenCount = 0;
  StreamSubscription<int>? _meldungenCountSub;

  void _refreshAllBodies() {
    for (final cb in _refreshCallbacks) {
      cb();
    }
  }

  @override
  void initState() {
    super.initState();
    _loadRole();
  }

  void _startMeldungenCountStream() {
    if (!_canSeeMeldungen(_role)) return;
    _meldungenCountSub?.cancel();
    _meldungenCountSub = _schichtplanService
        .streamMeldungenCount(widget.companyId)
        .listen((count) {
      if (mounted) setState(() => _meldungenCount = count);
    });
  }

  void _stopMeldungenCountStream() {
    _meldungenCountSub?.cancel();
    _meldungenCountSub = null;
  }

  Future<void> _loadRole() async {
    final user = _authService.currentUser;
    if (user == null) {
      if (mounted) setState(() => _effectiveRole = widget.userRole);
      _startMeldungenCountStream();
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
    if (hasMeldungen) {
      _startMeldungenCountStream();
    } else {
      _stopMeldungenCountStream();
    }
  }

  String? get _role => _effectiveRole ?? widget.userRole;

  @override
  void dispose() {
    _stopMeldungenCountStream();
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

  PreferredSizeWidget _buildTabBar() {
    return PreferredSize(
      preferredSize: const Size.fromHeight(48),
      child: Container(
        color: Colors.white,
        child: Row(
          children: [
            _buildTab(0, 'Monat'),
            _buildTab(1, 'Meldungen', badgeCount: _meldungenCount),
          ],
        ),
      ),
    );
  }

  Widget _buildTab(int index, String label, {int badgeCount = 0}) {
    final isSelected = _selectedTabIndex == index;
    return Expanded(
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => setState(() => _selectedTabIndex = index),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 14),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(
                  color: isSelected ? AppTheme.primary : Colors.transparent,
                  width: 3,
                ),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    color: isSelected ? AppTheme.primary : AppTheme.textMuted,
                    fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                    fontSize: 14,
                  ),
                ),
                if (badgeCount > 0) ...[
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                    decoration: const BoxDecoration(
                      color: Colors.red,
                      borderRadius: BorderRadius.all(Radius.circular(10)),
                    ),
                    child: Text(
                      badgeCount > 99 ? '99+' : '$badgeCount',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ],
            ),
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
        bottom: _canSeeMeldungen(_role) ? _buildTabBar() : null,
        actions: [
          IconButton(
            onPressed: _openOffeneSchichtMelden,
            icon: const Icon(Icons.person_add_outlined),
            tooltip: 'Verfügbarkeit angeben',
          ),
          if (_canEditEinstellungen(_role)) ...[
            IconButton(
              onPressed: _openSchichtAnlegen,
              icon: const Icon(Icons.add_circle_outline),
              tooltip: 'Schicht anlegen',
            ),
            IconButton(
              icon: const Icon(Icons.settings),
              tooltip: 'Einstellungen',
              onPressed: _openEinstellungen,
            ),
          ],
        ],
      ),
      body: _canSeeMeldungen(_role)
          ? IndexedStack(
              index: _selectedTabIndex,
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
    );
  }
}
