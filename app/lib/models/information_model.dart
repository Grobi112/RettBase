import 'package:cloud_firestore/cloud_firestore.dart';

/// Eine Information – Eintrag im Informationssystem
/// Firestore: kunden/{companyId}/informationen
class Information {
  final String id;
  final DateTime datum;
  final String uhrzeit; // HH:mm
  final String userId;
  final String userDisplayName;
  final String typ; // 'informationen' | 'verkehrslage' – Container, in dem die Info erscheint
  final String kategorie;
  final String laufzeit; // Aufbewahrungsdauer: 1_woche, 2_wochen, 3_wochen, 1_monat, 3_monate, 6_monate, 12_monate, bis_auf_widerruf
  final String prioritaet; // 'sehr_wichtig' | 'normal' (optional, Rückwärtskompatibilität)
  final String betreff;
  final String text;
  final DateTime createdAt;

  Information({
    required this.id,
    required this.datum,
    required this.uhrzeit,
    required this.userId,
    required this.userDisplayName,
    required this.typ,
    required this.kategorie,
    this.laufzeit = '1_monat',
    this.prioritaet = 'normal',
    required this.betreff,
    required this.text,
    required this.createdAt,
  });

  bool get isSehrWichtig => prioritaet == 'sehr_wichtig';

  /// Ablaufdatum ab Erstellungsdatum gemäß laufzeit
  DateTime? get expiryDate {
    if (laufzeit == 'bis_auf_widerruf') return null;
    final days = switch (laufzeit) {
      '1_woche' => 7,
      '2_wochen' => 14,
      '3_wochen' => 21,
      '1_monat' => 30,
      '3_monate' => 90,
      '6_monate' => 180,
      '12_monate' => 365,
      _ => null,
    };
    if (days == null) return null;
    return DateTime(createdAt.year, createdAt.month, createdAt.day).add(Duration(days: days));
  }

  /// true wenn die Frist abgelaufen ist (gilt nicht für bis_auf_widerruf)
  bool get isExpired {
    final exp = expiryDate;
    if (exp == null) return false;
    return DateTime.now().isAfter(exp);
  }

  factory Information.fromFirestore(String id, Map<String, dynamic> d) {
    DateTime datum = DateTime.now();
    final dVal = d['datum'];
    if (dVal is Timestamp) {
      datum = dVal.toDate();
    } else if (dVal is String) {
      datum = DateTime.tryParse(dVal) ?? datum;
    }

    DateTime createdAt = DateTime.now();
    final cVal = d['createdAt'];
    if (cVal is Timestamp) {
      createdAt = cVal.toDate();
    } else if (cVal is String) {
      createdAt = DateTime.tryParse(cVal) ?? createdAt;
    }

    return Information(
      id: id,
      datum: datum,
      uhrzeit: d['uhrzeit']?.toString() ?? '',
      userId: d['userId']?.toString() ?? '',
      userDisplayName: d['userDisplayName']?.toString() ?? '',
      typ: d['typ']?.toString() ?? 'informationen',
      kategorie: d['kategorie']?.toString() ?? '',
      laufzeit: d['laufzeit']?.toString() ?? '1_monat',
      prioritaet: d['prioritaet']?.toString() ?? 'normal',
      betreff: d['betreff']?.toString() ?? '',
      text: d['text']?.toString() ?? '',
      createdAt: createdAt,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'datum': Timestamp.fromDate(datum),
      'uhrzeit': uhrzeit,
      'userId': userId,
      'userDisplayName': userDisplayName,
      'typ': typ,
      'kategorie': kategorie,
      'laufzeit': laufzeit,
      'prioritaet': prioritaet,
      'betreff': betreff,
      'text': text,
      'createdAt': Timestamp.fromDate(createdAt),
    };
  }
}
