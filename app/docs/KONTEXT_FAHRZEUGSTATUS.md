# RettBase: Fahrzeugstatus – Kontext

> Kontextdokument für das Fahrzeugstatus-Modul (Übergabeprotokoll). Speichert Struktur, Features und Implementierungsdetails für zukünftige Sessions.

## 1. Übersicht

- **Modul-ID:** `fahrzeugstatus`
- **Titel (sichtbar):** „Fahrzeugstatus“
- **Bereich:** Firmenweit (alle Bereiche)
- **Sichtbarkeit:** Für alle Rollen (über Modul-Freischaltung)
- **Zweck:** Fahrer und Beifahrer können Mängel des zugeordneten Fahrzeugs einsehen, anlegen, bearbeiten und als behoben löschen

## 2. Ablauf

1. **Schicht anmelden** – Nutzer meldet sich in der Schichtanmeldung für eine Schicht an
2. **Fahrzeugzuordnung** – In der Schichtanmeldung wird ein konkretes Fahrzeug gewählt (nicht „Alle“)
3. **Fahrzeugstatus abrufen** – Das Modul zeigt das aktuelle Fahrzeug mit allen Einträgen

## 3. Firestore-Struktur

```
kunden/{companyId}/
  fahrzeugstatus/{fahrzeugId}/maengel/{mangelId}
    - titel (String, Pflicht)
    - beschreibung (String, optional)
    - maengelmelderGemeldet (bool, optional, default false)
    - createdBy (String, uid)
    - createdByName (String, Nachname des Erstellers)
    - createdAt (Timestamp)
    - updatedAt (Timestamp, bei Bearbeitung)
```

**Firestore-Regeln:** Abgedeckt durch `match /kunden/{kundenId}/{document=**}` – read, create, delete, update für `canAccessCompany(kundenId)`.

## 4. Funktionen

| Aktion | Beschreibung |
|--------|--------------|
| Einträge anzeigen | Liste aller Mängel des aktuellen Fahrzeugs (neueste zuerst) |
| Neuer Eintrag | Vollbild-Formular: Titel, Beschreibung, Checkbox „Mangel wurde an Mängelmelder gemeldet“ |
| Eintrag bearbeiten | Anklicken öffnet Vollbild-Formular (wie Fahrtenbuch), Titel/Beschreibung/Checkbox änderbar |
| Eintrag löschen | Mülltonne in Liste oder im Bearbeiten-Formular – „Als behoben löschen“ mit Bestätigung |
| Zur Schichtanmeldung | Bei „Keine Schicht“ oder „Kein Fahrzeug“: Button öffnet Schichtanmeldung |

## 5. UI-Details

### Listen-Layout (eine Zeile)
- **Links:** Titel (fett) · Erster Teil des Inhalts (erste Zeile, max. 120 Zeichen)
- **Rechts:** Datum · Ersteller (nur Nachname) · Mülltonne · Pfeil
- Abstand 20 px zwischen Titel und Inhalt
- Datum und Ersteller rechts vor der Mülltonne

### Formular (Vollbild, kein Popup)
- Titel „Neuer Eintrag“ oder „Eintrag bearbeiten“
- Felder: Titel/Kurzbeschreibung, Weitere Details (optional)
- Checkbox: „Mangel wurde an Mängelmelder gemeldet“ (optional, Erinnerung für Mängelmelder)
- Button: „Eintrag speichern“
- Bei Bearbeitung: Löschen-Button in AppBar

### Ersteller
- Nur **Nachname** wird gespeichert (displayName „Nachname, Vorname“ → vor Komma)
- Fallback: E-Mail-Prefix wenn kein Nachname ermittelbar

## 6. Relevante Dateien

| Datei | Rolle |
|-------|-------|
| lib/services/fahrzeugstatus_service.dart | streamMaengel, createMangel, updateMangel, deleteMangel |
| lib/screens/fahrzeugstatus_screen.dart | Hauptscreen, Mängel-Liste, Hinweise, Button „Zur Schichtanmeldung“ |
| lib/screens/fahrzeugstatus_mangel_form_screen.dart | Vollbild-Formular für Neu/Bearbeiten |
| lib/services/schicht_status_service.dart | getAktiveSchicht – ermittelt aktives Fahrzeug |
| lib/services/schichtanmeldung_service.dart | loadFahrzeuge, SchichtanmeldungEintrag mit fahrzeugId |
| lib/services/modules_service.dart | AppModule fahrzeugstatus |
| lib/screens/dashboard_screen.dart | case 'fahrzeugstatus', onOpenSchichtanmeldung |
| lib/screens/kundenverwaltung_screen.dart | Modulgruppe „Fahrzeuge & Sonstiges“ |
| lib/services/modulverwaltung_service.dart | ensureFahrzeugstatusModuleExists |

## 7. Hinweise

- **Keine Schicht:** Hinweis + Button „Zur Schichtanmeldung“
- **Fahrzeug „Alle“:** Hinweis + Button „Zur Schichtanmeldung“
- **Aktive Schicht:** Ermittlung über `SchichtStatusService.getAktiveSchicht()` – prüft ob aktuelle Zeit innerhalb der Schicht liegt
- **Sortierung:** Neueste zuerst (orderBy createdAt descending)
- **Legacy:** createdByName kann „Nachname, Vorname“ enthalten – Anzeige nutzt _erstellerNachname() für nur Nachname
