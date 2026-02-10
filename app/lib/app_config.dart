/// RettBase Native App - Konfiguration
/// Lädt die Web-App von rettbase.de (Firebase-Projekt: rettbase-app)
/// Arbeitet mit Kunden-ID (nicht Subdomain) – URL: kundenId.rettbase.de

class AppConfig {
  static const String rootDomain = 'rettbase.de';

  /// Basis-URL für die RettBase Web-App (Produktion)
  /// [kundenId] Kunden-ID, z.B. 'admin' → https://admin.rettbase.de
  static String getBaseUrl(String kundenId) {
    if (kundenId.isEmpty || kundenId == 'www') {
      return 'https://$rootDomain';
    }
    return 'https://$kundenId.$rootDomain';
  }

  /// Standard-Kunden-ID beim ersten Start (admin = Dashboard/Login)
  static const String defaultKundenId = 'admin';

  /// Bekannte Kunden-IDs für schnelle Auswahl
  static const List<String> knownKundenIds = [
    'admin',
    'www',
  ];
}
