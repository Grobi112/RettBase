# RettBase: Fahrtenbuch V2 – Kontext

> Kontextdokument für das Fahrtenbuch V2. Speichert Struktur, Features und Implementierungsdetails für zukünftige Sessions.

## 1. Übersicht

- **Modul-ID:** `fahrtenbuch` (Variante V2)
- **Modul-Varianten:** Fahrtenbuch existiert als V1 (klassisch) und V2 (erweitert). Variante pro Kunde in Einstellungen → Modul-Varianten wählbar.
- **Firestore:** `kunden/{companyId}/fahrtenbuchEintraegeV2`
- **Fahrzeuge:** Aus Flottenmanagement (`FahrtenbuchService.loadFahrzeuge`), Zuordnung Standort über `Fahrzeug.wache`

## 2. Startansicht: Fahrtenbuch-Menü

Beim Öffnen des Fahrtenbuchs erscheint **nicht** automatisch das Formular, sondern das **Fahrtenbuch-Menü** mit zwei Karten:

| Karte | Aktion |
|-------|--------|
| **Neuer Fahrtenbucheintrag** | Öffnet das Formular zum Erfassen eines neuen Eintrags |
| **Fahrtenübersicht** | Zeigt alle Fahrten aller Fahrzeuge mit Filtern |

- **Kein Plus-Icon** im Header des Fahrtenbuch-Menüs
- **Titel:** „Fahrtenbuch-Menü“

## 3. Fahrtenübersicht

- **Alle Fahrten** aller Fahrzeuge in einer Liste
- **Filter:**
  - **Datum** (von / bis)
  - **Standort** (Dropdown aus `schichtplanStandorte`; Zuordnung über `Fahrzeug.wache`)
  - **Fahrzeug** (Dropdown mit Kennzeichen)
- **Standort-Filter:** `FahrtenbuchV2Eintrag` hat kein Standort-Feld. Standort kommt über `Fahrzeug.wache`. Mapping: kennzeichen/rufname → wache (Standort-ID).
- **Eintragskarten:** Zeigen Kennzeichen, Datum, Zeit, Fahrer, Ziel, km-Differenz. Klick öffnet Bearbeitung.

## 4. Formular „Neuer Fahrtenbucheintrag“

- **Kennzeichen:** Dropdown (Format: „Kennzeichen (Fahrzeugkennung)“)
- **Pflichtfelder:** Kennzeichen, Fahrzeit von/bis, Fahrt von, Fahrt-Ziel, Grund, KM Beginn, KM Ende, Fahrer (wenn nicht aus Schicht)
- **Fahrt von / Fahrt-Ziel:** Zwei getrennte Felder (Startort und Zielort) – früher ein gemeinsames „Ziel“-Feld
- **Plausibilitätsprüfung KM:** KM-Stand Fahrtende darf nicht unter KM-Stand Fahrtbeginn liegen (und umgekehrt). Validierung erfolgt sofort bei Eingabe (`autovalidateMode: onUserInteraction` + Listener auf KM-Felder)
- **Vorausfüllung:** Bei Schichtanmeldung → Fahrtenbuch: Kennzeichen und Fahrzeug aus Schicht vorausgefüllt (`buildFahrtenbuchV2VorlageFromAnmeldung`)

## 5. Firestore-Struktur

```
kunden/{companyId}/
  fahrtenbuchEintraegeV2/{docId}
    - datum: Timestamp
    - fahrzeitVon, fahrzeitBis: string (HH:mm)
    - fahrtVon, ziel: string (Fahrt von / Fahrt-Ziel)
    - grundDerFahrt: string
    - kmAnfang, kmEnde, kmDienstlich, kmWohnortArbeit, kmPrivat: int
    - nameFahrer: string
    - kostenBetrag: num, kostenArt: string
    - fahrzeugkennung, kennzeichen: string
    - createdAt, updatedAt: Timestamp
    - createdBy: string (uid)
```

## 6. Rollen und Rechte

| Aktion | Rollen |
|--------|--------|
| **Einträge erfassen, bearbeiten** | Alle authentifizierten Nutzer |
| **Fahrtenübersicht anzeigen** | Alle authentifizierten Nutzer |
| **Drucken / PDF** | Nur: superadmin, admin, geschaeftsfuehrung, rettungsdienstleitung |

- `FahrtenbuchV2UebersichtScreen.canPrint(role)` – statische Methode für Druck-Berechtigung
- Druck-Button wird für andere Rollen nicht angezeigt (V1 und V2)

## 7. Wichtige Dateien

| Datei | Rolle |
|-------|-------|
| lib/screens/fahrtenbuch_v2_screen.dart | Hauptscreen, zeigt Fahrtenbuch-Menü; lädt Vorlage aus Schichtanmeldung |
| lib/screens/fahrtenbuch_v2_uebersicht_screen.dart | 2 Karten (Neuer Eintrag, Fahrtenübersicht); Filter; Druck-Button (rollenbasiert) |
| lib/screens/fahrtenbuch_v2_druck_screen.dart | PDF-Druck |
| lib/services/fahrtenbuch_v2_service.dart | streamEintraege(), loadFahrzeuge(), CRUD |
| lib/models/fahrtenbuch_v2_model.dart | FahrtenbuchV2Eintrag |
| lib/models/fahrtenbuch_v2_vorlage.dart | Vorlage für Vorausfüllung |
| lib/services/schichtanmeldung_service.dart | buildFahrtenbuchV2VorlageFromAnmeldung, loadStandorte |
| lib/models/fleet_model.dart | Fahrzeug.wache (Standort-ID) |

## 8. Technische Details

- **Company-ID:** Immer normalisiert (`trim().toLowerCase()`)
- **KM-Plausibilität:** Form mit `autovalidateMode: AutovalidateMode.onUserInteraction`; `_onKmAnfangEndeChanged` ruft `_formKey.currentState?.validate()` auf, damit Fehler sofort angezeigt werden
- **Fahrtenbuch V1:** `FahrtenbuchuebersichtScreen` nutzt ebenfalls `FahrtenbuchV2UebersichtScreen.canPrint()` für Druck-Berechtigung. V1 hat dieselbe KM-Plausibilitätsprüfung (KM Ende >= KM Anfang) mit `autovalidateMode` und Listener für sofortige Fehleranzeige
- **Dashboard:** Übergibt `userRole` an FahrtenbuchV2Screen und FahrtenbuchV2UebersichtScreen
- **Schichtanmeldung → Fahrtenbuch:** Öffnet FahrtenbuchV2Screen mit `initialVorlage`; Menü wird angezeigt, Vorlage wird beim Klick auf „Neuer Fahrtenbucheintrag“ verwendet
