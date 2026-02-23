# RettBase: Schichtplan NFS – Kontext

> Kontextdokument für das Schichtplan-Modul der Notfallseelsorge. Speichert Struktur, Features und Implementierungsdetails für zukünftige Sessions.

## 1. Übersicht

- **Bereich:** `notfallseelsorge`
- **Sichtbarkeit:** Nur bei `bereich == notfallseelsorge` (automatisch freigeschaltet)
- **Reiter:** „Monat“ (Monatsübersicht), „Meldungen“ (nur Admin/Koordinator/Superadmin)

## 2. Firestore-Struktur

```
kunden/{companyId}/
  schichtplanNfsStandorte/          # Standorte (name, order, active)
  schichtplanNfsBereitschaftsTypen/  # S1, S2, B etc. (name, color, beschreibung)
  schichtplanNfsMitarbeiter/         # Kopie aus mitarbeiter (mit Standort)
  schichtplanNfsMeldungen/           # Pending-Meldungen (Verfügbarkeit angeben)
  schichtplanNfsStundenplan/{dayId}  # dayId = DD.MM.YYYY, eintraege: { mitarbeiterId_stunde: typId }
  schichtplanNfsBereitschaften/{dayId}/bereitschaften/  # Legacy/alternativ
```

## 3. Screens und Komponenten

| Screen/Widget | Datei | Funktion |
|---------------|-------|----------|
| SchichtplanNfsScreen | schichtplan_nfs_screen.dart | Tab-Container (Monat, Meldungen) |
| SchichtplanNfsMonatsuebersichtBody | schichtplan_nfs_stundenplan_screen.dart | Kalender-Grid, Tag-Status (rot/grün/neutral) |
| SchichtplanNfsSchichtenScreen | schichtplan_nfs_schichten_screen.dart | Tagesansicht: Stundenübersicht + Eingesetzte Mitarbeiter |
| SchichtplanNfsMeldungenBody | schichtplan_nfs_meldungen_body.dart | Pending-Meldungen annehmen/ablehnen |
| SchichtplanNfsService | schichtplan_nfs_service.dart | Firestore-Operationen |

## 4. Monatsübersicht

- **Tag-Status:** `loadTageStatusForMonth` → rot = offene Stunden, grün = alle mit S1 belegt, neutral = sonst
- **Keine Schichttypen-Badges** in den Tageszellen (nur Tag-Nummer + Status-Farbe)
- Zellenhöhe: 44 px
- Klick auf Tag → SchichtplanNfsSchichtenScreen

## 5. Stundenübersicht (Tagesansicht)

- **24 Stunden-Chips** (00:00–01:00 bis 23:00–24:00)
- **Farben:** Rot = frei, Grün = S1 belegt, Grau = andere Typen
- **Kreise pro Stunde:** Anzahl pro Bereitschaftstyp (S1, S2, B, …)
  - Kreise in Typ-Farbe, weiße Zahl innen
  - 1–3 Typen: eine Zeile
  - 4+ Typen: zwei Zeilen (max. 3 Kreise pro Zeile)
- **Einheitliche Kartenhöhe:** 68 px für alle Chips
- **Datum:** Hinter „Stundenübersicht“ (nicht im AppBar-Header) – responsive
- **AppBar-Titel:** Nur „Schichten“ (ohne Datum)
- Zeit-Beschriftung: 13 px

## 6. Bereitschaftstypen

- **SchichtplanNfsBereitschaftstypUtils:** Farben S1 (grün), S2 (amber), B (lila)
- **Firestore-Farbe:** `color` (0xFFRRGGBB) überschreibt Standard
- Reihenfolge: S1, S2, B, dann alphabetisch

## 7. Mitarbeiter-Datenblatt

- **Pseudo-Email nicht anzeigen:** Wenn E-Mail mit `.rettbase.de` endet → „—“ statt anzeigen
- Zeigt nur echte, vom Nutzer hinterlegte Werte (E-Mail, Telefon, Ort)

## 8. Wichtige Dateien

| Datei | Rolle |
|-------|-------|
| lib/screens/schichtplan_nfs_screen.dart | Tab-Container, Reiter-Logik |
| lib/screens/schichtplan_nfs_stundenplan_screen.dart | Monatsübersicht, Bereitschaftsplan |
| lib/screens/schichtplan_nfs_schichten_screen.dart | Tagesansicht, Stunden-Chips, Mitarbeiter-Karten |
| lib/screens/schichtplan_nfs_meldungen_body.dart | Meldungen annehmen/ablehnen |
| lib/screens/schichtplan_nfs_schicht_anlegen_sheet.dart | Schicht anlegen |
| lib/screens/schichtplan_nfs_offene_schicht_melden_sheet.dart | Verfügbarkeit angeben |
| lib/services/schichtplan_nfs_service.dart | Firestore, loadStundenplanEintraege, loadTageStatusForMonth |
| lib/utils/schichtplan_nfs_bereitschaftstyp_utils.dart | Farben, filterAndSortS1S2B |

## 9. Firestore-Schreiblogik (wichtig)

**`schichtplanNfsStundenplan/{dayId}`:** Einträge werden mit `set()` **ohne** `SetOptions(merge: true)` geschrieben.

- **Ursache früherer Bugs:** Bei `merge: true` werden Map-Felder rekursiv gemerged – entfernte Keys werden **nicht** gelöscht, sondern bleiben erhalten.
- **Lösung:** `set(data)` ohne merge – das Dokument wird vollständig ersetzt, gelöschte Einträge verschwinden tatsächlich aus der DB.
- **Betroffene Methoden:** `deleteStundenplanEintraegeForMitarbeiter`, `deleteStundenplanEintraegeForMitarbeiterStunden`, `saveStundenplanEintrag`, `saveStundenplanEintraegeBatch`
- **Commit:** 08db50f

## 10. Letzte Änderungen (Feb 2026)

- Monatsübersicht: Schichttypen-Badges entfernt, nur Tag + Status
- Stundenübersicht: Kreise mit Farben/Anzahl pro Bereitschaftstyp pro Stunde
- 2 Zeilen für Kreise bei 4+ Typen, einheitliche Kartenhöhe 68 px
- Datum hinter „Stundenübersicht“ statt im Header (responsive)
- Größere Zeit-Beschriftung (13 px)
- Pseudo-Email nicht im Mitarbeiter-Datenblatt anzeigen
- TagStatusMitTypCounts in schichtplan_nfs_service (wird für Monat nicht mehr genutzt, Service behält Struktur)
- **Fix Löschen:** Firestore `set()` ohne merge – gelöschte Schichten werden dauerhaft aus DB entfernt (Commit 08db50f)
- **Performance:** Parallele Firestore-Operationen (Future.wait) – Monatsübersicht, Tagesansicht, Schicht anlegen, Bearbeiten, Meldungen annehmen (Commit d8369b4)

## 11. Performance-Optimierungen (Commit d8369b4)

- **loadTageStatusForMonth:** Alle Tage parallel statt 28–31 sequentielle Reads
- **loadTageMitEintraegen:** Parallele Reads
- **SchichtenScreen _load:** typen, mitarbeiter, eintraege parallel
- **SchichtAnlegenSheet:** Load (typen, mitarbeiter, eintraege pro Tag) und Save (alle Tage) parallel
- **Bearbeiten-Dialog:** saveStundenplanEintraegeBatch pro Tag statt saveStundenplanEintrag pro Stunde; alle Tage parallel
- **acceptMeldung:** Alle Tage parallel speichern
