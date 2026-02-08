import 'schichtanmeldung_service.dart';
import 'auth_service.dart';
import 'auth_data_service.dart';

/// App-weiter Service für den aktiven Schichtstatus.
/// Ein User, der sich für eine Schicht angemeldet hat, bleibt bis zur Endzeit
/// "aktiv" – unabhängig von App-Logout. Dieser Status beeinflusst den Arbeitsverlauf.
class SchichtStatusService {
  static final SchichtStatusService _instance = SchichtStatusService._();
  factory SchichtStatusService() => _instance;

  SchichtStatusService._();

  final _authService = AuthService();
  final _authDataService = AuthDataService();
  final _schichtService = SchichtanmeldungService();

  /// Gibt die aktive Schichtanmeldung des eingeloggten Users zurück, falls
  /// die aktuelle Zeit innerhalb der Schicht liegt (Start–Endzeit).
  /// Sonst null.
  Future<SchichtanmeldungEintrag?> getAktiveSchicht(String companyId) async {
    final user = _authService.currentUser;
    if (user == null) return null;

    final email = user.email ?? '';
    final uid = user.uid;
    final normalizedId = companyId.trim().toLowerCase();

    SchichtplanMitarbeiter? mitarbeiter;
    if (email.isNotEmpty) {
      mitarbeiter = await _schichtService.findMitarbeiterByEmail(companyId, email);
    }
    if (mitarbeiter == null && email.isNotEmpty && normalizedId != companyId) {
      mitarbeiter = await _schichtService.findMitarbeiterByEmail(normalizedId, email);
    }
    if (mitarbeiter == null && uid.isNotEmpty) {
      mitarbeiter = await _schichtService.findMitarbeiterByUid(companyId, uid);
    }
    if (mitarbeiter == null && uid.isNotEmpty && normalizedId != companyId) {
      mitarbeiter = await _schichtService.findMitarbeiterByUid(normalizedId, uid);
    }
    if (mitarbeiter == null && uid.isNotEmpty && email.isNotEmpty) {
      for (final cid in [companyId, normalizedId]) {
        if (cid.isEmpty) continue;
        mitarbeiter = await _schichtService.getSchichtplanMitarbeiterById(cid, uid);
        if (mitarbeiter != null) break;
        final authData = await _authDataService.getAuthData(uid, email, cid);
        final displayName = authData.displayName ?? '';
        if (displayName.contains(',')) {
          final parts = displayName.split(',').map((s) => s.trim()).toList();
          if (parts.length >= 2) {
            mitarbeiter = await _schichtService.findMitarbeiterByName(cid, parts[1], parts[0]);
            if (mitarbeiter != null) break;
          }
        }
        if (mitarbeiter == null && authData.vorname != null) {
          final nachname = displayName.replaceAll(authData.vorname!, '').replaceAll(',', '').trim();
          mitarbeiter = await _schichtService.findMitarbeiterByName(cid, authData.vorname!, nachname);
          if (mitarbeiter != null) break;
        }
      }
    }
    if (mitarbeiter == null) return null;

    var anmeldung = await _schichtService.getAktiveSchichtanmeldung(companyId, mitarbeiter.id);
    if (anmeldung == null && normalizedId != companyId) {
      anmeldung = await _schichtService.getAktiveSchichtanmeldung(normalizedId, mitarbeiter.id);
    }
    return anmeldung;
  }

  /// Kurzform: true, wenn der User aktuell in Schicht ist.
  Future<bool> istInSchicht(String companyId) async {
    final schicht = await getAktiveSchicht(companyId);
    return schicht != null;
  }
}
