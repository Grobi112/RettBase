import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// Ladebildschirm (nur Native) – Logo auf Brand-Gradient. Kein Fortschrittsbalken.
/// Web nutzt den HTML-Loader in index.html.
class SplashScreen extends StatelessWidget {
  /// Fortschritt (für API-Kompatibilität, wird auf Native nicht angezeigt)
  final double progress;

  const SplashScreen({super.key, required this.progress});

  static const double _logoHeight = 120;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SizedBox.expand(
        child: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                AppTheme.navyLight,
                AppTheme.navy,
                AppTheme.navyDark,
              ],
              stops: [0.0, 0.55, 1.0],
            ),
          ),
          child: SafeArea(
            child: Center(
              child: Image.asset(
                'img/rettbase-logo.png',
                height: _logoHeight,
                fit: BoxFit.contain,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
