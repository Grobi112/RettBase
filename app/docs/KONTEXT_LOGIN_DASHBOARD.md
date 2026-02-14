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
| `lib/screens/dashboard_screen.dart` | _load, Menü, Shortcuts, Begrüßung |
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

## 6. Hinweis zu Firestore-Daten

Die **tatsächlichen Inhalte** von Firestore (Dokumente, Werte) sind nicht in diesem Repo. Bei Problemen:
- Struktur und Pfade aus Code/ diesem Doc ableiten
- Konkrete Kunden-IDs/Probleme in der Anfrage nennen
