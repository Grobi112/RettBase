import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
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

/// Schichtplan NFS (Notfallseelsorge) – Bereitschaftsplan mit Wochen- und Monatsübersicht
class SchichtplanNfsScreen extends StatefulWidget {
  final String companyId;
  final String? userRole;
  final VoidCallback onBack;

  const SchichtplanNfsScreen({
    super.key,
    required this.companyId,
    this.userRole,
    required this.onBack,
  });

  @override
  State<SchichtplanNfsScreen> createState() => _SchichtplanNfsScreenState();
}

class _SchichtplanNfsScreenState extends State<SchichtplanNfsScreen>
    with SingleTickerProviderStateMixin {
  final List<void Function()> _refreshCallbacks = [];
  late TabController _tabController;

  void _refreshAllBodies() {
    for (final cb in _refreshCallbacks) {
      cb();
    }
  }

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this, initialIndex: 0);
    _tabController.addListener(() => setState(() {}));
  }

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
          userRole: widget.userRole,
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
        title: 'Schichtplan',
        onBack: widget.onBack,
        actions: [
          TextButton.icon(
            onPressed: _openOffeneSchichtMelden,
            icon: const Icon(Icons.person_add_outlined, size: 20),
            label: const Text('Verfügbarkeit angeben'),
          ),
          if (_canEditEinstellungen(widget.userRole)) ...[
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
          TabBar(
            controller: _tabController,
            labelColor: AppTheme.primary,
            unselectedLabelColor: AppTheme.textMuted,
            indicatorColor: AppTheme.primary,
            tabs: const [
              Tab(text: 'Monat'),
              Tab(text: 'Meldungen'),
            ],
          ),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                SchichtplanNfsMonatsuebersichtBody(
                  companyId: widget.companyId,
                  userRole: widget.userRole,
                  onRegisterRefresh: (fn) => _refreshCallbacks.add(fn),
                ),
                SchichtplanNfsMeldungenBody(
                  companyId: widget.companyId,
                  userRole: widget.userRole,
                  onRegisterRefresh: (fn) => _refreshCallbacks.add(fn),
                  onMeldungAngenommen: _refreshAllBodies,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
