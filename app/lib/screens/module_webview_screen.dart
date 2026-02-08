import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../models/app_module.dart';
import 'module_webview_widget.dart';

/// Zeigt ein Web-Modul (z.B. E-Mail/Office) in der App
class ModuleWebViewScreen extends StatelessWidget {
  final AppModule module;
  final String companyId;
  final String? loginEmail;
  final String? loginPassword;
  final VoidCallback? onBack;
  /// Wenn true: keine AppBar (Header kommt vom Dashboard)
  final bool hideAppBar;

  const ModuleWebViewScreen({
    super.key,
    required this.module,
    required this.companyId,
    this.loginEmail,
    this.loginPassword,
    this.onBack,
    this.hideAppBar = false,
  });

  @override
  Widget build(BuildContext context) {
    final scaffold = Scaffold(
      backgroundColor: Colors.white,
      appBar: AppTheme.buildModuleAppBar(
        title: module.label,
        onBack: onBack ?? () => Navigator.of(context).pop(),
      ),
      body: ModuleWebViewWidget(
        module: module,
        companyId: companyId,
        loginEmail: loginEmail,
        loginPassword: loginPassword,
      ),
    );

    // Explizite Zurück-Navigation bei eingebetteten Modulen (verhindert Null/Bool-Fehler)
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
