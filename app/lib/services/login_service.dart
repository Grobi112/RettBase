import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import '../app_config.dart';

/// Einzige Login-Logik für Web-App und Native App (gleich umgesetzt):
/// - 112 + Kunde „admin“ → Superadmin (Pseudo-E-Mail 112@admin.rettbase.de, nur Firebase Auth).
/// - Alle anderen Kunden: E-Mail oder Personalnummer → Suche in kunden/{companyId}/mitarbeiter,
///   dann Anmeldung mit echter E-Mail oder Pseudo-E-Mail {personalnummer}@{companyId}.rettbase.de.
/// Keine plattformspezifischen Abweichungen – [resolveLoginEmail] wird überall verwendet.
class LoginService {
  final _db = FirebaseFirestore.instance;

  static bool _isEmail(String s) =>
      RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(s.trim());

  /// Pseudo-E-Mail für Personalnummer-Login (z. B. 112 + admin → 112@admin.rettbase.de).
  /// Firebase Auth verlangt E-Mail+Passwort; mit dieser Adresse kann sich jemand per Personalnummer anmelden.
  static String _createPseudoEmail(String personalnummer, String companyId) =>
      '${personalnummer.trim()}@$companyId.${AppConfig.rootDomain}';

  /// Firestore-Pfade nutzen immer die normalisierte (kleingeschriebene) Kunden-ID.
  static String _normalizeCompanyId(String companyId) =>
      companyId.trim().toLowerCase();

  /// Personalnummer 112 in Firma Admin = Superadmin (nur in Firebase Auth, ggf. ohne Mitarb.-Eintrag).
  static bool _isAdminSuperadmin112(String companyId, String input) {
    final c = _normalizeCompanyId(companyId);
    return c == 'admin' && input.trim() == '112';
  }

  /// Ergebnis: E-Mail + optional Pfad zum Mitarbeiter-Dokument + effektive Company-ID (docId).
  ({String email, String? mitarbeiterDocPath, String? effectiveCompanyId}) _result(
    String email, String? docPath, String? effectiveCompanyId,
  ) => (email: email, mitarbeiterDocPath: docPath, effectiveCompanyId: effectiveCompanyId);

  /// Liefert die E-Mail für signInWithEmailAndPassword (Kompatibilität).
  Future<String> resolveLoginEmail(String emailOrPersonalnummer, String companyId) async {
    final r = await resolveLoginInfo(emailOrPersonalnummer, companyId);
    return r.email;
  }

  /// Liefert E-Mail + optional Mitarbeiter-Doc-Pfad + effektive Company-ID (für Auto-Create + UID-Update).
  Future<({String email, String? mitarbeiterDocPath, String? effectiveCompanyId})> resolveLoginInfo(
      String emailOrPersonalnummer, String companyId) async {
    final input = emailOrPersonalnummer.trim();
    if (input.isEmpty) throw Exception('Bitte Benutzerkennung eingeben.');

    if (_isEmail(input)) return _result(input, null, null);

    final normalizedCompanyId = _normalizeCompanyId(companyId);

    // Sonderfall: Superadmin 112 in Firma Admin – Login nur über Firebase Auth (112@admin.rettbase.de)
    if (_isAdminSuperadmin112(companyId, input)) {
      return _result(_createPseudoEmail('112', normalizedCompanyId), null, normalizedCompanyId);
    }

    // Personalnummer-Login: Suche in mitarbeiter (immer mit normalisierter Kunden-ID)
    var searchCompanyId = normalizedCompanyId;
    var snapshot = await _searchMitarbeiterByPn(searchCompanyId, input);
    if (snapshot.docs.isEmpty) {
      final resolved = await _resolveDocId(normalizedCompanyId);
      if (resolved != null && resolved != normalizedCompanyId) {
        searchCompanyId = resolved;
        snapshot = await _searchMitarbeiterByPn(searchCompanyId, input);
      }
    }
    if (snapshot.docs.isEmpty) {
      throw Exception('Benutzer mit Personalnummer "$input" nicht gefunden.');
    }

    final data = snapshot.docs.first.data();
    if (data['active'] == false || data['status'] == false) {
      throw Exception('Benutzer ist deaktiviert.');
    }

    final doc = snapshot.docs.first;
    final realEmail = data['email']?.toString();
    final docPseudo = data['pseudoEmail']?.toString();
    final isPseudo = realEmail != null && realEmail.endsWith('.${AppConfig.rootDomain}');
    String email;
    if (realEmail != null && realEmail.isNotEmpty && !isPseudo) {
      email = realEmail;
    } else if (docPseudo != null && docPseudo.isNotEmpty) {
      email = docPseudo;
    } else {
      email = _createPseudoEmail(input, searchCompanyId);
    }
    final path = 'kunden/$searchCompanyId/mitarbeiter/${doc.id}';
    return _result(email, path, searchCompanyId);
  }

  Future<QuerySnapshot<Map<String, dynamic>>> _searchMitarbeiterByPn(String companyId, String input) async {
    final ref = _db.collection('kunden').doc(companyId).collection('mitarbeiter');
    var snapshot = await ref.where('personalnummer', isEqualTo: input).limit(1).get();
    if (snapshot.docs.isEmpty && RegExp(r'^\d+$').hasMatch(input)) {
      snapshot = await ref
          .where('personalnummer', isEqualTo: int.tryParse(input) ?? input)
          .limit(1)
          .get();
    }
    return snapshot;
  }

  Future<String?> _resolveDocId(String companyId) async {
    try {
      final res = await FirebaseFunctions.instanceFor(region: 'europe-west1')
          .httpsCallable('kundeExists')
          .call<Map<String, dynamic>>({'companyId': companyId});
      if (res.data['exists'] == true) {
        final docId = (res.data['docId'] as String?)?.trim().toLowerCase();
        if (docId != null && docId.isNotEmpty) return docId;
      }
    } catch (_) {}
    return null;
  }
}
