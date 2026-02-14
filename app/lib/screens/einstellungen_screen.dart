import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import '../theme/app_theme.dart';
import '../services/auth_service.dart';
import '../services/push_notification_service.dart';
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
  bool _pushRequesting = false;
  String? _pushStatus;

  Future<void> _requestPushPermission() async {
    if (_pushRequesting) return;
    final user = AuthService().currentUser;
    if (user == null) return;
    setState(() => _pushRequesting = true);
    final permFuture = PushNotificationService.startNotificationPermissionRequestForWeb();
    try {
      final (success, needsReload) = permFuture != null
          ? await PushNotificationService.requestPermissionAndSaveTokenForWeb(
              widget.companyId,
              user.uid,
              permissionFuture: permFuture,
            )
          : (false, false);
      if (mounted) {
        setState(() {
          _pushRequesting = false;
          _pushStatus = success ? 'aktiviert' : (needsReload ? 'Seite neu laden' : 'abgebrochen');
        });
        if (needsReload) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Bitte Seite neu laden und erneut tippen'),
              duration: Duration(seconds: 5),
            ),
          );
        }
      }
    } catch (_) {
      if (mounted) setState(() => _pushRequesting = false);
    }
  }

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
          if (kIsWeb) ...[
            const SizedBox(height: 12),
            _PushNotificationCard(
              companyId: widget.companyId,
              status: _pushStatus,
              isRequesting: _pushRequesting,
              onTap: _requestPushPermission,
            ),
          ],
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

class _PushNotificationCard extends StatefulWidget {
  final String companyId;
  final String? status;
  final bool isRequesting;
  final VoidCallback onTap;

  const _PushNotificationCard({
    required this.companyId,
    required this.status,
    required this.isRequesting,
    required this.onTap,
  });

  @override
  State<_PushNotificationCard> createState() => _PushNotificationCardState();
}

class _PushNotificationCardState extends State<_PushNotificationCard> {
  bool _checking = false;
  bool? _tokenInFirestore;

  Future<void> _checkTokenStatus() async {
    if (_checking) return;
    setState(() {
      _checking = true;
      _tokenInFirestore = null;
    });
    try {
      final hasToken = await PushNotificationService.checkFcmTokenInFirestore(widget.companyId);
      if (mounted) {
        setState(() {
          _checking = false;
          _tokenInFirestore = hasToken;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _checking = false;
          _tokenInFirestore = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final perm = PushNotificationService.getNotificationPermissionStatusWeb();
    final granted = perm == 'granted';

    return Card(
      child: InkWell(
        onTap: granted ? null : (widget.isRequesting ? null : widget.onTap),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: (granted ? Colors.green : AppTheme.primary).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  granted ? Icons.notifications_active : Icons.notifications_off,
                  color: granted ? Colors.green : AppTheme.primary,
                  size: 28,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Chat-Benachrichtigungen',
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      granted
                          ? 'Push-Benachrichtigungen sind aktiv'
                          : widget.status == 'abgebrochen'
                              ? 'Berechtigung verweigert – erneut tippen zum Aktivieren'
                              : widget.isRequesting
                                  ? 'Bitte im Browser-Dialog erlauben…'
                                  : 'Tippen Sie hier, um Benachrichtigungen zu aktivieren (erforderlich auf dem Handy)',
                      style: TextStyle(fontSize: 13, color: Colors.grey[600]),
                    ),
                    if (granted) ...[
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          TextButton(
                            onPressed: _checking ? null : _checkTokenStatus,
                            style: TextButton.styleFrom(
                              padding: EdgeInsets.zero,
                              minimumSize: Size.zero,
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                            child: Text(
                              _checking
                                  ? 'Prüfe…'
                                  : 'Token-Status prüfen',
                              style: TextStyle(fontSize: 12, color: AppTheme.primary),
                            ),
                          ),
                          TextButton(
                            onPressed: () {
                              final ok = PushNotificationService.testBadgeApiWeb();
                              if (mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(ok
                                        ? 'Badge auf 5 gesetzt. App minimieren und PWA-Icon prüfen.'
                                        : 'Badge-API nicht verfügbar. Safari: Benachrichtigungen erlauben. Chrome Android: nicht unterstützt.'),
                                    duration: const Duration(seconds: 5),
                                  ),
                                );
                              }
                            },
                            style: TextButton.styleFrom(
                              padding: EdgeInsets.zero,
                              minimumSize: Size.zero,
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                            child: Text(
                              'Badge testen',
                              style: TextStyle(fontSize: 12, color: AppTheme.primary),
                            ),
                          ),
                          if (_tokenInFirestore != null) ...[
                            const SizedBox(width: 8),
                            Icon(
                              _tokenInFirestore == true ? Icons.check_circle : Icons.warning_amber_rounded,
                              size: 16,
                              color: _tokenInFirestore == true ? Colors.green : Colors.orange,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              _tokenInFirestore == true ? 'Token gespeichert' : 'Kein Token gefunden',
                              style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              if (widget.isRequesting)
                const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2))
              else if (!granted)
                Icon(Icons.touch_app, color: AppTheme.primary, size: 24),
            ],
          ),
        ),
      ),
    );
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
