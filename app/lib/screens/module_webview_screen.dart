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

  const ModuleWebViewScreen({
    super.key,
    required this.module,
    required this.companyId,
    this.loginEmail,
    this.loginPassword,
    this.onBack,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: AppTheme.headerBg,
        foregroundColor: Colors.white,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: onBack ?? () => Navigator.of(context).pop(),
        ),
        title: Text(module.label),
      ),
      body: ModuleWebViewWidget(
        module: module,
        companyId: companyId,
        loginEmail: loginEmail,
        loginPassword: loginPassword,
      ),
    );
  }
}
