import 'package:cloud_functions/cloud_functions.dart';
import '../app_config.dart';

/// Einzige Login-Logik für Web-App und Native App (gleich umgesetzt):
/// - Regel: Login NUR wenn Nutzer in Mitgliederverwaltung (kunden/{companyId}/mitarbeiter) hinterlegt ist.
/// - Ausnahme: admin@rettbase.de = Globaler Superadmin, Login ohne Mitarbeitereintrag, Zugriff überall.
/// - Ausnahme: Company „admin“ + 112 → Superadmin (112@admin.rettbase.de). Superadmins aus Admin haben uneingeschränkten Zugriff auf jede Company.
/// - Alle anderen: E-Mail oder PN → Cloud Function resolveLoginInfo (kein direkter Firestore-Zugriff vor Login, DSGVO/Sicherheit).
class LoginService {
  final _functions = FirebaseFunctions.instanceFor(region: 'europe-west1');

  /// Liefert die E-Mail für signInWithEmailAndPassword (Kompatibilität).
  Future<String> resolveLoginEmail(String emailOrPersonalnummer, String companyId) async {
    final r = await resolveLoginInfo(emailOrPersonalnummer, companyId);
    return r.email;
  }

  /// Liefert E-Mail + optional Mitarbeiter-Doc-Pfad + effektive Company-ID (für Auto-Create + UID-Update).
  /// Nutzt Cloud Function resolveLoginInfo – keine direkte Firestore-Leseberechtigung für mitarbeiter vor Login.
  Future<({String email, String? mitarbeiterDocPath, String? effectiveCompanyId})> resolveLoginInfo(
      String emailOrPersonalnummer, String companyId) async {
    final input = emailOrPersonalnummer.trim();
    if (input.isEmpty) throw Exception('Bitte Benutzerkennung eingeben.');

    try {
      final res = await _functions
          .httpsCallable('resolveLoginInfo')
          .call<Map<String, dynamic>>({
        'companyId': companyId.trim().toLowerCase(),
        'emailOrPersonalnummer': input,
      });
      final data = res.data ?? {};
      final email = (data['email'] as String?)?.trim();
      if (email == null || email.isEmpty) {
        throw Exception('Login-Info konnte nicht ermittelt werden.');
      }
      final path = data['mitarbeiterDocPath'] as String?;
      final effectiveCompanyId = (data['effectiveCompanyId'] as String?)?.trim().toLowerCase();
      return (
        email: email,
        mitarbeiterDocPath: path,
        effectiveCompanyId: effectiveCompanyId,
      );
    } on FirebaseFunctionsException catch (e) {
      final msg = e.message ?? 'Anmeldung fehlgeschlagen.';
      if (e.code == 'not-found' || e.code == 'failed-precondition') {
        throw Exception(msg);
      }
      throw Exception(msg);
    }
  }
}
