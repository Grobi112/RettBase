import 'package:cloud_firestore/cloud_firestore.dart';

/// Bereiche für Kunden – definieren, welches Menü angezeigt wird
abstract class KundenBereich {
  static const rettungsdienst = 'rettungsdienst';
  static const notfallseelsorge = 'notfallseelsorge';
  static const schulsanitaetsdienst = 'schulsanitaetsdienst';
  static const sanitaetsdienst = 'sanitaetsdienst';
  static const admin = 'admin';
  static const List<String> ids = [rettungsdienst, notfallseelsorge, schulsanitaetsdienst, sanitaetsdienst, admin];
  static const Map<String, String> labels = {
    rettungsdienst: 'Rettungsdienst',
    notfallseelsorge: 'Notfallseelsorge',
    schulsanitaetsdienst: 'Schulsanitätsdienst',
    sanitaetsdienst: 'Sanitätsdienst',
    admin: 'Admin',
  };
}

/// Kunde (Firma) aus Firestore: kunden/{id}
/// Verwendet Kunden-ID (nicht Subdomain) – Firestore-Feld 'subdomain' bleibt für Abwärtskompatibilität.
class Kunde {
  final String id;
  final String name;
  final String? address;
  final String? zipCity;
  final String? phone;
  final String? email;
  /// Kunden-ID (eindeutige Kennung, z.B. für Login-URL: kundenId.rettbase.de)
  final String kundenId;
  /// Bereich: definiert, welches Menü der Kunde sieht (rettungsdienst, notfallseelsorge, schulsanitaetsdienst, sanitaetsdienst)
  final String? bereich;
  final String status; // active, inactive, suspended
  final DateTime? createdAt;
  final String? creatorUid;

  const Kunde({
    required this.id,
    required this.name,
    this.address,
    this.zipCity,
    this.phone,
    this.email,
    required this.kundenId,
    this.bereich,
    this.status = 'active',
    this.createdAt,
    this.creatorUid,
  });

  factory Kunde.fromFirestore(String id, Map<String, dynamic> data) {
    DateTime? createdAt;
    final cv = data['createdAt'];
    if (cv is Timestamp) createdAt = cv.toDate();
    else if (cv is DateTime) createdAt = cv;
    else if (cv is Map && (cv['_seconds'] != null || cv['seconds'] != null)) {
      final s = cv['_seconds'] ?? cv['seconds'] ?? 0;
      final n = cv['_nanoseconds'] ?? cv['nanoseconds'] ?? 0;
      createdAt = DateTime.fromMillisecondsSinceEpoch((s as num).toInt() * 1000 + (n as num).toInt() ~/ 1000000);
    } else if (cv is String) {
      createdAt = DateTime.tryParse(cv);
    }
    // Firestore: 'subdomain' oder 'kundenId' (Abwärtskompatibilität)
    final kid = (data['kundenId'] ?? data['subdomain'] ?? id).toString();

    return Kunde(
      id: id,
      name: (data['name'] ?? id).toString(),
      address: data['address']?.toString(),
      zipCity: data['zipCity']?.toString(),
      phone: data['phone']?.toString(),
      email: data['email']?.toString(),
      kundenId: kid,
      bereich: data['bereich']?.toString(),
      status: (data['status'] ?? 'active').toString(),
      createdAt: createdAt,
      creatorUid: data['creatorUid']?.toString(),
    );
  }

  Map<String, dynamic> toFirestore() => {
        'name': name,
        'address': address,
        'zipCity': zipCity,
        'phone': phone,
        'email': email,
        'subdomain': kundenId, // Firestore behält 'subdomain' für Abwärtskompatibilität
        'bereich': bereich,
        'status': status,
      };

  String get statusLabel {
    switch (status) {
      case 'inactive':
        return 'Inaktiv';
      case 'suspended':
        return 'Gesperrt';
      default:
        return 'Aktiv';
    }
  }
}
