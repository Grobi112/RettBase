# RettBase Native App – Alle Erinnerungen

> Zentrales Kontextdokument: Wie die Flutter-App funktioniert und was bei Änderungen zu beachten ist.

---

## 1. Projekt-Fokus

- **Nur Flutter-App** (`app/`) wird weiterentwickelt
- **rettbase/** (standalone JS/HTML-Web-App) wird **nicht mehr** verwendet – ignorieren
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

### App-Start (main.dart)
- Bei geladenem Cache: `kundeExists(companyId)` aufrufen
- Wenn `docId != companyId`: Cache mit docId aktualisieren, an LoginScreen übergeben

### LoginService
- Fallback: Mitarbeiter nicht gefunden → `kundeExists` → Suche mit docId erneut
- Verwendet `pseudoEmail` aus Mitarbeiter-Doc, falls vorhanden
- Rückgabe: `effectiveCompanyId` (docId, wo Mitarbeiter gefunden wurde)

### LoginScreen
- Übergibt `effectiveCompanyId` ans Dashboard
- Aktualisiert SharedPreferences bei abweichender Company-ID

### AuthDataService
- Suche nach `personalnummer` als Fallback (zusätzlich zu uid, email, pseudoEmail)
- Erweiterte `altEmail`-Suche auch bei vorhandenem Doc (kundenId/subdomain)
- `vorname`/`nachname` in users-Doc für Admin-Anzeige

### Mitgliederverwaltung
- `saveUsersDoc`: schreibt `vorname`/`nachname` mit (für DisplayName)

### getCompanyBereich
- Fallback per `kundenId`/`subdomain` auch wenn Doc existiert aber `bereich` fehlt

### Einzige Login-Logik (Web + Native identisch)
- **Superadmin:** `112@admin.rettbase.de` – Nutzer existiert in rett-fe0fa
- **Andere Kunden:** E-Mail oder Personalnummer → Suche in `kunden/{companyId}/mitarbeiter`, Anmeldung mit echter E-Mail oder Pseudo-E-Mail `{personalnummer}@{companyId}.rettbase.de`
- Bei Login-Fehler auf Web: Authorized Domains / API-Key prüfen, nicht „Nutzer anlegen“

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
| **Schichtplan NFS** | `notfallseelsorge` | `schichtplanNfsStandorte`, `schichtplanNfsBereitschaftsTypen`, `schichtplanNfsMitarbeiter`, `schichtplanNfsBereitschaften/{dayId}/bereitschaften` |

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
- **Nur Web:** `firebase_options.dart` → web; Auth-Bridge (module_webview_widget, webview_screen)
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
| Cloud Functions | `functions/index.js` (kundeExists, saveMitarbeiterDoc, saveUsersDoc) |

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
- **Splash:** `height: narrow ? 100 : 140` (MediaQuery.width < 400 = narrow)
- **Login & Kunden-ID:** `height: Responsive.isCompact(context) ? 100 : 140`

### Hintergrund
- **Alle drei Screens:** `AppTheme.headerBg` (#1E1F26) – einheitlich

### Dateien
- `lib/screens/splash_screen.dart`, `lib/screens/login_screen.dart`, `lib/screens/company_id_screen.dart`

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
- Schulsanitäter/in 1: Name
- Einsatzort
- Patientendaten: Vorname, Name, Klasse (Geburtsdatum optional)
- Art des Vorfalls: mind. 1 Checkbox (Erkrankung/Unfall) + ggf. Zusatzfeld
- „Was hat der Verletzte gemacht“: mind. 1 Checkbox
- Erstbefund: Atmung (mind. 1), Puls, SpO2
- „Klagt über“: Pflichtfeld
- Getroffene Maßnahmen: mind. 1 (ohne Notruf/Eltern benachrichtigt)
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
| Einsatzprotokoll Service | `einsatzprotokoll_ssd_service.dart` |
| Logo/ Splash | `splash_screen.dart`, `img/rettbase_splash.png` |

