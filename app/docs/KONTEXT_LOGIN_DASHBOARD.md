# RettBase: Login- und Dashboard-Kontext

> Dieses Dokument speichert den Fortschritt der Login-/Dashboard-Fixes (kkg-luenen, Menü, Begrüßung) für zukünftige Sessions. **Firestore-Daten** sind nicht enthalten – nur Struktur und Logik.

## 1. Ausgangssituation

- **Kunden-ID** kann umbenannt werden (z.B. `keg-luenen` → `kkg-luenen`)
- Firestore-**Dokument-ID** bleibt oft unverändert (z.B. weiterhin `keg-luenen`)
- Mitarbeiter liegen unter `kunden/{docId}/mitarbeiter` – nicht unter der neuen kundenId
- Folge: Login mit neuer ID sucht am falschen Pfad, Begrüßung und Menü fehlen

## 2. Firestore-Struktur (relevante Pfade)

```
kunden/{docId}/
  - kundenId: "kkg-luenen"     # aktuelle Anzeige-ID (kann von docId abweichen)
  - subdomain: "kkg-luenen"   # Legacy, wird noch verwendet
  - bereich: "rettungsdienst" | "schulsanitaetsdienst" | ...
  mitarbeiter/{mitarbeiterDocId}
    - uid, personalnummer, vorname, nachname, role, pseudoEmail, email, active
  users/{uid}
    - email, role, mitarbeiterDocId, vorname, nachname

settings/menus/items/{bereich}
  - items: [ { type, id, label, children?, ... } ]

settings/modules/items/{moduleId}
  - roles, label, order, ...
```

## 3. Implementierte Lösungen

### 3.1 Cloud Function `kundeExists` (functions/index.js)
- Sucht per `kundenId` **und** `subdomain`, merged alle gefundenen Docs
- `_pickBestDocId`: bevorzugt Doc mit **anderer** ID als Suchbegriff (Umbenennungsfall)
- Rückgabe: `{ exists, docId }` – docId = Firestore-Dokument-ID

### 3.2 App-Start (main.dart)
- Bei geladenem Cache: `kundeExists(companyId)` aufrufen
- Wenn `docId != companyId`: Cache mit docId aktualisieren, an LoginScreen übergeben

### 3.3 LoginService
- Fallback: Mitarbeiter nicht gefunden → `kundeExists` → Suche mit docId erneut
- Verwendet `pseudoEmail` aus Mitarbeiter-Doc, falls vorhanden
- Rückgabe: `effectiveCompanyId` (docId, wo Mitarbeiter gefunden wurde)

### 3.4 LoginScreen
- Übergibt `effectiveCompanyId` ans Dashboard
- Aktualisiert SharedPreferences bei abweichender Company-ID
- **Mobile-Login-Fix**: `PushNotificationService.saveToken` wird mit `unawaited()` im Hintergrund ausgeführt – blockiert nicht mehr. Ursache: Auf mobilen Browsern hingen `ensureServiceWorkerRegisteredWeb()`/`getToken()` und ließen den Login-Ladekreis endlos laufen.

### 3.5 AuthDataService
- Suche nach `personalnummer` als Fallback (vorher nur uid, email, pseudoEmail)
- Erweiterte `altEmail`-Suche auch bei vorhandenem Doc (kundenId/subdomain)
- `vorname`/`nachname` in users-Doc für Admin-Anzeige

### 3.6 Mitgliederverwaltung
- `saveUsersDoc`: schreibt `vorname`/`nachname` mit (für DisplayName)

### 3.7 getCompanyBereich
- Fallback per `kundenId`/`subdomain` auch wenn Doc existiert aber `bereich` fehlt

### 3.8 Dashboard
- **Fix**: `List<AppModule?>.from(filtered)` statt `filtered.cast<AppModule?>()` – sonst `add(null)` wirft
- Fallback: `loadLegacyGlobalMenu()` wenn bereichs-Menü leer
- DisplayName-Fallback aus E-Mail-Prefix

### 3.9 Bereichs-spezifische Module (z.B. Einsatzprotokoll-SSD, Schichtplan NFS)
- **Regel**: Module, die nur für einen bestimmten Bereich sichtbar sind, werden bei passendem `bereich` **automatisch freigeschaltet** – ohne Eintrag in `kunden/{companyId}/modules`.
- **SSD (Einsatzprotokoll)**:
  - Nur sichtbar bei `bereich == schulsanitaetsdienst`
  - Gilt für alle Rollen, inkl. Admin/Superadmin – keine Ausnahme
  - Bei Schulsanitätsdienst: `ssdAutoEnabled` ersetzt explizite Freischaltung
- **TelefonlisteNFS** (Notfallseelsorge):
  - Nur sichtbar bei `bereich == notfallseelsorge`
  - Nachname, Vorname, Wohnort, Telefonnummer – Anklicken zum Anrufen
  - Admin, Koordinator, Superadmin: bearbeiten und einsehen; User: nur lesen
- **Schichtplan NFS**:
  - Nur sichtbar bei `bereich == notfallseelsorge`
  - Native Flutter-App, Bereitschaften-Verwaltung
  - Firestore: `schichtplanNfsStandorte`, `schichtplanNfsBereitschaftsTypen`, `schichtplanNfsMitarbeiter`, `schichtplanNfsBereitschaften/{dayId}/bereitschaften`
- **Neue bereichs-spezifische Module**: Gleiches Muster anwenden (Bereichs-Check + Auto-Enabled bei passendem Bereich).

## 4. Wichtige Dateien

| Datei | Rolle |
|-------|-------|
| `lib/main.dart` | Start, kundeExists-Cache-Auflösung |
| `lib/screens/company_id_screen.dart` | Kunden-ID-Eingabe, speichert docId |
| `lib/screens/login_screen.dart` | Login, effectiveCompanyId ans Dashboard |
| `lib/services/login_service.dart` | E-Mail/PN-Auflösung, Fallback kundeExists |
| `lib/services/auth_data_service.dart` | Rolle, DisplayName aus Firestore |
| `lib/services/kundenverwaltung_service.dart` | getCompanyBereich |
| `lib/services/modules_service.dart` | getModulesForCompany, bereichs-spezifische Module (SSD, Schichtplan NFS) |
| `lib/services/menueverwaltung_service.dart` | loadMenuStructure(bereich) |
| `lib/screens/dashboard_screen.dart` | _load, Menü, Shortcuts, Drawer (ohne Username, Benachrichtigungen/APK unter Abmelden) |
| `lib/screens/menueverwaltung_screen.dart` | Menü-Module: URL ausblenden, url: '' |
| `lib/screens/modulverwaltung_screen.dart` | Modul-URLs beim Laden normalisieren |
| `lib/services/modulverwaltung_service.dart` | ensureChatModuleExists, ensureSsdModuleExists, ensureSchichtplanNfsModuleExists, ensureTelefonlisteNfsModuleExists |
| `lib/screens/telefonliste_nfs_screen.dart` | TelefonlisteNFS (Notfallseelsorge) |
| `lib/screens/schichtplan_nfs_screen.dart` | Schichtplan NFS (Notfallseelsorge) |
| `lib/services/schichtplan_nfs_service.dart` | schichtplanNfs* Firestore-Operationen |
| `functions/index.js` | kundeExists, saveMitarbeiterDoc, saveUsersDoc |

## 5. Debug-Logging (bei Bedarf aktiv)

Dashboard und AuthDataService enthalten `debugPrint`-Ausgaben:
- uid, email, companyId
- authData (role, displayName, vorname)
- getCompanyBereich-Ergebnis
- loadMenuStructure-Anzahl Items
- Fehler inkl. StackTrace

## 6. Modul-URLs und Chat-Sichtbarkeit (Feb 2026)

### 6.1 Problem
- Chat (und andere native Flutter-Module) konnten in Firestore noch alte WebView-URLs haben (z.B. `/module/chat/chat.html`)
- Mit `url.isNotEmpty` öffnete das Dashboard `ModuleWebViewScreen` statt des nativen ChatScreens
- Chat war im Schnellstart sichtbar (via getModulesForSchnellstart + menuModuleIds), aber **nicht im Hamburger-Menü** – _allModules kam nur aus getModulesForCompany, fehlte bei fehlender expliziter Freischaltung

### 6.2 Lösung: URL immer leer für native Module
- **ModulesService.getModulesForCompany**: `url: ''` für alle defaultNativeModules (keine def['url'] aus Firestore)
- **MenueverwaltungService._normalizeItem**: bei `type == 'module'` → `url: ''` beim Laden
- **MenueverwaltungScreen**: _addModule setzt `url: ''`; _CustomItemDialog blendet URL bei Modulen aus
- **ModulverwaltungScreen**: _ModulFormScreen speichert immer `url: ''`; beim Laden werden defaultNativeModules mit `url: ''` überschrieben
- **ModulverwaltungService**: ensureChatModuleExists, ensureSsdModuleExists, **ensureSchichtplanNfsModuleExists** – setzen Firestore-Docs mit `url: ''`

### 6.3 Chat im Hamburger-Menü
- **Dashboard._load**: Menü-Modul-IDs (menuModuleIds) werden zu allMods ergänzt, wenn sie in defaultNativeModules sind und Rolle passt
- Dadurch erscheinen Menü-Module (z.B. Chat unter Notfallseelsorge) auch ohne explizite Freischaltung in kunden/{companyId}/modules im Drawer

## 7. Hamburger-Menü / Drawer (Feb 2026)

### 7.1 Layout
- **Header**: Nur RettBase-Logo, **kein Username** mehr unter dem Logo
- **Benachrichtigungen aktivieren** und **Android-App herunterladen** stehen **unter „Abmelden“** mit Abstand (SizedBox 24)

### 7.2 Darstellung Benachrichtigungen + Android-App
- Schriftgrößen: **Titel 12**, **Untertitel 10**
- Direkt untereinander (kein Zwischenabstand)
- `dense: true`, `contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 0)`
- Abstand zu „Abmelden“ darüber: 24 px

## 8. Login- und Kunden-ID-UI (Feb 2026)

### Labels entfernt
- **Keine Labels** über den Eingabefeldern – nur Platzhalter (hintText): „Kunden-ID eingeben“, „Email oder Personalnummer eingeben“, „Passwort eingeben“
- `floatingLabelBehavior: FloatingLabelBehavior.never` in allen InputDecorations (login_screen, company_id_screen, main.dart _buildCompanyIdForm)

### Tastatur-Layout (Kunden-ID + Login)
- `resizeToAvoidBottomInset: true` – Inhalt verschiebt sich bei Tastatur nach oben
- Bei Tastatur sichtbar: kompaktes Layout (kleineres Logo, reduzierte Abstände)
- `viewInsets.bottom` als unteres Padding, damit Feld und „Weiter“/„Login“-Button nicht von der schwarzen Up/Down-Toolbar verdeckt werden
- `Center` entfernt – Inhalt oben ausgerichtet, kein manuelles Scrollen nötig

### Scrollen
- `AlwaysScrollableScrollPhysics()` für SingleChildScrollView – Login und Kunden-ID-Screens sind immer scrollbar

### Horizontale Zentrierung (Desktop, Tablet, Querformat)
- `Center` um den ConstrainedBox – Formular ist auf breiten Screens (Desktop, Tablet, Mobil-Querformat) horizontal zentriert

### Betroffene Dateien
- `lib/screens/login_screen.dart`, `lib/screens/company_id_screen.dart`, `lib/main.dart`

## 9. Kundenverwaltung und Schnellstart (Feb 2026)

### Kundenverwaltung
- **createKunde()** (KundenverwaltungService): Legt bei neuem Kunden u.a. an: `settings/informationssystem` (leere containerSlots), `settings/schnellstart` (Slots `['','','','','','']`), keine Schicht-/Standort-Daten
- **Zum Kunden wechseln:** Nach Anlage eines Kunden SnackBar mit Aktion; in der Kundenliste Button „Zum Kunden wechseln“ – setzt companyId und navigiert zum Dashboard

### Schnellstart bei neuem Kunden
- **getModulesForSchnellstart** (ModulesService): Liefert auch leere Slots – kein Fallback mehr auf erste 6 Module. Bei neuem Kunden: 6 leere Slots statt voreingefüllte Module.

## 10. Letzte Session-Änderungen (Feb 2026)

- **Cloud Functions:** kundeExists, _resolveToDocId, ensureUsersDoc – Firestore-Queries parallel mit Promise.all
- **Web Build:** `--tree-shake-icons` in build_web.sh, deploy_web.sh, fw
- **Dashboard:** Module + Menü parallel, Container-Slots/Infos lazy geladen; EnsureUsersDocCache verhindert doppeltes ensureUsersDoc nach Login
- **LoginService:** Schnellpfad für 112 (admin) und admin@rettbase.de – kein Cloud-Call, kein Cold-Start
- **APK:** Entfernt – kein downloadUrl mehr in version.json; app_update_service_android gibt immer upToDate; increment_version.js löscht downloadUrl
- **Push:** permission-blocked nicht mehr als Fehler geloggt; bei denied wird getToken nicht versucht
- **Profil:** Gelöschte/geleerte Felder senden FieldValue.delete() – werden in Firestore korrekt entfernt (nicht mehr durch merge erhalten)
- **Web Version-Check:** siehe Abschnitt 10

## 11. Web-Versionsprüfung und Update (PWA, Handy)

**Ablauf (MUSS so bleiben):**

1. Nutzer öffnet PWA → Login erscheint
2. Nutzer loggt sich ein
3. **Versionsprüfung und Aktualisierung** (direkt nach erfolgreichem Login)
4. Nutzer geht z.B. auf EinsatzprotokollSSD → neue Version wird angezeigt

**Implementierung:**

- **Zeitpunkt:** Versionsprüfung läuft **nur nach erfolgreichem Login** (nicht auf dem Login-Bildschirm, kein Reload während der Anmeldung)
- **LoginScreen:** Nach `signInWithEmailAndPassword` bzw. `createUserWithEmailAndPassword` → `updateWebVersionFromServer()` → `runWebVersionCheckOnce(() => reload())` → dann Navigation zum Dashboard
- **Dashboard:** Versionsprüfung auch beim ersten Laden (falls Nutzer bereits eingeloggt)

**Technische Details (PWA-Handy):**

- **version.json:** Mit `fetch(..., { cache: 'no-store' })` laden – umgeht Service-Worker- und HTTP-Cache (sonst liefert der alte SW die gecachte alte Version)
- **reload():** Service Worker deregistrieren → 150 ms Verzögerung → `location.replace()` mit `?_nocache=Timestamp` (Cache-Bypass)
- **version.json-URL:** `https://app.rettbase.de/app/download/version.json` (AppConfig.androidUpdateCheckUrl)
- **Cooldown:** 2 Min nach Reload keine erneute Prüfung (verhindert Endlosschleife)
- **Relevante Dateien:** `lib/utils/web_version_check_web.dart`, `lib/utils/reload_web_web.dart`, `lib/screens/login_screen.dart`, `lib/screens/dashboard_screen.dart`

## 12. Hinweis zu Firestore-Daten

Die **tatsächlichen Inhalte** von Firestore (Dokumente, Werte) sind nicht in diesem Repo. Bei Problemen:
- Struktur und Pfade aus Code/ diesem Doc ableiten
- Konkrete Kunden-IDs/Probleme in der Anfrage nennen
