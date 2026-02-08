/// RettBase Native App - Konfiguration
/// Lädt die Web-App von rettbase.de (gleiche Datenbank: rett-fe0fa)

class AppConfig {
  static const String rootDomain = 'rettbase.de';

  /// Basis-URL für die RettBase Web-App (Produktion)
  static String getBaseUrl(String subdomain) {
    if (subdomain.isEmpty || subdomain == 'www') {
      return 'https://$rootDomain';
    }
    return 'https://$subdomain.$rootDomain';
  }

  /// Standard-Subdomain beim ersten Start (admin = Dashboard/Login)
  static const String defaultSubdomain = 'admin';

  /// Bekannte Subdomains für schnelle Auswahl
  static const List<String> knownSubdomains = [
    'admin',
    'www',
  ];
}
