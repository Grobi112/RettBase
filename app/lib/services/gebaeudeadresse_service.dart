import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

/// Statisches PLZ-Mapping als Offline-Fallback (wenn API nicht erreichbar).
const _ortToPlzFallback = <String, String>{
  'Bergkamen': '59192',
  'Bönen': '59199',
  'Fröndenberg/Ruhr': '58730',
  'Holzwickede': '59439',
  'Kamen': '59174',
  'Lünen': '44532',
  'Schwerte': '58239',
  'Selm': '59379',
  'Unna': '59423',
  'Werne': '59368',
};

/// Eintrag: Straße + Ort (+ PLZ)
class GebaeudeAdresseVorschlag {
  final String strasse;
  final String ort;
  final String plz;

  GebaeudeAdresseVorschlag({
    required this.strasse,
    required this.ort,
    required this.plz,
  });

  String get displayLabel => plz.isNotEmpty ? '$strasse, $plz $ort' : '$strasse, $ort';
}

/// Lädt gebaeudeadresse.csv und bietet Straßen-Suche mit Ort/PLZ-Vorschlägen.
/// PLZ wird automatisch über die OpenPLZ-API (openplzapi.org) ermittelt.
class GebaeudeAdresseService {
  List<GebaeudeAdresseVorschlag>? _cache;
  bool _loading = false;
  final _plzCache = <String, String>{};

  /// Holt PLZ für einen Ort über die OpenPLZ-API (oder Fallback/ Cache).
  Future<String> _plzFuerOrt(String ort) async {
    if (ort.isEmpty) return '';
    final cached = _plzCache[ort];
    if (cached != null) return cached;
    final fallback = _ortToPlzFallback[ort];
    if (fallback != null) {
      _plzCache[ort] = fallback;
      return fallback;
    }
    try {
      final uri = Uri.https(
        'openplzapi.org',
        '/de/Localities',
        {'name': ort},
      );
      final resp = await http.get(uri).timeout(const Duration(seconds: 5));
      if (resp.statusCode != 200) return '';
      final list = jsonDecode(resp.body) as List<dynamic>?;
      if (list == null || list.isEmpty) return '';
      for (final e in list) {
        if (e is Map<String, dynamic>) {
          final name = (e['name'] as String? ?? '').trim();
          final plz = (e['postalCode'] as String? ?? '').trim();
          if (name.toLowerCase() == ort.toLowerCase() && plz.isNotEmpty) {
            _plzCache[ort] = plz;
            return plz;
          }
        }
      }
      final first = list.first as Map<String, dynamic>?;
      final plz = (first?['postalCode'] as String? ?? '').trim();
      if (plz.isNotEmpty) {
        _plzCache[ort] = plz;
        return plz;
      }
    } catch (_) {}
    return '';
  }

  /// Eindeutige (Straße, Ort)-Kombinationen aus der CSV.
  Future<List<GebaeudeAdresseVorschlag>> loadCache() async {
    if (_cache != null) return _cache!;
    if (_loading) {
      while (_loading) {
        await Future<void>.delayed(const Duration(milliseconds: 100));
        if (_cache != null) return _cache!;
      }
    }
    _loading = true;
    try {
      final csv = await rootBundle.loadString('gebaeudeadresse.csv');
      final lines = csv.split('\n');
      final seen = <String>{};
      final ortToPlzPending = <String>{};
      final list = <GebaeudeAdresseVorschlag>[];

      for (var i = 1; i < lines.length; i++) {
        final line = lines[i];
        if (line.trim().isEmpty) continue;
        final parts = line.split(';');
        if (parts.length < 2) continue;
        final ort = parts[0].trim();
        final strasse = parts[1].trim();
        if (ort.isEmpty || strasse.isEmpty || ort == 'ORT') continue;

        final key = '$strasse|$ort';
        if (seen.contains(key)) continue;
        seen.add(key);

        var plz = _plzCache[ort] ?? _ortToPlzFallback[ort] ?? '';
        if (plz.isEmpty) ortToPlzPending.add(ort);
        list.add(GebaeudeAdresseVorschlag(strasse: strasse, ort: ort, plz: plz));
      }

      final ortList = ortToPlzPending.toList();
      final plzResults = await Future.wait(
        ortList.map((ort) => _plzFuerOrt(ort)),
      );
      final plzByOrt = <String, String>{};
      for (var i = 0; i < ortList.length; i++) {
        plzByOrt[ortList[i]] = plzResults[i];
      }
      for (var i = 0; i < list.length; i++) {
        final ort = list[i].ort;
        if (plzByOrt.containsKey(ort) && list[i].plz.isEmpty) {
          list[i] = GebaeudeAdresseVorschlag(
            strasse: list[i].strasse,
            ort: ort,
            plz: plzByOrt[ort]!,
          );
        }
      }

      list.sort((a, b) {
        final c = a.strasse.toLowerCase().compareTo(b.strasse.toLowerCase());
        if (c != 0) return c;
        return a.ort.compareTo(b.ort);
      });

      _cache = list;
      return list;
    } finally {
      _loading = false;
    }
  }

  /// Sucht Straßen, die mit [query] beginnen (case-insensitive).
  Future<List<GebaeudeAdresseVorschlag>> sucheStrasse(
    String query, {
    int limit = 20,
  }) async {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return [];

    final all = await loadCache();
    final result = <GebaeudeAdresseVorschlag>[];
    for (final e in all) {
      if (e.strasse.toLowerCase().startsWith(q)) {
        result.add(e);
        if (result.length >= limit) break;
      }
    }
    return result;
  }

  /// Sucht Straßen, die [query] enthalten (case-insensitive).
  Future<List<GebaeudeAdresseVorschlag>> sucheStrasseContains(
    String query, {
    int limit = 20,
  }) async {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return [];

    final all = await loadCache();
    final result = <GebaeudeAdresseVorschlag>[];
    for (final e in all) {
      if (e.strasse.toLowerCase().contains(q)) {
        result.add(e);
        if (result.length >= limit) break;
      }
    }
    return result;
  }
}

