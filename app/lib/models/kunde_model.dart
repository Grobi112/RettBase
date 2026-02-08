import 'package:cloud_firestore/cloud_firestore.dart';

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
    this.status = 'active',
    this.createdAt,
    this.creatorUid,
  });

  factory Kunde.fromFirestore(String id, Map<String, dynamic> data) {
    DateTime? createdAt;
    final cv = data['createdAt'];
    if (cv is Timestamp) createdAt = cv.toDate();
    else if (cv is DateTime) createdAt = cv;
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
