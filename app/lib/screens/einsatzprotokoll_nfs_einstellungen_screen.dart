import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import 'einsatzprotokoll_nfs_uebersicht_screen.dart';

/// Einstellungen für Einsatzprotokoll NFS – Menü mit Bereichen (wie Mitgliederverwaltung)
class EinsatzprotokollNfsEinstellungenScreen extends StatelessWidget {
  final String companyId;
  final String? userRole;
  final VoidCallback onBack;

  const EinsatzprotokollNfsEinstellungenScreen({
    super.key,
    required this.companyId,
    this.userRole,
    required this.onBack,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.surfaceBg,
      appBar: AppTheme.buildModuleAppBar(
        title: 'Einstellungen',
        onBack: onBack,
      ),
      body: ListView(
        padding: EdgeInsets.all(Responsive.horizontalPadding(context)),
        children: [
          _MenuTile(
            icon: Icons.list_alt,
            title: 'Protokollübersicht',
            subtitle: 'Gespeicherte Einsatzprotokolle anzeigen und verwalten',
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => EinsatzprotokollNfsUebersichtScreen(
                  companyId: companyId,
                  userRole: userRole ?? 'user',
                  onBack: () => Navigator.pop(context),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MenuTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _MenuTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: AppTheme.primary.withOpacity(0.15),
          child: Icon(icon, color: AppTheme.primary),
        ),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text(subtitle, style: TextStyle(fontSize: 13, color: AppTheme.textMuted)),
        trailing: const Icon(Icons.chevron_right, color: AppTheme.textMuted),
        onTap: onTap,
      ),
    );
  }
}
