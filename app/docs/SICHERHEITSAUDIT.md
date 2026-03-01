# Sicherheitsaudit RettBase Flutter-App

Stand: März 2026 (Commit 0436b75: Audit-Fixes, rettbase/ entfernt)

## Übersicht

Dieses Dokument fasst das Ergebnis der Sicherheitsüberprüfung des Projekts zusammen.

---

## 1. Firestore-Regeln

**Status: ✅ Abgesichert**

- **Kein Fallback-Regel:** Nicht abgedeckte Pfade werden verweigert (kein `match /{document=**} allow read` mehr).
- **Collection-Group-Regeln entfernt** – verhindert Queries über Firmengrenzen hinweg.
- **`kunden/{kundenId}/**`:** Zugriff nur mit `canAccessCompany(kundenId)` (Nutzer in `users` oder Superadmin).
- **`settings/**`:** Lesen für eingeloggte Nutzer; Schreiben nur für Superadmin (`isSuperadmin()`).

---

## 2. Storage-Regeln

**Status: ✅ Abgesichert (nach Korrektur)**

- **Company-Prüfung:** Über Custom Claims (`companyId`, `superadmin`), gesetzt von `ensureUsersDoc` nach Login.
- **Abgedeckte Pfade:**
  - `profile-images`, `email-attachments`, `chat-attachments`
  - `maengel-attachments`, `unfallbericht-attachments`, `einsatzprotokoll-ssd`
  - `dokumente` (ergänzt – fehlte zuvor)
  - `uebergriffsmeldung-attachments` (ergänzt – fehlte zuvor)
- **Catch-all:** `match /{allPaths=**} allow read, write: if false`

---

## 3. Cloud Functions

### 3.1 Authentifizierung & Autorisierung

| Function | Schutz |
|----------|--------|
| `kundeExists` | Rate-Limit (5/min), keine Auth nötig (Pre-Login) |
| `resolveLoginInfo` | Rate-Limit (5/min), keine Auth nötig (Pre-Login) |
| `exchangeToken` | `context.auth` oder `idToken`-Verifizierung |
| `createAuthUser` | `_requireAdminRole(companyId)` |
| `updateMitarbeiterPassword` | `_requireAdminRole(companyId)` + Prüfung, ob Zielnutzer in company |
| `saveMitarbeiterDoc` / `saveUsersDoc` | `_requireAdminRole(companyId)` |
| `deleteMitarbeiterFull` | `_requireAdminRole(companyId)` |
| `loadKunden` | `_requireSuperadminRole()` |
| `ensureUsersDoc` | Nutzer muss in `mitarbeiter` der Firma sein (oder Superadmin) |

### 3.2 Enumerationsschutz

- `kundeExists` und `resolveLoginInfo`: **Rate-Limit 5 Aufrufe/Minute pro IP**
- Optional: **Firebase App Check** (siehe `SICHERHEIT_API_KEYS_APP_CHECK.md`)

### 3.3 Bekannte Einschränkungen (niedriges Risiko)

- **createAuthUser:** Der Admin kann theoretisch Auth-Nutzer für beliebige E-Mails anlegen (nicht explizit in `mitarbeiter` validiert). Risiko: Niedrig – nur Admin-Rolle; der so erstellte Nutzer kann ohne passenden Mitarb.-Eintrag nicht sinnvoll einloggen.

---

## 4. Auth-Bridge / Webview

**Status: ✅ Abgesichert**

- **Kein Passwort im HTML:** Credentials bleiben in Flutter; `exchangeToken` liefert Custom-Token; `auth-callback.html` nutzt nur Token in der URL.
- **XSS-Fix:** `auth-callback.html` verwendet `textContent` statt `innerHTML` für Fehlermeldungen.
- Keine `innerHTML`/`eval`-Verwendung in `app/lib`.

---

## 5. API-Keys / VAPID-Key

**Status: ⚠️ Üblich, Konfiguration empfohlen**

- Firebase API-Keys und VAPID-Key in `firebase_options.dart` / `app_config.dart` sind clientseitig sichtbar – das ist bei Firebase üblich.
- **Empfehlung:** Einschränkung in Google Cloud Console (HTTP-Referrer, Paketname, Bundle-ID) wie in `SICHERHEIT_API_KEYS_APP_CHECK.md` dokumentiert.

---

## 6. Storage-Pfade (Path Traversal)

**Status: ✅ Unkritisch**

- `dokumente_service.dart` nutzt `fileName.split(RegExp(r'[/\\]')).last` – nur Dateiname, kein Pfad-Escape (Path-Traversal-Schutz).
- Firebase Storage behandelt `..` in Pfadsegmenten als Literal, kein Directory-Traversal.

---

## 7. Zusammenfassung der durchgeführten Korrekturen

1. **Storage-Regeln:** Pfade `dokumente` und `uebergriffsmeldung-attachments` ergänzt – Uploads waren zuvor durch Catch-all blockiert.
2. **Path-Traversal-Schutz:** `dokumente_service.uploadDokument` nutzt `fileName.split(RegExp(r'[/\\]')).last` – nur Dateiname im Storage-Pfad (März 2026).
3. **H2 Superadmin-Regex-Bypass:** Nur exakte E-Mail-Domains (`admin@rettbase.de`, `admin@rettbase`, `112@admin.rettbase.de`) – kein `contains('rettbase')` mehr (März 2026).
4. **K7 Root firestore.rules:** `menus` erfordert jetzt `request.auth != null` (März 2026).

---

## 8. Sicherheitsrelevante Lücken (Abfrage Feb 2026)

### 8.1 Geprüft – unkritisch

| Bereich | Status | Hinweis |
|---------|--------|---------|
| **Firestore-Regeln** | ✅ | `canAccessCompany` verhindert IDOR; kein Fallback |
| **Storage-Regeln** | ✅ | Company-Claims; Catch-all blockiert unbekannte Pfade |
| **Cloud Functions** | ✅ | Rate-Limit, Admin-Checks; keine Auth bei Pre-Login nötig |
| **XSS** | ✅ | Kein `innerHTML`/`eval` in `app/lib` |
| **Path Traversal** | ✅ | Dokumente-Service nutzt nur Dateiname |
| **Debug-Logs** | ✅ | Keine Passwörter; E-Mail/CompanyId nur in kDebugMode |
| **SharedPreferences** | ✅ | Nur Company-ID, keine Passwörter; unverschlüsselt, aber geringes Risiko |

### 8.2 Bekannte Schwachstellen (niedriges Risiko)

| Lücke | Risiko | Empfehlung |
|-------|--------|------------|
| **API-Keys/VAPID clientseitig** | Niedrig | Üblich bei Firebase. Einschränkung in Google Cloud Console empfohlen (siehe Abschnitt 5). |
| **createAuthUser ohne Mitarb.-Check** | Niedrig | Admin kann Auth-Nutzer anlegen; ohne Mitarb.-Eintrag kein sinnvoller Login (siehe 3.3). |

### 8.3 Nach Lade-Optimierung (Login → Dashboard)

- **ensureUsersDoc im Hintergrund:** Login navigiert sofort; `ensureUsersDoc` läuft asynchron. Das Dashboard ruft `ensureUsersDoc` in `_load` erneut auf. Theoretische Race: Wenn beide parallel laufen, kann einer zuerst fertig sein – unkritisch, da idempotent.
- **EnsureUsersDocCache:** Verhindert doppelte Aufrufe innerhalb von 15 s. Kein Sicherheitsrisiko.

### 8.4 Sicherheitstest (aktuelle Prüfung)

| Prüfung | Ergebnis | Details |
|---------|----------|---------|
| **Hardcoded Credentials** | ✅ | Keine Passwörter/Secrets im Code; API-Keys nur Firebase (üblich) |
| **XSS** | ✅ | Kein `innerHTML`/`eval` in `app/lib` |
| **Path Traversal (Upload)** | ✅ | `dokumente_service.dart` nutzt `fileName.split(RegExp(r'[/\\]')).last` – nur Dateiname, kein Pfad-Escape (Korrektur März 2026) |
| **IDOR** | ✅ | Firestore/Storage-Regeln prüfen `canAccessCompany` |
| **Debug-Logs** | ✅ | Keine Passwörter; sensible Daten nur in `kDebugMode` |
| **URL-Handling** | ✅ | `launchUrl`/`canLaunchUrl` für externe Links; `doc.fileUrl` aus eigenem Storage |
| **Input-Validierung** | ✅ | Company-ID, Kunden-ID: `RegExp`-Filter; Telefonnummern bereinigt |
| **Passwort-Übertragung** | ✅ | Nur an Firebase Auth; keine Weitergabe an Dritte |

### 8.5 Empfohlene nächste Schritte

1. **App Check** – aktuell nicht verwendet; Rate-Limit (5/min) reicht aus
2. **API-Key-Einschränkung** in der Google Cloud Console – siehe **`SICHERHEIT_SETUP_RUNBOOK.md`**; SHA-1 per `scripts/get_android_sha1.sh`
3. ~~**fileName-Sanitisierung**~~ ✅ Erledigt: `dokumente_service.uploadDokument` nutzt `fileName.split(RegExp(r'[/\\]')).last`
4. Regelmäßige Überprüfung der Firestore-/Storage-Regeln bei neuen Collections/Pfaden

---

## 9. Externes Audit – Zuordnung (März 2026)

Externes Sicherheitsaudit hat u.a. K1–K8, H1–H8 identifiziert. **Wichtig:** Die Flutter-App nutzt ausschließlich `app/`; `rettbase/` wurde März 2026 entfernt (Legacy-Code).

### 9.1 rettbase/ – Legacy, nicht relevant

| ID | Thema | Datei | Status |
|----|-------|-------|--------|
| K4 | Unauthentifizierter Lesezugriff mitarbeiter | rettbase/firestore.rules | `rettbase/` nicht verwendet; `app/firestore.rules` hat `canAccessCompany` |
| K5 | Cross-Company Datenzugriff | rettbase/firestore.rules | `rettbase/` nicht verwendet; `app/firestore.rules` hat `canAccessCompany` |
| K6 | Storage ohne Firmen-Check | rettbase/storage.rules | `rettbase/` nicht verwendet; `app/storage.rules` hat `canAccessCompany` |
| K8 | TLS rejectUnauthorized: false | rettbase/module/office/functions | `rettbase/` nicht verwendet |
| H1 | tempPassword in Firestore | rettbase/auth.js | `rettbase/` nicht verwendet; Flutter nutzt nur Firebase Auth |
| H3 | postMessage Wildcard-Origin | rettbase/dashboard.js | `rettbase/` nicht verwendet |
| H4 | Sensible Daten im localStorage | rettbase/dashboard.js | `rettbase/` nicht verwendet |

### 9.2 app/ – bereits behoben

| ID | Thema | Status |
|----|-------|--------|
| H2 | Superadmin-Regex-Bypass (admin@evil-rettbase.com) | ✅ Behoben: Nur exakte `admin@rettbase.de`, `admin@rettbase`, `112@admin.rettbase.de` |

### 9.3 app/ – geprüft, unkritisch

| ID | Thema | Status |
|----|-------|--------|
| H5 | IDOR bei Passwort-Reset (Cross-Company) | ✅ `updateMitarbeiterPassword` prüft: `_requireAdminRole(companyId)` + Zielnutzer muss in `kunden/{cid}/users` oder `mitarbeiter` sein |

### 9.4 WebView / Custom-Links

- **WebView** wird nur für Custom-Links (type: `custom` im Menü) genutzt; derzeit keine Custom-Links aktiv.
- Code bleibt erhalten für kundenspezifische Links (z.B. externe Module).
- K3 (Token in URL): Nur relevant, wenn Custom-Links aktiviert werden – Token ist kurzlebig und einmalig.
