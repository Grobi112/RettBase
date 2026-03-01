# RettBase: Telefonliste NFS – Kontext

> Kontextdokument für das Telefonliste-Modul der Notfallseelsorge. Speichert Struktur, Features und Implementierungsdetails für zukünftige Sessions.

## 1. Übersicht

- **Bereich:** `notfallseelsorge`
- **Sichtbarkeit:** Nur bei `bereich == notfallseelsorge` (automatisch freigeschaltet)
- **Datenquelle:** Mitgliederverwaltung – `kunden/{companyId}/mitarbeiter` (kein eigener Firestore-Subpfad)

## 2. Datenfelder

| Feld | Quelle | Anzeige |
|------|--------|---------|
| Nachname | `mitarbeiter.nachname` | Spalte |
| Vorname | `mitarbeiter.vorname` | Spalte |
| Wohnort | `mitarbeiter.ort` | Spalte |
| Telefonnummer | `mitarbeiter.telefon` oder `mitarbeiter.handynummer` | Spalte, tappbar zum Anrufen |

## 3. Rollen und Rechte

| Rolle | Bearbeiten | Lesen | Telefon tappen |
|-------|------------|-------|----------------|
| superadmin, admin, koordinator | ✓ | ✓ | ✓ |
| user | – | ✓ | ✓ |

- **Bearbeiten:** Dialog mit Cloud Function `saveMitarbeiterDoc` (region: europe-west1)
- **User:** Daten über Profil aktualisieren; in der Telefonliste nur lesen + Nummer antippen zum Anrufen

## 4. Sortierung

- **A–Z nach Nachname** (case-insensitive), dann Vorname
- Implementierung in `_filter()`: `filtered.sort((a, b) => nachname.compareTo → vorname.compareTo)`
- Nur aktive Mitarbeiter (`m.active == true`)

## 5. Suche

- Durchsucht: Name (Nachname + Vorname), Wohnort, Telefonnummer
- Case-insensitive, Teilstring-Match
- Suchfeld oben im Screen

## 6. Wichtige Dateien

| Datei | Rolle |
|-------|-------|
| lib/screens/telefonliste_nfs_screen.dart | Hauptscreen, Liste, Suche, Edit-Dialog |
| lib/services/mitarbeiter_service.dart | streamMitarbeiter |
| lib/utils/phone_format.dart | Formatierung der Telefonnummer |
| lib/models/mitarbeiter_model.dart | Mitarbeiter-Modell |

## 7. Technische Details

- **Cloud Function:** `saveMitarbeiterDoc` – speichert Änderungen in `kunden/{companyId}/mitarbeiter/{docId}`
- **Timestamp-Handling:** Vor dem Aufruf werden Firestore-Timestamps in Millisekunden konvertiert (`_prepareForCloudFunction`)

## 8. Layout (responsive)

### Hochformat Handy (Portrait, shortestSide < 600)

- **Gestapeltes Card-Layout** (kein Tabellen-Header)
- **Zeile 1:** Nachname, Vorname (fett, 16px)
- **Zeile 2:** Wohnort – Telefonnummer in einer Ebene
  - Wohnort links (grau, 13px)
  - Trennstrich „-“
  - Telefonnummer rechts mit Telefonhörer-Icon, anklickbar zum Anrufen (Primary-Farbe, unterstrichen)
- Telefonnummer einzeilig: `formatPhoneForDisplaySingleLine()`

### Querformat / Tablet

- **Tabellen-Layout** mit Header (Nachname, Vorname, Wohnort, Tel.Nr.)
- Telefonnummer **einzeilig** (Querformat: `formatPhoneForDisplaySingleLine`)
- Phone (Querformat): kompakte Spalten, Nachname+Vorname kombiniert
- Tablet: breitere Spalten, Nachname und Vorname getrennt

### Telefonformatierung

- `lib/utils/phone_format.dart`:
  - `formatPhoneForDisplay()` – 2 Zeilen (Vorwahl / Durchwahl) für Hochformat
  - `formatPhoneForDisplaySingleLine()` – für Querformat und gestapeltes Layout
