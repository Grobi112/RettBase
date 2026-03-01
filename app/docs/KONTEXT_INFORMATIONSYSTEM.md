# RettBase: Informationssystem – Kontext

> Kontextdokument für das Informationssystem. Speichert Struktur, Features und Implementierungsdetails für zukünftige Sessions.

## 1. Übersicht

- **Modul-ID:** `informationssystem`
- **Firmenweit:** Das Informationssystem funktioniert ausschließlich firmenweit. Pro Firma (companyId = Firestore docId) eine Konfiguration. Kein Bereich in der Pfadstruktur – alle Bereiche eines Kunden nutzen dieselben Container-Typen, Slots und Informationen.
- **Company-ID:** Immer `effectiveCompanyId` (authData.companyId) bzw. normalisiert (`trim().toLowerCase()`).
- **Daten:** Firestore (Einstellungen + Information-Einträge)
- **Zwei Ebenen:**
  1. **Container auf Hauptseite** – bis zu 6 Container (z.B. Informationen, Termine, Verkehrslage) auf dem Dashboard
  2. **Informationssystem-Modul** – Tabs pro Container-Typ, Einstellungen (Zahnrad), Erstellen/Bearbeiten/Löschen von Informationen

## 2. Firestore-Struktur

```
kunden/{companyId}/
  settings/informationssystem
    - containerTypes: [{id, label}, ...]     # Benutzerdefinierte Container-Typen
    - containerTypeOrder: [id, ...]          # Reihenfolge der Tabs
    - containerSlots: [id|null, ...]          # Bis zu 6 Slots für Hauptseite; null = "— Kein Container —"
    - kategorien: [string, ...]
    - updatedAt: Timestamp

  informationen/{docId}
    - datum, uhrzeit (HH:mm), userId, userDisplayName
    - typ, kategorie, laufzeit, prioritaet
    - betreff, text, createdAt
```

## 3. Container-Typen und Slots

| Konzept | Beschreibung |
|---------|--------------|
| **Container-Typen** | Definiert nur die *Namen* (ID + Label), z.B. „Informationen“, „Termine“. Standard: `informationen`, `verkehrslage`. Erweiterbar. |
| **containerTypeOrder** | Reihenfolge der Tabs im Informationssystem-Modul |
| **containerSlots** | **„Container auf Hauptseite“** – explizite Auswahl, welche Container auf der Hauptseite erscheinen (max. 6). `null` = nicht anzeigen. Nur hier gewählte Container werden angezeigt – nicht automatisch alle angelegten Typen. |
| **maxContainerSlots** | `InformationssystemService.maxContainerSlots = 6` |

- „— Kein Container —“ = `null` im Slot → dieser Container wird auf der Hauptseite nicht angezeigt
- **Layout Hauptseite:** 1 Container = volle Breite; 2+ Container = max. 2 nebeneinander; schmal (< 600 px): immer 1 Spalte
- **Neue Kunden:** `createKunde()` legt `settings/informationssystem` mit leeren `containerSlots` an. `loadContainerOrder()` liefert bei fehlenden Daten `List.filled(maxContainerSlots, null)` – keine voreingestellten Container.

## 4. Laufzeit-Optionen (Information)

| Wert | Anzeige |
|------|---------|
| 1_woche | 1 Woche |
| 2_wochen | 2 Wochen |
| 3_wochen | 3 Wochen |
| 1_monat | 1 Monat |
| 3_monate | 3 Monate |
| 6_monate | 6 Monate |
| 12_monate | 12 Monate |
| bis_auf_widerruf | bis auf Widerruf |

Abgelaufene Informationen werden beim Laden automatisch gelöscht.

## 5. Rollen und Rechte

| Aktion | Rollen |
|--------|--------|
| **Modul sichtbar** (Schnellstart, Menü) | superadmin, admin, leiterssd, geschaeftsfuehrung, rettungsdienstleitung, wachleitung, koordinator |
| **User:** Nur Container auf Hauptseite | Rolle `user` sieht das Modul nicht; Container auf der Hauptseite werden trotzdem angezeigt |
| **Erstellen, Bearbeiten, Löschen** (Informationen) | superadmin, admin, geschaeftsfuehrung, rettungsdienstleitung, leiterssd, wachleitung, koordinator |
| **Einstellungen** (Zahnrad, Container-Typen, Slots) | superadmin, admin, geschaeftsfuehrung, rettungsdienstleitung, koordinator |
| **Lesen** (Container auf Hauptseite, Detail-Dialog) | Alle authentifizierten Nutzer |

## 6. Wichtige Dateien

| Datei | Rolle |
|-------|-------|
| lib/services/informationssystem_service.dart | Einstellungen: containerTypes, containerSlots, kategorien; maxContainerSlots |
| lib/services/informationen_service.dart | CRUD für Information-Einträge |
| lib/models/information_model.dart | Information (typ, kategorie, laufzeit, expiryDate, isExpired) |
| lib/screens/informationssystem_screen.dart | Modul: Tabs pro Container-Typ, Zahnrad → Einstellungen |
| lib/screens/informationssystem_einstellungen_screen.dart | Einstellungen im Modul: Container-Typen, Container auf Hauptseite (6 Slots) |
| lib/screens/einstellungen_informationssystem_screen.dart | Einstellungen-Screen: Container-Slots, Kategorien, Information erstellen |
| lib/screens/information_anlegen_screen.dart | Information anlegen/bearbeiten; readOnly für User |
| lib/widgets/info_container_card.dart | Karte pro Container auf Hauptseite (Betreff, Kategorie, Datum, Detail-Dialog, Löschen) |
| lib/screens/home_screen.dart | Dashboard: containerSlotsListenable, InfoContainerCard pro Typ |
| lib/screens/dashboard_screen.dart | _loadContainerSlots, HomeScreen mit containerSlotsListenable |
| lib/screens/schnellstart_screen.dart | Dropdown-Wert nur anzeigen wenn Modul für Nutzer sichtbar |

## 7. Technische Details

- **Company-ID:** Immer normalisiert (`trim().toLowerCase()`). Dashboard/Einstellungen nutzen `effectiveCompanyId`.
- **InfoContainerCard:** Filtert `informationenItems` nach `i.typ == type`; Label aus `InfoContainerType.labels` oder type-ID
- **Schnellstart:** Slots firmenweit; wenn Slot ein Modul enthält, das der Nutzer nicht sieht (z.B. informationssystem für User), Dropdown zeigt „— Kein Modul —“ (value: null)
- **Kein Fallback:** Nur explizit in „Container auf Hauptseite“ gewählte Slots erscheinen auf der Hauptseite.
- **Layout:** 1 Container = volle Breite; 2+ Container = max. 2 nebeneinander (home_screen.dart).

## 8. Firmenweit-Garantie

| Komponente | Pfad/Logik | Firmenweit |
|------------|------------|------------|
| Einstellungen | `kunden/{companyId}/settings/informationssystem` | ✓ Kein Bereich |
| Informationen | `kunden/{companyId}/informationen` | ✓ Kein Bereich |
| Dashboard _loadContainerSlots | Nutzt effectiveCompanyId | ✓ |
| InformationssystemScreen | companyId von aufrufendem Modul (Dashboard) | ✓ |
| InformationssystemEinstellungenScreen | companyId von InformationssystemScreen (Zahnrad) | ✓ |
| EinstellungenInformationssystemScreen | companyId von EinstellungenScreen (Globale Einstellungen) | ✓ |
