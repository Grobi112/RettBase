# Sicherheitsaudit RettBase Flutter-App

Stand: Februar 2026

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

- `dokumente_service.dart` nutzt `file.path.split(RegExp(r'[/\\]')).last` – nur Dateiname, kein Pfad-Escape.
- Firebase Storage behandelt `..` in Pfadsegmenten als Literal, kein Directory-Traversal.

---

## 7. Zusammenfassung der durchgeführten Korrekturen

1. **Storage-Regeln:** Pfade `dokumente` und `uebergriffsmeldung-attachments` ergänzt – Uploads waren zuvor durch Catch-all blockiert.

---

## 8. Empfohlene nächste Schritte

1. **App Check** – aktuell nicht verwendet; Rate-Limit (5/min) reicht aus
2. **API-Key-Einschränkung** in der Google Cloud Console – siehe **`SICHERHEIT_SETUP_RUNBOOK.md`**; SHA-1 per `scripts/get_android_sha1.sh`
3. Regelmäßige Überprüfung der Firestore-/Storage-Regeln bei neuen Collections/Pfaden
