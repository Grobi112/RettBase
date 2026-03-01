# RettBase: Schichtanmeldung & Schichtübersicht – Kontext

> Kontextdokument für Schichtanmeldung und Schichtübersicht. Speichert Design-Regeln, Struktur und Implementierungsdetails für zukünftige Sessions.

## 1. Übersicht

| Feature | Beschreibung |
|---------|--------------|
| **Schichtanmeldung** | Nutzer meldet sich für eine Schicht an (Standort, Schicht, Fahrzeug, Rolle Fahrer/Beifahrer) |
| **Schichtübersicht** | Für Führungskräfte: Wer hat sich wann angemeldet (Standort, Schicht, Kennzeichen, Fahrer, Beifahrer) |

## 2. Schichtübersicht – Anzeige

Die Schichtübersicht gruppiert Anmeldungen nach **Standort → Schicht + Fahrzeug**. Pro Schichtgruppe werden angezeigt:

| Spalte | Inhalt |
|--------|--------|
| **Schicht** | Name der Schicht (z.B. Frühschicht, Spätschicht) |
| **Kennzeichen** | Fahrzeug-Kennzeichen (aus `FahrzeugKurz.kennzeichen` oder `displayName` als Fallback) |
| **Fahrer** | Name(n) der als Fahrer angemeldeten Mitarbeiter |
| **Beifahrer** | Name(n) der als Beifahrer angemeldeten Mitarbeiter |

- Bei `fahrzeugId == 'alle'` oder fehlendem Fahrzeug: Kennzeichen zeigt „–“
- Fahrzeuge werden via `SchichtanmeldungService.loadFahrzeuge(companyId)` geladen
- Kennzeichen-Lookup: `fahrzeugId` → `FahrzeugKurz` (id, kennzeichen, displayName)

## 3. Zugriffsrechte Schichtübersicht

- **Erlaubte Rollen:** superadmin, admin, wachleitung, rettungsdienstleitung, geschaeftsfuehrung, leiterrettungsdienst, leiterssd, koordinator
- **Löschen erlaubt:** superadmin, admin, rettungsdienstleitung, geschaeftsfuehrung, leiterrettungsdienst, leiterssd

## 4. Datenmodell

- **SchichtanmeldungEintrag:** id, datum, wacheId, schichtId, fahrzeugId, mitarbeiterId, rolle (fahrer/beifahrer), taetigkeit
- **FahrzeugKurz:** id, displayName, wache?, kennzeichen?

## 5. Kundentrennung

- **SchichtanmeldungService:** Alle Firestore-Pfade nutzen `_cid(companyId)` (trim, toLowerCase). Keine Fallback-Logik auf andere Kunden – bei neuem Kunden leere Collections.
- **FleetService.loadStandorte():** Company-ID ebenfalls normalisiert.

## 6. Firestore-Struktur

```
kunden/{companyId}/
  schichtanmeldungen/{anmeldungId}
    - datum, wacheId, schichtId, fahrzeugId, mitarbeiterId, rolle, taetigkeit, ...
  fahrzeuge/{fahrzeugId}
    - rufname, kennzeichen, ...
```

## 6. Mitarbeiter-Zuordnung (Mitgliederverwaltung = einzige Quelle)

**Regel:** Nutzer aus der Mitgliederverwaltung (`kunden/{companyId}/mitarbeiter`) können überall zugreifen – ohne separaten Eintrag in `schichtplanMitarbeiter`.

- **loadSchichtplanMitarbeiter:** Merge aus `schichtplanMitarbeiter` + `mitarbeiter` (aktive)
- **findMitarbeiterByEmail/ByUid:** Fallback auf `mitarbeiter`, wenn nicht in `schichtplanMitarbeiter`
- **getSchichtplanMitarbeiterById:** Fallback auf `mitarbeiter`, wenn nicht in `schichtplanMitarbeiter`
- **Schichtplan NFS:** Nutzt bereits `mitarbeiter`; Fallbacks für E-Mail/Pseudo-E-Mail und UID ergänzt

## 8. Wichtige Dateien

| Datei | Rolle |
|-------|-------|
| lib/screens/schichtanmeldung_screen.dart | Formular: Schicht anmelden, Fahrzeug wählen |
| lib/screens/schichtuebersicht_screen.dart | Übersicht für Führungskräfte: Standort, Schicht, Kennzeichen, Fahrer, Beifahrer |
| lib/services/schichtanmeldung_service.dart | loadStandorte, loadSchichten, loadFahrzeuge, loadSchichtanmeldungenForDateRange, SchichtanmeldungEintrag, FahrzeugKurz, Mitarbeiter-Fallbacks |
| lib/services/schichtplan_nfs_service.dart | NFS: loadMitarbeiter aus mitarbeiter, findMitarbeiterBy* mit Fallbacks |
