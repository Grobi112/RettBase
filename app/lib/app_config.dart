/// RettBase Native App - Konfiguration
/// Lädt die Web-App von rettbase.de (Firebase-Projekt: rett-fe0fa)
/// Arbeitet mit Kunden-ID (nicht Subdomain) – URL: kundenId.rettbase.de

class AppConfig {
  /// VAPID-Key für Web-Push (FCM).
  /// In Firebase Console: Projekt-Einstellungen → Cloud Messaging → Web-Konfiguration → Schlüsselpaar erzeugen.
  /// Ohne diesen Key funktionieren Push-Benachrichtigungen auf Web nicht.
  static const String? fcmWebVapidKey = 'BOry5KP4SOhFgMZXOEAC2L5kttPU47Tuc8VBBCGk3NGqHqumnF1-bfPbwVTxdXD2rntuCt1azw48FejwsunG5u4';
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
