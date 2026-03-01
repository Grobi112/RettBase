import 'package:dlibphonenumber/dlibphonenumber.dart';

/// Formatiert eine Telefonnummer für 2-Zeilen-Anzeige (Vorwahl / Durchwahl).
/// Nutzt libphonenumber für korrekte deutsche Vorwahl-Längen (z.B. 02378 Menden, nicht 0237).
/// Bei Fehlern oder nicht-parsbaren Nummern: Original zurück.
String formatPhoneForDisplay(String raw) {
  if (raw.trim().isEmpty) return raw;
  try {
    final phoneUtil = PhoneNumberUtil.instance;
    final region = raw.trim().startsWith('+') ? '' : 'DE';
    final parsed = phoneUtil.parse(raw, region);
    if (!phoneUtil.isPossibleNumber(parsed)) return raw;
    final national = phoneUtil.format(parsed, PhoneNumberFormat.national);
    final trimmed = national.trim();
    final spaceIdx = trimmed.indexOf(' ');
    if (spaceIdx > 0 && spaceIdx < trimmed.length - 1) {
      return '${trimmed.substring(0, spaceIdx).trim()}\n${trimmed.substring(spaceIdx + 1).trim()}';
    }
    return trimmed;
  } catch (_) {
    return raw;
  }
}

/// Formatiert eine Telefonnummer einzeilig (z.B. für Querformat).
/// Nutzt libphonenumber wie [formatPhoneForDisplay], aber ohne Zeilenumbruch.
String formatPhoneForDisplaySingleLine(String raw) {
  if (raw.trim().isEmpty) return raw;
  try {
    final phoneUtil = PhoneNumberUtil.instance;
    final region = raw.trim().startsWith('+') ? '' : 'DE';
    final parsed = phoneUtil.parse(raw, region);
    if (!phoneUtil.isPossibleNumber(parsed)) return raw;
    final national = phoneUtil.format(parsed, PhoneNumberFormat.national);
    return national.trim();
  } catch (_) {
    return raw;
  }
}
