import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import 'einstellungen_schichtarten_screen.dart';
import 'einstellungen_informationssystem_screen.dart';

/// Globale Einstellungen – Übersicht (Hamburger-Menü)
class EinstellungenScreen extends StatefulWidget {
  final String companyId;
  final VoidCallback? onBack;
  /// Wird aufgerufen, wenn Informationssystem-Einstellungen gespeichert wurden
  final VoidCallback? onInformationssystemSaved;
  final bool hideAppBar;

  const EinstellungenScreen({
    super.key,
    required this.companyId,
    this.onBack,
    this.onInformationssystemSaved,
    this.hideAppBar = false,
  });

  @override
  State<EinstellungenScreen> createState() => _EinstellungenScreenState();
}

class _EinstellungenScreenState extends State<EinstellungenScreen> {
  @override
  Widget build(BuildContext context) {
    final scaffold = Scaffold(
      backgroundColor: AppTheme.surfaceBg,
      appBar: AppTheme.buildModuleAppBar(
        title: 'Einstellungen',
        onBack: widget.onBack ?? () => Navigator.of(context).pop(),
      ),
      body: ListView(
        padding: EdgeInsets.all(Responsive.horizontalPadding(context)),
        children: [
          Text(
            'Globale Einstellungen',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: AppTheme.textSecondary,
                  fontWeight: FontWeight.w500,
                ),
          ),
          const SizedBox(height: 12),
          _SettingsCard(
            icon: Icons.schedule,
            title: 'Schicht- und Standortverwaltung',
            subtitle: 'Standorte anlegen, Schichtarten mit Start-/Endzeit zuordnen',
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => EinstellungenSchichtartenScreen(
                  companyId: widget.companyId,
                  onBack: () => Navigator.of(context).pop(),
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          _SettingsCard(
            icon: Icons.info_outline,
            title: 'Informationssystem',
            subtitle: 'Container auf der Hauptseite (Informationen, Verkehrslage) anordnen',
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => EinstellungenInformationssystemScreen(
                  companyId: widget.companyId,
                  onBack: () => Navigator.of(context).pop(),
                  onSaved: widget.onInformationssystemSaved,
                ),
              ),
            ).then((_) => widget.onInformationssystemSaved?.call()),
          ),
          const SizedBox(height: 12),
          _SettingsCard(
            icon: Icons.tune,
            title: 'Weitere Einstellungen',
            subtitle: 'In Kürze verfügbar',
            onTap: null,
          ),
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
}

class _SettingsCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;

  const _SettingsCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppTheme.primary.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: AppTheme.primary, size: 28),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 4),
                    Text(subtitle, style: TextStyle(fontSize: 13, color: Colors.grey[600])),
                  ],
                ),
              ),
              if (onTap != null) Icon(Icons.chevron_right, color: Colors.grey[400]),
            ],
          ),
        ),
      ),
    );
  }
}
