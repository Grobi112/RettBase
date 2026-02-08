import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

/// Unterschriftenfeld – Zeichnen mit Touch, Stift oder Maus
class _SigStroke {
  final List<Offset> points;
  _SigStroke(this.points);
}

const _penColor = Colors.black;
const _penWidth = 2.5;

class SignaturePad extends StatefulWidget {
  final double height;

  const SignaturePad({super.key, this.height = 120});

  @override
  State<SignaturePad> createState() => SignaturePadState();
}

class SignaturePadState extends State<SignaturePad> {
  final List<_SigStroke> _strokes = [];
  final GlobalKey _repaintKey = GlobalKey();
  static const Color _canvasBg = Color(0xFFFAFAFA);

  void clear() => setState(() => _strokes.clear());

  bool get hasContent => _strokes.isNotEmpty;

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
    _strokes.add(_SigStroke([e.localPosition]));
    setState(() {});
  }

  void _onPointerMove(PointerMoveEvent e) {
    if (_strokes.isEmpty) return;
    _strokes.last.points.add(e.localPosition);
    setState(() {});
  }

  void _onPointerUp(PointerUpEvent e) {}

  void _onPointerCancel(PointerCancelEvent e) {}

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
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Unterschrift',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: Colors.grey.shade800),
                ),
                TextButton.icon(
                  onPressed: hasContent ? clear : null,
                  icon: Icon(Icons.refresh, size: 18, color: hasContent ? Colors.grey.shade700 : Colors.grey.shade400),
                  label: Text('Unterschrift wiederholen', style: TextStyle(fontSize: 13, color: hasContent ? Colors.grey.shade700 : Colors.grey.shade400)),
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                ),
              ],
            ),
          ),
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
                    painter: _SignaturePainter(strokes: _strokes),
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

class _SignaturePainter extends CustomPainter {
  final List<_SigStroke> strokes;

  _SignaturePainter({required this.strokes});

  @override
  void paint(Canvas canvas, Size size) {
    for (final stroke in strokes) {
      if (stroke.points.length < 2) continue;
      final paint = Paint()
        ..color = _penColor
        ..strokeWidth = _penWidth
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
  bool shouldRepaint(covariant _SignaturePainter oldDelegate) => oldDelegate.strokes != strokes;
}
