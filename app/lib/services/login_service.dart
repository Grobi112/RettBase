import 'package:cloud_firestore/cloud_firestore.dart';
import '../app_config.dart';

/// Ermittelt die Login-E-Mail aus E-Mail oder Personalnummer (wie auth.js).
class LoginService {
  final _db = FirebaseFirestore.instance;

  static bool _isEmail(String s) =>
      RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(s.trim());

  static String _createPseudoEmail(String personalnummer, String companyId) =>
      '${personalnummer.trim()}@$companyId.${AppConfig.rootDomain}';

  /// Liefert die E-Mail für signInWithEmailAndPassword.
  /// Bei E-Mail: Rückgabe unverändert.
  /// Bei Personalnummer: Suche in mitarbeiter, dann echte E-Mail oder Pseudo-Email.
  Future<String> resolveLoginEmail(String emailOrPersonalnummer, String companyId) async {
    final input = emailOrPersonalnummer.trim();
    if (input.isEmpty) throw Exception('Bitte Benutzerkennung eingeben.');

    if (_isEmail(input)) return input;

    // Personalnummer-Login: Suche in mitarbeiter
    final mitarbeiterRef = _db.collection('kunden').doc(companyId).collection('mitarbeiter');
    var snapshot = await mitarbeiterRef.where('personalnummer', isEqualTo: input).limit(1).get();
    if (snapshot.docs.isEmpty && RegExp(r'^\d+$').hasMatch(input)) {
      snapshot = await mitarbeiterRef
          .where('personalnummer', isEqualTo: int.tryParse(input) ?? input)
          .limit(1)
          .get();
    }
    if (snapshot.docs.isEmpty) {
      throw Exception('Benutzer mit Personalnummer "$input" nicht gefunden.');
    }

    final data = snapshot.docs.first.data();
    if (data['active'] == false || data['status'] == false) {
      throw Exception('Benutzer ist deaktiviert.');
    }

    final realEmail = data['email']?.toString();
    final isPseudo = realEmail != null && realEmail.endsWith('.${AppConfig.rootDomain}');
    if (realEmail != null && realEmail.isNotEmpty && !isPseudo) {
      return realEmail;
    }
    return _createPseudoEmail(input, companyId);
  }
}
