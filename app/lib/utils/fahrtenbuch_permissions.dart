/// Berechtigungen für Fahrtenbucheinträge
///
/// Bearbeiten: Admin, Geschäftsführung, Rettungsdienstleitung, Wachleitung
/// sowie derjenige, der den Eintrag erfasst hat (createdBy).
/// Alle anderen haben nur Leserechte.
class FahrtenbuchPermissions {
  static const _editRoles = [
    'superadmin',
    'admin',
    'geschaeftsfuehrung',
    'rettungsdienstleitung',
    'wachleitung',
  ];

  /// Prüft, ob der Nutzer einen Fahrtenbucheintrag bearbeiten darf.
  static bool canEdit({
    required String? userRole,
    required String? userId,
    required String? createdBy,
  }) {
    if (userId == null || userId.isEmpty) return false;
    if (userRole != null && _editRoles.contains(userRole.toLowerCase().trim())) {
      return true;
    }
    if (createdBy != null && createdBy.isNotEmpty && createdBy == userId) {
      return true;
    }
    return false;
  }
}
