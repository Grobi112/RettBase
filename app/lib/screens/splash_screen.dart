import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// Ladebildschirm mit determinierter Fortschrittsanzeige (0.0–1.0).
/// Einfacher Balken, der sich von links nach rechts füllt.
class SplashScreen extends StatelessWidget {
  /// Fortschritt 0.0–1.0
  final double progress;

  const SplashScreen({super.key, required this.progress});

  /// Einheitliche Logo-Größe (120px) für nahtlosen Übergang vom HTML-Platzhalter.
  static const double _logoHeight = 120;

  @override
  Widget build(BuildContext context) {
    final narrow = MediaQuery.sizeOf(context).width < 400;
    return Scaffold(
      backgroundColor: AppTheme.headerBg,
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: narrow ? 24 : 48),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Image.asset(
                  'img/rettbase_splash.png',
                  height: _logoHeight,
                  fit: BoxFit.contain,
                ),
                SizedBox(height: narrow ? 24 : 32),
                _ProgressBar(progress: progress.clamp(0.0, 1.0), narrow: narrow),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Determiniert: Balken füllt sich von links nach rechts.
class _ProgressBar extends StatelessWidget {
  final double progress;
  final bool narrow;

  const _ProgressBar({required this.progress, this.narrow = false});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: narrow ? 180 : 240,
      height: 8,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: CustomPaint(
          painter: _ProgressBarPainter(progress: progress),
          size: Size(narrow ? 180 : 240, 8),
        ),
      ),
    );
  }
}

class _ProgressBarPainter extends CustomPainter {
  final double progress;

  _ProgressBarPainter({required this.progress});

  @override
  void paint(Canvas canvas, Size size) {
    // Hintergrund-Track
    final trackPaint = Paint()
      ..color = Colors.white.withOpacity(0.15)
      ..style = PaintingStyle.fill;

    final trackRRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(0, 0, size.width, size.height),
      Radius.circular(size.height / 2),
    );
    canvas.drawRRect(trackRRect, trackPaint);

    // Füllung von links nach rechts
    final fillWidth = size.width * progress.clamp(0.0, 1.0);
    if (fillWidth > 0) {
      final fillRect = RRect.fromRectAndRadius(
        Rect.fromLTWH(0, 0, fillWidth, size.height),
        Radius.circular(size.height / 2),
      );
      final fillPaint = Paint()
        ..color = AppTheme.primary
        ..style = PaintingStyle.fill;
      canvas.drawRRect(fillRect, fillPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _ProgressBarPainter oldDelegate) =>
      oldDelegate.progress != progress;
}
