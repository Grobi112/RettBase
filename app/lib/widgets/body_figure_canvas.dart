import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter/material.dart';

class _Stroke {
  final List<Offset> points;
  final Color color;
  final double strokeWidth;

  _Stroke({required this.points, required this.color, required this.strokeWidth});
}

/// Zeichenbares Körperfigur-Widget – Vorder- und Rückansicht aus Nutzer-Vorlage
class BodyFigureCanvas extends StatefulWidget {
  final double height;
  final ValueChanged<List<List<Offset>>>? onFrontStrokesChanged;
  final ValueChanged<List<List<Offset>>>? onBackStrokesChanged;
  final List<List<Offset>>? initialFrontStrokes;
  final List<List<Offset>>? initialBackStrokes;

  const BodyFigureCanvas({
    super.key,
    this.height = 320,
    this.onFrontStrokesChanged,
    this.onBackStrokesChanged,
    this.initialFrontStrokes,
    this.initialBackStrokes,
  });

  @override
  State<BodyFigureCanvas> createState() => BodyFigureCanvasState();
}

class BodyFigureCanvasState extends State<BodyFigureCanvas> {
  final List<_Stroke> _frontStrokes = [];
  final List<_Stroke> _backStrokes = [];
  final GlobalKey _repaintKey = GlobalKey();
  bool _drawingOnFront = true;
  double _canvasWidth = 400;
  static const _penColor = Colors.red;
  static const _strokeWidth = 4.0;
  ui.Image? _templateImage;

  @override
  void initState() {
    super.initState();
    _loadTemplateImage();
    if (widget.initialFrontStrokes != null) {
      for (final pts in widget.initialFrontStrokes!) {
        if (pts.length >= 2) _frontStrokes.add(_Stroke(points: List.from(pts), color: _penColor, strokeWidth: _strokeWidth));
      }
    }
    if (widget.initialBackStrokes != null) {
      for (final pts in widget.initialBackStrokes!) {
        if (pts.length >= 2) _backStrokes.add(_Stroke(points: List.from(pts), color: _penColor, strokeWidth: _strokeWidth));
      }
    }
  }

  Future<void> _loadTemplateImage() async {
    try {
      final data = await rootBundle.load('img/koerperfigur_vorlage.png');
      final codec = await ui.instantiateImageCodec(data.buffer.asUint8List());
      final frame = await codec.getNextFrame();
      if (mounted) setState(() => _templateImage = frame.image);
    } catch (_) {
      if (mounted) setState(() {});
    }
  }

  void _clear() {
    setState(() {
      _frontStrokes.clear();
      _backStrokes.clear();
      widget.onFrontStrokesChanged?.call([]);
      widget.onBackStrokesChanged?.call([]);
    });
  }

  void _notifyChanges() {
    widget.onFrontStrokesChanged?.call(_frontStrokes.map((s) => List<Offset>.from(s.points)).toList());
    widget.onBackStrokesChanged?.call(_backStrokes.map((s) => List<Offset>.from(s.points)).toList());
  }

  void _onPointerDown(PointerDownEvent e) {
    final local = e.localPosition;
    final w = (_canvasWidth > 0 ? _canvasWidth : 400) / 2;
    final stroke = _Stroke(points: [local], color: _penColor, strokeWidth: _strokeWidth);
    if (local.dx < w) {
      _drawingOnFront = true;
      _frontStrokes.add(stroke);
    } else {
      _drawingOnFront = false;
      _backStrokes.add(stroke);
    }
    setState(() {});
  }

  void _onPointerMove(PointerMoveEvent e) {
    final local = e.localPosition;
    if (_drawingOnFront && _frontStrokes.isNotEmpty) {
      _frontStrokes.last.points.add(local);
      setState(() {});
    } else if (!_drawingOnFront && _backStrokes.isNotEmpty) {
      _backStrokes.last.points.add(local);
      setState(() {});
    }
  }

  void _onPointerUp(PointerUpEvent e) {
    _notifyChanges();
  }

  void _onPointerCancel(PointerCancelEvent e) {}

  Future<Uint8List?> captureImage() async {
    final boundary = _repaintKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
    if (boundary == null) return null;
    final image = await boundary.toImage(pixelRatio: 2.0);
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    return byteData?.buffer.asUint8List();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFFAFAFA),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey.shade400),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.grey.shade200,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
            ),
            child: Row(
              children: [
                Text('Verletzte Stelle markieren (mit Finger zeichnen):', style: TextStyle(fontSize: 13, color: Colors.grey.shade700)),
                const Spacer(),
                if (_frontStrokes.isNotEmpty || _backStrokes.isNotEmpty)
                  TextButton.icon(
                    onPressed: _clear,
                    icon: const Icon(Icons.delete_outline, size: 18),
                    label: const Text('Löschen'),
                  ),
              ],
            ),
          ),
          LayoutBuilder(
            builder: (context, constraints) {
              final availableW = constraints.maxWidth.isFinite ? constraints.maxWidth : widget.height;
              final availableH = constraints.maxHeight.isFinite ? constraints.maxHeight : widget.height;
              // Vorlage 413x413 → quadratisch. Canvas quadratisch = Figuren behalten Proportion.
              final side = [availableW, availableH, widget.height]
                  .where((v) => v.isFinite && v > 0)
                  .fold<double>(widget.height, (a, b) => a < b ? a : b);
              return SizedBox(
                width: side,
                height: side,
                child: LayoutBuilder(
                  builder: (context, innerConstraints) {
                    _canvasWidth = innerConstraints.maxWidth;
                    final size = Size(innerConstraints.maxWidth, innerConstraints.maxHeight);
                    return Listener(
                  behavior: HitTestBehavior.opaque,
                  onPointerDown: _onPointerDown,
                  onPointerMove: _onPointerMove,
                  onPointerUp: _onPointerUp,
                  onPointerCancel: _onPointerCancel,
                  child: RepaintBoundary(
                    key: _repaintKey,
                    child: CustomPaint(
                      size: size,
                      painter: _BodyFigureWithStrokesPainter(
                        templateImage: _templateImage,
                        frontStrokes: _frontStrokes,
                        backStrokes: _backStrokes,
                      ),
                    ),
                  ),
                );
              },
            ),
          );
        },
      ),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                Text('Vorderseite', style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                Text('Rückseite', style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _BodyFigureWithStrokesPainter extends CustomPainter {
  final ui.Image? templateImage;
  final List<_Stroke> frontStrokes;
  final List<_Stroke> backStrokes;

  _BodyFigureWithStrokesPainter({
    required this.templateImage,
    required this.frontStrokes,
    required this.backStrokes,
  });

  void _drawBodyFromTemplate(Canvas canvas, Size size, bool isFront) {
    if (templateImage == null) {
      _drawBodyFallback(canvas, size, isFront);
      return;
    }
    final img = templateImage!;
    final iw = img.width.toDouble();
    final ih = img.height.toDouble();
    final halfW = iw / 2;
    final srcRect = isFront
        ? Rect.fromLTWH(halfW, 0, halfW, ih)
        : Rect.fromLTWH(0, 0, halfW, ih);
    final srcAspect = halfW / ih;
    final dstAspect = size.width / size.height;
    // Seitenverhältnis bewahren – Figur nicht verzerren
    final Rect dstRect;
    if (srcAspect > dstAspect) {
      final h = size.width / srcAspect;
      final top = (size.height - h) / 2;
      dstRect = Rect.fromLTWH(0, top, size.width, h);
    } else {
      final w = size.height * srcAspect;
      final left = (size.width - w) / 2;
      dstRect = Rect.fromLTWH(left, 0, w, size.height);
    }
    canvas.drawImageRect(img, srcRect, dstRect, Paint()..filterQuality = FilterQuality.medium);
  }

  void _drawBodyFallback(Canvas canvas, Size size, bool isFront) {
    final paint = Paint()
      ..color = Colors.grey.shade400
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    final cx = size.width * 0.5;
    final headRadius = size.width * 0.12;
    final shoulderWidth = size.width * 0.35;
    final bodyTop = headRadius * 2.2;
    final bodyBottom = size.height * 0.55;
    canvas.drawCircle(Offset(cx, headRadius), headRadius, paint);
    final bodyPath = Path();
    bodyPath.moveTo(cx - shoulderWidth / 2, bodyTop);
    bodyPath.lineTo(cx + shoulderWidth / 2, bodyTop);
    bodyPath.lineTo(cx + shoulderWidth / 3, bodyBottom);
    bodyPath.lineTo(cx + 8, bodyBottom);
    bodyPath.lineTo(cx, size.height - 4);
    bodyPath.lineTo(cx - 8, bodyBottom);
    bodyPath.lineTo(cx - shoulderWidth / 3, bodyBottom);
    bodyPath.close();
    canvas.drawPath(bodyPath, paint);
    final armLength = size.width * 0.25;
    if (isFront) {
      canvas.drawLine(Offset(cx - shoulderWidth / 2 - 4, bodyTop + 15), Offset(cx - shoulderWidth / 2 - 4 - armLength, bodyTop + 40), paint);
      canvas.drawLine(Offset(cx + shoulderWidth / 2 + 4, bodyTop + 15), Offset(cx + shoulderWidth / 2 + 4 + armLength, bodyTop + 40), paint);
    } else {
      canvas.drawLine(Offset(cx - shoulderWidth / 2, bodyTop + 15), Offset(cx - shoulderWidth / 2 - armLength, bodyTop + 40), paint);
      canvas.drawLine(Offset(cx + shoulderWidth / 2, bodyTop + 15), Offset(cx + shoulderWidth / 2 + armLength, bodyTop + 40), paint);
    }
    canvas.drawLine(Offset(cx - 12, bodyBottom), Offset(cx - 15, size.height - 8), paint);
    canvas.drawLine(Offset(cx + 12, bodyBottom), Offset(cx + 15, size.height - 8), paint);
  }

  void _drawStrokes(Canvas canvas, Size halfSize, List<_Stroke> strokes, double offsetX) {
    for (final stroke in strokes) {
      if (stroke.points.length < 2) continue;
      final paint = Paint()
        ..color = stroke.color
        ..strokeWidth = stroke.strokeWidth
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..style = PaintingStyle.stroke
        ..isAntiAlias = true;
      final path = Path();
      path.moveTo(stroke.points.first.dx - offsetX, stroke.points.first.dy);
      for (var i = 1; i < stroke.points.length; i++) {
        path.lineTo(stroke.points[i].dx - offsetX, stroke.points[i].dy);
      }
      canvas.drawPath(path, paint);
    }
  }

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width / 2;
    final h = size.height;

    canvas.save();
    canvas.clipRect(Rect.fromLTWH(0, 0, w, h));
    _drawBodyFromTemplate(canvas, Size(w, h), true);
    _drawStrokes(canvas, Size(w, h), frontStrokes, 0);
    canvas.restore();

    canvas.save();
    canvas.translate(w, 0);
    canvas.clipRect(Rect.fromLTWH(0, 0, w, h));
    _drawBodyFromTemplate(canvas, Size(w, h), false);
    _drawStrokes(canvas, Size(w, h), backStrokes, w);
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _BodyFigureWithStrokesPainter old) =>
      old.templateImage != templateImage || old.frontStrokes != frontStrokes || old.backStrokes != backStrokes;
}
