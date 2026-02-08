import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// Informationssystem – Module mit Bereichen Informationen und Verkehrslage
/// Alle Rollen können hinzufügen und löschen
class InformationssystemScreen extends StatefulWidget {
  final String companyId;
  final VoidCallback? onBack;

  const InformationssystemScreen({
    super.key,
    required this.companyId,
    this.onBack,
  });

  @override
  State<InformationssystemScreen> createState() => _InformationssystemScreenState();
}

class _InformationssystemScreenState extends State<InformationssystemScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.surfaceBg,
      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: AppTheme.primary,
        elevation: 1,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: widget.onBack ?? () => Navigator.of(context).pop(),
        ),
        title: Text('Informationssystem', style: TextStyle(color: AppTheme.primary, fontWeight: FontWeight.w600)),
        bottom: TabBar(
          controller: _tabController,
          labelColor: AppTheme.primary,
          indicatorColor: AppTheme.primary,
          tabs: const [
            Tab(text: 'Informationen'),
            Tab(text: 'Verkehrslage'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _InfoSection(companyId: widget.companyId),
          _VerkehrslageSection(companyId: widget.companyId),
        ],
      ),
    );
  }
}

class _InfoSection extends StatelessWidget {
  final String companyId;

  const _InfoSection({required this.companyId});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        _PlaceholderCard(
          icon: Icons.info_outline,
          title: 'Informationen',
          subtitle: 'Hier werden interne Informationen angezeigt. In Kürze können alle Mitarbeiter Einträge hinzufügen und löschen.',
        ),
      ],
    );
  }
}

class _VerkehrslageSection extends StatelessWidget {
  final String companyId;

  const _VerkehrslageSection({required this.companyId});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        _PlaceholderCard(
          icon: Icons.traffic,
          title: 'Verkehrslage',
          subtitle: 'Hier wird die aktuelle Verkehrslage angezeigt. In Kürze können alle Mitarbeiter Einträge hinzufügen und löschen.',
        ),
      ],
    );
  }
}

class _PlaceholderCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;

  const _PlaceholderCard({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 32, color: AppTheme.primary),
                const SizedBox(width: 12),
                Text(title, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: AppTheme.textPrimary)),
              ],
            ),
            const SizedBox(height: 12),
            Text(subtitle, style: TextStyle(fontSize: 14, color: AppTheme.textSecondary, height: 1.4)),
          ],
        ),
      ),
    );
  }
}
