# RettBase Native App – Alle Erinnerungen

> Zentrales Kontextdokument: Wie die Flutter-App funktioniert und was bei Änderungen zu beachten ist.

---

## 1. Projekt-Fokus

- **Nur Flutter-App** (`app/`) wird weiterentwickelt
- **rettbase/** wurde entfernt (März 2026) – Legacy JS/HTML-Web-App gelöscht, keine Kunden-Subdomains mehr. Commit: a95249c
- **Legacy-*.html-Redirects** in `dashboard_screen.dart` entfernt – Fallbacks für `mitarbeiterverwaltung.html`, `kundenverwaltung.html`, `modulverwaltung.html`, `menue.html` waren tot (url immer `''` durch `_normalizeItem`). Default: nur noch `mod.url.isNotEmpty` → ModuleWebViewScreen, sonst PlaceholderModuleScreen.
- **Zielplattformen:** iOS, Android, macOS, Web (`flutter build web`)
- **Firebase-Projekt:** rett-fe0fa (einheitlich für alle Plattformen)

---

## 2. Login & Kunden-ID (inkl. Dashboard)

### Ausgangssituation
- **Kunden-ID** kann umbenannt sein (z.B. `keg-luenen` → `kkg-luenen`), Firestore-**docId** bleibt oft alt
- Mitarbeiter liegen unter `kunden/{docId}/mitarbeiter` – **immer docId** nutzen, nicht kundenId
- Folge bei Umbenennung: Login sucht am falschen Pfad, Begrüßung und Menü fehlen

### Cloud Function `kundeExists` (functions/index.js)
- Sucht per `kundenId` **und** `subdomain`, merged alle gefundenen Docs
- `_pickBestDocId`: bevorzugt Doc mit **anderer** ID als Suchbegriff (Umbenennungsfall)
- Rückgabe: `{ exists, docId }` – docId = Firestore-Dokument-ID
- **Rate-Limit:** max. 15 Aufrufe/Minute pro IP (Schutz vor Enumerations-Angriffen)

### App-Start (main.dart)
- Bei geladenem Cache: `kundeExists(companyId)` aufrufen
- Wenn `docId != companyId`: Cache mit docId aktualisieren, an LoginScreen übergeben

### LoginService
- Fallback: Mitarbeiter nicht gefunden → `kundeExists` → Suche mit docId erneut
- Verwendet `pseudoEmail` aus Mitarbeiter-Doc, falls vorhanden
- Rückgabe: `effectiveCompanyId` (docId, wo Mitarbeiter gefunden wurde)
- **Pflicht:** Login nur wenn Nutzer in Mitarbeiterverwaltung (E-Mail wirft sonst Exception) – siehe §20

### LoginScreen
- Übergibt `effectiveCompanyId` ans Dashboard
- Aktualisiert SharedPreferences bei abweichender Company-ID
- Ruft nach Login `ensureUsersDoc` auf (für Firestore-Zugriffsregeln)

### AuthDataService
- Suche nach `personalnummer` als Fallback (zusätzlich zu uid, email, pseudoEmail)
- Erweiterte `altEmail`-Suche auch bei vorhandenem Doc (kundenId/subdomain)
- `vorname`/`nachname` in users-Doc für Admin-Anzeige

### Mitgliederverwaltung
- `saveUsersDoc`: schreibt `vorname`/`nachname` mit (für DisplayName)
- **Kontext:** docs/KONTEXT_MITARBEITERVERWALTUNG.md

### getCompanyBereich
- Fallback per `kundenId`/`subdomain` auch wenn Doc existiert aber `bereich` fehlt

### Login-Regeln (Web + Native identisch)
- **Regel:** Nur Mitglieder in der Mitgliederverwaltung (`kunden/{companyId}/mitarbeiter`) können sich einloggen.
- **Ausnahme 1:** `admin@rettbase.de` – Globaler Superadmin, Login ohne Mitarbeitereintrag, Zugriff überall.
- **Ausnahme 2:** Company „admin“ + Personalnummer 112 → Superadmin (`112@admin.rettbase.de`). Nur bei Company „admin“.
- **Admin-Superadmins** (users oder mitarbeiter in admin mit role superadmin) haben uneingeschränkten Zugriff auf jede Company, auch ohne dort in Mitgliederverwaltung zu stehen.
- Andere Kunden: E-Mail oder PN → Suche in mitarbeiter, Anmeldung mit echter E-Mail oder Pseudo-E-Mail

### Kritische Patterns
- **Shortcuts:** `List<AppModule?>.from(filtered)` verwenden, **NICHT** `.cast<AppModule?>()` – sonst schlägt `add(null)` fehl
- **Dashboard:** Fallback `loadLegacyGlobalMenu()` wenn bereichs-Menü leer, DisplayName-Fallback aus E-Mail-Prefix

### Wichtige Dateien (Login/Dashboard)
- `main.dart`, `company_id_screen.dart`, `login_screen.dart`, `login_service.dart`, `auth_data_service.dart`, `kundenverwaltung_service.dart`, `modules_service.dart`, `menueverwaltung_service.dart`, `dashboard_screen.dart`

---

## 3. Bereichs-spezifische Module

- Module, die **nur für einen bestimmten Bereich** sichtbar sind, werden bei passendem `bereich` **automatisch freigeschaltet** – ohne Eintrag in `kunden/{companyId}/modules`
- **Keine Ausnahme** für Admin/Superadmin – auch sie sehen nur, was der Bereich hergibt

| Modul | Bereich | Firestore-Pfade |
|-------|---------|-----------------|
| **SSD (Einsatzprotokoll)** | `schulsanitaetsdienst` | – |
| **Schichtplan NFS** | `notfallseelsorge` | `schichtplanNfsStandorte`, `schichtplanNfsBereitschaftsTypen`, `schichtplanNfsMitarbeiter`, `schichtplanNfsBereitschaften/{dayId}/bereitschaften`, `schichtplanNfsStundenplan/{dayId}`. **Kontext:** docs/KONTEXT_SCHICHTPLAN_NFS.md |
| **TelefonlisteNFS** | `notfallseelsorge` | Daten aus Mitgliederverwaltung (`kunden/{companyId}/mitarbeiter`). Rechte: Admin/Koordinator/Superadmin bearbeiten, User nur lesen + Nummer antippen zum Anrufen. User pflegen ihre Daten über das Profil. **Kontext:** docs/KONTEXT_TELEFONLISTE_NFS.md |
| **Einsatzprotokoll NFS** | `notfallseelsorge` | Nur wenn Admin das Modul freischaltet und ins Menü einpflegt (kein Auto-Enable). Firestore: `kunden/{companyId}/einsatzprotokoll-nfs`. **Kontext:** docs/KONTEXT_EINSATZPROTOKOLL_NFS.md |

- **Neue bereichs-spezifische Module:** Gleiches Muster in `getModulesForCompany` (Bereichs-Check + Auto-Enabled)

---

## 4. Chat

- **Vollständig nativ** – keine WebView, kein iframe
- **ChatScreen** (chat_screen.dart), **ChatService** (chat_service.dart), **ChatModel** (models/chat.dart)
- **loadMessages** – einmaliges Laden per Firestore `.get()` (FutureBuilder, robust auf Flutter Web)
- **streamMessages** – Echtzeit-Updates per `.snapshots()` (optional)
- **streamUnreadCount** – Gesamtzahl ungelesen für Badge
- **Badge:** Dashboard `_chatUnreadNotifier` → Hamburger-Menü + Schnellstart (HomeScreen `chatUnreadListenable`, _ShortcutButton bei `module.id == 'chat'`)
- **Firestore:** `kunden/{companyId}/chats/{chatId}` (participants, lastMessageAt, unreadCount, lastReadAt) und `.../messages/{messageId}` (from, text, createdAt, attachments)
- **Direct-Chat-ID:** `direct_{uid1}_{uid2}` (alphabetisch)
- **Unread:** unreadCount[uid] + Fallback: letzte Nachricht von anderem, lastReadAt prüfen

### Push-Benachrichtigungen & App-Badge
- **PushNotificationService** (lib/services/push_notification_service.dart): FCM, Token speichern, Badge
- **FCM-Token** in `kunden/{companyId}/users/{uid}` (fcmToken, fcmTokenUpdatedAt) – nach Login speichern
- **Cloud Functions:** `onNewChatMessage` (neue Nachricht), `onNewGroupChat` (zur Gruppe hinzugefügt) – senden FCM an Empfänger
- **FCM-Token:** zusätzlich in `fcmTokens/{uid}` (global) gespeichert – Cloud Function nutzt Fallback, falls `kunden/{companyId}/users/{uid}` leer
- **Badge Native:** flutter_app_badger (nur iOS/Android, nicht Web), aktualisiert bei Chat-Unread-Änderung
- **Badge PWA/Web:** Navigator Badging API (setAppBadge). **Safari iOS** ab 16.4, aber nur mit Notification-Permission. **Chrome Android:** nicht unterstützt (Plattform-Limit) – siehe docs/WEB_PUSH_SETUP.md §5
- **App über Push öffnen:** `initialChatFromNotification` → Dashboard ruft `_maybeOpenChatFromNotification` auf, übergibt `initialChatId` an ChatScreen
- **Android:** POST_NOTIFICATIONS in AndroidManifest; **iOS:** UIBackgroundModes remote-notification in Info.plist
- **Deploy Cloud Function:** `firebase deploy --only functions:onNewChatMessage`
- **Web-Push:** `web/firebase-messaging-sw.js` für Background-Nachrichten; **VAPID-Key** in `AppConfig.fcmWebVapidKey` (Firebase Console → Cloud Messaging → Web → Schlüsselpaar erzeugen); ohne Key kein FCM-Token auf Web

---

## 5. Schnellstart

- **6 Slots** in `kunden/{companyId}/settings/schnellstart`
- **getModulesForSchnellstart:** Union aus getModulesForCompany und **Menü-Modulen** – damit z.B. Chat in gespeicherten Slots wählbar ist, auch wenn es nur im Menü erscheint
- **Leere Slots** (alle null) = kein Custom → alle Module angezeigt

---

## 6. Menü

- **loadMenuStructure(bereich)** aus `settings/menus/items/{bereich}`
- **Fallback:** `loadLegacyGlobalMenu()` wenn bereichs-Menü leer
- DisplayName-Fallback aus E-Mail-Prefix

### Benutzerdefinierte Menü-Titel (Feb 2026)
- **Menü-Titel:** In der Menüverwaltung kann pro Modul ein eigener Titel gesetzt werden (z.B. „Telefonliste“ statt „TelefonlisteNFS“)
- **Anzeige:** Dieser Titel wird überall verwendet: Hamburger-Menü, Schnellstart, Schnellstart-Dropdown, **AppBar-Titel** der Modul-Screens
- **Technik:** `MenueverwaltungService.extractModuleLabelsFromMenu()` extrahiert Modul-ID → Label; `_moduleFromMenuItem()` nutzt `item['label']`; alle Modul-Screens haben optionalen Parameter `title`, Dashboard übergibt `mod.label`

---

## 7. UI-Standards

### AppBar (Module)
- Immer **AppTheme.buildModuleAppBar()**
- Weißer Hintergrund, hellblauer Chevron + Titel, Aktionen rechts
- „Neue X“-Buttons **rechts in der AppBar**, nicht als FAB

### PopUps/Dialoge
- **Zentriert** (Center / Alignment.center)
- **Responsive:** Mobile ~90 % Breite, Desktop max. 480–560px
- **Auswahl-/Such-Dialoge:** oben ausgerichtet (Alignment.topCenter)
- **Struktur:** Drag-Handle, Header (Titel + Schließen), Suchfeld, scrollbarer Inhalt
- **Suchfeld:** filled, abgerundet, Icons.search_rounded

### Druck/PDF
- **AppBar:** Icons.print + Icons.save in actions
- **PdfPreview:** `useActions: false`, `allowPrinting: false`, `allowSharing: false`
- **onError** setzen – kein umrandetes X (ErrorWidget)
- **Nur ASCII** für Platzhalter: `-` nicht `–` oder `•` (PDF-Schriften)

### Farben (AppTheme)
- primary: #0EA5E9, headerBg: #1E1F26, surfaceBg: #F4F5F7, textPrimary: #1E1F26
- Breakpoints: 400 (compact), 600 (narrow), 900 (medium)

---

## 8. Web vs. Native (Flutter)

- **Gemeinsam:** LoginService, ModulesService, allgemeine Screens
- **Nur Web:** `firebase_options.dart` → web; Auth-Bridge (module_webview_widget)
- **Nur Native:** `firebase_options.dart` → android, ios, macos
- **Nicht** beide Plattformen gleichzeitig ändern – nur wenn ausdrücklich gefordert

---

## 9. Wichtige Dateien

| Bereich | Dateien |
|---------|---------|
| Start | `main.dart`, `company_id_screen.dart` |
| Login | `login_screen.dart`, `login_service.dart`, `auth_data_service.dart` |
| Dashboard | `dashboard_screen.dart`, `home_screen.dart` |
| Module | `modules_service.dart`, `menueverwaltung_service.dart`, `kundenverwaltung_service.dart` |
| Chat | `chat_screen.dart`, `chat_service.dart`, `models/chat.dart` |
| Cloud Functions | `functions/index.js` (kundeExists, **resolveLoginInfo**, ensureUsersDoc, createAuthUser, updateMitarbeiterPassword, saveMitarbeiterDoc, saveUsersDoc, createMitarbeiterDoc, deleteMitarbeiterFull, loadKunden) |

---

## 10. Firestore-Struktur (Kurzreferenz)

```
kunden/{docId}/
  kundenId, subdomain, bereich    # kundenId kann von docId abweichen (Umbenennung)
  mitarbeiter/{id}  – uid, personalnummer, vorname, nachname, role, pseudoEmail, email, active
  users/{uid}      – email, role, mitarbeiterDocId, vorname, nachname
  settings/schnellstart – [slot1, slot2, ...]
  chats/{chatId}/messages/{msgId}

settings/menus/items/{bereich}   – items: [ { type, id, label, children?, ... } ]
settings/modules/items/{moduleId} – roles, label, order, ...
```

**Hinweis:** Die tatsächlichen Firestore-Inhalte sind nicht im Repo. Bei Problemen: Struktur aus Code/ diesem Doc ableiten, konkrete Kunden-IDs in der Anfrage nennen.

---

## 11. Debug

- Dashboard, AuthDataService: `debugPrint` für uid, companyId, authData, getCompanyBereich, loadMenuStructure
- Fehler inkl. StackTrace ausgeben

---

## 12. Splash-, Login- und Kunden-ID-Screens (Logo & Hintergrund)

### Logo
- **Bild:** `img/rettbase_splash.png` (RettBase mit Slogan „Einfach. Sicher. Digital.“, dunkelgrauer Hintergrund im Bild)
- **Verwendung:** Splash-Screen, Login-Screen, Kunden-ID-Screen (CompanyIdScreen)

### Größen
- **Splash:** `height: 120` (einheitlich mit HTML-Platzhalter für nahtlosen Übergang)
- **Login & Kunden-ID:** `height: Responsive.isCompact(context) ? 100 : 140`

### Hintergrund
- **Alle drei Screens:** `AppTheme.headerBg` (#1E1F26) – einheitlich

### Dateien
- `lib/screens/splash_screen.dart`, `lib/screens/login_screen.dart`, `lib/screens/company_id_screen.dart`

### Login- und Kunden-ID-UI (Feb 2026)
- **Keine Labels** über Feldern – nur hintText; `floatingLabelBehavior: FloatingLabelBehavior.never`
- **Tastatur-Layout:** resizeToAvoidBottomInset, viewInsets.bottom-Padding, kompaktes Layout bei Tastatur (kleineres Logo)
- **Scrollen:** AlwaysScrollableScrollPhysics() für SingleChildScrollView
- **Zentrierung:** Center um ConstrainedBox – horizontal zentriert auf Desktop, Tablet, Mobil-Querformat
- **Kontext:** docs/KONTEXT_LOGIN_DASHBOARD.md §8

---

## 13. Einsatzprotokoll SSD – Einsatz-Nr.

### Zurücksetzen
- **Superadmin-Button** (↻ Icon) in Protokollübersicht: setzt nächste Nr. auf **20260001**
- Nur für Superadmin sichtbar

### Firestore
- `kunden/{companyId}/settings/einsatzprotokoll-ssd` mit Feld `nextEinsatzNr` (z.B. "20260001")
- Wenn gesetzt: `getNextEinsatzNr` nutzt diesen Wert und erhöht beim Abruf
- Sonst: max aus `einsatzprotokoll-ssd`-Protokollen ermitteln

### Service (einsatzprotokoll_ssd_service.dart)
- `getNextEinsatzNr(companyId)` – prüft zuerst Settings
- `setNextEinsatzNr(companyId, nr)` – manuelles Setzen

### Migration
- `bin/migrate_reset_einsatznr.dart` – setzt für alle Kunden nextEinsatzNr = 20260001
- **Nicht** mit `dart run` (Flutter-Deps), alternativ: `flutter run -t bin/migrate_reset_einsatznr.dart` oder über UI-Button

---

## 14. Einsatzprotokoll SSD – Pflichtfelder & Validierung

### Pflichtfeld-Darstellung
- **Leer:** gelber Hintergrund
- **Ausgefüllt:** weißer Hintergrund
- Nur Checkbox-Inhalt gelb, Labels unverändert

### Pflichtfelder (Mindestanforderungen)
- Schulsanitäter/in 1: Vorname, Name
- Einsatzort
- Patientendaten: Vorname, Name, Klasse (Geburtsdatum optional)
- Art des Vorfalls: mind. 1 Checkbox (Erkrankung/Unfall) + ggf. Zusatzfeld
- „Was hat der Verletzte gemacht“: mind. 1 Checkbox
- Erstbefund: Atmung (mind. 1), Puls, SpO2
- Erstbefund bei Unfall: Schmerzen (mind. 1 der 3 Optionen), „Welche Verletzung liegt vermutlich vor“ (mind. 1 der 4 Optionen)
- „Klagt über“: Pflichtfeld
- „Mindestens eine Person informiert“: nur Pflichtfeld, wenn Notruf oder Eltern benachrichtigt angekreuzt
- Bei „Lehrer informiert“: Pflichtfeld „Name des Lehrers / der Lehrerin“
- Getroffene Maßnahmen: mind. 1 (ohne Notruf/Eltern benachrichtigt)
- Verlaufsbeschreibung: Pflichtfeld
- Schilderung, Informiert-Gruppe, Übergabe an, Unterschrift Schulsanitäter/in 1

### Validierung
- Popup mit **„Hinweis“** (fett, rot) und Text: „Es wurden nicht alle Pflichtfelder ausgefüllt. Bitte ausfüllen.“

### Sonstiges
- Button „Protokoll speichern“: roter Hintergrund
- SpO2-Label: nur „SpO2“ (ohne Klammer)

---

## 15. Informationssystem

- Dropdown-Fehler: ungültige Werte prüfen und bereinigen
- Leere Container in Sortierung ausblenden

---

## 16. Schnellstart (Home)

- Nur **belegte** Schnellstart-Felder anzeigen
- Eigenen Schnellstart **nicht** nach Menü filtern

---

## 17. WebApp-spezifisch

- **Service-Worker-Update:** periodische Prüfung, Reload bei neuem Build
- **Favicon:** RB-Logo (`web/favicon.png` aus `img/RBapp.png`)

---

## 18. Wichtige Dateien (Ergänzung)

| Bereich | Dateien |
|---------|---------|
| Einsatzprotokoll SSD | `einsatzprotokoll_ssd_screen.dart`, `einsatzprotokoll_ssd_uebersicht_screen.dart`, `einsatzprotokoll_ssd_druck_screen.dart` |
| Einsatzprotokoll NFS | `einsatzprotokoll_nfs_screen.dart` |
| Einsatzprotokoll Service | `einsatzprotokoll_ssd_service.dart`, `einsatzprotokoll_nfs_service.dart` |
| Logo/ Splash | `splash_screen.dart`, `img/rettbase_splash.png` |

---

## 19. APK-Update – Deaktiviert (Stand: 2025)

**Aktueller Stand:** APK-In-App-Update ist **entfernt**. Kein Update-Dialog, kein Download-Link im Dashboard, keine App-Update-Karte in Einstellungen.

### Was existiert, aber nicht genutzt wird
- `lib/services/app_update_service*.dart`, `app_update_types.dart` – Code bleibt, wird nirgends aufgerufen. APK-Updates entfernt (Play Store).
- `app_config.dart`: `androidUpdateCheckUrl` – für Web-Versionscheck (version.json) genutzt
- `web/increment_version.js`, `web/version.json` – für Web-Versionierung, APK-Vergleich aus

### Was zurückgenommen wurde
- **app_installer_plus** (In-App-Download/Install) – entfernt, hatte XML-Änderungen (FileProvider, Permissions) die Probleme verursachten
- **Android Launch-Screen** mit Logo – zurück auf weißen Standard (launch_background, colors.xml, launch_splash entfernt)
- **screenOrientation fullSensor** – zurückgenommen
- **Update-Link im Dashboard** – entfernt
- **Einstellungen App-Update-Karte** – entfernt

### Web-App (Stand Feb 2026)
- **Kein Update-Banner mehr** – bei neuer Version (version.json) wird die Seite **automatisch** neu geladen
- **version.json-Check:** nur **einmal** beim App-Start im Ladefenster (vor Dashboard/Login); keine periodische Prüfung mehr in der Session
- **Versionierung:** `web/version.json` + `web/increment_version.js` – wird bei `./fw`, `./flutter build web`, `./scripts/build_web.sh`, `./scripts/deploy_web.sh` automatisch erhöht. Manuell: `node web/increment_version.js`
- **Cache-Leerung beim Aufruf:** firebase.json headers + index.html Meta-Tags für index.html, JS, manifest, version.json

---

## 20. Sicherheitsmaßnahmen (Feb 2026)

### Login nur mit Mitarbeiterverwaltung
- **LoginService:** E-Mail-Login wirft Exception, wenn Nutzer nicht in `mitarbeiter` oder deaktiviert
- **AuthDataService:** Kein Mitarb.-Treffer → `role: 'guest'` statt `role: 'user'`
- **Dashboard:** Bei `role == 'guest'` und `uid != null` → Sign-out, Weiterleitung zu Login
- **Superadmin 112@admin.rettbase.de** weiterhin ohne Mitarb.-Eintrag möglich

### Passwort vergessen
- Nur wenn E-Mail/Personalnummer in Mitarbeiterverwaltung gefunden → `sendPasswordResetEmail`
- Nutzt `resolveLoginInfo` zur Prüfung (inkl. Pseudo-E-Mail bei PN-Login)

### kundeExists Rate-Limit
- Max. 5 Aufrufe/Minute pro Client-IP (Schutz vor Enumerations-Angriffen)
- Bei Überschreitung: `resource-exhausted` → „Zu viele Anfragen“
- CompanyIdScreen zeigt spezifische Meldung für `resource-exhausted`

### Cloud Functions mit Rollenprüfung
- `_requireAdminRole(context, companyId)`: Prüft Admin/Superadmin/LeiterSSD
- **createAuthUser, updateMitarbeiterPassword:** benötigen `companyId` im Request; nur Admin/Superadmin/LeiterSSD
- **saveUsersDoc, saveMitarbeiterDoc, createMitarbeiterDoc:** ebenfalls Rollenprüfung
- **deleteMitarbeiterFull:** DSGVO-vollständige Löschung – siehe unten

### DSGVO-vollständige Mitgliedslöschung (deleteMitarbeiterFull)
- **Mitgliederverwaltung → Löschen** ruft `deleteMitarbeiterFull` auf (Cloud Function)
- **Cloud Function** entfernt alle **Kerndaten**: Auth, mitarbeiter, users, userTiles, fcmTokens, Profil-Fotos, Schichtplan-Einträge
- **Erstellte Dokumente** (Einsatzprotokolle, Chats, Meldungen) behalten `createdBy`/Name – für Historie/Nachvollziehbarkeit gewollt
- **Storage-Bucket:** `admin.initializeApp` mit `storageBucket`; `bucket("rett-fe0fa.firebasestorage.app")` explizit – sonst Fehler beim Löschen
- Nur Admin/Superadmin/LeiterSSD

### Firestore-Regeln kundenspezifisch
- `canAccessCompany(kundenId)`: Zugriff nur wenn `kunden/{kundenId}/users/{uid}` existiert ODER Superadmin
- `isSuperadmin()`: admin@rettbase.de, 112@admin.rettbase.de
- `belongsToCompany(kundenId)`: `exists(users/uid)`
- `kunden/{kundenId}/**`: read/write nur mit `canAccessCompany` (mitarbeiter read: if true bleibt für Login-Suche)
- **settings/** weiterhin `isLoggedIn()` (globale Konfig)

### ensureUsersDoc (Cloud Function)
- Stellt users-Dokument für Firestore-Zugriffsregeln her
- Aufruf: LoginScreen nach erfolgreichem Login, Dashboard zu Beginn von _load
- Verifiziert Nutzer in mitarbeiter; Superadmin: sofort erstellen
- Ohne users-Doc: Firestore-Regeln würden Zugriff verweigern

### Sicherheit (Feb 2026)
- **Erledigt:** Firestore Fallback entfernt; mitarbeiter über Cloud Function resolveLoginInfo; Storage Profil nur für eigene UID; loadKunden nur Superadmin
- **Erledigt (Punkt 1–3):** Collection-Group-Regeln entfernt (waren zu permissiv); Storage: Company-Prüfung per Custom Claims (companyId, superadmin) – ensureUsersDoc setzt diese; Settings: Schreibzugriff nur noch für isSuperadmin(); Lesezugriff weiterhin für alle eingeloggten Nutzer. Token-Refresh nach ensureUsersDoc (getIdToken(true)) für gültige Claims bei Storage-Zugriff.
- **Erledigt (Punkt 4–5):** App Check **nicht verwendet** – Rate-Limit (5/min) reicht. API-Keys: docs/SICHERHEIT_API_KEYS_APP_CHECK.md, docs/SICHERHEIT_SETUP_RUNBOOK.md
- **Sicherheitsaudit:** docs/SICHERHEITSAUDIT.md; Storage-Regeln: `dokumente`, `uebergriffsmeldung-attachments` ergänzt
- **Externes Audit (März 2026):** K4–K6, K8, H1, H3, H4 betreffen `rettbase/` (Legacy, nicht verwendet). H2 behoben. H5 geprüft – `updateMitarbeiterPassword` hat Firmen-Check. Siehe SICHERHEITSAUDIT.md §9.

---

## 21. Einstellungen – bereichsspezifisch (Feb 2026)

### Schulsanitätsdienst
- **Schicht- und Standortverwaltung** in Einstellungen ausgeblendet (bereich == schulsanitaetsdienst)
- Dashboard übergibt `_bereich` an EinstellungenScreen

### Chat-Benachrichtigungen – entfernt
- **Komplett entfernt:** Einstellungen-Karte, Dashboard-Drawer-Eintrag, Chat-Push-Banner
- Kein UI mehr zum Aktivieren/Prüfen von Push-Benachrichtigungen

---

## 22. Firebase-Passwort-Reset-E-Mail

- **Firebase Console** → Authentication → Templates → Passwort zurücksetzen
- **Deutsche Vorlage** mit Link „Passwort jetzt zurücksetzen“ (Bold, zentriert, 14px)
- Platzhalter: %APP_NAME%, %EMAIL%, %LINK%

