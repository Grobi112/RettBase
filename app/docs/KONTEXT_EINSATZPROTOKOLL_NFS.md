# RettBase: Einsatzprotokoll NFS – Kontext

> Kontextdokument für das Einsatzprotokoll-Modul der Notfallseelsorge. Speichert Struktur, Features und Implementierungsdetails für zukünftige Sessions.

## 1. Übersicht

- **Modul-ID:** `einsatzprotokollnfs`
- **Titel (sichtbar):** „Einsatzprotokoll Notfallseelsorge“
- **Bereich:** `notfallseelsorge`
- **Sichtbarkeit:** Nur wenn Firma „admin“ das Modul freischaltet und ins Menü einpflegt (kein Auto-Enable wie Schichtplan/Telefonliste)
- **4 Bereiche:** Einsatzdaten, Einsatzbericht, Einsatzverlauf, Sonstiges (auf-/zuklappbar wie Einsatzprotokoll SSD)

## 2. Firestore-Struktur

```
kunden/{companyId}/
  einsatzprotokoll-nfs/   # Protokolle (createdAt, createdBy, createdByName, …)
```

## 3. Screens und Services

| Screen/Service | Datei | Funktion |
|----------------|-------|----------|
| EinsatzprotokollNfsScreen | einsatzprotokoll_nfs_screen.dart | Formular mit 4 Bereichen |
| EinsatzprotokollNfsService | einsatzprotokoll_nfs_service.dart | Firestore create, streamProtokolle |

## 4. Bereich „Einsatzdaten“ (abgeschlossen)

**Linke Spalte:**
- Vor- und Nachname (read-only, Vorname zuerst – vom eingeloggten Nutzer)
- Alarmierung durch: Koordinator, sonstige (Checkboxen)

**Rechte Spalte:**
- Einsatz-Datum (TT.MM.JJJJ, ohne Vorbelegung – Datumswähler)
- Einsatz-Nr. (nur Ziffern)
- Eintreffen vor Ort (HH:MM) – Zeitwähler
- Abfahrt vom Einsatzort (HH:MM) – Zeitwähler
- Einsatzende (HH:MM) – Zeitwähler

**Unter beiden Spalten:**
- Einsatzindikation (Dropdown): bitte auswählen …, ÜTN, häuslicher Todesfall, frustrane Reanimation, Suizid, Verkehrsunfall, Arbeitsunfall, Schuleinsatz, Brand/Explosion/Unwetter, Gewalttat/Verbrechen, Große Einsatzlage, plötzlicher Kindstod, sonstiges
- Einsatz im: öffentlicher Bereich, privater Bereich (Checkboxen)

**Weitere Details:**
- Alle Felder Pflichtfelder mit gelber Hervorhebung (_pflichtfeldGelb)
- Zeitwähler: `showTimePicker` mit `initialEntryMode: TimePickerEntryMode.input`, 24h-Format
- Keine Tastatureingabe in den Uhrzeitfeldern – nur Zeitwähler-Dialog

## 5. Bereiche 2–4 (noch nicht implementiert)

- **Einsatzbericht:** Inhalt folgt
- **Einsatzverlauf:** Inhalt folgt
- **Sonstiges:** Inhalt folgt

## 6. Integration

| Stelle | Anpassung |
|--------|-----------|
| modules_service.dart | Modul `einsatzprotokollnfs`, nur bei expliziter Freischaltung (kein Auto-Enable) |
| dashboard_screen.dart | Route für `einsatzprotokollnfs` |
| menueverwaltung_screen.dart | Modul für Notfallseelsorge-Menü verfügbar |
| modulverwaltung_screen.dart | Modul in der Modulverwaltung |
| modulverwaltung_service.dart | ensureEinsatzprotokollNfsModuleExists() |

## 7. Wichtige Dateien

| Datei | Rolle |
|-------|-------|
| lib/screens/einsatzprotokoll_nfs_screen.dart | Formular mit 4 Bereichen, Einsatzdaten |
| lib/services/einsatzprotokoll_nfs_service.dart | Firestore create, streamProtokolle |

## 8. Letzte Änderungen (Feb 2026)

- Modul erstellt mit 4 Bereichen (Einsatzdaten, Einsatzbericht, Einsatzverlauf, Sonstiges)
- Einsatzdaten vollständig: Name, Alarmierung, Datum, Einsatz-Nr., 3 Uhrzeiten, Einsatzindikation, Einsatz im
- Pflichtfelder mit gelber Hervorhebung
- Zeitwähler mit Eingabemodus als Standard, 24h-Format
- Kein Auto-Enable – nur sichtbar wenn Admin das Modul freischaltet und ins Menü aufnimmt
