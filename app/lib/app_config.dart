/// RettBase Native App - Konfiguration
/// Lädt die Web-App von rettbase.de (Firebase-Projekt: rett-fe0fa)
/// Arbeitet mit Kunden-ID (nicht Subdomain) – URL: kundenId.rettbase.de

class AppConfig {
  /// VAPID-Key für Web-Push (FCM).
  /// In Firebase Console: Projekt-Einstellungen → Cloud Messaging → Web-Konfiguration → Schlüsselpaar erzeugen.
  /// Ohne diesen Key funktionieren Push-Benachrichtigungen auf Web nicht.
  static const String? fcmWebVapidKey = 'BOry5KP4SOhFgMZXOEAC2L5kttPU47Tuc8VBBCGk3NGqHqumnF1-bfPbwVTxdXD2rntuCt1azw48FejwsunG5u4';
  static const String rootDomain = 'rettbase.de';

  /// Prüft, ob E-Mail eine Pseudo-/Alias-Adresse ist (z.B. 112@nfsunna.rettbase.de).
  /// Diese sollen nirgends angezeigt werden.
  static bool isPseudoOrAliasEmail(String? email) {
    if (email == null || email.isEmpty || !email.contains('@')) return false;
    final domain = email.split('@').last.toLowerCase();
    return domain == rootDomain || domain.endsWith('.$rootDomain');
  }

  /// APK-Sideload: **ein Ordner** `app/download/` auf dem Webserver (Firebase oder FTP):
  /// - `version.json` – von Android + Web für Update-Check geladen
  /// - `rettbase.apk` – Installationspaket
  static const String? androidUpdateCheckUrl =
      'https://app.rettbase.de/download/version.json';

  /// Fallback, wenn `version.json` kein `apkUrl` enthält.
  static const String androidApkDownloadUrlDefault =
      'https://app.rettbase.de/download/rettbase.apk';

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
