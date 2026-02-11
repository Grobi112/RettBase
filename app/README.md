# RettBase – Schulsanitätsdienst

WebApp für den Schulsanitätsdienst (Einsätze, Wachbuch, Checklisten, Fahrtenbuch u. a.).  
Firebase-Projekt: **rett-fe0fa** (Projektnummer 740721219821).

## Web-App & Firebase

- Die App ist eine **Flutter-App** (kein npm). Firebase wird über die Dart-Pakete `firebase_core`, `cloud_firestore`, `firebase_auth` usw. eingebunden.
- **Web-Plattform:** In `lib/firebase_options.dart` ist die Web-Konfiguration für **rett-fe0fa** hinterlegt. Den Platzhalter `YOUR_WEB_API_KEY` ersetzen:
  - **Option A:** In der [Firebase Console](https://console.firebase.google.com/) → Projekt „rett-fe0fa“ → Einstellungen → Ihre Apps → Web-App → Konfiguration kopieren (feld `apiKey`).
  - **Option B:** Im Projektordner ausführen: `dart run flutterfire configure` – erzeugt/aktualisiert die Firebase-Optionen für alle Plattformen.
- **Lokal starten (Web):** `flutter run -d chrome` oder `flutter run -d web-server --web-port=8080`

## Sicherheit und Zugriff (Web + nativ)

- **Ein Projekt für alle Plattformen:** Web, Android, iOS und macOS nutzen dasselbe Firebase-Projekt (**rett-fe0fa**). Login und Datenbank-Zugriffe sind damit identisch.
- **Login:** E-Mail/Personalnummer + Passwort wie in der nativen App; Kunden-ID wird kleingeschrieben für Firestore-Pfade verwendet (`kunden/{companyId}/...`). Admin + Personalnummer 112 wird als Superadmin unterstützt.
- **Module im Webbrowser:** Alle Web-Module (Mitgliederverwaltung, Modul-/Menü-Verwaltung, Kundenverwaltung als Web-URL usw.) werden in der WebApp **im iframe** geöffnet – nicht in einem separaten Fenster. So laufen sie im gleichen Browser-Kontext (gleiche Origin bei gleicher Domain) und haben Zugriff auf Auth/Cookies und die richtige Datenbank.
- **Firestore:** Alle Zugriffe nutzen die normalisierte Kunden-ID und die Sammlungen `kunden/{companyId}/mitarbeiter`, `kunden/{companyId}/modules` usw. in **rett-fe0fa**. Für die WebApp die App idealerweise unter derselben Domain wie die Modul-URLs hosten (z. B. admin.rettbase.de), damit der iframe die Anmeldung teilt.

## Automatisches Deployment (Strato)

Die WebApp kann per **GitHub Actions** automatisch gebaut und per FTP zu Strato hochgeladen werden.

### Ablauf

1. Du pushst Code auf den Branch **`main`** (oder startest den Workflow manuell).
2. GitHub baut die App mit `flutter build web`.
3. Der Inhalt von `build/web/` wird per FTP auf deinen Strato-Server hochgeladen.

### Einrichtung (einmalig)

1. **Repository auf GitHub**  
   Code in ein GitHub-Repository pushen (z. B. `github.com/DeinName/rett-fe0fa`).

2. **FTP-Zugangsdaten als Secrets anlegen**  
   Im Repo: **Settings** → **Secrets and variables** → **Actions** → **New repository secret**.  
   Anlegen:

   | Secret-Name      | Inhalt (Beispiel)        | Pflicht |
   |------------------|---------------------------|--------|
   | `FTP_SERVER`     | z. B. `ftp.strato.de` oder die von Strato angegebene Adresse | Ja |
   | `FTP_USERNAME`   | Dein Strato-FTP-Benutzername | Ja |
   | `FTP_PASSWORD`   | Dein Strato-FTP-Passwort  | Ja |
   | `FTP_SERVER_DIR` | Zielordner auf dem Server, mit `/` am Ende, z. B. `./` oder `public_html/` | Nein (Standard: `./`) |
   | `FTP_PORT`       | Nur nötig, wenn Strato einen anderen Port als 21 verwendet | Nein |
   | `FTP_PROTOCOL`  | `ftp` oder `ftps` (verschlüsselt), falls Strato FTPS anbietet | Nein |

3. **Workflow-Datei**  
   Der Workflow liegt unter `.github/workflows/deploy-web-strato.yml`. Nach dem ersten Push auf `main` läuft das Deployment automatisch. Unter **Actions** siehst du den Fortschritt und eventuelle Fehler.

4. **Manueller Start**  
   Unter **Actions** → **Deploy WebApp zu Strato** → **Run workflow** kannst du das Deployment jederzeit ohne Push auslösen.

### Strato: FTP-Daten finden

Im Strato-Kundenbereich (Login auf strato.de) unter **Webspace / Hosting** oder **FTP-Zugang** findest du Serveradresse, Benutzername und Passwort. Dort steht auch, ob ein Unterordner (z. B. `public_html` oder `www`) als Webroot genutzt wird – diesen dann in `FTP_SERVER_DIR` eintragen (mit Schrägstrich am Ende, z. B. `public_html/`).

## Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Lab: Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Cookbook: Useful Flutter samples](https://docs.flutter.dev/cookbook)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.
