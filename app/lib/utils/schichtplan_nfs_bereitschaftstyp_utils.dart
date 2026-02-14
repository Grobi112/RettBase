import 'package:flutter/material.dart';
import '../services/schichtanmeldung_service.dart';
import '../theme/app_theme.dart';

/// Zentrale Helper für Bereitschaftstypen S1, S2, B:
/// - Erlaubte Reihenfolge: S1, S2, B
/// - Farbliche Kennzeichnung für alle Dropdowns
class SchichtplanNfsBereitschaftstypUtils {
  static const _reihenfolge = ['S1', 'S2', 'B'];

  /// Farben für S1 (grün), S2 (amber), B (lila)
  static const _farben = {
    's1': Color(0xFF10B981),
    's2': Color(0xFFF59E0B),
    'b': Color(0xFF8B5CF6),
  };

  /// Filtert auf S1, S2, B und sortiert in dieser Reihenfolge
  static List<BereitschaftsTyp> filterAndSortS1S2B(
    List<BereitschaftsTyp> typen,
  ) {
    final erlaubt = typen.where((t) {
      final n = t.name.trim().toLowerCase();
      return n == 's1' || n == 's2' || n == 'b';
    }).toList();
    erlaubt.sort((a, b) {
      final na = a.name.trim().toLowerCase();
      final nb = b.name.trim().toLowerCase();
      final ia = _reihenfolge.indexWhere(
        (x) => x.toLowerCase() == na,
      );
      final ib = _reihenfolge.indexWhere(
        (x) => x.toLowerCase() == nb,
      );
      return ia.compareTo(ib);
    });
    return erlaubt;
  }

  /// Farbe für Typ (anhand Name oder Firestore-Farbe)
  static Color colorForTyp(
    BereitschaftsTyp typ, {
    List<BereitschaftsTyp>? alleTypen,
  }) {
    if (typ.color != null) return Color(typ.color!);
    final n = typ.name.trim().toLowerCase();
    return _farben[n] ?? AppTheme.textMuted;
  }

  /// Farbe für Typ-Id (z.B. in Dropdowns)
  static Color colorForTypId(String typId, List<BereitschaftsTyp> typen) {
    final t = typen.where((x) => x.id == typId).firstOrNull;
    if (t == null) return AppTheme.textMuted;
    return colorForTyp(t);
  }
}
