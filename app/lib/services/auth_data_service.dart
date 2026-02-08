import 'package:cloud_firestore/cloud_firestore.dart';

/// Holt Rolle und Benutzerdaten aus Firestore – analog zu getAuthData in auth.js
class AuthDataService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  /// admin@rettbase.de = Superadmin für JEDEN Kunden (übergreifend)
  static bool _isGlobalSuperadmin(String email) {
    return email.trim().toLowerCase() == 'admin@rettbase.de';
  }

  /// Personalnummer 112 = Superadmin NUR bei Kunde Admin
  static bool _isAdminOnlySuperadmin(String companyId, String email) {
    if (companyId != 'admin') return false;
    return email.trim().toLowerCase() == '112@admin.rettbase.de';
  }

  Future<AuthData> getAuthData(String uid, String email, String companyId) async {
    if (uid.isEmpty || email.isEmpty) {
      return AuthData(role: 'guest', companyId: companyId, uid: null, displayName: null, vorname: null);
    }

    String? role;
    String? displayName;

    if (_isGlobalSuperadmin(email)) {
      String? dn;
      try {
        final byEmail = await _db.collection('kunden/admin/mitarbeiter').where('email', isEqualTo: 'admin@rettbase.de').limit(1).get();
        if (byEmail.docs.isNotEmpty) {
          final m = byEmail.docs.first.data();
          dn = _formatName(m['vorname'], m['nachname']);
        }
      } catch (_) {}
      return AuthData(role: 'superadmin', companyId: companyId, uid: uid, displayName: dn ?? 'Superadmin', vorname: null);
    }

    if (companyId == 'admin') {
      final adminUser = await _db.doc('kunden/admin/users/$uid').get();
      if (adminUser.exists) {
        final d = adminUser.data() ?? {};
        role = (d['role'] ?? 'user').toString().toLowerCase();
        displayName = _formatName(d['vorname'], d['nachname']) ?? d['displayName']?.toString();
        if (displayName == null || displayName!.isEmpty) {
          final mitarbeiterByUid = await _db.collection('kunden').doc('admin').collection('mitarbeiter').where('uid', isEqualTo: uid).limit(1).get();
          if (mitarbeiterByUid.docs.isNotEmpty) {
            final m = mitarbeiterByUid.docs.first.data();
            displayName = _formatName(m['vorname'], m['nachname']);
          } else {
            final mitarbeiterDoc = await _db.doc('kunden/admin/mitarbeiter/$uid').get();
            if (mitarbeiterDoc.exists) {
              final m = mitarbeiterDoc.data();
              displayName = _formatName(m?['vorname'], m?['nachname']);
            }
          }
        }
        final vorname = (d['vorname'] ?? '').toString().trim();
        return AuthData(role: role, companyId: 'admin', uid: uid, displayName: displayName, vorname: vorname.isNotEmpty ? vorname : null);
      }
      if (_isAdminOnlySuperadmin(companyId, email)) {
        String? dn;
        try {
          var byPn = await _db.collection('kunden/admin/mitarbeiter').where('personalnummer', isEqualTo: '112').limit(1).get();
          if (byPn.docs.isEmpty) {
            byPn = await _db.collection('kunden/admin/mitarbeiter').where('personalnummer', isEqualTo: 112).limit(1).get();
          }
          if (byPn.docs.isNotEmpty) {
            final m = byPn.docs.first.data();
            dn = _formatName(m['vorname'], m['nachname']);
          }
        } catch (_) {}
        return AuthData(role: 'superadmin', companyId: 'admin', uid: uid, displayName: dn ?? 'Superadmin', vorname: null);
      }
    }

    var mitarbeiter = await _db.doc('kunden/$companyId/mitarbeiter/$uid').get();
    if (mitarbeiter.exists) {
      final d = mitarbeiter.data();
      role = (d?['role'] ?? 'user').toString().toLowerCase();
      displayName = _formatName(d?['vorname'], d?['nachname']);
      final vorname = (d?['vorname'] ?? '').toString().trim();
      return AuthData(role: role, companyId: companyId, uid: uid, displayName: displayName, vorname: vorname.isNotEmpty ? vorname : null);
    }

    try {
      final byUid = await _db.collection('kunden').doc(companyId).collection('mitarbeiter').where('uid', isEqualTo: uid).limit(1).get();
      if (byUid.docs.isNotEmpty) {
        final d = byUid.docs.first.data();
        role = (d['role'] ?? 'user').toString().toLowerCase();
        displayName = _formatName(d['vorname'], d['nachname']);
        final v = (d['vorname'] ?? '').toString().trim();
        return AuthData(role: role, companyId: companyId, uid: uid, displayName: displayName, vorname: v.isNotEmpty ? v : null);
      }
    } catch (_) {}

    try {
      final byEmail = await _db.collection('kunden').doc(companyId).collection('mitarbeiter').where('email', isEqualTo: email).limit(1).get();
      if (byEmail.docs.isEmpty) {
        final byPseudo = await _db.collection('kunden').doc(companyId).collection('mitarbeiter').where('pseudoEmail', isEqualTo: email).limit(1).get();
        if (byPseudo.docs.isNotEmpty) {
          final d = byPseudo.docs.first.data();
          role = (d['role'] ?? 'user').toString().toLowerCase();
          displayName = _formatName(d['vorname'], d['nachname']);
          final v = (d['vorname'] ?? '').toString().trim();
          return AuthData(role: role, companyId: companyId, uid: uid, displayName: displayName, vorname: v.isNotEmpty ? v : null);
        }
      } else {
        final d = byEmail.docs.first.data();
        role = (d['role'] ?? 'user').toString().toLowerCase();
        displayName = _formatName(d['vorname'], d['nachname']);
        final v = (d['vorname'] ?? '').toString().trim();
        return AuthData(role: role, companyId: companyId, uid: uid, displayName: displayName, vorname: v.isNotEmpty ? v : null);
      }
    } catch (_) {}

    return AuthData(role: 'user', companyId: companyId, uid: uid, displayName: email.split('@').first, vorname: null);
  }

  String? _formatName(dynamic vorname, dynamic nachname) {
    final v = vorname?.toString().trim();
    final n = nachname?.toString().trim();
    if (v != null && n != null && v.isNotEmpty && n.isNotEmpty) return '$n, $v';
    if (n != null && n.isNotEmpty) return n;
    if (v != null && v.isNotEmpty) return v;
    return null;
  }
}

class AuthData {
  final String role;
  final String companyId;
  final String? uid;
  final String? displayName;
  final String? vorname;

  AuthData({required this.role, required this.companyId, this.uid, this.displayName, this.vorname});
}
