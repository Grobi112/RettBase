import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// Platzhalter für Module, die noch nativ umgesetzt werden
class PlaceholderModuleScreen extends StatelessWidget {
  final String moduleName;
  final VoidCallback? onBack;
  final bool hideAppBar;

  const PlaceholderModuleScreen({
    super.key,
    required this.moduleName,
    this.onBack,
    this.hideAppBar = false,
  });

  @override
  Widget build(BuildContext context) {
    final scaffold = Scaffold(
      backgroundColor: AppTheme.surfaceBg,
      appBar: AppTheme.buildModuleAppBar(
        title: moduleName,
        onBack: onBack ?? () => Navigator.of(context).pop(),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.construction, size: 64, color: AppTheme.textMuted),
              const SizedBox(height: 16),
              Text(
                'In Entwicklung',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      color: AppTheme.textPrimary,
                    ),
              ),
              const SizedBox(height: 8),
              Text(
                'Dieses Modul wird gerade für die App entwickelt.',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppTheme.textSecondary),
              ),
            ],
          ),
        ),
      ),
    );

    if (hideAppBar && onBack != null) {
      return PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) onBack!();
        },
        child: scaffold,
      );
    }
    return scaffold;
  }
}
