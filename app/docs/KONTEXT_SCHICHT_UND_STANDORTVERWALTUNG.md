# RettBase: Schicht- und Standortverwaltung – Kontext

> Kontextdokument für die Schicht- und Standortverwaltung (Einstellungen). Speichert Design-Regeln, Struktur und Implementierungsdetails für zukünftige Sessions.

## 1. Übersicht

- **Zugang:** Einstellungen → Schicht- und Standortverwaltung
- **Bereich:** Rettungsdienst, Sanitätsdienst etc. – **nicht** Schulsanitätsdienst (dort ausgeblendet)
- **Wichtig:** Dieser Bereich hat **nichts mit Notfallseelsorge (NFS)** zu tun. NFS ist ein eigener Bereich mit eigener Verwaltung (Schichtplan NFS Einstellungen).

## 2. Drei Sektionen

| Sektion | Inhalt |
|---------|--------|
| **Standorte** | Wachen/Standorte anlegen, bearbeiten, löschen |
| **Bereitschafts-Typen** | Typen (z.B. BNK, BTK) anlegen, bearbeiten, löschen |
| **Schichtarten** | Schichten mit Standort, optionalem Bereitschafts-Typ, Start-/Endzeit |

## 3. Design-Regeln (Referenz: Standorte)

**Standorte und Bereitschafts-Typen müssen identisch aussehen** – gleiche Höhe, gleiche Formatierung.

### ListTile-Konfiguration (beide Sektionen)

```dart
ListTile(
  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
  minVerticalPadding: 0,
  minLeadingWidth: 0,
  title: Text(name, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500)),
  trailing: Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      IconButton(icon: const Icon(Icons.edit, size: 20), onPressed: ...),
      IconButton(icon: Icon(Icons.delete, size: 20, color: Colors.red[700]), onPressed: ...),
    ],
  ),
)
```

### Verbote für Bereitschafts-Typen

- **Kein Kreis**, **keine Uhr**, **kein Icon** vor dem Text (kein `leading`)
- **Kein „Von NFS übernehmen“** – dieser Bereich hat mit NFS nichts zu tun
- Kein Subtitle in der Liste (Beschreibung nur im Bearbeiten-Dialog)

### Farbauswahl

- Die Farbauswahl im Bereitschafts-Typ-Dialog gilt **nur für den Bereich Notfallseelsorge**
- Bei anderen Bereichen: kein Farb-Picker, nur Name und Beschreibung

## 4. Kundentrennung

- **SchichtanmeldungService:** Alle Firestore-Pfade nutzen `_cid(companyId)` (trim, toLowerCase). Keine Daten anderer Kunden.
- **Neue Kunden:** Beim Anlegen eines Kunden werden keine Schicht-/Standort-Daten kopiert – leere Collections.

## 5. Firestore-Struktur

```
kunden/{companyId}/
  schichtplanStandorte/{standortId}
    - name, order
  schichtplanBereitschaftsTypen/{typId}
    - name, beschreibung?, color? (nur NFS)
  schichtplanSchichten/{schichtId}
    - name, standortId, typId?, startTime, endTime, endetFolgetag, order, active
```

## 6. Zeitfelder (Startzeit / Endzeit)

- **Format:** HH:mm (z.B. 07:00, 19:00)
- **Eingabe HHMM:** Wenn der Nutzer vier Ziffern ohne Doppelpunkt eingibt (z.B. 1900), wird beim Speichern automatisch in HH:MM konvertiert (19:00). `_normalizeZeit()` in `einstellungen_schichtarten_screen.dart`

## 7. Wichtige Dateien

| Datei | Rolle |
|-------|-------|
| lib/screens/einstellungen_schichtarten_screen.dart | Hauptscreen, alle drei Sektionen; `_normalizeZeit()` für HHMM→HH:MM |
| lib/screens/einstellungen_screen.dart | Öffnet SchichtartenScreen, übergibt bereich |
| lib/services/schichtanmeldung_service.dart | loadStandorte, loadBereitschaftsTypen, loadSchichten, CRUD für alle |

## 8. Header

Alle drei Sektionen nutzen `_SectionHeader` – einheitlicher Titel + Plus-Button rechts.
