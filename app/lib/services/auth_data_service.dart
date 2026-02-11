import 'package:cloud_firestore/cloud_firestore.dart';

/// Holt Rolle und Benutzerdaten aus Firestore – analog zu getAuthData in auth.js
class AuthDataService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  /// admin@rettbase.de / admin@rettbase = Superadmin für JEDEN Kunden (übergreifend)
  static bool _isGlobalSuperadmin(String email) {
    final e = email.trim().toLowerCase();
    return e == 'admin@rettbase.de' ||
        e == 'admin@rettbase' ||
        (e.startsWith('admin@') && e.contains('rettbase'));
  }

  /// Personalnummer 112 = Superadmin NUR bei Kunde Admin
  static bool _isAdminOnlySuperadmin(String companyId, String email) {
    if (companyId.trim().toLowerCase() != 'admin') return false;
    final e = email.trim().toLowerCase();
    return e == '112@admin.rettbase.de' ||
        e.startsWith('112@admin') ||
        (e.startsWith('112@') && e.contains('admin'));
  }

  Future<AuthData> getAuthData(String uid, String email, String companyId) async {
    if (uid.isEmpty || email.isEmpty) {
      return AuthData(role: 'guest', companyId: companyId, uid: null, displayName: null, vorname: null);
    }

    final cid = companyId.trim().toLowerCase();
    String? role;
    String? displayName;

    if (_isGlobalSuperadmin(email)) {
      String? dn;
      String? vorname;
      try {
        final e = email.trim().toLowerCase();
        var byEmail = await _db.collection('kunden/admin/mitarbeiter')
            .where('email', isEqualTo: e)
            .limit(1)
            .get();
        if (byEmail.docs.isEmpty && email.trim() != e) {
          byEmail = await _db.collection('kunden/admin/mitarbeiter')
              .where('email', isEqualTo: email.trim())
              .limit(1)
              .get();
        }
        if (byEmail.docs.isEmpty) {
          final fallback = await _db.collection('kunden/admin/mitarbeiter')
              .where('email', isEqualTo: 'admin@rettbase.de')
              .limit(1)
              .get();
          if (fallback.docs.isNotEmpty) {
            byEmail = fallback;
          } else {
            final alt = await _db.collection('kunden/admin/mitarbeiter')
                .where('email', isEqualTo: 'Admin@rettbase.de')
                .limit(1)
                .get();
            if (alt.docs.isNotEmpty) byEmail = alt;
          }
        }
        if (byEmail.docs.isNotEmpty) {
          final m = byEmail.docs.first.data();
          dn = _formatName(m['vorname'], m['nachname']);
          vorname = (m['vorname'] ?? '').toString().trim();
        }
        if (dn == null || dn.isEmpty) {
          final userDoc = await _db.doc('kunden/admin/users/$uid').get();
          if (userDoc.exists) {
            final d = userDoc.data() ?? {};
            dn = _formatName(d['vorname'], d['nachname']) ?? d['displayName']?.toString();
            if (vorname == null || vorname.isEmpty) {
              vorname = (d['vorname'] ?? '').toString().trim();
            }
          }
        }
      } catch (_) {}
      final fallbackName = email.contains('@') ? email.split('@').first : 'Superadmin';
      return AuthData(role: 'superadmin', companyId: cid, uid: uid, displayName: dn ?? fallbackName, vorname: vorname?.isNotEmpty == true ? vorname : null);
    }

    if (cid == 'admin') {
      if (_isAdminOnlySuperadmin(cid, email)) {
        String? dn;
        String? vorname;
        try {
          var byPn = await _db.collection('kunden/admin/mitarbeiter').where('personalnummer', isEqualTo: '112').limit(1).get();
          if (byPn.docs.isEmpty) {
            byPn = await _db.collection('kunden/admin/mitarbeiter').where('personalnummer', isEqualTo: 112).limit(1).get();
          }
          if (byPn.docs.isNotEmpty) {
            final m = byPn.docs.first.data();
            dn = _formatName(m['vorname'], m['nachname']);
            vorname = (m['vorname'] ?? '').toString().trim();
          }
          if (dn == null || dn.isEmpty) {
            final adminUser = await _db.doc('kunden/admin/users/$uid').get();
            if (adminUser.exists) {
              final d = adminUser.data() ?? {};
              dn = _formatName(d['vorname'], d['nachname']) ?? d['displayName']?.toString();
              if (vorname == null || vorname.isEmpty) {
                vorname = (d['vorname'] ?? '').toString().trim();
              }
            }
          }
        } catch (_) {}
        final fallbackName = email.contains('@') ? email.split('@').first : 'Superadmin';
        return AuthData(role: 'superadmin', companyId: cid, uid: uid, displayName: dn ?? fallbackName, vorname: vorname?.isNotEmpty == true ? vorname : null);
      }
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
        final dn = displayName ?? (email.contains('@') ? email.split('@').first : null);
        return AuthData(role: role, companyId: cid, uid: uid, displayName: dn ?? 'Benutzer', vorname: vorname.isNotEmpty ? vorname : null);
      }
    }

    var mitarbeiter = await _db.doc('kunden/$cid/mitarbeiter/$uid').get();
    if (mitarbeiter.exists) {
      final d = mitarbeiter.data();
      role = (d?['role'] ?? 'user').toString().toLowerCase();
      displayName = _formatName(d?['vorname'], d?['nachname']);
      final vorname = (d?['vorname'] ?? '').toString().trim();
      return AuthData(role: role, companyId: cid, uid: uid, displayName: displayName, vorname: vorname.isNotEmpty ? vorname : null);
    }

    try {
      final byUid = await _db.collection('kunden').doc(cid).collection('mitarbeiter').where('uid', isEqualTo: uid).limit(1).get();
      if (byUid.docs.isNotEmpty) {
        final d = byUid.docs.first.data();
        role = (d['role'] ?? 'user').toString().toLowerCase();
        displayName = _formatName(d['vorname'], d['nachname']);
        final v = (d['vorname'] ?? '').toString().trim();
        return AuthData(role: role, companyId: cid, uid: uid, displayName: displayName, vorname: v.isNotEmpty ? v : null);
      }
    } catch (_) {}

    try {
      final byEmail = await _db.collection('kunden').doc(cid).collection('mitarbeiter').where('email', isEqualTo: email).limit(1).get();
      if (byEmail.docs.isEmpty) {
        final byPseudo = await _db.collection('kunden').doc(cid).collection('mitarbeiter').where('pseudoEmail', isEqualTo: email).limit(1).get();
        if (byPseudo.docs.isNotEmpty) {
          final d = byPseudo.docs.first.data();
          role = (d['role'] ?? 'user').toString().toLowerCase();
          displayName = _formatName(d['vorname'], d['nachname']);
          final v = (d['vorname'] ?? '').toString().trim();
          return AuthData(role: role, companyId: cid, uid: uid, displayName: displayName, vorname: v.isNotEmpty ? v : null);
        }
      } else {
        final d = byEmail.docs.first.data();
        role = (d['role'] ?? 'user').toString().toLowerCase();
        displayName = _formatName(d['vorname'], d['nachname']);
        final v = (d['vorname'] ?? '').toString().trim();
        return AuthData(role: role, companyId: cid, uid: uid, displayName: displayName, vorname: v.isNotEmpty ? v : null);
      }
    } catch (_) {}

    final nameFromEmail = email.contains('@') ? email.split('@').first : 'Benutzer';
    return AuthData(role: 'user', companyId: cid, uid: uid, displayName: nameFromEmail.isNotEmpty ? nameFromEmail : 'Benutzer', vorname: null);
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
