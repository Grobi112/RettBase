import 'dart:async';
import 'dart:html' as html;

/// Phase 2 (Flutter _initApp): 50–100%. Phase 1 (HTML) deckt 0–50% ab.
/// Nimmt nie ab, damit Übergang Phase 1→2 durchgängig ist.
void updateProgress(double progress) {
  final fill = html.document.getElementById('splash-bar-fill');
  if (fill != null) {
    fill.dataset['phase2'] = 'true';
    final phase2 = progress.clamp(0.0, 1.0) * 0.5;
    final cur = _parseWidth(fill.style.width ?? '');
    final p = cur > (0.5 + phase2) ? cur : (0.5 + phase2);
    fill.style.width = '${p * 100}%';
  }
}

double _parseWidth(String s) {
  if (s.endsWith('%')) {
    return (double.tryParse(s.substring(0, s.length - 1)) ?? 0) / 100;
  }
  return 0;
}

/// Entfernt den HTML-Ladebildschirm (nur Web). Kurzer Fade-out für weichen Übergang.
void removeLoader() {
  final loader = html.document.getElementById('flutter-init-loader');
  if (loader == null) return;
  loader.style.opacity = '0';
  Timer(const Duration(milliseconds: 220), () => loader.remove());
}
