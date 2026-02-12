import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_signature_pad/flutter_signature_pad.dart';

/// Unterschriftenfeld – nutzt flutter_signature_pad (Canvas-basiert, funktioniert auf Web mit Maus/Touch/Stift)
class SignaturePad extends StatefulWidget {
  final double height;

  const SignaturePad({super.key, this.height = 120});

  @override
  State<SignaturePad> createState() => SignaturePadState();
}

class SignaturePadState extends State<SignaturePad> {
  final GlobalKey<SignatureState> _signKey = GlobalKey<SignatureState>();

  void clear() {
    _signKey.currentState?.clear();
    setState(() {});
  }

  bool get hasContent => _signKey.currentState?.hasPoints ?? false;

  Future<Uint8List?> captureImage() async {
    final sign = _signKey.currentState;
    if (sign == null || !sign.hasPoints) return null;
    try {
      final image = await sign.getData();
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      return byteData?.buffer.asUint8List();
    } catch (_) {
      return null;
    }
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
            child: Signature(
              key: _signKey,
              color: Colors.black,
              strokeWidth: 2.5,
              backgroundPainter: null,
            ),
          ),
        ],
      ),
    );
  }
}
