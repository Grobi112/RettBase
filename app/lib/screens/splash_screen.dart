import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _shimmerAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat();
    _shimmerAnimation = Tween<double>(begin: -1.0, end: 2.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.headerBg,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Image.asset(
              'img/rettbase.png',
              height: 80,
              fit: BoxFit.contain,
            ),
            const SizedBox(height: 24),
            Text(
              'Rettungsdienst-Management',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.bold,
                color: Colors.white.withOpacity(0.95),
                letterSpacing: 0.5,
              ),
            ),
            const SizedBox(height: 28),
            _ModernLoadingBar(shimmerAnimation: _shimmerAnimation),
          ],
        ),
      ),
    );
  }
}

class _ModernLoadingBar extends StatelessWidget {
  final Animation<double> shimmerAnimation;

  const _ModernLoadingBar({required this.shimmerAnimation});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 240,
      height: 8,
      child: AnimatedBuilder(
        animation: shimmerAnimation,
        builder: (context, child) {
          return ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: CustomPaint(
              painter: _LoadingBarPainter(
                progress: (shimmerAnimation.value + 1) / 3,
              ),
            ),
          );
        },
      ),
    );
  }
}

class _LoadingBarPainter extends CustomPainter {
  final double progress;

  _LoadingBarPainter({required this.progress});

  @override
  void paint(Canvas canvas, Size size) {
    final trackPaint = Paint()
      ..color = Colors.white.withOpacity(0.15)
      ..style = PaintingStyle.fill;

    final trackRRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(0, 0, size.width, size.height),
      Radius.circular(size.height / 2),
    );
    canvas.drawRRect(trackRRect, trackPaint);

    final barWidth = size.width * 0.42;
    final x = (size.width + barWidth) * progress - barWidth;
    final drawRect = Rect.fromLTWH(x.clamp(0.0, size.width - 1), 0, barWidth, size.height);
    final barRect = RRect.fromRectAndRadius(drawRect, Radius.circular(size.height / 2));

    final gradient = LinearGradient(
      begin: Alignment.centerLeft,
      end: Alignment.centerRight,
      colors: [
        AppTheme.primary.withOpacity(0.4),
        AppTheme.primary,
        Colors.white,
        AppTheme.primary,
        AppTheme.primary.withOpacity(0.4),
      ],
      stops: const [0.0, 0.4, 0.5, 0.6, 1.0],
    );
    final barPaint = Paint()
      ..shader = gradient.createShader(drawRect)
      ..style = PaintingStyle.fill;

    canvas.drawRRect(barRect, barPaint);
  }

  @override
  bool shouldRepaint(covariant _LoadingBarPainter oldDelegate) =>
      oldDelegate.progress != progress;
}
