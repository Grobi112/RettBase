# RettBase: Einsatzprotokoll NFS – Kontext

> Kontextdokument für das Einsatzprotokoll-Modul der Notfallseelsorge. Speichert Struktur, Features und Implementierungsdetails für zukünftige Sessions.

## 1. Übersicht

- **Modul-ID:** `einsatzprotokollnfs`
- **Titel (sichtbar):** „Einsatzprotokoll Notfallseelsorge“
- **Bereich:** `notfallseelsorge`
- **Sichtbarkeit:** Nur wenn Firma „admin“ das Modul freischaltet und ins Menü einpflegt (kein Auto-Enable)
- **4 Bereiche:** Einsatzdaten, Einsatzbericht, Einsatzverlauf, Sonstiges (auf-/zuklappbar)

## 2. Firestore-Struktur

```
kunden/{companyId}/
  einsatzprotokoll-nfs/           # Protokolle
  einsatzprotokoll-nfs-zähler/    # Zähler pro Jahr für laufende interne Nr.
    {Jahr}/                       # z.B. "2026" mit lastNumber
```

**Firestore-Regeln:** Einsatzprotokoll-nfs: create, read, delete – **kein update** (laufendeInterneNr unveränderbar).

## 3. Screens und Services

| Screen/Service | Datei | Funktion |
|----------------|-------|----------|
| EinsatzprotokollNfsScreen | einsatzprotokoll_nfs_screen.dart | Formular mit 4 Bereichen |
| EinsatzprotokollNfsDruckScreen | einsatzprotokoll_nfs_druck_screen.dart | PDF-Vorschau, Drucken, Teilen, Löschen |
| EinsatzprotokollNfsEinstellungenScreen | einsatzprotokoll_nfs_einstellungen_screen.dart | Einstellungen (Zahnrad) |
| EinsatzprotokollNfsUebersichtScreen | einsatzprotokoll_nfs_uebersicht_screen.dart | Protokollübersicht mit Filter |
| EinsatzprotokollNfsService | einsatzprotokoll_nfs_service.dart | create, getNextLaufendeInterneNr, streamProtokolle, delete |

## 4. Bereich „Einsatzdaten“

**Linke Spalte (breite Ansicht ≥600px):**
- Laufende interne Nr. (read-only, disabled, Format YYYYNNNN z.B. 20260001 – wird beim Formular-Load reserviert)
- Vor- und Nachname (read-only, Vorname zuerst)
- Alarmierung durch: Koordinator, sonstige (Checkboxen)
- Einsatzindikation (Dropdown)
- Einsatz im: öffentlicher Bereich, privater Bereich (Checkboxen)
- Wurden NFS nachalarmiert?: Ja, Nein (Checkboxen, Pflichtfeld)
- Bei Ja: Label „Namen der nachalarmierten NFS eingeben“ über Textfeld

**Rechte Spalte:**
- Einsatz-Datum, Einsatz-Nr., Alarmierungszeit, Eintreffen, Abfahrt, Einsatzende
- Einsatzdauer (HH.MM, berechnet), Gefahrene KM

**Laufende interne Nr.:**
- Format: YYYYNNNN (z.B. 20260001)
- Neues Jahr → Zähler bei 0001
- Beim Formular-Öffnen wird nächste Nr. geladen und angezeigt
- Nicht änderbar (enabled: false, Firestore: kein update)

## 5. Bereich „Einsatzbericht“

- Situation vor Ort
- Meine Rolle / Aufgabe
- Weitere Betreuung durch (Dropdown, mit „sonstiges“-Feld)

## 6. Bereich „Einsatzverlauf“

- Verlauf der Begleitung
- Weitere Betreuung durch (Dropdown)
- Situation am Ende vor Ort
- Wurden weitere Dienste in den Einsatz einbezogen?: Ja/Nein (Checkboxen)
- Bei Ja: Textfeld rechts neben Checkboxen, hintText „Namen der Dienste“

## 7. Bereich „Sonstiges“

- Was ist interessant für eine Fallbesprechung?
- Ist eine gesonderte Einsatznachbesprechung gewünscht? (Dropdown, mit „sonstiges“-Feld)

## 8. PDF-Ansicht

- Einsatzdaten: Laufende interne Nr., Vor- und Nachname, Alarmierung durch (Wert), Einsatzindikation, Einsatz im (Wert), NFS nachalarmiert (Ja/Nein, bei Ja mit Namen)
- Einsatzbericht, Einsatzverlauf, Sonstiges
- Zeichen-Sanitisierung: problematische Unicode-Zeichen (☒, –, etc.) durch `-` ersetzen (pdf-zeichen-sanitisierung.mdc)
- Kein „Erstellt von“ (Name steht oben)

## 9. Integration

| Stelle | Anpassung |
|--------|-----------|
| modules_service.dart | Modul `einsatzprotokollnfs` |
| dashboard_screen.dart | Route für `einsatzprotokollnfs` |
| menueverwaltung_screen.dart | Modul für Notfallseelsorge-Menü |
| modulverwaltung_screen.dart | Modul in der Modulverwaltung |

## 10. Wichtige Dateien

| Datei | Rolle |
|-------|-------|
| lib/screens/einsatzprotokoll_nfs_screen.dart | Formular |
| lib/screens/einsatzprotokoll_nfs_druck_screen.dart | PDF |
| lib/screens/einsatzprotokoll_nfs_einstellungen_screen.dart | Einstellungen |
| lib/screens/einsatzprotokoll_nfs_uebersicht_screen.dart | Übersicht |
| lib/services/einsatzprotokoll_nfs_service.dart | Firestore-Service |
| firestore.rules | Regeln für einsatzprotokoll-nfs (kein update) |
| .cursor/rules/pdf-zeichen-sanitisierung.mdc | PDF-Zeichen ersetzen |
