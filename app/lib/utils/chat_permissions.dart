/// Berechtigungen für Chat: Gruppen erstellen, Mitglieder hinzufügen.
///
/// Erlaubte Rollen: Admin, Koordinator, Geschäftführung, Rettungsdienstleitung, Wachleitung
class ChatPermissions {
  static const _groupManageRoles = [
    'superadmin',
    'admin',
    'koordinator',
    'geschaeftsfuehrung',
    'rettungsdienstleitung',
    'wachleitung',
  ];

  /// Prüft, ob der Nutzer Gruppen erstellen und Mitglieder hinzufügen darf.
  static bool canManageGroups(String? userRole) {
    if (userRole == null || userRole.isEmpty) return false;
    return _groupManageRoles.contains(userRole.toLowerCase().trim());
  }
}
