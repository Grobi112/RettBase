# RettBase: Mitarbeiterverwaltung – Kontext

> Kontextdokument für die Mitarbeiterverwaltung (Mitgliederverwaltung). Speichert Struktur, Features und Implementierungsdetails für zukünftige Sessions.

## 1. Übersicht

- **Zweck:** Zentrale Stammdatenverwaltung für alle Mitarbeiter eines Kunden. Voraussetzung für Login, Rollen und Zugriff.
- **Zugriff:** Nur Superadmin, Admin, LeiterSSD (Rettungsdienst) bzw. Superadmin, Admin, Koordinator (Notfallseelsorge)
- **Einstieg:** Dashboard → Modul „Mitgliederverwaltung“ / „Mitarbeiterverwaltung“
- **Datenquelle:** `kunden/{docId}/mitarbeiter` – **immer docId** nutzen, nicht kundenId (Umbenennungsfall)

## 2. Firestore-Struktur

```
kunden/{docId}/mitarbeiter/{mitarbeiterDocId}
  - uid, personalnummer, vorname, nachname, role
  - email, pseudoEmail (z.B. {pn}@{companyId}.rettbase.de)
  - telefon, handynummer, strasse, hausnummer, plz, ort
  - fuehrerschein, qualifikation (RH, RS, RA, NFS), angestelltenverhaeltnis
  - geburtsdatum, active, createdAt, updatedAt

kunden/{docId}/users/{uid}
  - email, role, mitarbeiterDocId, vorname, nachname, status
  - (Admin-Superadmins auch ohne Mitarb.-Doc möglich)
```

## 3. Rollen und Rechte

### Rettungsdienst
- **Rollen:** user, ovd, wachleitung, leiterssd, supervisor, admin
- **Neuanlage:** LeiterSSD, Admin, Superadmin
- **Löschen:** nur Admin, Superadmin

### Notfallseelsorge
- **Rollen:** user, koordinator, admin
- **Neuanlage:** Koordinator, Admin, Superadmin
- **Löschen:** nur Admin, Superadmin

### Admin-Firma
- Zusätzliche Rolle: **superadmin**
- Superadmin darf nicht gelöscht werden

## 4. Formular – bereichsspezifisch

### Alle Bereiche (gemeinsame Felder)
- Personalnummer, E-Mail
- Vorname, Nachname
- Geburtsdatum
- Straße, Hausnummer, PLZ, Ort
- Telefon
- Rolle, Aktiv
- Passwort (bei Anlage bzw. optional bei Bearbeitung)

### Nur Rettungsdienst (nicht NFS/SSD)
- **Führerscheinklasse** (Dropdown)
- **Qualifikation** (RH, RS, RA, NFS)
- **Vertrag** (Vollzeit, Teilzeit, GfB, Ausbildung, Ehrenamt)

### Notfallseelsorge & Schulsanitätsdienst
- Führerscheinklasse, Qualifikation, Vertrag werden **ausgeblendet**
- Beim Speichern: diese Felder werden auf `null` gesetzt

## 5. Cloud Functions (functions/index.js)

| Funktion | Region | Beschreibung |
|----------|--------|--------------|
| createAuthUser | europe-west1 | Legt Firebase-Auth-User an (Admin/Superadmin/LeiterSSD) |
| updateMitarbeiterPassword | europe-west1 | Setzt Passwort (uid oder email) |
| saveMitarbeiterDoc | europe-west1 | Schreibt Änderungen in mitarbeiter (umgeht Firestore-Regeln) |
| createMitarbeiterDoc | europe-west1 | Legt neues Mitarbeiter-Dokument an |
| deleteMitarbeiterFull | europe-west1 | DSGVO-vollständige Löschung (Auth, mitarbeiter, users, userTiles, FCM, Profil-Fotos, Schichtplan-Einträge) |
| saveUsersDoc | europe-west1 | Schreibt users-Dokument (für Admin/fromUsersOnly) |

## 6. Funktionen der Mitarbeiterverwaltung

1. **Liste:** Suche nach Name, E-Mail, Qualifikation, Personalnummer
2. **Anlegen:** Formular mit Validierung (Personalnummer oder E-Mail Pflicht; Eindeutigkeit)
3. **Bearbeiten:** Änderung aller Stammdaten
4. **Aktivieren/Deaktivieren:** Toggle für `active`
5. **Passwort setzen:** Für E-Mail oder Personalnummer; optional Auth-User anlegen
6. **Löschen:** Nur Admin/Superadmin; Superadmin-Rolle nicht löschbar; `deleteMitarbeiterFull` für DSGVO-Löschung

## 7. Wichtige Dateien

| Datei | Rolle |
|-------|-------|
| lib/screens/mitarbeiterverwaltung_screen.dart | Hauptscreen, Liste, Formular, Anlegen/Bearbeiten/Löschen |
| lib/services/mitarbeiter_service.dart | loadMitarbeiter, streamMitarbeiter, updateMitarbeiterFields, createMitarbeiter |
| lib/models/mitarbeiter_model.dart | Mitarbeiter-Modell, fromFirestore, toFirestore, fromUsersDoc |

## 8. Abhängigkeiten

- **Login:** `resolveLoginInfo` prüft Mitarbeiterverwaltung; ohne Eintrag kein Login (außer Superadmin 112@admin.rettbase.de, admin@rettbase.de)
- **Telefonliste NFS:** nutzt `streamMitarbeiter`, `saveMitarbeiterDoc` für Bearbeitung
- **Schichtplan NFS:** `loadMitarbeiter` aus mitarbeiter, Kopie in schichtplanNfsMitarbeiter, Zuordnung per E-Mail/UID

## 9. Technische Details

- **Bereich:** Wird vom Dashboard als `bereich` übergeben; steuert Rollen und Formularfelder
- **Admin-Sonderfall:** Bei companyId='admin' und leerer mitarbeiter-Liste werden users-Docs als Mitarbeiter angezeigt (`fromUsersOnly`)
- **Pseudo-E-Mail:** `{personalnummer}@{companyId}.rettbase.de` für Login ohne echte E-Mail
