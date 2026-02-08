import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Stift-Segment mit Punkten und Eigenschaften
class _Stroke {
  final List<Offset> points;
  final Color color;
  final double strokeWidth;
  final bool isEraser;

  _Stroke({
    required this.points,
    required this.color,
    required this.strokeWidth,
    this.isEraser = false,
  });
}

/// Zeichenfläche mit Stift, Radierer, Rückgängig und Löschen
class SketchCanvas extends StatefulWidget {
  final double height;

  const SketchCanvas({super.key, this.height = 240});

  @override
  State<SketchCanvas> createState() => SketchCanvasState();
}

class SketchCanvasState extends State<SketchCanvas> {
  final List<_Stroke> _strokes = [];
  final GlobalKey _repaintKey = GlobalKey();
  Color _penColor = Colors.black;
  double _penWidth = 3.0;
  double _eraserWidth = 24.0;
  bool _isEraser = false;
  static const Color _canvasBg = Color(0xFFFAFAFA);

  void _pen() => setState(() => _isEraser = false);

  void _eraser() => setState(() => _isEraser = true);

  void _undo() {
    if (_strokes.isEmpty) return;
    setState(() => _strokes.removeLast());
  }

  void _clear() => setState(() => _strokes.clear());

  bool get hasContent => _strokes.isNotEmpty;

  /// Canvas als PNG-Bild erfassen (für Upload)
  Future<Uint8List?> captureImage() async {
    if (_strokes.isEmpty) return null;
    try {
      final boundary = _repaintKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) return null;
      final image = await boundary.toImage(pixelRatio: 2.0);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      return byteData?.buffer.asUint8List();
    } catch (_) {
      return null;
    }
  }

  void _onPointerDown(PointerDownEvent e) {
    final local = e.localPosition;
    _strokes.add(_Stroke(
      points: [local],
      color: _isEraser ? _canvasBg : _penColor,
      strokeWidth: _isEraser ? _eraserWidth : _penWidth,
      isEraser: _isEraser,
    ));
    setState(() {});
  }

  void _onPointerMove(PointerMoveEvent e) {
    if (_strokes.isEmpty) return;
    final local = e.localPosition;
    _strokes.last.points.add(local);
    setState(() {});
  }

  void _onPointerUp(PointerUpEvent e) {
    // Stroke bereits in Move hinzugefügt
  }

  void _onPointerCancel(PointerCancelEvent e) {
    // Keine Aktion nötig
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: _canvasBg,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey.shade400),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Toolbar
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.grey.shade200,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
            ),
            child: Row(
              children: [
                _ToolButton(
                  icon: Icons.edit,
                  label: 'Stift',
                  selected: !_isEraser,
                  onTap: _pen,
                ),
                const SizedBox(width: 8),
                _ToolButton(
                  icon: Icons.cleaning_services,
                  label: 'Radierer',
                  selected: _isEraser,
                  onTap: _eraser,
                ),
                const SizedBox(width: 8),
                _ToolButton(
                  icon: Icons.undo,
                  label: 'Rückgängig',
                  onTap: _undo,
                  enabled: _strokes.isNotEmpty,
                ),
                const SizedBox(width: 8),
                _ToolButton(
                  icon: Icons.delete_outline,
                  label: 'Löschen',
                  onTap: _clear,
                  enabled: _strokes.isNotEmpty,
                ),
              ],
            ),
          ),
          // Canvas
          SizedBox(
            height: widget.height,
            width: double.infinity,
            child: Listener(
              behavior: HitTestBehavior.opaque,
              onPointerDown: _onPointerDown,
              onPointerMove: _onPointerMove,
              onPointerUp: _onPointerUp,
              onPointerCancel: _onPointerCancel,
              child: RepaintBoundary(
                key: _repaintKey,
                child: CustomPaint(
                  painter: _SketchPainter(strokes: _strokes),
                  size: Size.infinite,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SketchPainter extends CustomPainter {
  final List<_Stroke> strokes;

  _SketchPainter({required this.strokes});

  @override
  void paint(Canvas canvas, Size size) {
    for (final stroke in strokes) {
      if (stroke.points.length < 2) continue;
      final paint = Paint()
        ..color = stroke.color
        ..strokeWidth = stroke.strokeWidth
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..style = PaintingStyle.stroke
        ..isAntiAlias = true;
      final path = Path()..moveTo(stroke.points.first.dx, stroke.points.first.dy);
      for (var i = 1; i < stroke.points.length; i++) {
        path.lineTo(stroke.points[i].dx, stroke.points[i].dy);
      }
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _SketchPainter oldDelegate) =>
      oldDelegate.strokes != strokes;
}

class _ToolButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool selected;
  final bool enabled;

  const _ToolButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.selected = false,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? AppTheme.primary.withOpacity(0.2) : Colors.transparent,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 20,
                color: enabled
                    ? (selected ? AppTheme.primary : Colors.grey.shade700)
                    : Colors.grey.shade400,
              ),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  color: enabled
                      ? (selected ? AppTheme.primary : Colors.grey.shade700)
                      : Colors.grey.shade400,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
